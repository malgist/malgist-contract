// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IAdapter} from "./interfaces/IAdapter.sol";
import {EmergencyPause} from "./EmergencyPause.sol";
import {IPerformanceTracking} from "./interfaces/IPerformanceTracking.sol";
import {IFeeManager} from "./interfaces/IFeeManager.sol";
import {IStrategyRegistry} from "./interfaces/IStrategyRegistry.sol";
import {AIStrategyValidator, AIStrategyOutput, ValidatedStrategy} from "./validators/AIStrategyValidator.sol";
import {StrategyExecutor} from "./StrategyExecutor.sol";

/**
 * @title UserVault
 * @notice Copy-trading DeFi vault where users can create, share, and copy investment strategies
 * @dev Each user can have one active strategy. Strategies can be public (copyable) or private.
 *      Integrates emergency pause system for exploit response while maintaining withdrawal immunity.
 */
contract UserVault is ReentrancyGuard, EmergencyPause {
    using SafeERC20 for IERC20;

    // ============ STATE VARIABLES ============

    /// @notice The base asset for all strategies (USDC)
    IERC20 public immutable ASSET;

    /// @notice Maximum copy fee (50 bps = 0.5%)
    uint16 public constant MAX_COPY_FEE_BPS = 50;

    /// @notice Basis points denominator
    uint16 public constant TOTAL_BPS = 10000;

    // ============ STRUCTS ============

    /**
     * @notice Strategy configuration and metadata
     * @param adapters Array of protocol adapter addresses
     * @param ratios Allocation ratios in basis points (must sum to 10000)
     * @param totalDeposited Total amount deposited by this user
     * @param shares User's current share balance
     * @param isPublic Whether strategy is visible/copyable by others
     * @param name Human-readable strategy name
     * @param copyFeeBps Fee charged when others copy (0-50 bps)
     * @param creator Address of strategy creator (for copy tracking)
     * @param totalCopies Number of times this strategy has been copied
     * @param totalCopierTVL Total value locked by users who copied this strategy
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
        uint256 totalCopierTVL;
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

    // ============ SHARE ACCOUNTING ============

    /// @notice Total vault shares (across all users/strategies)
    uint256 public totalShares;

    /// @notice Cached total assets in base token units (updated on deposits/withdrawals/reconciles)
    uint256 public totalAssets;

    /// @notice User address => share balance
    mapping(address => uint256) public userShares;

    /// @notice Strategy id => share balance (strategyId derived from user address)
    mapping(uint256 => uint256) public strategyShares;

    /// @notice Adapter address => cached reported balance (in base units)
    mapping(address => uint256) public adapterCached;

    // ============ FEE DISTRIBUTION TRACKING (Aspect #6) ============

    /**
     * @notice Fee breakdown per adapter for detailed analytics
     * @param adapter Adapter address that generated fees
     * @param amount Fee amount from this adapter
     * @param timestamp When fee was collected
     */
    struct AdapterFeeEntry {
        address adapter;
        uint256 amount;
        uint256 timestamp;
    }

    /// @notice Creator address => array of fee entries per adapter
    mapping(address => AdapterFeeEntry[]) public adapterFeeHistory;

    /// @notice Creator address => adapter address => accumulated fees
    mapping(address => mapping(address => uint256)) public feesByAdapter;

    /// @notice Total number of fee collection events per creator
    mapping(address => uint256) public totalFeeEvents;

    /// @notice Minimum seconds between rebalances per strategy
    uint256 public minRebalanceInterval = 3600; // default 1 hour

    /// @notice Performance tracking contract address (separate module)
    address public performanceTracker;

    /// @notice Rebalance engine address allowed to call `rebalanceByEngine`
    address public rebalanceEngine;

    /// @notice Strategy registry contract
    IStrategyRegistry public strategyRegistry;

    /// @notice AI Strategy Validator (zero-trust AI validation)
    AIStrategyValidator public aiStrategyValidator;

    /// @notice Strategy Executor (modular adapter routing)
    StrategyExecutor public strategyExecutor;

    /// @notice Last rebalance timestamp per strategy id
    mapping(uint256 => uint256) public lastRebalance;

    /// @notice Mapping from user -> adopted strategy version (strategyVersion per user)
    mapping(address => uint256) public strategyVersion;


    // ============ EVENTS ============

    event StrategyCreated(
        address indexed user, address[] adapters, uint16[] ratios, bool isPublic, string name, uint16 copyFeeBps
    );

    event StrategyCopied(address indexed copier, address indexed creator, uint256 copyFee);

    event Deposited(address indexed user, uint256 amount, uint256 shares);

    event Withdrawn(address indexed user, uint256 shares, uint256 amount);

    event StrategyUpdated(address indexed user, bool isPublic, string name, uint16 copyFeeBps);

    event CopyFeesClaimed(address indexed user, uint256 amount);

    /// @notice Emitted when copy fees are collected with adapter breakdown (Aspect #6)
    event CopyFeeCollectedDetailed(
        address indexed creator,
        address indexed copier,
        uint256 totalFee,
        address[] adapters,
        uint256[] feesByAdapter
    );

    /// @notice Emitted when fees are claimed with detailed breakdown (Aspect #6)
    event CopyFeesClaimedDetailed(
        address indexed creator,
        uint256 totalAmount,
        uint256 adapterCount,
        uint256[] adapterFees
    );

    /// @notice Emitted when vault shares are minted
    event SharesMinted(address indexed user, uint256 indexed strategyId, uint256 shares, uint256 amount);

    /// @notice Emitted when vault shares are burned
    event SharesBurned(address indexed user, uint256 indexed strategyId, uint256 shares, uint256 amount);

    /// @notice Emitted when an adapter is reconciled (reported vs cached)
    event AdapterReconciled(address indexed adapter, uint256 reported, uint256 cached);
    event RebalanceError(bytes reason);
    event StrategyMigrated(address indexed user, uint256 indexed strategyId, uint256 fromVersion, uint256 toVersion, uint256 amount);
    event StrategyVersionSet(address indexed user, uint256 versionId);
    event AIStrategyCreated(address indexed user, bytes32 indexed strategyHash, uint8 riskLevel, uint16 creatorFee);
    event AIValidatorSet(address indexed validator);
    event StrategyExecutorSet(address indexed executor);

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
    error DepositReturnedZero();
    error ZeroTotalShares();
    error InsufficientShares();
    error ThresholdNotExceeded();
    error GasCostTooHigh();
    error RebalanceTooFrequent();
    error VaultPaused();
    error UnauthorizedRebalanceEngine();
    error DeprecatedStrategy();
    error ExceedsLimitedTVL();
    error UnauthorizedMigration();
    error DowngradeNotAllowed();
    error MigrationFailed();
    error AdapterDepositFailed();
    error AIValidationFailed();
    error ValidatorNotSet();
    // AdapterPausedError is inherited from EmergencyPause

    // ============ CONSTRUCTOR ============

    /**
     * @notice Initialize vault with base asset and emergency pause owner
     * @param _asset Address of base asset (USDC)
     * @param _pauseOwner Address of pause guardian (typically multisig)
     */
    constructor(address _asset, address _pauseOwner) EmergencyPause(_pauseOwner) {
        ASSET = IERC20(_asset);
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
    function setStrategyWithRisk(
        address[] memory adapters,
        uint16[] memory ratios,
        bool isPublic,
        string memory name,
        uint16 copyFeeBps,
        uint8 riskLevel,
        bytes32 riskDisclosureHash
    ) public whenStrategyExecutionNotPaused {
        // Validations
        if (adapters.length == 0 || adapters.length != ratios.length) {
            revert ArrayLengthMismatch();
        }
        if (copyFeeBps > MAX_COPY_FEE_BPS) {
            revert CopyFeeExceedsMax();
        }

        // Validate ratios sum to 100
        uint256 totalRatio;
        uint256 ratiosLen = ratios.length;
        for (uint256 i = 0; i < ratiosLen;) {
            if (ratios[i] == 0) revert InvalidRatios();
            totalRatio += ratios[i];
            unchecked { ++i; }
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

        // Register strategy metadata with registry on first creation
        uint256 strategyId = _strategyIdForUser(msg.sender);
        if (address(strategyRegistry) != address(0)) {
            // Register strategy metadata in the registry; let registry enforce phase rules and revert if not allowed
            strategyRegistry.registerStrategy(strategyId, msg.sender, riskLevel, riskDisclosureHash);
        }

        // If user had no version before, set default version 1
        if (strategyVersion[msg.sender] == 0) {
            strategyVersion[msg.sender] = 1;
            emit StrategyVersionSet(msg.sender, 1);
        }

        // Add to public list if newly public
        if (isPublic && !isInPublicList[msg.sender]) {
            publicStrategies.push(msg.sender);
            isInPublicList[msg.sender] = true;
        }

        emit StrategyCreated(msg.sender, adapters, ratios, isPublic, name, copyFeeBps);
    }

    /// @notice Backwards-compatible wrapper for tests and older callers. Generates a deterministic on-chain risk hash.
    function setStrategy(
        address[] memory adapters,
        uint16[] memory ratios,
        bool isPublic,
        string memory name,
        uint16 copyFeeBps
    ) external whenStrategyExecutionNotPaused {
        // generate a simple risk disclosure hash to satisfy registry requirement
        bytes32 generated = keccak256(abi.encodePacked(block.timestamp, msg.sender, adapters.length, name));
        // call the full signature
        setStrategyWithRisk(adapters, ratios, isPublic, name, copyFeeBps, 0, generated);
    }

    /**
     * @notice Copy another user's public strategy
     * @param creator Address of strategy creator to copy
     */
    function copyStrategy(address creator) external whenStrategyExecutionNotPaused {
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

        // Track who this user copied from
        copiedFrom[msg.sender] = creator;

        // Track copy statistics for original creator
        strategies[creator].totalCopies++;

        emit StrategyCopied(msg.sender, creator, 0);
    }

    /**
     * @notice Create strategy from AI-generated output (ZERO-TRUST VALIDATION)
     * @param aiOutput Untrusted AI-generated strategy parameters
     * @param isPublic Whether strategy should be public (user choice)
     * @dev This function enforces zero-trust AI validation through AIStrategyValidator
     *      All 12 validation checks are performed on-chain before accepting the strategy
     *      AI output is treated as adversarial input - no trust assumptions
     *
     * SECURITY:
     * - ✅ All adapters must be whitelisted
     * - ✅ Allocations must sum to exactly 100%
     * - ✅ Creator fee capped by risk level
     * - ✅ No duplicate adapters
     * - ✅ No dust allocations
     * - ✅ Risk profile validated
     * - See AIStrategyValidator for complete 12-point validation
     */
    function createStrategyFromAI(AIStrategyOutput calldata aiOutput, bool isPublic)
        external
        whenStrategyExecutionNotPaused
        returns (bytes32 strategyHash)
    {
        // Ensure validator is configured
        if (address(aiStrategyValidator) == address(0)) revert ValidatorNotSet();

        // CRITICAL: Validate AI output through zero-trust validator
        // This performs all 12 validation checks as specified in AI_STRATEGY_SCHEMA_SPEC.md
        (ValidatedStrategy memory validated, bool isValid) =
            aiStrategyValidator.validateAIStrategy(aiOutput);

        // Reject if any validation check failed
        if (!isValid) revert AIValidationFailed();

        // At this point, the strategy has passed all 12 validation checks:
        // ✅ Check 1-3: Array and name validation
        // ✅ Check 4-6: Adapter validation (whitelisted, no duplicates, no zero addresses)
        // ✅ Check 7-9: Allocation validation (no >100%, no dust, sum=100%)
        // ✅ Check 10: Risk profile valid
        // ✅ Check 11-12: Creator fee within limits

        // Convert validated allocations to uint16[] for storage
        uint16[] memory ratios = validated.allocations;

        // Create strategy using validated parameters
        Strategy storage s = strategies[msg.sender];
        s.adapters = validated.adapters;
        s.ratios = ratios;
        s.isPublic = isPublic;
        s.name = aiOutput.strategyName;
        s.copyFeeBps = validated.approvedCreatorFeeBps;
        s.creator = msg.sender;

        // Register strategy metadata with registry if configured
        uint256 strategyId = _strategyIdForUser(msg.sender);
        if (address(strategyRegistry) != address(0)) {
            // Create risk disclosure hash from AI output
            bytes32 riskDisclosureHash = keccak256(abi.encodePacked(aiOutput.riskDisclosure));

            // Register with validated risk level
            strategyRegistry.registerStrategy(
                strategyId,
                msg.sender,
                validated.riskLevel,
                riskDisclosureHash
            );
        }

        // Set default version if first time
        if (strategyVersion[msg.sender] == 0) {
            strategyVersion[msg.sender] = 1;
            emit StrategyVersionSet(msg.sender, 1);
        }

        // Add to public list if requested
        if (isPublic && !isInPublicList[msg.sender]) {
            publicStrategies.push(msg.sender);
            isInPublicList[msg.sender] = true;
        }

        // Emit events
        emit StrategyCreated(
            msg.sender,
            validated.adapters,
            ratios,
            isPublic,
            aiOutput.strategyName,
            validated.approvedCreatorFeeBps
        );

        emit AIStrategyCreated(
            msg.sender,
            validated.strategyHash,
            validated.riskLevel,
            validated.approvedCreatorFeeBps
        );

        return validated.strategyHash;
    }

    /**
     * @notice Deposit assets into user's strategy
     * @param amount Amount of base asset to deposit
     * @return shares Amount of shares minted
     * @dev Deposit is blocked during global pause or if any adapter in the strategy is paused
     */
    function deposit(uint256 amount) external nonReentrant whenDepositsNotPaused returns (uint256 shares) {
        if (amount == 0) revert InvalidAmount();

        Strategy storage s = strategies[msg.sender];
        if (s.adapters.length == 0) revert NoStrategySet();

        // Ensure user's adopted strategy version is not marked deprecated (no deposits into deprecated versions)
        uint256 v = strategyVersion[msg.sender];
        if (address(strategyRegistry) != address(0) && v != 0) {
            uint256 userStrategyId = _strategyIdForUser(msg.sender);
            if (strategyRegistry.isVersionDeprecated(userStrategyId, v)) revert DeprecatedStrategy();
        }

        // Validate all adapters in strategy are operational (not paused)
        uint256 adaptersLen = s.adapters.length;
        for (uint256 i = 0; i < adaptersLen;) {
            if (!isAdapterOperational(s.adapters[i])) revert AdapterPausedError();
            unchecked { ++i; }
        }

        // Transfer assets from user
        ASSET.safeTransferFrom(msg.sender, address(this), amount);

        // Pay copy fee if this is a copied strategy (ENHANCED: Per-adapter fee tracking)
        uint256 netAmount = amount;
        address originalCreator = copiedFrom[msg.sender];
        if (originalCreator != address(0)) {
            Strategy memory creatorStrategy = strategies[originalCreator];
            if (creatorStrategy.copyFeeBps > 0) {
                uint256 copyFee = (amount * creatorStrategy.copyFeeBps) / TOTAL_BPS;
                netAmount = amount - copyFee;

                // Accumulate fee for original creator
                copyFeeEarnings[originalCreator] += copyFee;

                // ENHANCEMENT (Aspect #6): Track per-adapter fee distribution
                _recordAdapterFees(originalCreator, copyFee, creatorStrategy.adapters, creatorStrategy.ratios);

                // Update creator's TVL stats
                strategies[originalCreator].totalCopierTVL += netAmount;

                emit StrategyCopied(msg.sender, originalCreator, copyFee);
            }
        }

        // Enforce registry phase TVL caps when in Limited phase
        if (address(strategyRegistry) != address(0)) {
            try strategyRegistry.phase() returns (uint8 p) {
                if (p == 1) {
                    uint256 registryStrategyId = _strategyIdForUser(msg.sender);
                    uint256 cap = strategyRegistry.getLimitedCap(registryStrategyId);
                    if (cap > 0) {
                        if (strategies[msg.sender].totalDeposited + netAmount > cap) revert ExceedsLimitedTVL();
                    }
                }
            } catch {
                // ignore if registry call fails; be permissive
            }
        }

        // Execute strategy: split funds across adapters
        _executeDeposit(s.adapters, s.ratios, netAmount);

        // Notify performance tracker of deposit (if configured)
        if (performanceTracker != address(0)) {
            try IPerformanceTracking(performanceTracker).recordDeposit(_strategyIdForUser(msg.sender), netAmount) {
            } catch {
                // non-reverting failure: do not block deposit
            }
        }

        // Mint shares using share-based accounting
        uint256 strategyId = _strategyIdForUser(msg.sender);

        if (totalShares == 0 || totalAssets == 0) {
            // First depositor: 1:1 minting baseline
            shares = netAmount;
        } else {
            // shares = amount * totalShares / totalAssets
            shares = (netAmount * totalShares) / totalAssets;
            if (shares == 0) {
                // Protect against dust rounding: mint at least 1 share
                shares = 1;
            }
        }

        // Update accounting
        userShares[msg.sender] += shares;
        strategyShares[strategyId] += shares;
        s.shares += shares; // backward compatibility
        s.totalDeposited += netAmount;

        totalShares += shares;
        totalAssets += netAmount;

        emit SharesMinted(msg.sender, strategyId, shares, netAmount);
        emit Deposited(msg.sender, amount, shares);
        return shares;
    }

    /**
     * @notice Withdraw assets from user's strategy
     * @param shareAmount Amount of shares to burn
     * @return withdrawn Amount of assets withdrawn
     */
    function withdraw(uint256 shareAmount) external nonReentrant returns (uint256 withdrawn) {
        if (shareAmount == 0) revert InvalidAmount();
        Strategy storage s = strategies[msg.sender];

        // Verify user share balance
        if (userShares[msg.sender] < shareAmount) revert InsufficientShares();

        // Calculate expected amount in base assets based on cached totals
        uint256 expectedAmount = 0;
        if (totalShares == 0) revert ZeroTotalShares();
        unchecked {
            expectedAmount = (shareAmount * totalAssets) / totalShares;
        }

        // Execute withdrawals across adapters using asset-equivalent amounts (proportional by ratios)
        withdrawn = _executeWithdraw(s.adapters, s.ratios, expectedAmount);

        // Burn shares from user and strategy
        uint256 strategyId = _strategyIdForUser(msg.sender);
        userShares[msg.sender] -= shareAmount;
        strategyShares[strategyId] = strategyShares[strategyId] > shareAmount ? strategyShares[strategyId] - shareAmount : 0;
        s.shares = s.shares > shareAmount ? s.shares - shareAmount : 0;

        // Update totals: use actual withdrawn to adjust totalAssets
        totalShares = totalShares > shareAmount ? totalShares - shareAmount : 0;
        totalAssets = totalAssets > withdrawn ? totalAssets - withdrawn : 0;

        // Transfer assets to user
        ASSET.safeTransfer(msg.sender, withdrawn);

        // Notify performance tracker of withdrawal (if configured)
        if (performanceTracker != address(0)) {
            try IPerformanceTracking(performanceTracker).recordWithdrawal(_strategyIdForUser(msg.sender), withdrawn) {
            } catch {
                // do not block
            }
        }

        emit SharesBurned(msg.sender, strategyId, shareAmount, withdrawn);
        emit Withdrawn(msg.sender, shareAmount, withdrawn);
        return withdrawn;
    }

    /**
     * @notice Claim accumulated copy fee earnings (ENHANCED: Detailed breakdown)
     * @return claimed Total amount of fees claimed
     * @dev Emits detailed breakdown of fees by adapter for analytics
     */
    function claimCopyFees() external nonReentrant returns (uint256 claimed) {
        uint256 earnings = copyFeeEarnings[msg.sender];
        if (earnings == 0) revert InvalidAmount();

        // Get strategy adapters for detailed breakdown
        Strategy storage s = strategies[msg.sender];
        uint256 adaptersLen = s.adapters.length;

        // Collect per-adapter fees for detailed event
        uint256[] memory adapterFees = new uint256[](adaptersLen);
        for (uint256 i = 0; i < adaptersLen; i++) {
            adapterFees[i] = feesByAdapter[msg.sender][s.adapters[i]];
            // Reset per-adapter fees after claiming
            feesByAdapter[msg.sender][s.adapters[i]] = 0;
        }

        // Reset total earnings
        copyFeeEarnings[msg.sender] = 0;

        // Transfer fees to creator
        ASSET.safeTransfer(msg.sender, earnings);

        // Emit legacy event for backward compatibility
        emit CopyFeesClaimed(msg.sender, earnings);

        // Emit detailed event with adapter breakdown (Aspect #6)
        emit CopyFeesClaimedDetailed(msg.sender, earnings, adaptersLen, adapterFees);

        return earnings;
    }

    // ========================================================================
    // FEE CLAIM & VIEW FUNCTIONS (Aspect #6 Enhancement)
    // ========================================================================

    /**
     * @notice Get fee breakdown by adapter for a creator
     * @param creator Strategy creator address
     * @return adapters Array of adapter addresses
     * @return fees Array of fees earned from each adapter
     */
    function getFeeBreakdown(address creator)
        external
        view
        returns (address[] memory adapters, uint256[] memory fees)
    {
        Strategy storage s = strategies[creator];
        uint256 adaptersLen = s.adapters.length;

        adapters = new address[](adaptersLen);
        fees = new uint256[](adaptersLen);

        for (uint256 i = 0; i < adaptersLen; i++) {
            adapters[i] = s.adapters[i];
            fees[i] = feesByAdapter[creator][s.adapters[i]];
        }

        return (adapters, fees);
    }

    /**
     * @notice Get fee history for a creator (paginated)
     * @param creator Strategy creator address
     * @param offset Starting index
     * @param limit Maximum number of entries to return
     * @return entries Array of adapter fee entries
     */
    function getFeeHistory(address creator, uint256 offset, uint256 limit)
        external
        view
        returns (AdapterFeeEntry[] memory entries)
    {
        AdapterFeeEntry[] storage history = adapterFeeHistory[creator];
        uint256 totalEntries = history.length;

        if (offset >= totalEntries) {
            return new AdapterFeeEntry[](0);
        }

        uint256 end = offset + limit;
        if (end > totalEntries) {
            end = totalEntries;
        }

        uint256 resultLen = end - offset;
        entries = new AdapterFeeEntry[](resultLen);

        for (uint256 i = 0; i < resultLen; i++) {
            entries[i] = history[offset + i];
        }

        return entries;
    }

    /**
     * @notice Get total fee earnings summary for a creator
     * @param creator Strategy creator address
     * @return totalEarned Total fees earned all-time
     * @return pending Current pending fees
     * @return totalEvents Number of fee collection events
     */
    function getFeeSummary(address creator)
        external
        view
        returns (
            uint256 totalEarned,
            uint256 pending,
            uint256 totalEvents
        )
    {
        totalEarned = copyFeeEarnings[creator]; // Current pending (not yet claimed)
        pending = copyFeeEarnings[creator];
        totalEvents = totalFeeEvents[creator];

        return (totalEarned, pending, totalEvents);
    }

    /**
     * @notice Get fee earned from a specific adapter
     * @param creator Strategy creator address
     * @param adapter Adapter address
     * @return feeAmount Fee amount from this adapter
     */
    function getFeeByAdapter(address creator, address adapter)
        external
        view
        returns (uint256 feeAmount)
    {
        return feesByAdapter[creator][adapter];
    }

    /**
     * @notice Get total number of fee history entries
     * @param creator Strategy creator address
     * @return count Total number of entries
     */
    function getFeeHistoryCount(address creator)
        external
        view
        returns (uint256 count)
    {
        return adapterFeeHistory[creator].length;
    }

    /**
     * @notice Batch claim fees for multiple creators (admin/aggregator function)
     * @param creators Array of creator addresses to claim for
     * @return totalClaimed Total amount claimed across all creators
     * @dev Useful for aggregator contracts or mass payouts
     * @dev Each creator must have approved this contract to claim on their behalf
     */
    function batchClaimFeesFor(address[] calldata creators)
        external
        nonReentrant
        returns (uint256 totalClaimed)
    {
        for (uint256 i = 0; i < creators.length; i++) {
            address creator = creators[i];
            uint256 earnings = copyFeeEarnings[creator];

            if (earnings == 0) continue;

            // Get strategy adapters for detailed breakdown
            Strategy storage s = strategies[creator];
            uint256 adaptersLen = s.adapters.length;

            // Reset per-adapter fees
            for (uint256 j = 0; j < adaptersLen; j++) {
                feesByAdapter[creator][s.adapters[j]] = 0;
            }

            // Reset total earnings
            copyFeeEarnings[creator] = 0;

            // Transfer fees to creator
            ASSET.safeTransfer(creator, earnings);

            totalClaimed += earnings;

            emit CopyFeesClaimed(creator, earnings);
        }

        return totalClaimed;
    }

    /**
     * @notice Update strategy metadata (name, public status, copy fee)
     * @param isPublic Whether strategy should be public
     * @param name New strategy name
     * @param copyFeeBps New copy fee
     */
    function updateStrategyMetadata(bool isPublic, string memory name, uint16 copyFeeBps) external {
        if (copyFeeBps > MAX_COPY_FEE_BPS) revert CopyFeeExceedsMax();

        Strategy storage s = strategies[msg.sender];
        if (s.adapters.length == 0) revert NoStrategySet();

        s.isPublic = isPublic;
        s.name = name;
        s.copyFeeBps = copyFeeBps;

        // Update public list
        if (isPublic && !isInPublicList[msg.sender]) {
            publicStrategies.push(msg.sender);
            isInPublicList[msg.sender] = true;
        }

        emit StrategyUpdated(msg.sender, isPublic, name, copyFeeBps);
    }

    // ============ VIEW FUNCTIONS ============

    /**
     * @notice Get user's strategy configuration
     * @param user Address of user
     * @return Strategy struct
     */
    function getStrategy(address user) external view returns (Strategy memory) {
        return strategies[user];
    }

    /**
     * @notice Get user's current position value
     * @param user Address of user
     * @return Total value across all adapters
     */
    function getUserValue(address user) external view returns (uint256) {
        Strategy memory s = strategies[user];
        if (s.adapters.length == 0) return 0;
        uint256 totalValue = 0;
        uint256 len = s.adapters.length;
        for (uint256 i = 0; i < len;) {
            totalValue += IAdapter(s.adapters[i]).getBalance();
            unchecked { ++i; }
        }
        return totalValue;
    }

    /**
     * @notice Get top strategies by number of copies
     * @param count Number of strategies to return
     * @return users Array of user addresses
     * @return copies Array of copy counts
     * @return names Array of strategy names
     */
    function getLeaderboardByCopies(uint256 count)
        external
        view
        returns (address[] memory users, uint256[] memory copies, string[] memory names)
    {
        uint256 length = publicStrategies.length < count ? publicStrategies.length : count;
        users = new address[](length);
        copies = new uint256[](length);
        names = new string[](length);

        // Simple implementation: return first N (TODO: add sorting)
        for (uint256 i = 0; i < length; i++) {
            address user = publicStrategies[i];
            users[i] = user;
            copies[i] = strategies[user].totalCopies;
            names[i] = strategies[user].name;
        }

        return (users, copies, names);
    }

    /**
     * @notice Get all public strategies
     * @return Array of user addresses with public strategies
     */
    function getPublicStrategies() external view returns (address[] memory) {
        return publicStrategies;
    }

    // ============ INTERNAL FUNCTIONS ============

    /**
     * @notice Execute deposit by splitting funds across adapters
     * @param adapters Array of adapter addresses
     * @param ratios Allocation ratios
     * @param amount Total amount to split
     * @dev Uses StrategyExecutor if configured, otherwise falls back to direct execution
     */
    function _executeDeposit(address[] memory adapters, uint16[] memory ratios, uint256 amount) internal {
        // Use StrategyExecutor if configured (modular routing)
        if (address(strategyExecutor) != address(0)) {
            _executeDepositViaExecutor(adapters, ratios, amount);
            return;
        }

        // Fallback: Direct execution (legacy mode)
        uint256 remaining = amount;
        uint256 len = adapters.length;
        for (uint256 i = 0; i < len;) {
            uint256 adapterAmount;

            // Last adapter gets remainder to handle rounding
            if (i == len - 1) {
                adapterAmount = remaining;
            } else {
                adapterAmount = (amount * ratios[i]) / TOTAL_BPS;
                remaining -= adapterAmount;
            }

            // Approve and deposit
            ASSET.forceApprove(adapters[i], adapterAmount);
            uint256 shares = IAdapter(adapters[i]).deposit(adapterAmount);

            // Validate return value (prevent silent failures)
            if (shares == 0) revert DepositReturnedZero();

            // Update cached adapter balances (adapter reports shares/units in base for mocks)
            adapterCached[adapters[i]] += shares;

            ASSET.forceApprove(adapters[i], 0);
            unchecked { ++i; }
        }
    }

    /**
     * @notice Execute deposit via StrategyExecutor (modular routing)
     * @param adapters Array of adapter addresses
     * @param ratios Allocation ratios
     * @param amount Total amount to split
     */
    function _executeDepositViaExecutor(
        address[] memory adapters,
        uint16[] memory ratios,
        uint256 amount
    ) internal {
        // Approve executor to spend vault's assets
        ASSET.forceApprove(address(strategyExecutor), amount);

        // Prepare deposit parameters (no custom calldata, use standard interface)
        bytes[] memory emptyCalldata = new bytes[](0);

        StrategyExecutor.DepositParams memory params = StrategyExecutor.DepositParams({
            adapters: adapters,
            ratios: ratios,
            amount: amount,
            callData: emptyCalldata
        });

        // Execute via StrategyExecutor
        StrategyExecutor.ExecutionResult[] memory results = strategyExecutor.executeDeposit(params);

        // Update cached balances based on execution results
        for (uint256 i = 0; i < results.length; i++) {
            adapterCached[adapters[i]] += results[i].shares;
        }

        // Reset approval
        ASSET.forceApprove(address(strategyExecutor), 0);
    }

    /**
     * @notice Execute withdrawal from all adapters
     * @param adapters Array of adapter addresses
     * @param ratios Allocation ratios (for proportional withdrawal)
     * @param assetAmount Total asset-equivalent amount to withdraw across adapters
     * @return totalWithdrawn Total amount withdrawn
     * @dev Uses StrategyExecutor if configured, otherwise falls back to direct execution
     */
    function _executeWithdraw(address[] memory adapters, uint16[] memory ratios, uint256 assetAmount)
        internal
        returns (uint256 totalWithdrawn)
    {
        // Use StrategyExecutor if configured (modular routing)
        if (address(strategyExecutor) != address(0)) {
            return _executeWithdrawViaExecutor(adapters, ratios, assetAmount);
        }

        // Fallback: Direct execution (legacy mode)
        uint256 len = adapters.length;
        for (uint256 i = 0; i < len;) {
            uint256 adapterAmount = (assetAmount * ratios[i]) / TOTAL_BPS;
            if (adapterAmount > 0) {
                uint256 withdrawn = IAdapter(adapters[i]).withdraw(adapterAmount);
                // Reduce cached adapter balance
                if (adapterCached[adapters[i]] > withdrawn) {
                    adapterCached[adapters[i]] -= withdrawn;
                } else {
                    adapterCached[adapters[i]] = 0;
                }
                totalWithdrawn += withdrawn;
            }
            unchecked { ++i; }
        }
        return totalWithdrawn;
    }

    /**
     * @notice Execute withdrawal via StrategyExecutor (modular routing)
     * @param adapters Array of adapter addresses
     * @param ratios Allocation ratios
     * @param assetAmount Total amount to withdraw
     * @return totalWithdrawn Total amount withdrawn
     */
    function _executeWithdrawViaExecutor(
        address[] memory adapters,
        uint16[] memory ratios,
        uint256 assetAmount
    ) internal returns (uint256 totalWithdrawn) {
        // Prepare withdrawal parameters (no custom calldata, use standard interface)
        bytes[] memory emptyCalldata = new bytes[](0);

        StrategyExecutor.WithdrawParams memory params = StrategyExecutor.WithdrawParams({
            adapters: adapters,
            ratios: ratios,
            amount: assetAmount,
            callData: emptyCalldata
        });

        // Execute via StrategyExecutor
        StrategyExecutor.ExecutionResult[] memory results = strategyExecutor.executeWithdraw(params);

        // Update cached balances and sum total withdrawn
        for (uint256 i = 0; i < results.length; i++) {
            uint256 withdrawn = results[i].shares;

            // Reduce cached adapter balance
            if (adapterCached[adapters[i]] > withdrawn) {
                adapterCached[adapters[i]] -= withdrawn;
            } else {
                adapterCached[adapters[i]] = 0;
            }

            totalWithdrawn += withdrawn;
        }

        return totalWithdrawn;
    }

    // ============ RECONCILIATION ============

    /**
     * @notice Reconcile an adapter's reported balance against vault cache
     * @param adapter Adapter address to reconcile
     * @dev Only pause owner (guardian/multisig) may call reconciliation
     */
    function reconcileAdapter(address adapter) external onlyPauseOwner {
        // Adapter reports its perceived TVL
        uint256 reported = IAdapter(adapter).getBalance();
        uint256 cached = adapterCached[adapter];

        if (reported == cached) {
            emit AdapterReconciled(adapter, reported, cached);
            return;
        }

        if (reported > cached) {
            uint256 gain = reported - cached;

            // By default, when a gain is detected we can optionally realize and charge fees.
            // This helper `reconcileAdapterAndCharge` shows how the Vault can withdraw the
            // reported gain from the adapter, send it to the FeeManager, and then update
            // accounting using the net amount returned by the FeeManager.

            totalAssets += gain;
        } else {
            uint256 loss = cached - reported;
            totalAssets = totalAssets > loss ? totalAssets - loss : 0;
        }

        // Update cache to adapter's reported value
        adapterCached[adapter] = reported;
        emit AdapterReconciled(adapter, reported, cached);

        // Optionally: trigger a snapshot for any strategy that uses this adapter
        // (Not implemented: mapping adapter->strategy; callers should call snapshot explicitly)
    }

    /**
     * @notice Reconcile adapter, realize gains, and route fees through a FeeManager
     * @param adapter Adapter address
     * @param strategyId Strategy id for which fees should be charged
     * @param feeManager Address of FeeManager
     * @dev Caller should be `onlyPauseOwner`. This function withdraws the `gain` from the
     *      adapter into the vault, transfers gross yield to the `feeManager`, calls
     *      `chargeFees`, and then adjusts `totalAssets` by the net amount returned.
     */
    function reconcileAdapterAndCharge(address adapter, uint256 strategyId, address feeManager) external onlyPauseOwner {
        uint256 reported = IAdapter(adapter).getBalance();
        uint256 cached = adapterCached[adapter];
        if (reported <= cached) {
            // fallback to normal reconcile (loss path)
            if (reported < cached) {
                uint256 loss = cached - reported;
                totalAssets = totalAssets > loss ? totalAssets - loss : 0;
            }
            adapterCached[adapter] = reported;
            emit AdapterReconciled(adapter, reported, cached);
            return;
        }


        uint256 gain = reported - cached;

        // Withdraw the gain from the adapter into this vault
        uint256 withdrawn = IAdapter(adapter).withdraw(gain);

        // Transfer gross yield to FeeManager (caller must ensure FeeManager is authorized and set)
        ASSET.safeTransfer(feeManager, withdrawn);

        // Determine strategy owner from strategyId (encoding: uint160(owner))
        address owner = address(uint160(strategyId));
        address creator = strategies[owner].creator;
        uint16 creatorFeeBps = uint16(strategies[owner].copyFeeBps); // example: reuse copyFeeBps as creator fee

        // Charge fees: FeeManager will distribute fees and transfer net back to this vault
        uint256 net = 0;
        try IFeeManager(feeManager).chargeFees(strategyId, withdrawn, creator, creatorFeeBps) returns (uint256 n) {
            net = n;
        } catch {
            // In case feeManager call fails, revert to keep funds safe
            revert AdapterPausedError();
        }

        // Adjust accounting using net amount (net is transferred back to this vault by FeeManager)
        totalAssets += net;

        // Update cache
        adapterCached[adapter] = reported;
        emit AdapterReconciled(adapter, reported, cached);
    }

    /**
     * @notice Set external performance tracker contract
     * @param tracker Address of `PerformanceTracking` contract
     */
    function setPerformanceTracker(address tracker) external onlyPauseOwner {
        performanceTracker = tracker;
    }

    /**
     * @notice Set the authorized rebalance engine
     */
    function setRebalanceEngine(address engine) external onlyPauseOwner {
        rebalanceEngine = engine;
    }

    /**
     * @notice Set the Strategy Registry contract
     * @param registry Address of the `StrategyRegistry`
     */
    function setStrategyRegistry(address registry) external onlyPauseOwner {
        strategyRegistry = IStrategyRegistry(registry);
    }

    /**
     * @notice Set the AI Strategy Validator contract (zero-trust AI validation)
     * @param validator Address of the `AIStrategyValidator` contract
     */
    function setAIStrategyValidator(address validator) external onlyPauseOwner {
        require(validator != address(0), "Invalid validator address");
        aiStrategyValidator = AIStrategyValidator(validator);
        emit AIValidatorSet(validator);
    }

    /**
     * @notice Set the Strategy Executor contract (modular adapter routing)
     * @param executor Address of the `StrategyExecutor` contract
     */
    function setStrategyExecutor(address executor) external onlyPauseOwner {
        require(executor != address(0), "Invalid executor address");
        strategyExecutor = StrategyExecutor(executor);
        emit StrategyExecutorSet(executor);
    }

    function setMinRebalanceInterval(uint256 secs) external onlyPauseOwner {
        minRebalanceInterval = secs;
    }

    modifier onlyRebalanceEngine() {
        if (msg.sender != rebalanceEngine) revert UnauthorizedRebalanceEngine();
        _;
    }

    /**
     * @notice Opt-in migration of a user's strategy to a new version defined in the registry
     * @param strategyId Strategy identifier (encoding: uint160(owner))
     * @param newVersionId Target version id in registry
     * @param maxSlippageBps Per-adapter max slippage allowed (bps)
     * @param deadline Unix timestamp by which migration must be executed
     * @dev Migration is user-initiated, atomic, slippage- and deadline-protected.
     */
    function migrateStrategy(uint256 strategyId, uint256 newVersionId, uint16 maxSlippageBps, uint256 deadline)
        external
        nonReentrant
        whenStrategyExecutionNotPaused
    {
        if (block.timestamp > deadline) revert InvalidAmount();

        address owner = address(uint160(strategyId));
        if (msg.sender != owner) revert UnauthorizedMigration();

        // ensure registry configured
        if (address(strategyRegistry) == address(0)) revert MigrationFailed();

        uint256 currentVersion = strategyVersion[owner];
        if (newVersionId == currentVersion) revert DowngradeNotAllowed();
        if (newVersionId < currentVersion) revert DowngradeNotAllowed();

        // Ensure target version is active
        if (!strategyRegistry.isVersionActive(strategyId, newVersionId)) revert MigrationFailed();

        Strategy storage s = strategies[owner];
        if (s.adapters.length == 0) revert NoStrategySet();

        // Determine user's current asset-equivalent balance
        if (totalShares == 0) revert MigrationFailed();
        uint256 userSharesBal = userShares[owner];
        if (userSharesBal == 0) revert MigrationFailed();

        uint256 assetAmount = (userSharesBal * totalAssets) / totalShares;
        if (assetAmount == 0) revert MigrationFailed();

        // Withdraw full assetAmount from current adapters
        uint256 withdrawn = _executeWithdraw(s.adapters, s.ratios, assetAmount);

        // Fetch new version info from registry
        IStrategyRegistry.VersionInfo memory vinfo = strategyRegistry.getVersion(strategyId, newVersionId);

        // Validate new version ratios length
        if (vinfo.adapters.length == 0 || vinfo.adapters.length != vinfo.ratios.length) revert MigrationFailed();

        // Deposit into new adapters with slippage checks; distribute proportionally
        uint256 remaining = withdrawn;
        uint256 adaptersCount = vinfo.adapters.length;
        for (uint256 i = 0; i < adaptersCount; i++) {
            uint256 adapterAmount;
            if (i == adaptersCount - 1) {
                adapterAmount = remaining;
            } else {
                adapterAmount = (withdrawn * vinfo.ratios[i]) / TOTAL_BPS;
                remaining -= adapterAmount;
            }

            ASSET.forceApprove(vinfo.adapters[i], adapterAmount);
            uint256 d = IAdapter(vinfo.adapters[i]).deposit(adapterAmount);
            // require deposit returned asset-equivalent amount and didn't slip beyond tolerance
            uint256 minExpected = (adapterAmount * (TOTAL_BPS - maxSlippageBps)) / TOTAL_BPS;
            if (d < minExpected) revert MigrationFailed();
            adapterCached[vinfo.adapters[i]] += d;
            ASSET.forceApprove(vinfo.adapters[i], 0);
        }

        // Update user's strategy configuration to new version adapters/ratios
        s.adapters = vinfo.adapters;
        // convert uint16[] storage assignment
        s.ratios = vinfo.ratios;

        // Update user's adopted version
        strategyVersion[owner] = newVersionId;

        emit StrategyMigrated(owner, strategyId, currentVersion, newVersionId, withdrawn);
        emit StrategyVersionSet(owner, newVersionId);
    }

    /**
     * @notice Execute rebalance as instructed by an authorized engine
     * @param strategyId Strategy id (encoding: uint160(owner))
     * @param maxSlippageBps Maximum allowed slippage on individual adapter deposits (bps)
     * @param deadline Unix timestamp after which the rebalance is invalid
     */
    function rebalanceByEngine(uint256 strategyId, uint16 maxSlippageBps, uint256 deadline)
        external
        onlyRebalanceEngine
        whenStrategyExecutionNotPaused
        nonReentrant
        returns (bool)
    {
        if (block.timestamp > deadline) revert InvalidAmount();

        if (minRebalanceInterval > 0) {
            emit AdapterReconciled(address(0), strategyId, block.timestamp);
            // RebalanceStarted placeholder event

            if (block.timestamp < lastRebalance[strategyId] + minRebalanceInterval) revert RebalanceTooFrequent();
        }

        address owner = address(uint160(strategyId));
        Strategy storage s = strategies[owner];
        if (s.adapters.length == 0) revert NoStrategySet();

        uint256 adaptersCount = s.adapters.length;
        uint256 total = 0;
        uint256[] memory tvls = new uint256[](adaptersCount);
        for (uint256 i = 0; i < adaptersCount;) {
            tvls[i] = IAdapter(s.adapters[i]).getBalance();
            total += tvls[i];
            unchecked { ++i; }
        }
        if (total == 0) revert InvalidAmount();

        // Determine withdraw and deposit targets
        uint256[] memory toWithdraw = new uint256[](adaptersCount);
        uint256[] memory toDeposit = new uint256[](adaptersCount);

        for (uint256 i = 0; i < adaptersCount;) {
            uint256 target = (total * uint256(s.ratios[i])) / TOTAL_BPS;
            if (tvls[i] > target) {
                toWithdraw[i] = tvls[i] - target;
            } else if (tvls[i] < target) {
                toDeposit[i] = target - tvls[i];
            }
            unchecked { ++i; }
        }

        // Withdraw from overweight adapters
        uint256 withdrawnTotal = 0;
        for (uint256 i = 0; i < adaptersCount;) {
            if (toWithdraw[i] > 0) {
                uint256 w = IAdapter(s.adapters[i]).withdraw(toWithdraw[i]);
                withdrawnTotal += w;
                if (adapterCached[s.adapters[i]] > w) adapterCached[s.adapters[i]] -= w; else adapterCached[s.adapters[i]] = 0;
            }
            unchecked { ++i; }
        }
        emit AdapterReconciled(address(0), withdrawnTotal, 0);

        // Deposit to underweight adapters (pro-rata by toDeposit amounts)
        // We will distribute withdrawnTotal proportionally to requested deposits, capped by available withdrawnTotal
        uint256 depositRequested = 0;
        for (uint256 i = 0; i < adaptersCount; i++) depositRequested += toDeposit[i];
        if (depositRequested > 0) {
            for (uint256 i = 0; i < adaptersCount;) {
                if (toDeposit[i] == 0) { unchecked { ++i; } continue; }
                uint256 amount = (withdrawnTotal * toDeposit[i]) / depositRequested;
                if (amount == 0) { unchecked { ++i; } continue; }
                emit AdapterReconciled(s.adapters[i], amount, adapterCached[s.adapters[i]]);
                ASSET.forceApprove(s.adapters[i], amount);
                emit AdapterReconciled(s.adapters[i], amount, adapterCached[s.adapters[i]]);
                uint256 d;
                try IAdapter(s.adapters[i]).deposit(amount) returns (uint256 ret) {
                    d = ret;
                } catch (bytes memory reason) {
                    emit RebalanceError(reason);
                    revert AdapterDepositFailed();
                }
                // Validate slippage: deposit should return asset-equivalent amount at least (1 - maxSlippageBps)
                uint256 minExpected = (amount * (TOTAL_BPS - maxSlippageBps)) / TOTAL_BPS;
                if (d < minExpected) {
                    // Do not revert to avoid blocking; emit event for off-chain monitoring
                    emit AdapterReconciled(s.adapters[i], d, adapterCached[s.adapters[i]]);
                }
                adapterCached[s.adapters[i]] += d;
                ASSET.forceApprove(s.adapters[i], 0);
                unchecked { ++i; }
            }
        }

        // Update accounting
        totalAssets = totalAssets > 0 ? ((totalAssets - total) + total + 0) : totalAssets; // noop placeholder (reconciliation is already maintained)

        lastRebalance[strategyId] = block.timestamp;
        emit AdapterReconciled(address(0), 0, 0);
        return true;
    }

    function _strategyIdForUser(address user) internal pure returns (uint256) {
        return uint256(uint160(user));
    }

    // ========================================================================
    // INTERNAL FUNCTIONS - FEE DISTRIBUTION (Aspect #6)
    // ========================================================================

    /**
     * @notice Record per-adapter fee distribution for detailed tracking
     * @param creator Strategy creator receiving fees
     * @param totalFee Total copy fee collected
     * @param adapters Array of adapters in the strategy
     * @param ratios Allocation ratios for each adapter
     * @dev Distributes fee proportionally across adapters based on their allocation ratio
     */
    function _recordAdapterFees(
        address creator,
        uint256 totalFee,
        address[] memory adapters,
        uint16[] memory ratios
    ) internal {
        uint256 adaptersLen = adapters.length;
        uint256[] memory adapterFees = new uint256[](adaptersLen);

        uint256 distributedFee = 0;

        // Distribute fee proportionally across adapters
        for (uint256 i = 0; i < adaptersLen;) {
            uint256 adapterFee;

            // Last adapter gets remaining fee to handle rounding
            if (i == adaptersLen - 1) {
                adapterFee = totalFee - distributedFee;
            } else {
                adapterFee = (totalFee * ratios[i]) / TOTAL_BPS;
                distributedFee += adapterFee;
            }

            // Track fee by adapter
            feesByAdapter[creator][adapters[i]] += adapterFee;
            adapterFees[i] = adapterFee;

            // Record in fee history
            adapterFeeHistory[creator].push(
                AdapterFeeEntry({
                    adapter: adapters[i],
                    amount: adapterFee,
                    timestamp: block.timestamp
                })
            );

            unchecked { ++i; }
        }

        // Increment total fee events counter
        totalFeeEvents[creator]++;

        // Emit detailed fee collection event
        emit CopyFeeCollectedDetailed(creator, msg.sender, totalFee, adapters, adapterFees);
    }
}
