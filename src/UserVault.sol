// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IAdapter} from "./interfaces/IAdapter.sol";

/**
 * @title UserVault
 * @notice Copy-trading DeFi vault where users can create, share, and copy investment strategies
 * @dev Each user can have one active strategy. Strategies can be public (copyable) or private.
 */
contract UserVault is ReentrancyGuard {
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

    // ============ CONSTRUCTOR ============

    /**
     * @notice Initialize vault with base asset
     * @param _asset Address of base asset (USDC)
     */
    constructor(address _asset) {
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
    function setStrategy(
        address[] memory adapters,
        uint16[] memory ratios,
        bool isPublic,
        string memory name,
        uint16 copyFeeBps
    ) external {
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
    function copyStrategy(address creator) external {
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
     * @notice Deposit assets into user's strategy
     * @param amount Amount of base asset to deposit
     * @return shares Amount of shares minted
     */
    function deposit(uint256 amount) external nonReentrant returns (uint256 shares) {
        if (amount == 0) revert InvalidAmount();

        Strategy storage s = strategies[msg.sender];
        if (s.adapters.length == 0) revert NoStrategySet();

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
        if (s.shares < shareAmount) revert InsufficientBalance();

        // Withdraw proportionally from all adapters
        withdrawn = _executeWithdraw(s.adapters, s.ratios, shareAmount);

        // Burn shares
        s.shares -= shareAmount;
        s.totalDeposited = s.totalDeposited > withdrawn ? s.totalDeposited - withdrawn : 0;

        // Transfer assets to user
        ASSET.safeTransfer(msg.sender, withdrawn);

        emit Withdrawn(msg.sender, shareAmount, withdrawn);
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
        for (uint256 i = 0; i < s.adapters.length; i++) {
            totalValue += IAdapter(s.adapters[i]).getBalance();
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

            // Approve and deposit
            ASSET.forceApprove(adapters[i], adapterAmount);
            IAdapter(adapters[i]).deposit(adapterAmount);
            ASSET.forceApprove(adapters[i], 0);
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
