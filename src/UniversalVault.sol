// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IAdapter} from "./interfaces/IAdapter.sol";
import {EmergencyPause} from "./EmergencyPause.sol";

/**
 * @title UniversalVault
 * @notice Copy-trading DeFi vault with integrated emergency pause system
 * @dev Example integration of EmergencyPause for production-grade safety
 *
 * Integration pattern:
 * - Inherit from EmergencyPause
 * - Use modifiers: whenDepositsNotPaused, whenStrategyExecutionNotPaused, withdrawalAlwaysPermitted
 * - Check adapter status before adapter calls: _checkAdapterOperational(adapter)
 * - Withdrawals NEVER check pause state (intentional for safety)
 */
contract UniversalVault is ReentrancyGuard, EmergencyPause {
    using SafeERC20 for IERC20;
    using SafeERC20 for IERC20;

    // ============ STATE VARIABLES ============

    IERC20 public immutable ASSET;
    uint16 public constant MAX_COPY_FEE_BPS = 50;
    uint16 public constant TOTAL_BPS = 10000;

    // Strategy storage (same as UserVault)
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

    mapping(address => Strategy) public strategies;
    address[] public publicStrategies;
    mapping(address => bool) public isInPublicList;
    mapping(address => uint256) public copyFeeEarnings;
    mapping(address => address) public copiedFrom;

    // ============ EVENTS ============

    event StrategyCreated(
        address indexed user, address[] adapters, uint16[] ratios, bool isPublic, string name, uint16 copyFeeBps
    );
    event StrategyCopied(address indexed copier, address indexed creator, uint256 copyFee);
    event Deposited(address indexed user, uint256 amount, uint256 shares);
    event Withdrawn(address indexed user, uint256 shares, uint256 amount);
    event StrategyUpdated(address indexed user, bool isPublic, string name, uint16 copyFeeBps);
    event CopyFeesClaimed(address indexed user, uint256 amount);

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
    error AdapterCallFailed();
    error AdapterDepositFailed();
    error AdapterWithdrawFailed();

    // ============ CONSTRUCTOR ============

    /**
     * @notice Initialize vault with base asset and pause owner
     * @param _asset Address of base asset (USDC)
     * @param _pauseOwner Address authorized to control emergency pause (multisig)
     */
    constructor(address _asset, address _pauseOwner) EmergencyPause(_pauseOwner) {
        ASSET = IERC20(_asset);
    }

    // ============ STRATEGY MANAGEMENT ============

    /**
     * @notice Set user's strategy configuration
     * @param adapters Array of protocol adapter addresses
     * @param ratios Allocation ratios in basis points
     * @param isPublic Whether strategy should be public
     * @param name Strategy name
     * @param copyFeeBps Fee to charge copiers (0-50 bps)
     * @dev Strategy creation is blocked during global pause
     */
    function setStrategy(
        address[] memory adapters,
        uint16[] memory ratios,
        bool isPublic,
        string memory name,
        uint16 copyFeeBps
    ) external whenStrategyExecutionNotPaused {
        if (adapters.length == 0 || adapters.length != ratios.length) {
            revert ArrayLengthMismatch();
        }
        if (copyFeeBps > MAX_COPY_FEE_BPS) {
            revert CopyFeeExceedsMax();
        }

        // Validate all adapters are operational
        for (uint256 i = 0; i < adapters.length; i++) {
            _checkAdapterOperational(adapters[i]);
        }

        // Validate ratios
        uint256 totalRatio;
        for (uint256 i = 0; i < ratios.length; i++) {
            if (ratios[i] == 0) revert InvalidRatios();
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

        if (isPublic && !isInPublicList[msg.sender]) {
            publicStrategies.push(msg.sender);
            isInPublicList[msg.sender] = true;
        }

        emit StrategyCreated(msg.sender, adapters, ratios, isPublic, name, copyFeeBps);
    }

    /**
     * @notice Copy another user's public strategy
     * @param creator Address of strategy creator to copy
     * @dev Strategy copying is blocked during global pause
     */
    function copyStrategy(address creator) external whenStrategyExecutionNotPaused {
        if (creator == msg.sender) revert CannotCopySelf();

        Strategy memory original = strategies[creator];
        if (!original.isPublic) revert StrategyNotPublic();
        if (original.adapters.length == 0) revert NoStrategySet();

        Strategy storage userStrategy = strategies[msg.sender];
        userStrategy.adapters = original.adapters;
        userStrategy.ratios = original.ratios;
        userStrategy.isPublic = false;
        userStrategy.name = string(abi.encodePacked("Copy of ", original.name));
        userStrategy.copyFeeBps = 0;
        userStrategy.creator = msg.sender;

        copiedFrom[msg.sender] = creator;
        strategies[creator].totalCopies++;

        emit StrategyCopied(msg.sender, creator, 0);
    }

    // ============ DEPOSITS & WITHDRAWALS ============

    /**
     * @notice Deposit assets into user's strategy
     * @param amount Amount of base asset to deposit
     * @return shares Amount of shares minted
     *
     * EMERGENCY CONTROL:
     * - Blocked if global pause is active
     * - Checks each adapter is operational before calling deposit()
     * - Silent adapter failures are caught (return value validation)
     *
     * NON-EMERGENCY (Always Allowed):
     * - Copy fee payment
     * - TVL tracking updates
     */
    function deposit(uint256 amount) external nonReentrant whenDepositsNotPaused returns (uint256 shares) {
        if (amount == 0) revert InvalidAmount();

        Strategy storage s = strategies[msg.sender];
        if (s.adapters.length == 0) revert NoStrategySet();

        // Transfer assets from user
        ASSET.safeTransferFrom(msg.sender, address(this), amount);

        // Process copy fees (not affected by pause - ensures earnings accessibility)
        uint256 netAmount = amount;
        address originalCreator = copiedFrom[msg.sender];
        if (originalCreator != address(0)) {
            Strategy memory creatorStrategy = strategies[originalCreator];
            if (creatorStrategy.copyFeeBps > 0) {
                uint256 copyFee = (amount * creatorStrategy.copyFeeBps) / TOTAL_BPS;
                netAmount = amount - copyFee;
                copyFeeEarnings[originalCreator] += copyFee;
                strategies[originalCreator].totalCopierTVL += netAmount;
                emit StrategyCopied(msg.sender, originalCreator, copyFee);
            }
        }

        // Execute strategy with adapter operational checks
        _executeDepositWithPauseCheck(s.adapters, s.ratios, netAmount);

        // Mint shares
        shares = netAmount;
        s.shares += shares;
        s.totalDeposited += netAmount;

        emit Deposited(msg.sender, amount, shares);
        return shares;
    }

    /**
     * @notice Withdraw assets from user's strategy
     * @param shareAmount Amount of shares to burn
     * @return withdrawn Amount of assets withdrawn
     *
     * EMERGENCY CONTROL:
     * - NO PAUSE CHECKS - withdrawals ALWAYS work, even during emergency
     * - This is intentional and critical for user safety
     *
     * Safety Features:
     * - nonReentrant guard
     * - Balance validation
     * - Proportional withdrawal from all adapters
     */
    function withdraw(uint256 shareAmount) external nonReentrant withdrawalAlwaysPermitted returns (uint256 withdrawn) {
        if (shareAmount == 0) revert InvalidAmount();

        Strategy storage s = strategies[msg.sender];
        if (s.shares < shareAmount) revert InsufficientBalance();

        // Execute withdrawal from all adapters (no pause checks)
        withdrawn = _executeWithdrawWithoutPauseCheck(s.adapters, s.ratios, shareAmount);

        // Update state
        s.shares -= shareAmount;
        s.totalDeposited = s.shares; // Simplified accounting

        // Transfer assets to user
        ASSET.safeTransfer(msg.sender, withdrawn);

        // Decrement creator's TVL if this is a copied strategy
        address originalCreator = copiedFrom[msg.sender];
        if (originalCreator != address(0)) {
            Strategy storage creatorStrategy = strategies[originalCreator];
            if (creatorStrategy.totalCopierTVL >= withdrawn) {
                creatorStrategy.totalCopierTVL -= withdrawn;
            }
        }

        emit Withdrawn(msg.sender, shareAmount, withdrawn);
        return withdrawn;
    }

    /**
     * @notice Emergency withdrawal (alias for withdraw)
     * @param shareAmount Amount of shares to burn
     * @return withdrawn Amount of assets withdrawn
     * 
     * This function is identical to withdraw() but serves as explicit
     * documentation that withdrawals are allowed during emergency pause
     */
    function emergencyWithdraw(uint256 shareAmount)
        external
        nonReentrant
        withdrawalAlwaysPermitted
        returns (uint256 withdrawn)
    {
        if (shareAmount == 0) revert InvalidAmount();

        Strategy storage s = strategies[msg.sender];
        if (s.shares < shareAmount) revert InsufficientBalance();

        withdrawn = _executeWithdrawWithoutPauseCheck(s.adapters, s.ratios, shareAmount);
        s.shares -= shareAmount;
        s.totalDeposited = s.shares;
        ASSET.safeTransfer(msg.sender, withdrawn);

        address originalCreator = copiedFrom[msg.sender];
        if (originalCreator != address(0)) {
            Strategy storage creatorStrategy = strategies[originalCreator];
            if (creatorStrategy.totalCopierTVL >= withdrawn) {
                creatorStrategy.totalCopierTVL -= withdrawn;
            }
        }

        emit Withdrawn(msg.sender, shareAmount, withdrawn);
        return withdrawn;
    }

    /**
     * @notice Claim accumulated copy fees
     * @dev Copy fees are NOT affected by pause - they represent user earnings
     */
    function claimCopyFees() external nonReentrant {
        uint256 amount = copyFeeEarnings[msg.sender];
        if (amount == 0) revert InvalidAmount();

        copyFeeEarnings[msg.sender] = 0;
        ASSET.safeTransfer(msg.sender, amount);

        emit CopyFeesClaimed(msg.sender, amount);
    }

    // ============ INTERNAL FUNCTIONS (EMERGENCY PAUSE INTEGRATION) ============

    /**
     * @notice Execute deposit across adapters with pause checks
     * @param adapters Array of adapter addresses
     * @param ratios Allocation ratios
     * @param amount Amount to deposit
     *
     * Safety features:
     * - Checks each adapter is operational (not paused)
     * - Validates deposit return values (no silent failures)
     * - Reverts on adapter failure
     */
    function _executeDepositWithPauseCheck(address[] memory adapters, uint16[] memory ratios, uint256 amount)
        internal
    {
        uint256 remaining = amount;

        for (uint256 i = 0; i < adapters.length; i++) {
            // CRITICAL: Check adapter is operational
            _checkAdapterOperational(adapters[i]);

            // Calculate allocation for this adapter
            uint256 adapterAmount = (amount * ratios[i]) / TOTAL_BPS;
            if (i == adapters.length - 1) {
                adapterAmount = remaining; // Remainder to last adapter
            }

            // Approve and execute deposit
            ASSET.forceApprove(adapters[i], adapterAmount);
            uint256 shares = IAdapter(adapters[i]).deposit(adapterAmount);

            // CRITICAL: Validate deposit succeeded
            if (shares == 0) revert AdapterCallFailed();

            remaining -= adapterAmount;
        }
    }

    /**
     * @notice Execute withdrawal from all adapters (NO pause checks)
     * @param adapters Array of adapter addresses
     * @param ratios Allocation ratios
     * @param shareAmount Amount to withdraw
     * @return totalWithdrawn Total amount withdrawn across all adapters
     *
     * Design: Withdrawals bypass ALL pause checks (intentional)
     * User funds are never locked, even during emergency
     */
    function _executeWithdrawWithoutPauseCheck(address[] memory adapters, uint16[] memory ratios, uint256 shareAmount)
        internal
        returns (uint256 totalWithdrawn)
    {
        totalWithdrawn = 0;

        for (uint256 i = 0; i < adapters.length; i++) {
            // Calculate proportional withdrawal
            uint256 withdrawAmount = (shareAmount * ratios[i]) / TOTAL_BPS;

            // Execute withdrawal (no pause checks)
            uint256 withdrawn = IAdapter(adapters[i]).withdraw(withdrawAmount);
            totalWithdrawn += withdrawn;
        }
    }
}
