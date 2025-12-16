// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./interfaces/IPerformanceTracking.sol";

/**
 * @title PerformanceTracking
 * @notice Records periodic TVL snapshots per strategy and computes simple on-chain ROI
 * @dev Vault should call `recordDeposit`, `recordWithdrawal`, and periodically `takeSnapshot`.
 *      Heavy APY calculations are expected to be performed off-chain using snapshots.
 */
contract PerformanceTracking is IPerformanceTracking, Ownable {
    /// @notice Minimum interval between snapshots per strategy (seconds)
    uint256 public minSnapshotInterval = 1 hours;

    /// @notice Address of vault that is allowed to push deposit/withdraw records
    address public vault;

    /// @notice Keepers allowed to trigger snapshots
    mapping(address => bool) public keepers;

    /// @notice Stored snapshots per strategy
    mapping(uint256 => Snapshot[]) internal _snapshots;

    /// @notice Current TVL per strategy (cached)
    mapping(uint256 => uint128) internal _currentTVL;

    /// @notice Cumulative deposits and withdrawals per strategy
    mapping(uint256 => uint256) public cumulativeDeposits;
    mapping(uint256 => uint256) public cumulativeWithdrawals;

    // ============ EVENTS & ERRORS ============
    event SnapshotTaken(uint256 indexed strategyId, uint128 tvl, uint64 timestamp);
    event StrategyTVLUpdated(uint256 indexed strategyId, uint128 tvl);
    event KeeperSet(address indexed keeper, bool enabled);

    error NotAuthorized();
    error SnapshotTooSoon();
    error InvalidStrategy();
    error DivisionByZero();

    modifier onlyVault() {
        if (msg.sender != vault) revert NotAuthorized();
        _;
    }

    modifier onlyKeeperOrOwnerOrVault() {
        if (msg.sender != owner() && !keepers[msg.sender] && msg.sender != vault) revert NotAuthorized();
        _;
    }

    constructor(address _vault, address initialOwner) Ownable(initialOwner) {
        vault = _vault;
    }

    // ============ ADMIN ============
    function setVault(address _vault) external onlyOwner {
        vault = _vault;
    }

    function setKeeper(address keeper, bool enabled) external onlyOwner {
        keepers[keeper] = enabled;
        emit KeeperSet(keeper, enabled);
    }

    function setMinSnapshotInterval(uint256 secs) external onlyOwner {
        minSnapshotInterval = secs;
    }

    // ============ VAULT-ONLY CALLS ============
    function recordDeposit(uint256 strategyId, uint256 amount) external onlyVault {
        if (strategyId == 0) revert InvalidStrategy();
        cumulativeDeposits[strategyId] += amount;
    }

    function recordWithdrawal(uint256 strategyId, uint256 amount) external onlyVault {
        if (strategyId == 0) revert InvalidStrategy();
        cumulativeWithdrawals[strategyId] += amount;
    }

    /**
     * @notice Take a snapshot for a strategy (vault or keeper/owner)
     * @param strategyId Strategy identifier
     * @param tvl Current TVL in base asset units (should be provided by vault)
     */
    function takeSnapshot(uint256 strategyId, uint128 tvl) external onlyKeeperOrOwnerOrVault {
        if (strategyId == 0) revert InvalidStrategy();

        // Rate-limit snapshots to avoid spam
        Snapshot[] storage sarr = _snapshots[strategyId];
        if (sarr.length > 0) {
            Snapshot storage last = sarr[sarr.length - 1];
            if (block.timestamp < uint256(last.timestamp) + minSnapshotInterval) revert SnapshotTooSoon();
        }

        Snapshot memory snap = Snapshot({ timestamp: uint64(block.timestamp), tvl: tvl });
        sarr.push(snap);

        _currentTVL[strategyId] = tvl;

        emit SnapshotTaken(strategyId, tvl, uint64(block.timestamp));
        emit StrategyTVLUpdated(strategyId, tvl);
    }

    // ============ VIEWS ============
    function getSnapshots(uint256 strategyId) external view returns (Snapshot[] memory) {
        return _snapshots[strategyId];
    }

    function getLastSnapshot(uint256 strategyId) external view returns (Snapshot memory) {
        Snapshot[] storage sarr = _snapshots[strategyId];
        if (sarr.length == 0) return Snapshot({ timestamp: 0, tvl: 0 });
        return sarr[sarr.length - 1];
    }

    function getStrategyTVL(uint256 strategyId) external view returns (uint128) {
        return _currentTVL[strategyId];
    }

    function getStrategyLastUpdate(uint256 strategyId) external view returns (uint64) {
        Snapshot[] storage sarr = _snapshots[strategyId];
        if (sarr.length == 0) return 0;
        return sarr[sarr.length - 1].timestamp;
    }

    /**
     * @notice Compute ROI as fixed-point signed value scaled by 1e18
     * @dev ROI = (currentTVL - depositedCapital) / depositedCapital
     * @return roi Signed integer scaled by 1e18 (e.g., 0.05 => 5e16)
     */
    function getStrategyROI(uint256 strategyId) external view returns (int256) {
        uint256 deposits = cumulativeDeposits[strategyId];
        uint256 withdraws = cumulativeWithdrawals[strategyId];
        uint256 net = deposits > withdraws ? deposits - withdraws : 0;
        if (net == 0) return 0;

        uint128 current = _currentTVL[strategyId];
        int256 delta = int256(uint256(current)) - int256(net);

        // scale by 1e18
        int256 scaled = (delta * int256(1e18)) / int256(net);
        return scaled;
    }

    // ============ Helper / Maintenance ============
    function _clearSnapshots(uint256 strategyId) external onlyOwner {
        delete _snapshots[strategyId];
        _currentTVL[strategyId] = 0;
        cumulativeDeposits[strategyId] = 0;
        cumulativeWithdrawals[strategyId] = 0;
    }

    // ============ Off-chain APY guidance (not executed on-chain) ============
    /*
    Off-chain APY sample (7-day window):
    1) Fetch snapshots for last 7 days
    2) Compute time-weighted ROI over interval: sum( (t_i+1 - t_i) * ROI_i ) / total_time
    3) Annualize: APY = (1 + time_weighted_ROI)^(365 / window_days) - 1
    */
}
