// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/*
 * @status EXPERIMENTAL
 * @network Prototype only
 * @used-by ComposableVault.sol
 * @notes Interface for composable vault research.
 */

/**
 * @title IComposableVault
 * @notice Interface for vaults that can compose with other vaults
 * @dev Enables Vault-of-Vaults architecture with strict invariant protection
 *
 * KEY CONCEPTS:
 * - Parent Vault: Takes deposits, routes to child vaults
 * - Child Vault: Either protocol adapter OR another ComposableVault
 * - Shares: Represent proportional ownership at each layer
 * - Assets: Flow through layers while maintaining invariants
 *
 * COMPOSITION MODEL:
 * Vault Layer 0 (User deposits USDC)
 *     ↓ deposits 1000 USDC
 * Vault Layer 1 (Parent - ERC4626 vault)
 *     ├─ receives 1000 USDC
 *     ├─ mints 1000 shares to Layer 0
 *     └─ routes to children
 * Vault Layer 2 (Child 1, Child 2, ...)
 *     ├─ Child 1: receives 500 USDC → issues share tokens
 *     └─ Child 2: receives 500 USDC → issues share tokens
 */

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IComposableVault is IERC20 {
    // ========================================================================
    // EVENTS
    // ========================================================================

    /**
     * @notice Emitted when a child vault is registered
     * @param childVault Address of the child vault
     * @param allocationBps Allocation in basis points
     */
    event ChildVaultAdded(
        address indexed childVault,
        uint16 allocationBps
    );

    /**
     * @notice Emitted when a child vault is removed
     * @param childVault Address of the child vault
     */
    event ChildVaultRemoved(address indexed childVault);

    /**
     * @notice Emitted when assets are routed to a child vault
     * @param childVault Address of the child vault
     * @param assets Amount of assets routed
     * @param sharesReceived Shares received from child vault
     */
    event RoutedToChild(
        address indexed childVault,
        uint256 assets,
        uint256 sharesReceived
    );

    /**
     * @notice Emitted when assets are retrieved from a child vault
     * @param childVault Address of the child vault
     * @param sharesRedeemed Shares redeemed from child
     * @param assetsReceived Assets received from child
     */
    event RetrievedFromChild(
        address indexed childVault,
        uint256 sharesRedeemed,
        uint256 assetsReceived
    );

    /**
     * @notice Emitted when vault depth or structure changes
     * @param newMaxDepth New maximum allowed vault depth
     */
    event MaxDepthUpdated(uint256 newMaxDepth);

    // ========================================================================
    // DATA STRUCTURES
    // ========================================================================

    /**
     * @notice Information about a child vault
     */
    struct ChildVaultInfo {
        address vaultAddress;        // Address of child vault
        uint16 allocationBps;        // Target allocation (basis points)
        uint256 currentShares;       // Shares held in child vault
        uint256 lastRebalanceTime;   // Last rebalance timestamp
        bool isActive;               // Active/inactive flag
    }

    /**
     * @notice Vault composition metadata
     */
    struct VaultComposition {
        uint256 depth;               // Vault depth (0 = leaf, 1 = parent of leaves)
        address parentVault;         // Parent vault address (if composed)
        uint256 compositionIndex;    // Index in parent's children list
    }

    // ========================================================================
    // COMPOSITION QUERIES
    // ========================================================================

    /**
     * @notice Get composition metadata for this vault
     * @return Composition info (depth, parent, index)
     */
    function getComposition() external view returns (VaultComposition memory);

    /**
     * @notice Check if vault is a leaf (no children)
     * @return True if leaf vault (deposits to protocols, not vaults)
     */
    function isLeafVault() external view returns (bool);

    /**
     * @notice Get number of child vaults
     * @return Count of active child vaults
     */
    function getChildVaultCount() external view returns (uint256);

    /**
     * @notice Get child vault info by index
     * @param index Index in children array
     * @return Child vault information
     */
    function getChildVault(uint256 index) 
        external view 
        returns (ChildVaultInfo memory);

    /**
     * @notice Get all child vaults
     * @return Array of child vault info
     */
    function getAllChildVaults() 
        external view 
        returns (ChildVaultInfo[] memory);

    /**
     * @notice Check if address is a direct child vault
     * @param potentialChild Address to check
     * @return True if address is registered as child vault
     */
    function isChildVault(address potentialChild) 
        external view 
        returns (bool);

    // ========================================================================
    // COMPOSITION SETUP (OWNER ONLY)
    // ========================================================================

    /**
     * @notice Register a child vault
     * @dev Only owner can register. Prevents circular dependencies.
     * @param childVault Address of child vault
     * @param allocationBps Target allocation in basis points
     */
    function addChildVault(address childVault, uint16 allocationBps) external;

    /**
     * @notice Unregister a child vault
     * @dev Only owner can remove. Withdraws all assets first.
     * @param childVault Address of child vault to remove
     */
    function removeChildVault(address childVault) external;

    /**
     * @notice Update child vault allocation
     * @param childVault Address of child vault
     * @param newAllocationBps New allocation in basis points
     */
    function updateChildAllocation(address childVault, uint16 newAllocationBps) external;

    /**
     * @notice Set maximum vault depth
     * @param newMaxDepth Maximum allowed composition depth
     */
    function setMaxVaultDepth(uint256 newMaxDepth) external;

    // ========================================================================
    // COMPOSABLE DEPOSIT/WITHDRAWAL
    // ========================================================================

    /**
     * @notice Deposit assets and get routed to child vaults
     * @param assets Amount to deposit
     * @param receiver Address to receive shares
     * @return shares Shares minted to receiver
     *
     * FLOW:
     * 1. Receive assets from user
     * 2. Mint shares to receiver
     * 3. Route assets to child vaults per allocations
     * 4. Hold child vault shares (not transfer to user)
     */
    function composableDeposit(uint256 assets, address receiver)
        external
        returns (uint256 shares);

    /**
     * @notice Withdraw assets by redeeming from child vaults
     * @param shares Amount of vault shares to redeem
     * @param receiver Address to receive assets
     * @param owner Owner of shares
     * @return assets Assets withdrawn
     *
     * FLOW:
     * 1. Burn shares from owner
     * 2. Redeem from child vaults (proportional to shares held)
     * 3. Aggregate assets from children
     * 4. Transfer assets to receiver
     */
    function composableWithdraw(uint256 shares, address receiver, address owner)
        external
        returns (uint256 assets);

    // ========================================================================
    // REBALANCING & HARVESTING
    // ========================================================================

    /**
     * @notice Rebalance assets across child vaults
     * @dev Moves assets to match target allocations
     */
    function rebalanceChildVaults() external;

    /**
     * @notice Harvest yields from all child vaults
     * @return totalHarvested Total assets harvested
     */
    function harvestFromChildren() external returns (uint256 totalHarvested);

    /**
     * @notice Get rebalancing needs
     * @return needsRebalance True if significantly out of balance
     * @return rebalanceAmount Amount to move (approximate)
     */
    function getRebalancingNeeded() 
        external view 
        returns (bool needsRebalance, uint256 rebalanceAmount);

    // ========================================================================
    // TOTAL ASSETS & VALUE QUERIES
    // ========================================================================

    /**
     * @notice Get total assets across all layers
     * @dev Aggregates: direct holdings + (child shares × child share price)
     * @return Total assets value (conservative)
     */
    function getTotalAssetsRecursive() external view returns (uint256);

    /**
     * @notice Get assets held in specific child vault
     * @param childVault Address of child vault
     * @return Assets value held in child (in parent asset terms)
     */
    function getAssetsInChild(address childVault) 
        external view 
        returns (uint256);

    /**
     * @notice Get composition breakdown
     * @return directAssets Assets held directly (not in children)
     * @return childAssets Assets in child vaults
     * @return totalAssets Total (direct + children)
     */
    function getCompositionBreakdown() 
        external view 
        returns (uint256 directAssets, uint256 childAssets, uint256 totalAssets);

    // ========================================================================
    // SAFETY & INVARIANT CHECKS
    // ========================================================================

    /**
     * @notice Verify all invariants hold
     * @return isValid True if all invariants satisfied
     * @return failureReason Reason if invariant violated
     */
    function verifyInvariants() 
        external view 
        returns (bool isValid, string memory failureReason);

    /**
     * @notice Check if circular dependency exists
     * @param potentialChild Address to check
     * @return hasCircle True if adding potentialChild would create cycle
     */
    function wouldCreateCircularDependency(address potentialChild) 
        external view 
        returns (bool hasCircle);

    /**
     * @notice Check if vault depth would be exceeded
     * @param potentialChild Address to check
     * @return exceedsDepth True if adding would exceed max depth
     */
    function wouldExceedMaxDepth(address potentialChild) 
        external view 
        returns (bool exceedsDepth);
}
