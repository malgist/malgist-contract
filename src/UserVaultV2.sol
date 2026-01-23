// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/*
 * @status LEGACY
 * @network Legacy testnet
 * @used-by UserVaultV2Integration.t.sol
 * @notes Second-gen vault retained for regression testing only.
 */

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IAdapter} from "./interfaces/IAdapter.sol";
import {Pausable} from "./Pausable.sol";
import {LeaderboardLib} from "./libraries/LeaderboardLib.sol";

/**
 * @title UserVaultV2
 * @notice Enhanced copy-trading DeFi vault with leaderboard sorting, TVL tracking, and pause mechanism
 * @dev Production-grade implementation with PRIORITY 1 features
 */
contract UserVaultV2 is ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;
    using LeaderboardLib for LeaderboardLib.LeaderboardEntry[];

    // ============ STATE VARIABLES ============

    /// @notice The base asset for all strategies (USDC)
    IERC20 public immutable ASSET;

    /// @notice Maximum copy fee (50 bps = 0.5%)
    uint16 public constant MAX_COPY_FEE_BPS = 50;

    /// @notice Basis points denominator
    uint16 public constant TOTAL_BPS = 10000;

    // ============ STRUCTS ============

    /**
     * @notice Strategy configuration and metadata with enhanced TVL tracking
     */
    struct Strategy {
        address[] adapters;
        uint16[] ratios;
        uint256 totalDeposited;
        uint256 shares;
        bool isPublic;
        string name;
        uint16 copyFeeBps;
        address creator;
        uint256 totalCopies;
        uint256 totalCopierTVL; // TVL from all copiers
        uint256 lastUpdated; // Last timestamp updated
    }

    /**
     * @notice Leaderboard ranking entry
     */
    struct RankingEntry {
        address strategy;
        uint256 value;
        uint256 rank;
        string name;
    }

    // ============ STORAGE ============

    /// @notice User address => Strategy configuration
    mapping(address => Strategy) public strategies;

    /// @notice Array of users with public strategies (for leaderboard)
    address[] public publicStrategies;

    /// @notice Track if user is in public strategies array
    mapping(address => bool) public isInPublicList;

    /// @notice Accumulated earnings from copy fees
    mapping(address => uint256) public copyFeeEarnings;

    /// @notice Track who a user copied their strategy from
    mapping(address => address) public copiedFrom;

    /// @notice Last TVL snapshot timestamp (for gas-efficient leaderboard updates)
    uint256 public lastLeaderboardUpdate;

    /// @notice Update frequency for leaderboard (in seconds)
    uint256 public leaderboardUpdateFrequency = 1 hours;

    // ============ EVENTS ============

    event StrategyCreated(
        address indexed user, address[] adapters, uint16[] ratios, bool isPublic, string name, uint16 copyFeeBps
    );

    event StrategyCopied(address indexed copier, address indexed creator, uint256 copyFee);

    event Deposited(address indexed user, uint256 amount, uint256 shares, uint256 timestamp);

    event Withdrawn(address indexed user, uint256 shares, uint256 amount, uint256 timestamp);

    event StrategyUpdated(address indexed user, bool isPublic, string name, uint16 copyFeeBps);

    event CopyFeesClaimed(address indexed user, uint256 amount);

    event TVLUpdated(address indexed strategy, uint256 tvl, uint256 timestamp);

    event LeaderboardUpdated(address indexed strategy, uint256 rank, uint256 timestamp);

    // ============ ERRORS ============

    error InvalidRatios();
    error RatiosMustSumTo100();
    error ArrayLengthMismatch();
    error StrategyNotPublic();
    error CopyFeeExceedsMax();
    error NoStrategySet();
    error InsufficientBalance();
    error InvalidAmount();
    error CannotCopySelf();
    error VaultPausedForDeposits();
    error AdapterNotOperational();

    // ============ CONSTRUCTOR ============

    /**
     * @notice Initialize vault with base asset
     * @param _asset Address of base asset (USDC)
     * @param _owner Owner/governance address
     */
    constructor(address _asset, address _owner) Pausable(_owner) {
        ASSET = IERC20(_asset);
        lastLeaderboardUpdate = block.timestamp;
    }

    // ============ EXTERNAL FUNCTIONS ============

    /**
     * @notice Create or update user's strategy
     * @param adapters Array of protocol adapter addresses
     * @param ratios Allocation ratios in basis points
     * @param isPublic Whether strategy should be public
     * @param name Strategy name
     * @param copyFeeBps Fee to charge copiers (0-50 bps)
     */
    function setStrategy(
        address[] memory adapters,
        uint16[] memory ratios,
        bool isPublic,
        string memory name,
        uint16 copyFeeBps
    ) external whenNotPaused {
        // Validations
        if (adapters.length == 0 || adapters.length != ratios.length) {
            revert ArrayLengthMismatch();
        }
        if (copyFeeBps > MAX_COPY_FEE_BPS) {
            revert CopyFeeExceedsMax();
        }

        // Validate ratios sum to 100%
        uint256 totalRatio;
        for (uint256 i = 0; i < ratios.length; i++) {
            if (ratios[i] == 0) revert InvalidRatios();
            if (pausedAdapters[adapters[i]]) revert AdapterNotOperational();
            totalRatio += ratios[i];
        }
        if (totalRatio != TOTAL_BPS) revert RatiosMustSumTo100();

        // Store strategy
        Strategy storage s = strategies[msg.sender];
        s.adapters = adapters;
        s.ratios = ratios;
        s.isPublic = isPublic;
        s.name = name;
        s.copyFeeBps = copyFeeBps;
        s.creator = msg.sender;
        s.lastUpdated = block.timestamp;

        // Add to public list if newly public
        if (isPublic && !isInPublicList[msg.sender]) {
            publicStrategies.push(msg.sender);
            isInPublicList[msg.sender] = true;
        }

        emit StrategyCreated(msg.sender, adapters, ratios, isPublic, name, copyFeeBps);
    }

    /**
     * @notice Copy another user's public strategy
     * @param creator Address of strategy creator to copy
     */
    function copyStrategy(address creator) external whenNotPaused {
        if (creator == msg.sender) revert CannotCopySelf();

        Strategy memory original = strategies[creator];
        if (!original.isPublic) revert StrategyNotPublic();
        if (original.adapters.length == 0) revert NoStrategySet();

        // Copy strategy configuration
        Strategy storage userStrategy = strategies[msg.sender];
        userStrategy.adapters = original.adapters;
        userStrategy.ratios = original.ratios;
        userStrategy.isPublic = false; // User's copy is private by default
        userStrategy.name = string(abi.encodePacked("Copy of ", original.name));
        userStrategy.copyFeeBps = 0; // No copy fee on copied strategies
        userStrategy.creator = msg.sender;
        userStrategy.lastUpdated = block.timestamp;

        // Track who this user copied from
        copiedFrom[msg.sender] = creator;

        // Track copy statistics for original creator
        strategies[creator].totalCopies++;

        emit StrategyCopied(msg.sender, creator, 0);
    }

    /**
     * @notice Deposit assets into user's strategy (REVERT if paused)
     * @param amount Amount of base asset to deposit
     * @param slippageTolerance Maximum acceptable slippage in basis points
     * @return shares Amount of shares minted
     */
    function deposit(uint256 amount, uint16 slippageTolerance) external nonReentrant whenNotPaused returns (uint256 shares) {
        if (amount == 0) revert InvalidAmount();

        Strategy storage s = strategies[msg.sender];
        if (s.adapters.length == 0) revert NoStrategySet();

        // Validate all adapters are operational
        for (uint256 i = 0; i < s.adapters.length; i++) {
            if (pausedAdapters[s.adapters[i]]) revert AdapterNotOperational();
        }

        // Transfer assets from user
        ASSET.safeTransferFrom(msg.sender, address(this), amount);

        // Pay copy fee if this is a copied strategy
        uint256 netAmount = amount;
        address originalCreator = copiedFrom[msg.sender];
        if (originalCreator != address(0)) {
            Strategy memory creatorStrategy = strategies[originalCreator];
            if (creatorStrategy.copyFeeBps > 0) {
                uint256 copyFee = (amount * creatorStrategy.copyFeeBps) / TOTAL_BPS;
                netAmount = amount - copyFee;

                // Accumulate fee for original creator
                copyFeeEarnings[originalCreator] += copyFee;

                // Update creator's TVL stats
                strategies[originalCreator].totalCopierTVL += netAmount;

                emit StrategyCopied(msg.sender, originalCreator, copyFee);
            }
        }

        // Execute strategy: split funds across adapters
        _executeDeposit(s.adapters, s.ratios, netAmount);

        // Mint shares 1:1 (simplified for MVP)
        shares = netAmount;
        s.shares += shares;
        s.totalDeposited += netAmount;
        s.lastUpdated = block.timestamp;

        emit Deposited(msg.sender, amount, shares, block.timestamp);
        emit TVLUpdated(msg.sender, s.totalDeposited + s.totalCopierTVL, block.timestamp);

        return shares;
    }

    /**
     * @notice Withdraw assets from user's strategy (ALLOWED even if paused)
     * @param shareAmount Amount of shares to burn
     * @return withdrawn Amount of assets withdrawn
     */
    function withdraw(uint256 shareAmount) external nonReentrant returns (uint256 withdrawn) {
        if (shareAmount == 0) revert InvalidAmount();

        Strategy storage s = strategies[msg.sender];
        if (s.shares < shareAmount) revert InsufficientBalance();

        // Withdraw proportionally from all adapters
        withdrawn = _executeWithdraw(s.adapters, s.ratios, shareAmount);

        // Burn shares
        s.shares -= shareAmount;
        s.totalDeposited = s.totalDeposited > withdrawn ? s.totalDeposited - withdrawn : 0;
        s.lastUpdated = block.timestamp;

        // Transfer assets to user
        ASSET.safeTransfer(msg.sender, withdrawn);

        emit Withdrawn(msg.sender, shareAmount, withdrawn, block.timestamp);
        emit TVLUpdated(msg.sender, s.totalDeposited + s.totalCopierTVL, block.timestamp);

        return withdrawn;
    }

    /**
     * @notice Claim accumulated copy fee earnings
     */
    function claimCopyFees() external nonReentrant {
        uint256 earnings = copyFeeEarnings[msg.sender];
        if (earnings == 0) revert InvalidAmount();

        copyFeeEarnings[msg.sender] = 0;
        ASSET.safeTransfer(msg.sender, earnings);

        emit CopyFeesClaimed(msg.sender, earnings);
    }

    /**
     * @notice Update strategy metadata (name, public status, copy fee)
     */
    function updateStrategyMetadata(bool isPublic, string memory name, uint16 copyFeeBps) external whenNotPaused {
        if (copyFeeBps > MAX_COPY_FEE_BPS) revert CopyFeeExceedsMax();

        Strategy storage s = strategies[msg.sender];
        if (s.adapters.length == 0) revert NoStrategySet();

        s.isPublic = isPublic;
        s.name = name;
        s.copyFeeBps = copyFeeBps;
        s.lastUpdated = block.timestamp;

        // Update public list
        if (isPublic && !isInPublicList[msg.sender]) {
            publicStrategies.push(msg.sender);
            isInPublicList[msg.sender] = true;
        }

        emit StrategyUpdated(msg.sender, isPublic, name, copyFeeBps);
    }

    // ============ LEADERBOARD VIEW FUNCTIONS ============

    /**
     * @notice Get top strategies ranked by total copies (with sorting)
     * @param count Number of top strategies to return
     * @return rankings Array of ranking entries
     */
    function getLeaderboardByCopies(uint256 count) external view returns (RankingEntry[] memory rankings) {
        uint256 length = publicStrategies.length;
        if (length == 0) return new RankingEntry[](0);

        // Build entries array
        LeaderboardLib.LeaderboardEntry[] memory entries = new LeaderboardLib.LeaderboardEntry[](length);
        for (uint256 i = 0; i < length; i++) {
            address user = publicStrategies[i];
            entries[i] = LeaderboardLib.LeaderboardEntry({user: user, value: strategies[user].totalCopies});
        }

        // Sort and get top N
        LeaderboardLib.LeaderboardEntry[] memory sorted = LeaderboardLib.getTopN(entries, count);

        // Build ranking results
        rankings = new RankingEntry[](sorted.length);
        for (uint256 i = 0; i < sorted.length; i++) {
            rankings[i] = RankingEntry({
                strategy: sorted[i].user,
                value: sorted[i].value,
                rank: i + 1,
                name: strategies[sorted[i].user].name
            });
        }

        return rankings;
    }

    /**
     * @notice Get top strategies ranked by Total Value Locked (TVL)
     * @param count Number of top strategies to return
     * @return rankings Array of ranking entries with TVL values
     */
    function getLeaderboardByTVL(uint256 count) external view returns (RankingEntry[] memory rankings) {
        uint256 length = publicStrategies.length;
        if (length == 0) return new RankingEntry[](0);

        // Build entries array with TVL values
        LeaderboardLib.LeaderboardEntry[] memory entries = new LeaderboardLib.LeaderboardEntry[](length);
        for (uint256 i = 0; i < length; i++) {
            address user = publicStrategies[i];
            Strategy memory strat = strategies[user];
            uint256 tvl = strat.totalDeposited + strat.totalCopierTVL;
            entries[i] = LeaderboardLib.LeaderboardEntry({user: user, value: tvl});
        }

        // Sort and get top N
        LeaderboardLib.LeaderboardEntry[] memory sorted = LeaderboardLib.getTopN(entries, count);

        // Build ranking results
        rankings = new RankingEntry[](sorted.length);
        for (uint256 i = 0; i < sorted.length; i++) {
            rankings[i] = RankingEntry({
                strategy: sorted[i].user,
                value: sorted[i].value,
                rank: i + 1,
                name: strategies[sorted[i].user].name
            });
        }

        return rankings;
    }

    /**
     * @notice Get user's strategy with TVL breakdown
     * @param user Address of user
     * @return strategy Strategy struct
     * @return totalTVL Total TVL (deposits + copier deposits)
     * @return copierTVL TVL from copiers only
     */
    function getStrategyWithTVL(address user)
        external
        view
        returns (Strategy memory strategy, uint256 totalTVL, uint256 copierTVL)
    {
        strategy = strategies[user];
        copierTVL = strategy.totalCopierTVL;
        totalTVL = strategy.totalDeposited + copierTVL;
    }

    /**
     * @notice Get all public strategies with current rankings
     * @return strategies Array of public strategy addresses
     * @return tvls Array of TVL values for each strategy
     * @return copies Array of copy counts for each strategy
     */
    function getPublicStrategiesWithMetrics()
        external
        view
        returns (address[] memory, uint256[] memory tvls, uint256[] memory copies)
    {
        uint256 length = publicStrategies.length;
        tvls = new uint256[](length);
        copies = new uint256[](length);

        for (uint256 i = 0; i < length; i++) {
            address user = publicStrategies[i];
            Strategy memory s = strategies[user];
            tvls[i] = s.totalDeposited + s.totalCopierTVL;
            copies[i] = s.totalCopies;
        }

        return (publicStrategies, tvls, copies);
    }

    /**
     * @notice Get user's current position value (updated in real-time from adapters)
     * @param user Address of user
     * @return Total value across all adapters
     */
    function getUserValue(address user) external view returns (uint256) {
        Strategy memory s = strategies[user];
        if (s.adapters.length == 0) return 0;

        uint256 totalValue = 0;
        for (uint256 i = 0; i < s.adapters.length; i++) {
            totalValue += IAdapter(s.adapters[i]).getBalance();
        }
        return totalValue;
    }

    /**
     * @notice Get strategy ranking by TVL (percentile)
     * @param user Address of user
     * @return percentile Ranking percentile (0-10000 basis points)
     */
    function getStrategyTVLPercentile(address user) external view returns (uint256 percentile) {
        uint256 length = publicStrategies.length;
        if (length == 0) return 0;

        // Build TVL array
        uint256[] memory tvls = new uint256[](length);
        uint256 userTVL = 0;
        bool userFound = false;

        for (uint256 i = 0; i < length; i++) {
            address stratUser = publicStrategies[i];
            Strategy memory s = strategies[stratUser];
            uint256 tvl = s.totalDeposited + s.totalCopierTVL;
            tvls[i] = tvl;

            if (stratUser == user) {
                userTVL = tvl;
                userFound = true;
            }
        }

        if (!userFound) return 0;

        // Calculate percentile
        percentile = LeaderboardLib.getPercentile(userTVL, tvls);
    }

    // ============ INTERNAL FUNCTIONS ============

    /**
     * @notice Execute deposit by splitting funds across adapters
     * @param adapters Array of adapter addresses
     * @param ratios Allocation ratios
     * @param amount Total amount to split
     */
    function _executeDeposit(address[] memory adapters, uint16[] memory ratios, uint256 amount) internal {
        uint256 remaining = amount;

        for (uint256 i = 0; i < adapters.length; i++) {
            uint256 adapterAmount;

            // Last adapter gets remainder to handle rounding
            if (i == adapters.length - 1) {
                adapterAmount = remaining;
            } else {
                adapterAmount = (amount * ratios[i]) / TOTAL_BPS;
                remaining -= adapterAmount;
            }

            if (adapterAmount > 0) {
                // Approve and deposit
                ASSET.forceApprove(adapters[i], adapterAmount);
                IAdapter(adapters[i]).deposit(adapterAmount);
                ASSET.forceApprove(adapters[i], 0);
            }
        }
    }

    /**
     * @notice Execute withdrawal from all adapters
     * @param adapters Array of adapter addresses
     * @param ratios Allocation ratios (for proportional withdrawal)
     * @param shareAmount Amount of shares to withdraw
     * @return totalWithdrawn Total amount withdrawn
     */
    function _executeWithdraw(address[] memory adapters, uint16[] memory ratios, uint256 shareAmount)
        internal
        returns (uint256 totalWithdrawn)
    {
        for (uint256 i = 0; i < adapters.length; i++) {
            uint256 adapterShares = (shareAmount * ratios[i]) / TOTAL_BPS;
            if (adapterShares > 0) {
                uint256 withdrawn = IAdapter(adapters[i]).withdraw(adapterShares);
                totalWithdrawn += withdrawn;
            }
        }
        return totalWithdrawn;
    }
}
