// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IAdapter} from "./interfaces/IAdapter.sol";

interface IUserVault {
    struct Strategy { address[] adapters; uint16[] ratios; uint256 totalDeposited; uint256 shares; bool isPublic; string name; uint16 copyFeeBps; address creator; uint256 totalCopies; uint256 totalCopierTVL; }
    function getStrategy(address user) external view returns (Strategy memory);
    function rebalanceByEngine(uint256 strategyId, uint16 maxSlippageBps, uint256 deadline) external returns (bool);
    function isGlobalPauseActive() external view returns (bool);
}

/**
 * @title AutoRebalanceEngine
 * @notice Threshold-based auto-rebalance engine for MALGIST
 * @dev This contract validates thresholds and gas guard, then calls `UserVault.rebalanceByEngine`
 */
contract AutoRebalanceEngine {
    using SafeERC20 for IERC20;

    // ======== ERRORS ========
    error ThresholdNotExceeded();
    error GasCostTooHigh();
    error RebalanceTooFrequent();
    error VaultPaused();
    error NotAuthorized();

    // ======== EVENTS ========
    event RebalanceTriggered(uint256 indexed strategyId, address indexed caller, bool autoTriggered);
    event RebalanceExecuted(uint256 indexed strategyId, address indexed caller);
    event RebalanceSkipped(uint256 indexed strategyId, string reason);
    event RebalanceFailed(uint256 indexed strategyId, string reason);

    // ======== STATE ========
    IUserVault public immutable vault;
    IERC20 public immutable ASSET;

    // thresholds
    uint16 public globalRebalanceThresholdBps = 500; // default 5%
    uint16 public constant MAX_REBALANCE_THRESHOLD_BPS = 2000;
    mapping(uint256 => uint16) public perStrategyThresholdBps;

    // gas guard: require at least `minGasLeft` gas to execute rebalance
    uint256 public minGasLeft = 100_000;

    // roles
    address public admin;
    address public keeper;

    constructor(address _vault, address _asset, address _admin) {
        vault = IUserVault(_vault);
        ASSET = IERC20(_asset);
        admin = _admin;
        keeper = _admin;
    }

    // ======== ADMIN ========
    modifier onlyAdmin() {
        if (msg.sender != admin) revert NotAuthorized();
        _;
    }

    modifier onlyKeeperOrAdmin() {
        if (msg.sender != keeper && msg.sender != admin) revert NotAuthorized();
        _;
    }

    function setGlobalThreshold(uint16 bps) external onlyAdmin {
        require(bps <= MAX_REBALANCE_THRESHOLD_BPS, "threshold cap");
        globalRebalanceThresholdBps = bps;
    }

    function setPerStrategyThreshold(uint256 strategyId, uint16 bps) external onlyAdmin {
        require(bps <= MAX_REBALANCE_THRESHOLD_BPS, "threshold cap");
        perStrategyThresholdBps[strategyId] = bps;
    }

    function setMinGasLeft(uint256 g) external onlyAdmin { minGasLeft = g; }

    function setKeeper(address k) external onlyAdmin { keeper = k; }

    // ======== TRIGGERS ========
    /**
     * @notice Manual rebalance callable by keeper or governance (admin)
     */
    function rebalanceManual(uint256 strategyId, uint16 maxSlippageBps, uint256 deadline) external onlyKeeperOrAdmin returns (bool) {
        emit RebalanceTriggered(strategyId, msg.sender, false);
        _gasGuard();
        _pauseGuard();
        // Manual trigger may bypass threshold guards (keeper/governance may force rebalance)
        try vault.rebalanceByEngine(strategyId, maxSlippageBps, deadline) returns (bool success) {
            if (success) emit RebalanceExecuted(strategyId, msg.sender);
            return success;
        } catch Error(string memory reason) {
            emit RebalanceFailed(strategyId, reason);
            revert(reason);
        } catch {
            emit RebalanceFailed(strategyId, "unknown");
            revert("unknown");
        }
    }

    /**
     * @notice Permissionless rebalance; anyone may call if threshold exceeded and gas guard passes
     */
    function rebalanceAuto(uint256 strategyId, uint16 maxSlippageBps, uint256 deadline) external returns (bool) {
        emit RebalanceTriggered(strategyId, msg.sender, true);
        // gas guard
        _gasGuard();
        // pause guard
        _pauseGuard();
        // threshold
        bool ok = _thresholdGuard(strategyId);
        if (!ok) {
            emit RebalanceSkipped(strategyId, "threshold");
            revert ThresholdNotExceeded();
        }

        try vault.rebalanceByEngine(strategyId, maxSlippageBps, deadline) returns (bool success) {
            if (success) emit RebalanceExecuted(strategyId, msg.sender);
            return success;
        } catch Error(string memory reason) {
            emit RebalanceFailed(strategyId, reason);
            revert(reason);
        } catch {
            emit RebalanceFailed(strategyId, "unknown");
            revert("unknown");
        }
    }

    // ======== GUARDS ========
    function _gasGuard() internal view {
        // simple gas-left check: require enough gas remaining
        if (gasleft() < minGasLeft) revert GasCostTooHigh();
    }

    function _pauseGuard() internal view {
        if (vault.isGlobalPauseActive()) revert VaultPaused();
    }

    function _thresholdGuard(uint256 strategyId) internal view returns (bool) {
        // read strategy data
        address owner = address(uint160(strategyId));
        IUserVault.Strategy memory s = vault.getStrategy(owner);

        uint256 adaptersCount = s.adapters.length;
        if (adaptersCount == 0) return false;

        uint256 total = 0;
        uint256[] memory tvls = new uint256[](adaptersCount);
        for (uint256 i = 0; i < adaptersCount; i++) {
            tvls[i] = IAdapter(s.adapters[i]).getBalance();
            total += tvls[i];
        }
        if (total == 0) return false;

        uint16 threshold = perStrategyThresholdBps[strategyId] == 0 ? globalRebalanceThresholdBps : perStrategyThresholdBps[strategyId];

        // compute drift in BPS for each adapter
        for (uint256 i = 0; i < adaptersCount; i++) {
            uint256 currentBps = (tvls[i] * 10000) / total;
            uint256 targetBps = s.ratios[i];
            uint256 drift = currentBps > targetBps ? currentBps - targetBps : targetBps - currentBps;
            if (drift >= threshold) return true;
        }
        return false;
    }
}
