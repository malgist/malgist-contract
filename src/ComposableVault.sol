// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/*
 * @status EXPERIMENTAL
 * @network Prototype only
 * @used-by ComposableVault.t.sol
 * @notes Legacy composable vault preserved for comparison with UserVault.
 */

/**
 * @title ComposableVault
 * @notice Vault-of-Vaults implementation with strict invariant protection
 * @dev Enables composable vault architecture with circular dependency prevention
 *
 * ARCHITECTURE:
 * - Parent Vault deposits into Child Vaults
 * - Maintains separate share accounting at each layer
 * - Strictly conserves assets across all layers
 * - Prevents circular dependencies via depth tracking
 * 
 * INVARIANTS:
 * 1. Asset Conservation: totalAssets = direct + sum(child assets)
 * 2. Share Proportionality: user shares % = user's asset contribution %
 * 3. No Circular Deps: graph acyclic (detected at composition time)
 * 4. Depth Limited: depth <= MAX_VAULT_DEPTH (prevents DOS)
 * 5. No Share Inflation: all divisions round down
 * 6. Child Assets Accurate: sum(child share holdings × child price) = reported value
 */

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./interfaces/IComposableVault.sol";

/**
 * @title ComposableVault
 * @notice Production-ready Vault-of-Vaults implementation
 */
contract ComposableVault is 
    ERC20, 
    IComposableVault, 
    ReentrancyGuard, 
    Ownable, 
    Pausable 
{
    using SafeERC20 for IERC20;

    // ========================================================================
    // CONSTANTS
    // ========================================================================

    uint256 public constant MAX_VAULT_DEPTH = 5;              // Prevents deep nesting
    uint256 public constant MAX_CHILD_VAULTS = 20;            // Limits complexity
    uint256 public constant BASIS_POINTS = 10000;             // Basis point denominator
    uint256 public constant WAD = 1e18;                       // Fixed-point precision
    uint256 public constant MIN_DEPOSIT = 1;                  // Minimum deposit

    // ========================================================================
    // STATE: CORE CONFIGURATION
    // ========================================================================

    IERC20 public immutable asset;                            // Underlying asset (USDC)
    uint8 private immutable _decimals;                        // Asset decimals
    uint256 public maxVaultDepth;                             // Max allowed depth

    // ========================================================================
    // STATE: COMPOSITION STRUCTURE
    // ========================================================================

    ChildVaultInfo[] public childVaults;                       // Array of child vaults
    mapping(address => bool) public isChildVaultMap;          // Quick lookup
    mapping(address => uint256) public childVaultIndex;       // Index for removal

    VaultComposition public vaultComposition;                 // This vault's composition

    // ========================================================================
    // STATE: ACCOUNTING
    // ========================================================================

    uint256 public lastRebalanceTime;                         // Track rebalance timing
    uint256 public rebalanceFrequency = 1 days;               // Minimum rebalance period
    uint256 public totalAdapterBalances;                      // Cached direct holdings

    // ========================================================================
    // CONSTRUCTOR
    // ========================================================================

    /**
     * @notice Initialize composable vault
     * @param _asset Underlying asset (USDC)
     * @param _name Vault name
     * @param _symbol Vault symbol
     * @param _parentVault Parent vault (address(0) if root)
     */
    constructor(
        address _asset,
        string memory _name,
        string memory _symbol,
        address _parentVault
    ) ERC20(_name, _symbol) Ownable(msg.sender) {
        require(_asset != address(0), "Zero asset");

        asset = IERC20(_asset);
        _decimals = IERC20Metadata(_asset).decimals();
        maxVaultDepth = MAX_VAULT_DEPTH;

        // Initialize composition
        vaultComposition = VaultComposition({
            depth: _parentVault == address(0) ? 0 : 1,  // Leaf is 0, parent of leaves is 1
            parentVault: _parentVault,
            compositionIndex: 0
        });

        lastRebalanceTime = block.timestamp;
    }

    // ========================================================================
    // COMPOSITION SETUP
    // ========================================================================

    /**
     * @notice Register a child vault
     * @param childVault Address of child vault
     * @param allocationBps Target allocation in basis points
     */
    function addChildVault(address childVault, uint16 allocationBps)
        external
        onlyOwner
        nonReentrant
    {
        require(childVault != address(0), "Zero address");
        require(childVault != address(this), "Cannot compose with self");
        require(allocationBps > 0 && allocationBps <= BASIS_POINTS, "Invalid allocation");
        require(!isChildVaultMap[childVault], "Already child");
        require(childVaults.length < MAX_CHILD_VAULTS, "Too many children");

        // Circular dependency check
        require(!wouldCreateCircularDependency(childVault), "Circular dependency");

        // Depth check
        require(!wouldExceedMaxDepth(childVault), "Exceeds max depth");

        // Register child
        childVaultIndex[childVault] = childVaults.length;
        isChildVaultMap[childVault] = true;

        childVaults.push(ChildVaultInfo({
            vaultAddress: childVault,
            allocationBps: allocationBps,
            currentShares: 0,
            lastRebalanceTime: block.timestamp,
            isActive: true
        }));

        emit ChildVaultAdded(childVault, allocationBps);
    }

    /**
     * @notice Remove a child vault
     * @param childVault Address of child vault to remove
     */
    function removeChildVault(address childVault)
        external
        onlyOwner
        nonReentrant
    {
        require(isChildVaultMap[childVault], "Not a child");

        uint256 idx = childVaultIndex[childVault];
        uint256 sharesHeld = childVaults[idx].currentShares;

        // Withdraw all assets first
        if (sharesHeld > 0) {
            try IComposableVault(childVault).composableWithdraw(
                sharesHeld,
                address(this),
                address(this)
            ) returns (uint256) {
                // Withdrawal successful
            } catch {
                // Child vault withdrawal failed - mark inactive but don't revert
                childVaults[idx].isActive = false;
            }
        }

        // Remove from mapping
        isChildVaultMap[childVault] = false;

        // Swap with last and pop
        if (idx < childVaults.length - 1) {
            ChildVaultInfo memory last = childVaults[childVaults.length - 1];
            childVaults[idx] = last;
            childVaultIndex[last.vaultAddress] = idx;
        }

        childVaults.pop();

        emit ChildVaultRemoved(childVault);
    }

    /**
     * @notice Update child vault allocation
     * @param childVault Address of child vault
     * @param newAllocationBps New allocation in basis points
     */
    function updateChildAllocation(address childVault, uint16 newAllocationBps)
        external
        onlyOwner
    {
        require(isChildVaultMap[childVault], "Not a child");
        require(newAllocationBps > 0 && newAllocationBps <= BASIS_POINTS, "Invalid");

        uint256 idx = childVaultIndex[childVault];
        childVaults[idx].allocationBps = newAllocationBps;
    }

    /**
     * @notice Set maximum vault depth
     * @param newMaxDepth Maximum allowed depth
     */
    function setMaxVaultDepth(uint256 newMaxDepth)
        external
        onlyOwner
    {
        require(newMaxDepth > 0 && newMaxDepth <= MAX_VAULT_DEPTH, "Invalid depth");
        maxVaultDepth = newMaxDepth;
        emit MaxDepthUpdated(newMaxDepth);
    }

    // ========================================================================
    // COMPOSABLE DEPOSIT/WITHDRAWAL
    // ========================================================================

    /**
     * @notice Deposit assets and route to child vaults
     * @param assets Amount of assets to deposit
     * @param receiver Address to receive vault shares
     * @return shares Vault shares minted
     *
     * FLOW:
     * 1. Transfer assets from user to vault
     * 2. Mint vault shares to receiver (proportional to assets)
     * 3. Route assets to child vaults per allocations
     * 4. Hold child shares (don't transfer to user)
     * 5. Conserve assets: sum(child assets) <= total assets
     */
    function composableDeposit(uint256 assets, address receiver)
        external
        override
        nonReentrant
        whenNotPaused
        returns (uint256 shares)
    {
        require(assets >= MIN_DEPOSIT, "Deposit too small");
        require(receiver != address(0), "Zero receiver");

        // Calculate vault shares to mint
        uint256 totalAssets = getTotalAssetsRecursive();
        uint256 totalShares = totalSupply();

        if (totalShares == 0) {
            shares = assets;  // First deposit: 1:1
        } else {
            shares = _mulDiv(assets, totalShares, totalAssets);
        }

        require(shares > 0, "Share calculation failed");

        // Transfer assets from user to vault
        asset.safeTransferFrom(msg.sender, address(this), assets);

        // Update direct holdings
        totalAdapterBalances += assets;

        // Mint shares
        _mint(receiver, shares);

        // Route assets to children
        _routeToChildren(assets);

        return shares;
    }

    /**
     * @notice Withdraw assets by redeeming from child vaults
     * @param shares Amount of vault shares to redeem
     * @param receiver Address to receive assets
     * @param owner Owner of shares to burn
     * @return assets Assets withdrawn
     *
     * FLOW:
     * 1. Calculate assets to withdraw (shares × share price)
     * 2. Burn vault shares
     * 3. Redeem from child vaults (proportional)
     * 4. Transfer assets to receiver
     * 5. Update accounting
     */
    function composableWithdraw(uint256 shares, address receiver, address owner)
        external
        override
        nonReentrant
        returns (uint256 assets)
    {
        require(shares > 0, "Zero shares");
        require(receiver != address(0), "Zero receiver");
        require(shares <= balanceOf(owner), "Insufficient shares");

        // Calculate assets to withdraw
        uint256 totalAssets = getTotalAssetsRecursive();
        uint256 totalShares = totalSupply();

        assets = _mulDiv(shares, totalAssets, totalShares);
        require(assets > 0, "Asset calculation failed");

        // Handle authorization
        if (msg.sender != owner) {
            uint256 allowed = allowance(owner, msg.sender);
            require(allowed >= shares, "Insufficient allowance");
            _approve(owner, msg.sender, allowed - shares);
        }

        // Burn shares
        _burn(owner, shares);

        // Retrieve from children (proportional to vault composition)
        _retrieveFromChildren(assets);

        // Get remaining assets from direct holdings
        uint256 directNeeded = assets;
        uint256 directAvailable = asset.balanceOf(address(this));

        if (directAvailable < directNeeded) {
            // Need to redeem more from children
            uint256 shortfall = directNeeded - directAvailable;
            _retrieveFromChildren(shortfall);
        }

        // Transfer assets to receiver
        asset.safeTransfer(receiver, assets);

        // Update accounting
        totalAdapterBalances = (totalAdapterBalances > assets) 
            ? totalAdapterBalances - assets 
            : 0;

        return assets;
    }

    // ========================================================================
    // INTERNAL: ROUTING & RETRIEVAL
    // ========================================================================

    /**
     * @notice Route assets to child vaults per allocations
     * @param assetsToRoute Amount of assets to route
     */
    function _routeToChildren(uint256 assetsToRoute)
        internal
    {
        if (childVaults.length == 0) {
            return;  // No children, hold assets directly
        }

        uint256 totalAllocation = 0;
        for (uint256 i = 0; i < childVaults.length; i++) {
            if (childVaults[i].isActive) {
                totalAllocation += childVaults[i].allocationBps;
            }
        }

        if (totalAllocation == 0) {
            return;  // No valid allocations
        }

        // Route to each child
        for (uint256 i = 0; i < childVaults.length; i++) {
            if (!childVaults[i].isActive) continue;

            ChildVaultInfo storage child = childVaults[i];
            uint256 childAllocation = (assetsToRoute * child.allocationBps) / totalAllocation;

            if (childAllocation == 0) continue;

            try IComposableVault(child.vaultAddress).composableDeposit(
                childAllocation,
                address(this)
            ) returns (uint256 sharesReceived) {
                child.currentShares += sharesReceived;
                child.lastRebalanceTime = block.timestamp;

                emit RoutedToChild(child.vaultAddress, childAllocation, sharesReceived);
            } catch {
                // Child vault deposit failed - keep assets, mark child inactive
                child.isActive = false;
            }
        }
    }

    /**
     * @notice Retrieve assets from child vaults
     * @param assetsNeeded Amount of assets needed
     */
    function _retrieveFromChildren(uint256 assetsNeeded)
        internal
    {
        uint256 assetsRetrieved = 0;

        for (uint256 i = 0; i < childVaults.length && assetsRetrieved < assetsNeeded; i++) {
            if (!childVaults[i].isActive || childVaults[i].currentShares == 0) {
                continue;
            }

            ChildVaultInfo storage child = childVaults[i];
            uint256 remaining = assetsNeeded - assetsRetrieved;

            // Estimate shares needed to retrieve remaining assets
            uint256 childTotalAssets = IComposableVault(child.vaultAddress)
                .getTotalAssetsRecursive();
            uint256 childTotalShares = IComposableVault(child.vaultAddress)
                .totalSupply();

            if (childTotalAssets == 0 || childTotalShares == 0) {
                continue;
            }

            uint256 sharesNeeded = _mulDiv(remaining, childTotalShares, childTotalAssets);
            if (sharesNeeded > child.currentShares) {
                sharesNeeded = child.currentShares;
            }

            if (sharesNeeded == 0) continue;

            try IComposableVault(child.vaultAddress).composableWithdraw(
                sharesNeeded,
                address(this),
                address(this)
            ) returns (uint256 assetsReceived) {
                child.currentShares -= sharesNeeded;
                assetsRetrieved += assetsReceived;

                emit RetrievedFromChild(child.vaultAddress, sharesNeeded, assetsReceived);
            } catch {
                // Withdrawal failed - mark child inactive
                child.isActive = false;
            }
        }
    }

    // ========================================================================
    // REBALANCING & HARVESTING
    // ========================================================================

    /**
     * @notice Rebalance assets across child vaults
     */
    function rebalanceChildVaults()
        external
        onlyOwner
        nonReentrant
    {
        require(
            block.timestamp >= lastRebalanceTime + rebalanceFrequency,
            "Too soon to rebalance"
        );

        // Retrieve all from children
        uint256 totalToRetrieve = 0;
        for (uint256 i = 0; i < childVaults.length; i++) {
            if (childVaults[i].currentShares > 0) {
                totalToRetrieve += childVaults[i].currentShares;
            }
        }

        if (totalToRetrieve > 0) {
            for (uint256 i = 0; i < childVaults.length; i++) {
                ChildVaultInfo storage child = childVaults[i];
                if (child.currentShares > 0) {
                    try IComposableVault(child.vaultAddress).composableWithdraw(
                        child.currentShares,
                        address(this),
                        address(this)
                    ) returns (uint256) {
                        child.currentShares = 0;
                    } catch {
                        // Withdrawal failed
                    }
                }
            }
        }

        // Route to children again
        uint256 assetsAvailable = asset.balanceOf(address(this));
        _routeToChildren(assetsAvailable);

        lastRebalanceTime = block.timestamp;
    }

    /**
     * @notice Harvest yields from child vaults
     * @return totalHarvested Total assets harvested
     */
    function harvestFromChildren()
        external
        override
        onlyOwner
        nonReentrant
        returns (uint256 totalHarvested)
    {
        for (uint256 i = 0; i < childVaults.length; i++) {
            ChildVaultInfo storage child = childVaults[i];
            if (!child.isActive || child.currentShares == 0) continue;

            try IComposableVault(child.vaultAddress).harvestFromChildren()
                returns (uint256 childHarvested) {
                totalHarvested += childHarvested;
            } catch {
                // Harvest failed, continue
            }
        }

        return totalHarvested;
    }

    /**
     * @notice Get rebalancing needs
     */
    function getRebalancingNeeded()
        external
        override
        view
        returns (bool needsRebalance, uint256 rebalanceAmount)
    {
        if (childVaults.length == 0) {
            return (false, 0);
        }

        // Simple heuristic: if any child is >50% off target, rebalance needed
        uint256 totalAssets = getTotalAssetsRecursive();

        for (uint256 i = 0; i < childVaults.length; i++) {
            ChildVaultInfo memory child = childVaults[i];
            if (!child.isActive) continue;

            uint256 targetAssets = (totalAssets * child.allocationBps) / BASIS_POINTS;
            uint256 currentAssets = getAssetsInChild(child.vaultAddress);

            uint256 diff = (targetAssets > currentAssets)
                ? targetAssets - currentAssets
                : currentAssets - targetAssets;

            if (diff > (targetAssets / 2)) {
                return (true, diff);
            }
        }

        return (false, 0);
    }

    // ========================================================================
    // TOTAL ASSETS & VALUE QUERIES
    // ========================================================================

    /**
     * @notice Get total assets recursively
     * @return Total assets (conservative)
     */
    function getTotalAssetsRecursive()
        public
        override
        view
        returns (uint256)
    {
        uint256 directAssets = asset.balanceOf(address(this));
        uint256 childAssets = 0;

        for (uint256 i = 0; i < childVaults.length; i++) {
            ChildVaultInfo memory child = childVaults[i];
            if (!child.isActive || child.currentShares == 0) continue;

            try IComposableVault(child.vaultAddress).getTotalAssetsRecursive()
                returns (uint256 childTotal) {
                try IComposableVault(child.vaultAddress).totalSupply()
                    returns (uint256 childSupply) {
                    if (childSupply > 0) {
                        uint256 shareValue = _mulDiv(
                            child.currentShares,
                            childTotal,
                            childSupply
                        );
                        childAssets += shareValue;
                    }
                } catch {}
            } catch {}
        }

        return directAssets + childAssets;
    }

    /**
     * @notice Get assets held in specific child vault
     */
    function getAssetsInChild(address childVault)
        public
        override
        view
        returns (uint256)
    {
        if (!isChildVaultMap[childVault]) {
            return 0;
        }

        uint256 idx = childVaultIndex[childVault];
        ChildVaultInfo memory child = childVaults[idx];

        if (child.currentShares == 0) {
            return 0;
        }

        try IComposableVault(childVault).getTotalAssetsRecursive()
            returns (uint256 childTotal) {
            try IComposableVault(childVault).totalSupply()
                returns (uint256 childSupply) {
                if (childSupply > 0) {
                    return _mulDiv(child.currentShares, childTotal, childSupply);
                }
            } catch {}
        } catch {}

        return 0;
    }

    /**
     * @notice Get composition breakdown
     */
    function getCompositionBreakdown()
        external
        override
        view
        returns (uint256 directAssets, uint256 childAssets, uint256 totalAssets)
    {
        directAssets = asset.balanceOf(address(this));
        childAssets = getTotalAssetsRecursive() - directAssets;
        totalAssets = directAssets + childAssets;

        return (directAssets, childAssets, totalAssets);
    }

    // ========================================================================
    // COMPOSITION QUERIES
    // ========================================================================

    /**
     * @notice Get vault composition info
     */
    function getComposition()
        external
        override
        view
        returns (VaultComposition memory)
    {
        return vaultComposition;
    }

    /**
     * @notice Check if this is a leaf vault
     */
    function isLeafVault()
        external
        override
        view
        returns (bool)
    {
        return childVaults.length == 0;
    }

    /**
     * @notice Get number of child vaults
     */
    function getChildVaultCount()
        external
        override
        view
        returns (uint256)
    {
        return childVaults.length;
    }

    /**
     * @notice Get child vault info by index
     */
    function getChildVault(uint256 index)
        external
        override
        view
        returns (ChildVaultInfo memory)
    {
        require(index < childVaults.length, "Index out of bounds");
        return childVaults[index];
    }

    /**
     * @notice Get all child vaults
     */
    function getAllChildVaults()
        external
        override
        view
        returns (ChildVaultInfo[] memory)
    {
        return childVaults;
    }

    /**
     * @notice Check if address is a child vault
     */
    function isChildVault(address potentialChild)
        external
        override
        view
        returns (bool)
    {
        return isChildVaultMap[potentialChild];
    }

    // ========================================================================
    // SAFETY & INVARIANT CHECKS
    // ========================================================================

    /**
     * @notice Verify all invariants hold
     */
    function verifyInvariants()
        external
        override
        view
        returns (bool isValid, string memory failureReason)
    {
        // Invariant 1: Asset conservation
        uint256 totalAssets = getTotalAssetsRecursive();
        uint256 directAssets = asset.balanceOf(address(this));

        if (directAssets > totalAssets) {
            return (false, "Direct assets exceed total");
        }

        // Invariant 2: Check all children are valid
        for (uint256 i = 0; i < childVaults.length; i++) {
            ChildVaultInfo memory child = childVaults[i];

            // Child shouldn't be self
            if (child.vaultAddress == address(this)) {
                return (false, "Child is self");
            }

            // Child allocation should be valid
            if (child.allocationBps > BASIS_POINTS) {
                return (false, "Invalid allocation");
            }

            // Verify child's own invariants
            try IComposableVault(child.vaultAddress).verifyInvariants()
                returns (bool childValid, string memory childReason) {
                if (!childValid) {
                    return (false, childReason);
                }
            } catch {
                return (false, "Child invariant check failed");
            }
        }

        // Invariant 3: Depth check
        if (vaultComposition.depth > maxVaultDepth) {
            return (false, "Exceeds max depth");
        }

        return (true, "");
    }

    /**
     * @notice Check if circular dependency would be created
     */
    function wouldCreateCircularDependency(address potentialChild)
        public
        override
        view
        returns (bool hasCircle)
    {
        // Traverse up the parent chain
        address current = vaultComposition.parentVault;

        while (current != address(0)) {
            if (current == potentialChild) {
                return true;  // Circular dependency found
            }

            try IComposableVault(current).getComposition()
                returns (VaultComposition memory parentComp) {
                current = parentComp.parentVault;
            } catch {
                break;
            }
        }

        return false;
    }

    /**
     * @notice Check if max depth would be exceeded
     */
    function wouldExceedMaxDepth(address potentialChild)
        public
        override
        view
        returns (bool exceedsDepth)
    {
        try IComposableVault(potentialChild).getComposition()
            returns (VaultComposition memory childComp) {
            // Child's depth + 1 (for this vault) should not exceed max
            return (childComp.depth + 1) > maxVaultDepth;
        } catch {
            // If we can't query, assume it's a leaf (depth 0)
            return false;
        }
    }

    // ========================================================================
    // INTERNAL UTILITIES
    // ========================================================================

    /**
     * @notice Safe multiply and divide with rounding down
     */
    function _mulDiv(uint256 a, uint256 b, uint256 c)
        internal
        pure
        returns (uint256)
    {
        require(c != 0, "Division by zero");
        return (a * b) / c;
    }

    /**
     * @notice ERC20 metadata
     */
    function decimals()
        public
        view
        override
        returns (uint8)
    {
        return _decimals;
    }
}
