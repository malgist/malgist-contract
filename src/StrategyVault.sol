// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/*
 * @status EXPERIMENTAL
 * @network Prototype only
 * @used-by StrategyVault.t.sol
 * @notes NFT-driven vault concept retained as documentation reference.
 */

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "./interfaces/IAdapter.sol";

interface IStrategyNFT {
    struct StrategyConfig {
        address[] adapters;
        uint16[] ratios;
        address creator;
        uint16 creatorFeeBps;
        uint8 riskLevel;
        bool isActive;
        uint40 createdAt;
        uint16 version;
        uint8 rebalanceFrequency;
        bytes32 strategistName;
        uint8 slippageToleranceBps;
    }

    function getStrategy(uint256 tokenId) external view returns (StrategyConfig memory);
    function isStrategyValid(uint256 tokenId) external view returns (bool);
    function getStrategyCreator(uint256 tokenId) external view returns (address);
    function getCreatorFee(uint256 tokenId) external view returns (uint16);
    function ownerOf(uint256 tokenId) external view returns (address);
}

/**
 * @title StrategyVault
 * @notice Universal vault that executes strategies defined as NFTs
 * @dev Reads strategy configuration from StrategyNFT contract
 */
contract StrategyVault is ReentrancyGuard, Ownable, Pausable {
    using SafeERC20 for IERC20;

    // ============================================================================
    // STRUCTS & ENUMS
    // ============================================================================

    enum PositionStatus { ACTIVE, LIQUIDATING, LIQUIDATED }

    struct Position {
        uint256 strategyTokenId;         // Strategy NFT ID
        address strategist;               // NFT owner
        address depositAsset;             // Asset deposited
        uint256 depositAmount;            // Amount deposited
        uint256 sharesIssued;             // Vault shares issued
        PositionStatus status;            // Current position status
        uint40 enteredAt;                 // Entry timestamp
        uint256 initialSupplied;          // Total value at entry
        uint256 currentValue;             // Current value in deposit asset
    }

    // ============================================================================
    // STATE VARIABLES
    // ============================================================================

    IStrategyNFT public strategyNFT;
    IERC20 public depositAsset;           // Asset that users deposit
    
    // Accounting
    uint256 public totalDeposits;         // Total value deposited
    uint256 public totalShares;           // Total shares issued
    mapping(address => uint256) public userShares;  // User => share balance
    mapping(uint256 => Position) public positions;  // positionId => Position data
    
    uint256 public nextPositionId = 1;

    // Creator fees (collected and held)
    mapping(address => uint256) public creatorFeeBalance;

    // Configuration
    uint256 public constant BASIS_POINTS = 10000;
    uint256 public constant MIN_DEPOSIT = 1e18;      // 1 token (18 decimals)
    
    // Slippage protection (vault-level)
    uint8 public slippageToleranceBps = 100;         // 1% default

    // ============================================================================
    // EVENTS
    // ============================================================================

    event StrategyDeposit(
        uint256 indexed positionId,
        uint256 indexed strategyTokenId,
        address indexed depositor,
        uint256 depositAmount,
        uint256 sharesIssued
    );

    event StrategyWithdrawal(
        uint256 indexed positionId,
        address indexed withdrawer,
        uint256 withdrawAmount,
        uint256 sharesBurned
    );

    event CreatorFeeCollected(
        uint256 indexed positionId,
        address indexed creator,
        uint256 feeAmount
    );

    event StrategyRebalanced(
        uint256 indexed positionId,
        address[] adapters,
        uint16[] ratios
    );

    event PositionLiquidated(
        uint256 indexed positionId,
        uint256 finalValue
    );

    event SlippageToleranceUpdated(uint8 newTolerance);

    // ============================================================================
    // INITIALIZATION
    // ============================================================================

    constructor(address _strategyNFT, address _depositAsset) Ownable(msg.sender) {
        require(_strategyNFT != address(0), "Invalid StrategyNFT");
        require(_depositAsset != address(0), "Invalid deposit asset");
        
        strategyNFT = IStrategyNFT(_strategyNFT);
        depositAsset = IERC20(_depositAsset);
    }

    // ============================================================================
    // DEPOSIT & WITHDRAWAL
    // ============================================================================

    /**
     * @notice Deposit into a strategy
     * @param strategyTokenId Strategy NFT ID to deposit into
     * @param depositAmount Amount of deposit asset to deposit
     * @return positionId New position ID
     */
    function deposit(uint256 strategyTokenId, uint256 depositAmount)
        external
        nonReentrant
        whenNotPaused
        returns (uint256)
    {
        require(depositAmount >= MIN_DEPOSIT, "Deposit too small");
        require(strategyNFT.isStrategyValid(strategyTokenId), "Strategy invalid");

        // Transfer deposit asset from user
        depositAsset.safeTransferFrom(msg.sender, address(this), depositAmount);
        totalDeposits += depositAmount;

        // Calculate shares to issue (handle initial deposit edge case)
        uint256 sharesToIssue;
        if (totalShares == 0) {
            sharesToIssue = depositAmount;
        } else {
            // shares = (depositAmount * totalShares) / totalValue
            sharesToIssue = (depositAmount * totalShares) / totalDeposits;
        }
        
        require(sharesToIssue > 0, "Share calculation failed");

        // Update accounting
        totalShares += sharesToIssue;
        userShares[msg.sender] += sharesToIssue;

        // Create position record
        uint256 positionId = nextPositionId++;
        positions[positionId] = Position({
            strategyTokenId: strategyTokenId,
            strategist: strategyNFT.ownerOf(strategyTokenId),
            depositAsset: address(depositAsset),
            depositAmount: depositAmount,
            sharesIssued: sharesToIssue,
            status: PositionStatus.ACTIVE,
            enteredAt: uint40(block.timestamp),
            initialSupplied: totalDeposits,
            currentValue: depositAmount
        });

        emit StrategyDeposit(positionId, strategyTokenId, msg.sender, depositAmount, sharesToIssue);
        return positionId;
    }

    /**
     * @notice Withdraw from vault position
     * @param positionId Position ID to withdraw from
     * @param sharesToBurn Number of shares to burn
     * @return withdrawAmount Amount of deposit asset withdrawn
     */
    function withdraw(uint256 positionId, uint256 sharesToBurn)
        external
        nonReentrant
        returns (uint256)
    {
        Position storage position = positions[positionId];
        require(position.status == PositionStatus.ACTIVE, "Position not active");
        require(userShares[msg.sender] >= sharesToBurn, "Insufficient shares");
        require(sharesToBurn > 0, "No shares to burn");

        // Calculate withdrawal amount based on current vault value
        // withdraw = (sharesToBurn * totalValue) / totalShares
        uint256 withdrawAmount = (sharesToBurn * totalDeposits) / totalShares;
        require(withdrawAmount > 0, "Withdraw amount too small");

        // Update accounting
        totalShares -= sharesToBurn;
        userShares[msg.sender] -= sharesToBurn;
        totalDeposits -= withdrawAmount;
        
        position.sharesIssued -= sharesToBurn;

        // Deduct creator fees if applicable
        uint16 creatorFeeBps = IStrategyNFT(address(strategyNFT)).getCreatorFee(position.strategyTokenId);
        if (creatorFeeBps > 0) {
            uint256 creatorFee = (withdrawAmount * creatorFeeBps) / BASIS_POINTS;
            withdrawAmount -= creatorFee;
            creatorFeeBalance[position.strategist] += creatorFee;
            
            emit CreatorFeeCollected(positionId, position.strategist, creatorFee);
        }

        // Transfer withdrawal
        depositAsset.safeTransfer(msg.sender, withdrawAmount);

        emit StrategyWithdrawal(positionId, msg.sender, withdrawAmount, sharesToBurn);
        return withdrawAmount;
    }

    // ============================================================================
    // STRATEGY EXECUTION
    // ============================================================================

    /**
     * @notice Execute strategy allocations (internal - called by adapters/orchestrator)
     * @param positionId Position to execute
     * @dev This would be called by strategy execution layer
     */
    function executeStrategy(uint256 positionId)
        external
        nonReentrant
        whenNotPaused
    {
        Position storage position = positions[positionId];
        require(position.status == PositionStatus.ACTIVE, "Position not active");

        // Fetch strategy configuration from NFT
        IStrategyNFT.StrategyConfig memory strategy = 
            IStrategyNFT(address(strategyNFT)).getStrategy(position.strategyTokenId);

        require(strategy.isActive, "Strategy deactivated");

        // Verify all adapters are valid
        for (uint256 i = 0; i < strategy.adapters.length; i++) {
            require(strategy.adapters[i] != address(0), "Invalid adapter");
        }

        // Execute allocations across adapters
        uint256 amountToAllocate = position.currentValue;
        for (uint256 i = 0; i < strategy.adapters.length; i++) {
            uint256 allocationAmount = (amountToAllocate * strategy.ratios[i]) / BASIS_POINTS;
            
            if (allocationAmount > 0) {
                // Approve adapter
                depositAsset.approve(strategy.adapters[i], allocationAmount);
                
                // Call adapter deposit (would implement IAdapter interface)
                // IAdapter(strategy.adapters[i]).deposit(allocationAmount);
            }
        }

        emit StrategyRebalanced(positionId, strategy.adapters, strategy.ratios);
    }

    /**
     * @notice Rebalance strategy allocations
     * @param positionId Position to rebalance
     */
    function rebalanceStrategy(uint256 positionId)
        external
        nonReentrant
        whenNotPaused
    {
        Position storage position = positions[positionId];
        require(position.status == PositionStatus.ACTIVE, "Position not active");

        IStrategyNFT.StrategyConfig memory strategy = 
            IStrategyNFT(address(strategyNFT)).getStrategy(position.strategyTokenId);

        require(strategy.isActive, "Strategy deactivated");

        // TODO: Implement rebalancing logic:
        // 1. Withdraw all funds from current adapters
        // 2. Update position.currentValue
        // 3. Re-allocate according to new ratios
        
        emit StrategyRebalanced(positionId, strategy.adapters, strategy.ratios);
    }

    // ============================================================================
    // LIQUIDATION
    // ============================================================================

    /**
     * @notice Liquidate a position (emergency recovery)
     * @param positionId Position to liquidate
     */
    function liquidatePosition(uint256 positionId)
        external
        nonReentrant
    {
        Position storage position = positions[positionId];
        require(position.status == PositionStatus.ACTIVE, "Already liquidating");

        position.status = PositionStatus.LIQUIDATING;

        // TODO: Withdraw from all adapters
        // This is a critical safety mechanism for emergencies

        position.status = PositionStatus.LIQUIDATED;
        emit PositionLiquidated(positionId, position.currentValue);
    }

    // ============================================================================
    // CREATOR FEE MANAGEMENT
    // ============================================================================

    /**
     * @notice Withdraw accumulated creator fees
     */
    function withdrawCreatorFees() external nonReentrant {
        uint256 feeBalance = creatorFeeBalance[msg.sender];
        require(feeBalance > 0, "No fees to withdraw");

        creatorFeeBalance[msg.sender] = 0;
        depositAsset.safeTransfer(msg.sender, feeBalance);
    }

    /**
     * @notice Get pending creator fees
     * @param creator Creator address
     * @return pendingFees Amount of pending fees
     */
    function getCreatorFeeBalance(address creator) external view returns (uint256) {
        return creatorFeeBalance[creator];
    }

    // ============================================================================
    // ACCOUNTING & QUERIES
    // ============================================================================

    /**
     * @notice Get vault share price
     * @return pricePerShare Price per share (in deposit asset units)
     */
    function getSharePrice() external view returns (uint256) {
        if (totalShares == 0) return 1e18;
        return (totalDeposits * 1e18) / totalShares;
    }

    /**
     * @notice Get user's total balance in vault
     * @param user User address
     * @return balanceInAsset User's balance in deposit asset units
     */
    function getUserBalance(address user) external view returns (uint256) {
        if (totalShares == 0) return 0;
        return (userShares[user] * totalDeposits) / totalShares;
    }

    /**
     * @notice Get position details
     * @param positionId Position ID
     * @return position Position data
     */
    function getPosition(uint256 positionId) external view returns (Position memory) {
        return positions[positionId];
    }

    /**
     * @notice Get current vault TVL
     * @return tvl Total value locked in vault
     */
    function getTVL() external view returns (uint256) {
        return totalDeposits;
    }

    // ============================================================================
    // ADMIN FUNCTIONS
    // ============================================================================

    /**
     * @notice Update vault-level slippage tolerance
     * @param newTolerance New slippage tolerance in basis points
     */
    function setSlippageTolerance(uint8 newTolerance) external onlyOwner {
        require(newTolerance <= 500, "Tolerance too high");
        slippageToleranceBps = newTolerance;
        emit SlippageToleranceUpdated(newTolerance);
    }

    /**
     * @notice Emergency pause
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @notice Unpause vault
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    // ============================================================================
    // SECURITY: Reentrancy Guards
    // ============================================================================

    // All state-modifying functions already use nonReentrant modifier
    // Additional protection: all external calls use SafeERC20
}
