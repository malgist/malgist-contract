// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {StrategyNFT} from "./StrategyNFT.sol";
import {IAdapter} from "./interfaces/IAdapter.sol";

/**
 * @title UniversalVault
 * @notice Dynamic vault that routes deposits to multiple DeFi protocols based on NFT strategy data
 * @dev This is the core innovation - reads adapter allocations from on-chain NFT data
 */
contract UniversalVault is ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;

    /// @notice The deposit/base token (e.g., USDC)
    IERC20 public immutable ASSET;

    /// @notice Reference to the StrategyNFT contract
    StrategyNFT public immutable STRATEGY_NFT;

    /// @notice Track user shares per strategy: strategyId => user => shares
    mapping(uint256 => mapping(address => uint256)) public userShares;

    /// @notice Track total shares per strategy: strategyId => totalShares
    mapping(uint256 => uint256) public totalStrategyShares;

    /// @notice Track creator fees accumulated per strategy: strategyId => fees
    mapping(uint256 => uint256) public accumulatedCreatorFees;

    /// @notice Basis points constant (10000 = 100%)
    uint16 public constant TOTAL_BPS = 10000;

    /// @notice Creator fee in basis points (100 = 1%)
    uint16 public constant CREATOR_FEE_BPS = 100; // 1% hardcoded for now

    /// @notice Emitted when a user deposits into a strategy
    event Deposited(uint256 indexed strategyId, address indexed user, uint256 assets, uint256 shares);

    /// @notice Emitted when a user withdraws from a strategy
    event Withdrawn(uint256 indexed strategyId, address indexed user, uint256 assets, uint256 shares);

    /// @notice Emitted when creator fees are claimed
    event CreatorFeesClaimed(uint256 indexed strategyId, address indexed creator, uint256 amount);

    /// @dev Errors
    error InvalidAmount();
    error StrategyNotActive();
    error InsufficientShares();
    error NotStrategyCreator();
    error NoFeesToClaim();

    constructor(address _asset, address _strategyNft) Ownable(msg.sender) {
        ASSET = IERC20(_asset);
        STRATEGY_NFT = StrategyNFT(_strategyNft);
    }

    /**
     * @notice Deposit assets into a strategy
     * @param strategyId The NFT token ID representing the strategy
     * @param assets Amount of tokens to deposit
     * @return shares Amount of shares minted to the user
     */
    function deposit(uint256 strategyId, uint256 assets) external nonReentrant returns (uint256 shares) {
        if (assets == 0) revert InvalidAmount();

        // Get strategy configuration from NFT
        StrategyNFT.Strategy memory strategy = STRATEGY_NFT.getStrategy(strategyId);
        if (!strategy.isActive) revert StrategyNotActive();

        // Transfer assets from user
        ASSET.safeTransferFrom(msg.sender, address(this), assets);

        // Calculate and deduct creator fee
        uint256 creatorFee = (assets * CREATOR_FEE_BPS) / TOTAL_BPS;
        uint256 netAssets = assets - creatorFee;

        // Accumulate creator fee
        accumulatedCreatorFees[strategyId] += creatorFee;

        // Execute strategy: split deposits across adapters
        _executeStrategyDeposit(strategy.adapters, strategy.ratios, netAssets);

        // Mint shares to user (1:1 for simplicity in MVP)
        shares = netAssets;
        userShares[strategyId][msg.sender] += shares;
        totalStrategyShares[strategyId] += shares;

        emit Deposited(strategyId, msg.sender, assets, shares);
        return shares;
    }

    /**
     * @notice Internal function to execute strategy deposit by splitting across adapters
     * @param adapters Array of adapter addresses
     * @param ratios Array of allocation ratios in basis points
     * @param amount Total amount to split
     */
    function _executeStrategyDeposit(address[] memory adapters, uint16[] memory ratios, uint256 amount) internal {
        uint256 remaining = amount;

        for (uint256 i = 0; i < adapters.length; i++) {
            uint256 adapterAmount;

            // For last adapter, use remaining to avoid rounding dust
            if (i == adapters.length - 1) {
                adapterAmount = remaining;
            } else {
                adapterAmount = (amount * ratios[i]) / TOTAL_BPS;
                remaining -= adapterAmount;
            }

            if (adapterAmount > 0) {
                // Approve adapter to spend tokens
                ASSET.forceApprove(adapters[i], adapterAmount);

                // Deposit to adapter
                IAdapter(adapters[i]).deposit(adapterAmount);

                // Reset approval for security
                ASSET.forceApprove(adapters[i], 0);
            }
        }
    }

    /**
     * @notice Withdraw assets from a strategy
     * @param strategyId The strategy to withdraw from
     * @param shares Amount of shares to burn (0 = withdraw all)
     * @return assets Amount of tokens returned to user
     */
    function withdraw(uint256 strategyId, uint256 shares) external nonReentrant returns (uint256 assets) {
        uint256 userBalance = userShares[strategyId][msg.sender];
        if (userBalance == 0) revert InsufficientShares();

        // If shares = 0, withdraw all
        uint256 sharesToBurn = (shares == 0) ? userBalance : shares;
        if (sharesToBurn > userBalance) revert InsufficientShares();

        // Get strategy configuration
        StrategyNFT.Strategy memory strategy = STRATEGY_NFT.getStrategy(strategyId);

        // Calculate proportional withdrawal from adapters
        uint256 totalWithdrawn = _executeStrategyWithdraw(strategy.adapters, strategy.ratios, sharesToBurn);

        // Burn user shares
        userShares[strategyId][msg.sender] -= sharesToBurn;
        totalStrategyShares[strategyId] -= sharesToBurn;

        // Transfer assets to user
        ASSET.safeTransfer(msg.sender, totalWithdrawn);

        emit Withdrawn(strategyId, msg.sender, totalWithdrawn, sharesToBurn);
        return totalWithdrawn;
    }

    /**
     * @notice Internal function to execute strategy withdrawal
     * @param adapters Array of adapter addresses
     * @param ratios Array of allocation ratios
     * @param shares Amount of shares being withdrawn
     * @return totalWithdrawn Total amount withdrawn from all adapters
     */
    function _executeStrategyWithdraw(address[] memory adapters, uint16[] memory ratios, uint256 shares)
        internal
        returns (uint256 totalWithdrawn)
    {
        uint256 remaining = shares;

        for (uint256 i = 0; i < adapters.length; i++) {
            uint256 adapterAmount;

            // For last adapter, use remaining
            if (i == adapters.length - 1) {
                adapterAmount = remaining;
            } else {
                adapterAmount = (shares * ratios[i]) / TOTAL_BPS;
                remaining -= adapterAmount;
            }

            if (adapterAmount > 0) {
                uint256 withdrawn = IAdapter(adapters[i]).withdraw(adapterAmount);
                totalWithdrawn += withdrawn;
            }
        }

        return totalWithdrawn;
    }

    /**
     * @notice Claim accumulated creator fees
     * @param strategyId The strategy to claim fees for
     */
    function claimCreatorFees(uint256 strategyId) external nonReentrant {
        StrategyNFT.Strategy memory strategy = STRATEGY_NFT.getStrategy(strategyId);
        if (msg.sender != strategy.creator) revert NotStrategyCreator();

        uint256 fees = accumulatedCreatorFees[strategyId];
        if (fees == 0) revert NoFeesToClaim();

        // Reset accumulated fees
        accumulatedCreatorFees[strategyId] = 0;

        // Transfer fees to creator
        ASSET.safeTransfer(strategy.creator, fees);

        emit CreatorFeesClaimed(strategyId, strategy.creator, fees);
    }

    /**
     * @notice Get user's position in a strategy
     * @param strategyId The strategy ID
     * @param user The user address
     * @return userShares_ User's share balance
     * @return totalShares_ Total shares in the strategy
     */
    function getUserPosition(uint256 strategyId, address user)
        external
        view
        returns (uint256 userShares_, uint256 totalShares_)
    {
        return (userShares[strategyId][user], totalStrategyShares[strategyId]);
    }
}
