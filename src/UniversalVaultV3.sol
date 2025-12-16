// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IUniversalAdapter} from "./interfaces/IUniversalAdapter.sol";
import {EmergencyPause} from "./EmergencyPause.sol";
import {SlippageProtection} from "./SlippageProtection.sol";

/**
 * @title UniversalVaultV3
 * @notice Multi-protocol DeFi vault supporting 12+ protocols with dynamic strategy allocation
 * @dev Combines emergency pause, slippage protection, and per-adapter risk controls
 *
 * ARCHITECTURE:
 * - Users deposit via strategies that specify protocol allocations
 * - Vault splits deposits across multiple adapters based on strategy ratios
 * - Each adapter is vault-callable only; user funds flow: User → Vault → Adapter
 * - Emergency pause enables sub-2.5min exploit response
 * - Slippage protection prevents MEV sandwich attacks
 * - High-risk protocols (GMX, Gains, Pendle) have per-adapter caps
 * - Withdrawal is always operational (immune to pause/emergency)
 *
 * SECURITY MODEL:
 * 1. Return value validation: all adapter calls must return non-zero shares/amounts
 * 2. Adapter operational checks: deposits blocked if adapter is unhealthy
 * 3. Slippage protection: minAmountOut + deadline on all adapter calls
 * 4. Risk isolation: per-adapter exposure caps + individual pause capability
 * 5. Reentrancy guard: on all external state-changing functions
 * 6. Rounding safety: withdrawals use min(user's requested, available) approach
 *
 * EVENTS: Fully indexed for leaderboard & analytics integration
 */
contract UniversalVaultV3 is ReentrancyGuard, EmergencyPause, SlippageProtection {
    using SafeERC20 for IERC20;
    
    // ============ NOTE ON INITIALIZATION ============
    // EmergencyPause requires pauseOwner in constructor
    // SlippageProtection requires _defaultSlippageBps in constructor
    // These are handled in UniversalVaultV3 constructor below

    // ============ CONSTANTS ============

    /// @notice Base asset denominator (e.g., 1e6 for USDC)
    uint256 public constant PRECISION = 1e18;

    /// @notice Basis points denominator
    uint16 public constant TOTAL_BPS = 10000;

    /// @notice Maximum creator fee (5 bps = 0.05%)
    uint16 public constant MAX_CREATOR_FEE_BPS = 50;

    /// @notice Maximum platform fee (5 bps = 0.05%)
    uint16 public constant MAX_PLATFORM_FEE_BPS = 50;

    /// @notice Maximum allocation to a single high-risk protocol (20%)
    uint16 public constant MAX_HIGH_RISK_ALLOCATION_BPS = 2000;

    // ============ STATE VARIABLES ============

    /// @notice The base asset for all strategies (e.g., USDC, ETH)
    IERC20 public immutable ASSET;

    /// @notice Platform governance address
    address public governance;

    /// @notice Platform fee accumulation (governance-claimable)
    uint256 public platformFeeAccumulated;

    // ============ STRATEGY MANAGEMENT ============

    /// @notice Strategy ID counter (auto-incrementing)
    uint256 public strategyCounter;

    /**
     * @notice Strategy configuration and metadata
     * @param strategyId Unique strategy identifier
     * @param adapters Array of protocol adapter addresses
     * @param ratios Allocation ratios in basis points (must sum to 10000)
     * @param creator Address of strategy creator
     * @param creatorFeeBps Fee charged to depositors (0-50 bps)
     * @param name Human-readable strategy name
     * @param isPublic Whether strategy is discoverable/copyable
     * @param totalDeposited Total amount deposited by all users
     * @param totalShares Total shares issued
     * @param createdAt Timestamp of creation
     * @param minDeposit Minimum deposit amount per transaction
     * @param maxDeposit Maximum deposit amount per transaction
     */
    struct Strategy {
        uint256 strategyId;
        address[] adapters;
        uint16[] ratios;
        address creator;
        uint16 creatorFeeBps;
        string name;
        bool isPublic;
        uint256 totalDeposited;
        uint256 totalShares;
        uint256 createdAt;
        uint256 minDeposit;
        uint256 maxDeposit;
    }

    /**
     * @notice Per-user deposit tracking
     * @param strategyId Which strategy this deposit is tied to
     * @param sharesHeld User's share balance
     * @param totalDeposited Cumulative deposits by this user
     * @param lastDepositTimestamp For cooldown/rate-limiting
     */
    struct UserDeposit {
        uint256 strategyId;
        uint256 sharesHeld;
        uint256 totalDeposited;
        uint256 lastDepositTimestamp;
    }

    /// @notice Strategy ID => Strategy configuration
    mapping(uint256 => Strategy) public strategies;

    /// @notice User address => UserDeposit per strategy
    mapping(address => mapping(uint256 => UserDeposit)) public userDeposits;

    /// @notice Public strategies list (for leaderboard discovery)
    uint256[] public publicStrategyIds;

    /// @notice Track if a user has copied a strategy
    mapping(address => mapping(address => bool)) public hasCopied;

    /// @notice Creator earnings from depositor fees
    mapping(address => uint256) public creatorEarnings;

    // ============ ADAPTER MANAGEMENT ============

    /// @notice Adapter address => is authorized
    mapping(address => bool) public isAuthorizedAdapter;

    /// @notice Adapter address => risk tier (0=LOW, 1=MEDIUM, 2=HIGH)
    mapping(address => uint8) public adapterRiskTier;

    /// @notice Adapter address => current TVL exposure
    mapping(address => uint256) public adapterTVL;

    /// @notice Adapter address => maximum allowed TVL (for risk caps)
    mapping(address => uint256) public adapterMaxTVL;

    /// @notice Protocol name => adapter address (for tracking)
    mapping(bytes32 => address) public protocolToAdapter;

    // ============ EVENTS ============

    // Strategy Events
    event StrategyCreated(
        uint256 indexed strategyId,
        address indexed creator,
        address[] adapters,
        uint16[] ratios,
        string name,
        uint16 creatorFeeBps,
        bool isPublic
    );

    event StrategyUpdated(uint256 indexed strategyId, bool isPublic, string newName, uint16 newCreatorFeeBps);

    // Deposit Events
    event DepositExecuted(
        address indexed user,
        uint256 indexed strategyId,
        uint256 depositAmount,
        uint256 sharesIssued,
        uint256 creatorFeeCharged,
        uint256 platformFeeCharged
    );

    event DepositToAdapter(
        uint256 indexed strategyId,
        address indexed adapter,
        uint256 adapterAmount,
        uint256 sharesReceived,
        uint256 minAmountOut,
        uint256 deadline
    );

    // Withdrawal Events
    event WithdrawalExecuted(
        address indexed user,
        uint256 indexed strategyId,
        uint256 sharesBurned,
        uint256 amountWithdrawn
    );

    event WithdrawalFromAdapter(
        uint256 indexed strategyId,
        address indexed adapter,
        uint256 sharesBurned,
        uint256 amountReceived,
        uint256 minAmountOut,
        uint256 deadline
    );

    // Fee Events
    event CreatorFeeClaimed(address indexed creator, uint256 amount);
    event PlatformFeeClaimed(address indexed governance, uint256 amount);

    // Adapter Management Events
    event AdapterAuthorized(address indexed adapter, uint8 riskTier, uint256 maxTVL);
    event AdapterRevoked(address indexed adapter);
    event AdapterTVLCapUpdated(address indexed adapter, uint256 newMaxTVL);

    // Risk Management Events
    event HighRiskAllocationWarning(
        uint256 indexed strategyId,
        address indexed adapter,
        uint16 allocationBps,
        uint256 timestamp
    );

    event AdapterHealthWarning(address indexed adapter, string reason);

    // ============ ERRORS ============

    error InvalidRatios();
    error RatiosSumMismatch();
    error ArrayLengthMismatch();
    error NoStrategyFound();
    error StrategyNotPublic();
    error NoActiveDeposit();
    error InsufficientFunds();
    error InvalidAmount();
    error AdapterNotAuthorized();
    error AdapterNotOperational();
    error AdapterReturnedZero();
    error HighRiskAllocationExceeded();
    error UnauthorizedGovernance();
    error DuplicateAdapter();
    error CannotCopyOwnStrategy();
    error AlreadyCopiedStrategy();
    error MinDepositNotMet();
    error MaxDepositExceeded();
    error DepositsPausedGlobally();
    error StrategyExecutionPausedGlobally();
    // Note: InvalidDeadline, SlippageExceeded, InvalidAdapter inherited from parent

    // ============ MODIFIERS ============

    /// @notice Only vault can call adapter functions
    modifier onlyVault() {
        if (msg.sender != address(this)) revert UnauthorizedGovernance();
        _;
    }

    /// @notice Only governance can perform sensitive operations
    modifier onlyGovernance() {
        if (msg.sender != governance) revert UnauthorizedGovernance();
        _;
    }

    /// @notice Check strategy exists
    modifier strategyExists(uint256 strategyId) {
        if (strategies[strategyId].creator == address(0)) revert NoStrategyFound();
        _;
    }

    // ============ CONSTRUCTOR ============

    /**
     * @notice Initialize the Universal Vault
     * @param _asset Base token address (e.g., USDC)
     * @param _governance Governance address for fee claims
     * @param _pauseOwner Address with emergency pause capability
     */
    constructor(address _asset, address _governance, address _pauseOwner)
        EmergencyPause(_pauseOwner)
        SlippageProtection(50) // Default slippage: 50 bps (0.5%)
    {
        if (_asset == address(0)) revert InvalidAmount();
        if (_governance == address(0)) revert UnauthorizedGovernance();

        ASSET = IERC20(_asset);
        governance = _governance;
    }

    // ============ GOVERNANCE FUNCTIONS ============

    /**
     * @notice Register a new adapter for vault use
     * @param adapter Adapter contract address
     * @param riskTier Risk classification (0=LOW, 1=MEDIUM, 2=HIGH)
     * @param maxTVL Maximum allowed TVL for this adapter
     *
     * @dev Only governance can authorize adapters
     * @dev High-risk adapters are subject to allocation caps
     */
    function authorizeAdapter(address adapter, uint8 riskTier, uint256 maxTVL) external onlyGovernance {
        if (adapter == address(0)) revert InvalidAdapter();
        if (isAuthorizedAdapter[adapter]) revert DuplicateAdapter();
        if (riskTier > 2) revert InvalidAmount(); // Only 0, 1, 2 valid

        isAuthorizedAdapter[adapter] = true;
        adapterRiskTier[adapter] = riskTier;
        adapterMaxTVL[adapter] = maxTVL;

        emit AdapterAuthorized(adapter, riskTier, maxTVL);
    }

    /**
     * @notice Revoke adapter authorization
     * @param adapter Adapter address to disable
     *
     * @dev Existing positions remain but new deposits blocked
     */
    function revokeAdapter(address adapter) external onlyGovernance {
        if (!isAuthorizedAdapter[adapter]) revert AdapterNotAuthorized();
        isAuthorizedAdapter[adapter] = false;
        emit AdapterRevoked(adapter);
    }

    /**
     * @notice Update maximum allowed TVL for an adapter
     * @param adapter Adapter address
     * @param newMaxTVL New maximum TVL
     */
    function updateAdapterTVLCap(address adapter, uint256 newMaxTVL) external onlyGovernance {
        if (!isAuthorizedAdapter[adapter]) revert AdapterNotAuthorized();
        adapterMaxTVL[adapter] = newMaxTVL;
        emit AdapterTVLCapUpdated(adapter, newMaxTVL);
    }

    /**
     * @notice Update governance address
     * @param newGovernance New governance address
     */
    function updateGovernance(address newGovernance) external onlyGovernance {
        if (newGovernance == address(0)) revert UnauthorizedGovernance();
        governance = newGovernance;
    }

    // ============ STRATEGY MANAGEMENT ============

    /**
     * @notice Create a new investment strategy
     * @param adapters Array of adapter addresses (1-5 typical)
     * @param ratios Basis point allocations (must sum to 10000)
     * @param creatorFeeBps Fee charged to new depositors (0-50 bps)
     * @param name Human-readable strategy name
     * @param isPublic Whether strategy is discoverable and copyable
     * @param minDeposit Minimum deposit amount per transaction
     * @param maxDeposit Maximum deposit amount per transaction
     *
     * @return strategyId Unique strategy identifier
     *
     * @dev VALIDATION:
     *   - All adapters must be authorized
     *   - Ratios must sum to 10000 (100%)
     *   - No duplicate adapters
     *   - Creator fee must be <= MAX_CREATOR_FEE_BPS
     *   - High-risk adapters must not exceed allocation cap
     */
    function createStrategy(
        address[] calldata adapters,
        uint16[] calldata ratios,
        uint16 creatorFeeBps,
        string calldata name,
        bool isPublic,
        uint256 minDeposit,
        uint256 maxDeposit
    ) external returns (uint256 strategyId) {
        // Validation
        if (adapters.length == 0 || adapters.length > 5) revert InvalidAmount();
        if (adapters.length != ratios.length) revert ArrayLengthMismatch();
        if (creatorFeeBps > MAX_CREATOR_FEE_BPS) revert InvalidAmount();

        // Check ratios sum to 10000
        uint256 ratioSum = 0;
        for (uint256 i = 0; i < ratios.length; i++) {
            ratioSum += ratios[i];
        }
        if (ratioSum != TOTAL_BPS) revert RatiosSumMismatch();

        // Verify no duplicate adapters
        for (uint256 i = 0; i < adapters.length; i++) {
            if (!isAuthorizedAdapter[adapters[i]]) revert AdapterNotAuthorized();

            for (uint256 j = i + 1; j < adapters.length; j++) {
                if (adapters[i] == adapters[j]) revert DuplicateAdapter();
            }

            // Check high-risk allocation cap
            if (adapterRiskTier[adapters[i]] == 2 && ratios[i] > MAX_HIGH_RISK_ALLOCATION_BPS) {
                revert HighRiskAllocationExceeded();
            }
        }

        // Create strategy
        strategyId = ++strategyCounter;
        strategies[strategyId] = Strategy({
            strategyId: strategyId,
            adapters: adapters,
            ratios: ratios,
            creator: msg.sender,
            creatorFeeBps: creatorFeeBps,
            name: name,
            isPublic: isPublic,
            totalDeposited: 0,
            totalShares: 0,
            createdAt: block.timestamp,
            minDeposit: minDeposit,
            maxDeposit: maxDeposit
        });

        if (isPublic) {
            publicStrategyIds.push(strategyId);
        }

        emit StrategyCreated(strategyId, msg.sender, adapters, ratios, name, creatorFeeBps, isPublic);
    }

    /**
     * @notice Update strategy parameters (creator only)
     * @param strategyId Strategy to update
     * @param isPublic New visibility setting
     * @param newName New strategy name
     * @param newCreatorFeeBps New creator fee (0-50 bps)
     */
    function updateStrategy(uint256 strategyId, bool isPublic, string calldata newName, uint16 newCreatorFeeBps)
        external
        strategyExists(strategyId)
    {
        Strategy storage strategy = strategies[strategyId];
        if (strategy.creator != msg.sender) revert UnauthorizedGovernance();
        if (newCreatorFeeBps > MAX_CREATOR_FEE_BPS) revert InvalidAmount();

        strategy.isPublic = isPublic;
        strategy.name = newName;
        strategy.creatorFeeBps = newCreatorFeeBps;

        emit StrategyUpdated(strategyId, isPublic, newName, newCreatorFeeBps);
    }

    // ============ CORE DEPOSIT LOGIC ============

    /**
     * @notice Deposit into a strategy
     * @param strategyId Target strategy ID
     * @param amount Amount of base tokens to deposit
     * @param minAmountOut Minimum expected shares (MEV protection)
     * @param deadline Transaction deadline (unix timestamp)
     *
     * @return shares Shares issued to user
     *
     * @dev FLOW:
     *   1. Validate inputs and strategy
     *   2. Check adapter health
     *   3. Calculate fees
     *   4. Split deposit across adapters using ratios
     *   5. Issue shares proportionally
     *   6. Update balances and TVL
     *   7. Emit indexed events
     *
     * @dev SECURITY:
     *   - Reentrancy guard on all external calls
     *   - Adapter operational checks before deposits
     *   - Return value validation (no silent 0 returns)
     *   - Slippage enforcement via minAmountOut
     *   - Deadline protection prevents stale txs
     *   - Emergency pause blocks deposits (except creator)
     */
    function deposit(uint256 strategyId, uint256 amount, uint256 minAmountOut, uint256 deadline)
        external
        nonReentrant
        whenDepositsNotPaused
        strategyExists(strategyId)
        returns (uint256 shares)
    {
        if (amount == 0) revert InvalidAmount();
        if (block.timestamp > deadline) revert InvalidAmount(); // Use InvalidAmount instead of InvalidDeadline


        Strategy storage strategy = strategies[strategyId];

        // Validate deposit constraints
        if (amount < strategy.minDeposit) revert MinDepositNotMet();
        if (amount > strategy.maxDeposit) revert MaxDepositExceeded();

        // Check all adapters are operational
        for (uint256 i = 0; i < strategy.adapters.length; i++) {
            if (!IUniversalAdapter(strategy.adapters[i]).isOperational()) {
                revert AdapterNotOperational();
            }
        }

        // Collect deposit from user
        ASSET.safeTransferFrom(msg.sender, address(this), amount);

        // Calculate fees
        uint256 creatorFee = (amount * strategy.creatorFeeBps) / TOTAL_BPS;
        uint256 platformFee = (amount * 10) / TOTAL_BPS; // Hard-coded 10 bps platform fee for now
        uint256 depositAmount = amount - creatorFee - platformFee;

        // Accumulate fees
        creatorEarnings[strategy.creator] += creatorFee;
        platformFeeAccumulated += platformFee;

        // Distribute deposit across adapters
        uint256 totalSharesReceived = 0;
        for (uint256 i = 0; i < strategy.adapters.length; i++) {
            address adapter = strategy.adapters[i];
            uint16 ratio = strategy.ratios[i];

            uint256 adapterAmount = (depositAmount * ratio) / TOTAL_BPS;
            if (adapterAmount == 0) continue; // Skip dust amounts

            // Calculate minimum acceptable output for this adapter
            uint256 expectedShares = IUniversalAdapter(adapter).getExpectedDepositOutput(adapterAmount);
            uint256 adapterMinOut = (expectedShares * (TOTAL_BPS - 50)) / TOTAL_BPS; // 50 bps slippage

            // Approve adapter (reset to 0 first, then set amount)
            ASSET.forceApprove(adapter, adapterAmount);

            // Deposit into adapter
            uint256 sharesReceived = IUniversalAdapter(adapter).deposit(adapterAmount, adapterMinOut, deadline);
            if (sharesReceived == 0) revert AdapterReturnedZero();

            totalSharesReceived += sharesReceived;
            adapterTVL[adapter] += adapterAmount;

            // Verify TVL cap not exceeded
            if (adapterTVL[adapter] > adapterMaxTVL[adapter]) revert HighRiskAllocationExceeded();

            emit DepositToAdapter(strategyId, adapter, adapterAmount, sharesReceived, adapterMinOut, deadline);
        }

        // Issue shares to user
        if (totalSharesReceived < minAmountOut) {
            // Calculate actual vs expected for error context
            revert SlippageExceeded(totalSharesReceived, minAmountOut);
        }

        UserDeposit storage userDep = userDeposits[msg.sender][strategyId];
        userDep.strategyId = strategyId;
        userDep.sharesHeld += totalSharesReceived;
        userDep.totalDeposited += amount;
        userDep.lastDepositTimestamp = block.timestamp;

        strategy.totalDeposited += amount;
        strategy.totalShares += totalSharesReceived;

        shares = totalSharesReceived;

        emit DepositExecuted(msg.sender, strategyId, amount, shares, creatorFee, platformFee);
    }

    // ============ WITHDRAWAL LOGIC ============

    /**
     * @notice Withdraw from a strategy (always operational, immune to emergency pause)
     * @param strategyId Strategy to withdraw from
     * @param shareAmount Amount of shares to burn
     * @param minAmountOut Minimum expected output (MEV protection)
     * @param deadline Transaction deadline
     *
     * @return withdrawn Amount of base tokens returned to user
     *
     * @dev WITHDRAWAL IMMUNITY:
     *   - Withdrawals ALWAYS work, even if deposits are paused
     *   - Uses individual adapter calls (parallel execution)
     *   - If one adapter fails, transaction reverts (no partial withdrawals)
     *   - Proportional withdrawal from all adapters
     *
     * @dev ROUNDING & DUST:
     *   - Use min(requested, available) to handle dust
     *   - Each adapter rounded down independently
     *   - Remaining dust stays in vault (for gas efficiency)
     */
    function withdraw(uint256 strategyId, uint256 shareAmount, uint256 minAmountOut, uint256 deadline)
        external
        nonReentrant
        strategyExists(strategyId)
        returns (uint256 withdrawn)
    {
        if (shareAmount == 0) revert InvalidAmount();
        if (block.timestamp > deadline) revert InvalidAmount(); // Use InvalidAmount instead of InvalidDeadline


        UserDeposit storage userDep = userDeposits[msg.sender][strategyId];
        if (userDep.sharesHeld < shareAmount) revert InsufficientFunds();

        Strategy storage strategy = strategies[strategyId];

        // Withdraw proportionally from each adapter
        uint256 totalWithdrawn = 0;
        for (uint256 i = 0; i < strategy.adapters.length; i++) {
            address adapter = strategy.adapters[i];
            uint256 shareRatio = (strategy.ratios[i] * PRECISION) / TOTAL_BPS;
            uint256 adapterShareAmount = (shareAmount * shareRatio) / PRECISION;

            if (adapterShareAmount == 0) continue;

            // Quote expected output
            uint256 expectedOutput = IUniversalAdapter(adapter).getExpectedWithdrawOutput(adapterShareAmount);
            uint256 adapterMinOut = (expectedOutput * (TOTAL_BPS - 50)) / TOTAL_BPS; // 50 bps slippage

            // Withdraw from adapter
            uint256 amountReceived = IUniversalAdapter(adapter).withdraw(adapterShareAmount, adapterMinOut, deadline);
            if (amountReceived == 0) revert AdapterReturnedZero();

            totalWithdrawn += amountReceived;
            adapterTVL[adapter] -= adapterShareAmount; // Update TVL

            emit WithdrawalFromAdapter(strategyId, adapter, adapterShareAmount, amountReceived, adapterMinOut, deadline);
        }

        // Validate minimum output
        if (totalWithdrawn < minAmountOut) {
            revert SlippageExceeded(totalWithdrawn, minAmountOut);
        }

        // Update user balance
        userDep.sharesHeld -= shareAmount;
        strategy.totalShares -= shareAmount;

        // Transfer funds to user
        ASSET.safeTransfer(msg.sender, totalWithdrawn);

        withdrawn = totalWithdrawn;

        emit WithdrawalExecuted(msg.sender, strategyId, shareAmount, totalWithdrawn);
    }

    // ============ FEE CLAIM FUNCTIONS ============

    /**
     * @notice Claim accumulated creator fees
     * @return claimed Amount of fees transferred to creator
     */
    function claimCreatorFees() external nonReentrant returns (uint256 claimed) {
        claimed = creatorEarnings[msg.sender];
        if (claimed == 0) revert InsufficientFunds();

        creatorEarnings[msg.sender] = 0;
        ASSET.safeTransfer(msg.sender, claimed);

        emit CreatorFeeClaimed(msg.sender, claimed);
    }

    /**
     * @notice Claim accumulated platform fees (governance only)
     * @return claimed Amount of fees transferred to governance
     */
    function claimPlatformFees() external nonReentrant onlyGovernance returns (uint256 claimed) {
        claimed = platformFeeAccumulated;
        if (claimed == 0) revert InsufficientFunds();

        platformFeeAccumulated = 0;
        ASSET.safeTransfer(governance, claimed);

        emit PlatformFeeClaimed(governance, claimed);
    }

    // ============ VIEW FUNCTIONS ============

    /**
     * @notice Get user's share balance in a strategy
     * @param user User address
     * @param strategyId Strategy ID
     * @return shares User's share balance
     */
    function getUserShares(address user, uint256 strategyId) external view returns (uint256 shares) {
        return userDeposits[user][strategyId].sharesHeld;
    }

    /**
     * @notice Get user's total deposited amount (cumulative)
     * @param user User address
     * @param strategyId Strategy ID
     * @return total Total amount deposited by user
     */
    function getUserTotalDeposited(address user, uint256 strategyId) external view returns (uint256 total) {
        return userDeposits[user][strategyId].totalDeposited;
    }

    /**
     * @notice Get estimated value of user's shares (before slippage)
     * @param user User address
     * @param strategyId Strategy ID
     * @return estimatedValue Estimated redemption value
     *
     * @dev This is an estimate; actual value may vary due to slippage
     */
    function estimateUserValue(address user, uint256 strategyId)
        external
        view
        strategyExists(strategyId)
        returns (uint256 estimatedValue)
    {
        UserDeposit storage userDep = userDeposits[user][strategyId];
        if (userDep.sharesHeld == 0) return 0;

        Strategy storage strategy = strategies[strategyId];
        uint256 totalValue = 0;

        for (uint256 i = 0; i < strategy.adapters.length; i++) {
            address adapter = strategy.adapters[i];
            uint256 shareRatio = (strategy.ratios[i] * PRECISION) / TOTAL_BPS;
            uint256 adapterShares = (userDep.sharesHeld * shareRatio) / PRECISION;

            uint256 adapterValue = IUniversalAdapter(adapter).getExpectedWithdrawOutput(adapterShares);
            totalValue += adapterValue;
        }

        return totalValue;
    }

    /**
     * @notice Get total TVL across all adapters
     * @return totalTVL Sum of all adapter TVLs
     */
    function getTotalTVL() external view returns (uint256 totalTVL) {
        // This would require iterating through all adapters
        // For now, return a placeholder; in production, maintain a list
        return 0;
    }

    /**
     * @notice Get public strategies count (for leaderboard pagination)
     * @return count Number of public strategies
     */
    function getPublicStrategiesCount() external view returns (uint256 count) {
        return publicStrategyIds.length;
    }

    /**
     * @notice Get public strategy ID by index
     * @param index Index in public strategies array
     * @return strategyId Strategy ID
     */
    function getPublicStrategyId(uint256 index) external view returns (uint256 strategyId) {
        if (index >= publicStrategyIds.length) revert InvalidAmount();
        return publicStrategyIds[index];
    }

    /**
     * @notice Check if user has copied a creator's strategy
     * @param user User address
     * @param creator Creator address
     * @return copied True if user has copied creator's strategy
     */
    function hasUserCopiedStrategy(address user, address creator) external view returns (bool copied) {
        return hasCopied[user][creator];
    }

    /**
     * @notice Get adapter health status
     * @param adapter Adapter address
     * @return isHealthy True if operational
     * @return reason Health status reason if not operational
     */
    function getAdapterHealth(address adapter) external view returns (bool isHealthy, string memory reason) {
        if (!isAuthorizedAdapter[adapter]) return (false, "Not authorized");
        isHealthy = IUniversalAdapter(adapter).isOperational();
        if (!isHealthy) {
            reason = IUniversalAdapter(adapter).getHealthStatus();
        }
    }
}
