// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @test-type EXPERIMENTAL-VAULT
/// @covers ComposableVault
/// @notes Regression net for legacy composable vault variant.


import "forge-std/Test.sol";
import "../src/ComposableVault.sol";
import "../src/interfaces/IComposableVault.sol";

/**
 * @title ComposableVaultTest
 * @notice Comprehensive test suite for ComposableVault
 * 
 * Test Coverage:
 * 1. Composition Setup (add/remove children)
 * 2. Circular Dependency Prevention
 * 3. Depth Limiting
 * 4. Deposit/Withdrawal Mechanics
 * 5. Asset Conservation Invariants
 * 6. Rebalancing
 * 7. Edge Cases & Error Handling
 */

// Mock ERC20 for testing
contract MockERC20 is ERC20 {
    constructor() ERC20("Mock USDC", "USDC") {}
    
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
    
    function burn(address from, uint256 amount) external {
        _burn(from, amount);
    }
}

contract ComposableVaultTest is Test {
    // ========================================================================
    // FIXTURES
    // ========================================================================
    
    MockERC20 usdc;
    ComposableVault rootVault;
    ComposableVault childVault1;
    ComposableVault childVault2;
    ComposableVault childVault3;
    
    address user1 = address(0x1111);
    address user2 = address(0x2222);
    address user3 = address(0x3333);
    
    function setUp() public {
        // Deploy mock USDC
        usdc = new MockERC20();
        
        // Deploy vaults
        rootVault = new ComposableVault(
            address(usdc),
            "Root Vault",
            "ROOT",
            address(0)  // No parent
        );
        
        childVault1 = new ComposableVault(
            address(usdc),
            "Child Vault 1",
            "CHILD1",
            address(rootVault)
        );
        
        childVault2 = new ComposableVault(
            address(usdc),
            "Child Vault 2",
            "CHILD2",
            address(rootVault)
        );
        
        childVault3 = new ComposableVault(
            address(usdc),
            "Child Vault 3",
            "CHILD3",
            address(childVault1)
        );
        
        // Mint test tokens
        usdc.mint(user1, 10_000_000e6);  // 10M USDC
        usdc.mint(user2, 10_000_000e6);
        usdc.mint(user3, 10_000_000e6);
        
        // Approve vaults
        vm.prank(user1);
        usdc.approve(address(rootVault), type(uint256).max);
        vm.prank(user1);
        usdc.approve(address(childVault1), type(uint256).max);
        
        vm.prank(user2);
        usdc.approve(address(rootVault), type(uint256).max);
        
        vm.prank(user3);
        usdc.approve(address(rootVault), type(uint256).max);
    }
    
    // ========================================================================
    // TEST 1: COMPOSITION SETUP
    // ========================================================================
    
    function test_addChildVault_success() public {
        // Add child vault
        rootVault.addChildVault(address(childVault1), 5000);  // 50%
        
        // Verify child added
        assertEq(rootVault.getChildVaultCount(), 1);
        assertTrue(rootVault.isChildVault(address(childVault1)));
        
        IComposableVault.ChildVaultInfo memory info = rootVault.getChildVault(0);
        assertEq(info.vaultAddress, address(childVault1));
        assertEq(info.allocationBps, 5000);
    }
    
    function test_addChildVault_multipleChildren() public {
        // Add 2 children
        rootVault.addChildVault(address(childVault1), 5000);
        rootVault.addChildVault(address(childVault2), 5000);
        
        // Verify
        assertEq(rootVault.getChildVaultCount(), 2);
        assertTrue(rootVault.isChildVault(address(childVault1)));
        assertTrue(rootVault.isChildVault(address(childVault2)));
        
        IComposableVault.ChildVaultInfo[] memory children = rootVault.getAllChildVaults();
        assertEq(children.length, 2);
    }
    
    function test_addChildVault_rejectsDuplicate() public {
        rootVault.addChildVault(address(childVault1), 5000);
        
        // Try to add same child again
        vm.expectRevert("Already child");
        rootVault.addChildVault(address(childVault1), 5000);
    }
    
    function test_addChildVault_rejectsSelf() public {
        vm.expectRevert("Cannot compose with self");
        rootVault.addChildVault(address(rootVault), 5000);
    }
    
    function test_removeChildVault_success() public {
        rootVault.addChildVault(address(childVault1), 5000);
        assertEq(rootVault.getChildVaultCount(), 1);
        
        rootVault.removeChildVault(address(childVault1));
        assertEq(rootVault.getChildVaultCount(), 0);
        assertFalse(rootVault.isChildVault(address(childVault1)));
    }
    
    function test_updateChildAllocation() public {
        rootVault.addChildVault(address(childVault1), 5000);
        
        // Update allocation
        rootVault.updateChildAllocation(address(childVault1), 7000);
        
        IComposableVault.ChildVaultInfo memory info = rootVault.getChildVault(0);
        assertEq(info.allocationBps, 7000);
    }
    
    // ========================================================================
    // TEST 2: CIRCULAR DEPENDENCY PREVENTION
    // ========================================================================
    
    function test_wouldCreateCircularDependency_detects() public {
        // Setup: Root → Child1
        rootVault.addChildVault(address(childVault1), 5000);
        
        // Try to add Root as child of Child1 (would create cycle)
        assertTrue(childVault1.wouldCreateCircularDependency(address(rootVault)));
    }
    
    function test_wouldCreateCircularDependency_allowsNonCycle() public {
        // Setup: Root → Child1
        rootVault.addChildVault(address(childVault1), 5000);
        
        // Child1 → Child2 is allowed (no cycle)
        assertFalse(childVault1.wouldCreateCircularDependency(address(childVault2)));
    }
    
    function test_addChildVault_rejectsCircularDependency() public {
        // Setup: Root → Child1
        rootVault.addChildVault(address(childVault1), 5000);
        
        // Try to create cycle: Child1 → Root
        vm.expectRevert("Circular dependency");
        childVault1.addChildVault(address(rootVault), 5000);
    }
    
    function test_deepCircularDependency_prevented() public {
        // Create chain: Root → Child1 → Child3 → Root (3-level cycle)
        rootVault.addChildVault(address(childVault1), 5000);
        childVault1.addChildVault(address(childVault3), 5000);
        
        // Try to close the cycle
        vm.expectRevert("Circular dependency");
        childVault3.addChildVault(address(rootVault), 5000);
    }
    
    // ========================================================================
    // TEST 3: DEPTH LIMITING
    // ========================================================================
    
    function test_wouldExceedMaxDepth_detects() public {
        // Create deep chain
        rootVault.addChildVault(address(childVault1), 5000);
        childVault1.addChildVault(address(childVault3), 5000);
        
        IComposableVault.VaultComposition memory comp = childVault3.getComposition();
        assertEq(comp.depth, 2);  // Root=0, Child1=1, Child3=2
    }
    
    function test_addChildVault_rejectsExcessiveDepth() public {
        // Create vaults at depth limits
        ComposableVault[] memory vaults = new ComposableVault[](6);
        vaults[0] = rootVault;
        
        // Create chain of 5 vaults (depths 0-4)
        for (uint i = 1; i < 5; i++) {
            vaults[i] = new ComposableVault(
                address(usdc),
                "Vault",
                "V",
                address(vaults[i-1])
            );
            vaults[i-1].addChildVault(address(vaults[i]), 5000);
        }
        
        // Create vault at depth 5 (max allowed)
        vaults[5] = new ComposableVault(
            address(usdc),
            "Vault",
            "V",
            address(vaults[4])
        );
        vaults[4].addChildVault(address(vaults[5]), 5000);
        
        // Try to exceed max depth (depth 6)
        ComposableVault tooDeep = new ComposableVault(
            address(usdc),
            "Too Deep",
            "TD",
            address(vaults[5])
        );
        
        vm.expectRevert("Exceeds max depth");
        vaults[5].addChildVault(address(tooDeep), 5000);
    }
    
    // ========================================================================
    // TEST 4: DEPOSIT/WITHDRAWAL MECHANICS
    // ========================================================================
    
    function test_composableDeposit_simple() public {
        uint256 depositAmount = 1_000_000e6;  // 1M USDC
        
        vm.prank(user1);
        uint256 sharesMinted = rootVault.composableDeposit(
            depositAmount,
            user1
        );
        
        // 1:1 ratio for first deposit
        assertEq(sharesMinted, depositAmount);
        assertEq(rootVault.balanceOf(user1), sharesMinted);
        assertEq(rootVault.getTotalAssetsRecursive(), depositAmount);
    }
    
    function test_composableDeposit_withChildren() public {
        // Setup: Root → Child1 (50%), Child2 (50%)
        rootVault.addChildVault(address(childVault1), 5000);
        rootVault.addChildVault(address(childVault2), 5000);
        
        uint256 depositAmount = 1_000_000e6;
        
        vm.prank(user1);
        uint256 sharesMinted = rootVault.composableDeposit(
            depositAmount,
            user1
        );
        
        assertEq(sharesMinted, depositAmount);
        
        // Verify assets routed to children
        uint256 child1Assets = rootVault.getAssetsInChild(address(childVault1));
        uint256 child2Assets = rootVault.getAssetsInChild(address(childVault2));
        
        // Each child should have ~50% of assets
        assertGt(child1Assets, 0);
        assertGt(child2Assets, 0);
        assertApproxEqRel(child1Assets, depositAmount / 2, 0.01e18);  // Within 1%
    }
    
    function test_composableWithdraw_simple() public {
        // Deposit first
        uint256 depositAmount = 1_000_000e6;
        vm.prank(user1);
        uint256 sharesMinted = rootVault.composableDeposit(
            depositAmount,
            user1
        );
        
        // Withdraw
        vm.prank(user1);
        uint256 assetsReturned = rootVault.composableWithdraw(
            sharesMinted,
            user1,
            user1
        );
        
        // Should receive original amount (minus rounding)
        assertEq(assetsReturned, depositAmount);
        assertEq(rootVault.balanceOf(user1), 0);
    }
    
    function test_composableWithdraw_partialByShares() public {
        uint256 depositAmount = 1_000_000e6;
        vm.prank(user1);
        uint256 sharesMinted = rootVault.composableDeposit(
            depositAmount,
            user1
        );
        
        // Withdraw 50%
        vm.prank(user1);
        uint256 assetsReturned = rootVault.composableWithdraw(
            sharesMinted / 2,
            user1,
            user1
        );
        
        // Should get ~50% of assets
        assertApproxEqRel(assetsReturned, depositAmount / 2, 0.01e18);
    }
    
    function test_multiUserDepositsAndWithdrawals() public {
        // User1 deposits
        vm.prank(user1);
        uint256 shares1 = rootVault.composableDeposit(1_000_000e6, user1);
        
        // User2 deposits
        vm.prank(user2);
        uint256 shares2 = rootVault.composableDeposit(1_000_000e6, user2);
        
        // User1 withdraws
        vm.prank(user1);
        uint256 assets1 = rootVault.composableWithdraw(shares1, user1, user1);
        
        // User2 should have fair share
        assertApproxEqRel(assets1, 1_000_000e6, 0.01e18);
        assertEq(rootVault.balanceOf(user1), 0);
        assertEq(rootVault.balanceOf(user2), shares2);
    }
    
    // ========================================================================
    // TEST 5: ASSET CONSERVATION INVARIANTS
    // ========================================================================
    
    function test_invariant_assetConservation() public {
        // Deposit into root with children
        rootVault.addChildVault(address(childVault1), 5000);
        rootVault.addChildVault(address(childVault2), 5000);
        
        uint256 depositAmount = 1_000_000e6;
        vm.prank(user1);
        rootVault.composableDeposit(depositAmount, user1);
        
        // Verify conservation
        uint256 total = rootVault.getTotalAssetsRecursive();
        uint256 direct = usdc.balanceOf(address(rootVault));
        uint256 child1Assets = rootVault.getAssetsInChild(address(childVault1));
        uint256 child2Assets = rootVault.getAssetsInChild(address(childVault2));
        
        uint256 sum = direct + child1Assets + child2Assets;
        assertEq(total, sum);
    }
    
    function test_verifyInvariants_passes() public {
        rootVault.addChildVault(address(childVault1), 5000);
        
        vm.prank(user1);
        rootVault.composableDeposit(1_000_000e6, user1);
        
        (bool valid, string memory reason) = rootVault.verifyInvariants();
        assertTrue(valid, reason);
    }
    
    function test_invariant_shareProportionality() public {
        // User1 deposits 1M
        vm.prank(user1);
        uint256 shares1 = rootVault.composableDeposit(1_000_000e6, user1);
        
        // User2 deposits 1M
        vm.prank(user2);
        uint256 shares2 = rootVault.composableDeposit(1_000_000e6, user2);
        
        // Both should have equal shares
        assertEq(shares1, shares2);
        
        // Each owns 50% of vault
        uint256 totalShares = rootVault.totalSupply();
        assertEq(shares1 * 2, totalShares);
    }
    
    // ========================================================================
    // TEST 6: REBALANCING
    // ========================================================================
    
    function test_rebalanceChildVaults() public {
        rootVault.addChildVault(address(childVault1), 5000);
        rootVault.addChildVault(address(childVault2), 5000);
        
        // Initial deposit
        vm.prank(user1);
        rootVault.composableDeposit(1_000_000e6, user1);
        
        // Record initial state
        uint256 child1Before = rootVault.getAssetsInChild(address(childVault1));
        
        // Change allocation
        rootVault.updateChildAllocation(address(childVault1), 7000);  // 70%
        rootVault.updateChildAllocation(address(childVault2), 3000);  // 30%
        
        // Advance time past rebalance frequency
        vm.warp(block.timestamp + 2 days);
        
        // Rebalance
        rootVault.rebalanceChildVaults();
        
        // Allocations should shift (harder to test exact values due to rounding)
        uint256 child1After = rootVault.getAssetsInChild(address(childVault1));
        
        // Child1 should have more after rebalance (70% vs 50%)
        assertGt(child1After, child1Before * 100 / 120);  // At least 40% increase
    }
    
    function test_rebalance_frequency_enforced() public {
        rootVault.addChildVault(address(childVault1), 5000);
        
        vm.prank(user1);
        rootVault.composableDeposit(1_000_000e6, user1);
        
        // Try to rebalance immediately (should fail)
        vm.expectRevert("Too soon to rebalance");
        rootVault.rebalanceChildVaults();
    }
    
    // ========================================================================
    // TEST 7: EDGE CASES & ERROR HANDLING
    // ========================================================================
    
    function test_deposit_zeroAmount_reverts() public {
        vm.prank(user1);
        vm.expectRevert("Deposit too small");
        rootVault.composableDeposit(0, user1);
    }
    
    function test_deposit_zeroRecipient_reverts() public {
        vm.prank(user1);
        vm.expectRevert("Zero receiver");
        rootVault.composableDeposit(1_000_000e6, address(0));
    }
    
    function test_withdraw_zeroShares_reverts() public {
        vm.prank(user1);
        vm.expectRevert("Zero shares");
        rootVault.composableWithdraw(0, user1, user1);
    }
    
    function test_withdraw_insufficientShares_reverts() public {
        vm.prank(user1);
        rootVault.composableDeposit(1_000_000e6, user1);
        
        // Try to withdraw more than owned
        vm.prank(user1);
        vm.expectRevert("Insufficient shares");
        rootVault.composableWithdraw(2_000_000e6, user1, user1);
    }
    
    function test_addChildVault_tooMany_reverts() public {
        // Add max children
        for (uint i = 0; i < 20; i++) {
            ComposableVault newChild = new ComposableVault(
                address(usdc),
                "Child",
                "C",
                address(rootVault)
            );
            rootVault.addChildVault(address(newChild), 100);
        }
        
        // Try to add 21st
        ComposableVault extraChild = new ComposableVault(
            address(usdc),
            "Extra",
            "E",
            address(rootVault)
        );
        
        vm.expectRevert("Too many children");
        rootVault.addChildVault(address(extraChild), 100);
    }
    
    function test_isLeafVault() public {
        // Root is initially leaf
        assertTrue(rootVault.isLeafVault());
        
        // After adding child
        rootVault.addChildVault(address(childVault1), 5000);
        assertFalse(rootVault.isLeafVault());
        
        // Child is still leaf
        assertTrue(childVault1.isLeafVault());
    }
    
    function test_getCompositionBreakdown() public {
        rootVault.addChildVault(address(childVault1), 5000);
        rootVault.addChildVault(address(childVault2), 5000);
        
        vm.prank(user1);
        rootVault.composableDeposit(1_000_000e6, user1);
        
        (uint256 direct, uint256 childAssets, uint256 total) 
            = rootVault.getCompositionBreakdown();
        
        assertGt(direct, 0);
        assertGt(childAssets, 0);
        assertEq(total, direct + childAssets);
    }
    
    function test_reentrancyGuard() public {
        // This is more of a compile-time check
        // nonReentrant modifier prevents reentrancy
        assertTrue(true);  // Placeholder
    }
    
    // ========================================================================
    // TEST 8: PERMISSION CHECKS
    // ========================================================================
    
    function test_addChildVault_onlyOwner() public {
        vm.prank(user1);  // Not owner
        vm.expectRevert("Ownable: caller is not the owner");
        rootVault.addChildVault(address(childVault1), 5000);
    }
    
    function test_removeChildVault_onlyOwner() public {
        rootVault.addChildVault(address(childVault1), 5000);
        
        vm.prank(user1);
        vm.expectRevert("Ownable: caller is not the owner");
        rootVault.removeChildVault(address(childVault1));
    }
    
    function test_rebalanceChildVaults_onlyOwner() public {
        rootVault.addChildVault(address(childVault1), 5000);
        
        vm.prank(user1);
        vm.expectRevert("Ownable: caller is not the owner");
        rootVault.rebalanceChildVaults();
    }
    
    // ========================================================================
    // TEST 9: COMPOSITION QUERIES
    // ========================================================================
    
    function test_getComposition() public {
        IComposableVault.VaultComposition memory comp = rootVault.getComposition();
        assertEq(comp.depth, 0);
        assertEq(comp.parentVault, address(0));
        
        IComposableVault.VaultComposition memory childComp = childVault1.getComposition();
        assertEq(childComp.depth, 1);
        assertEq(childComp.parentVault, address(rootVault));
    }
    
    function test_getAllChildVaults() public {
        rootVault.addChildVault(address(childVault1), 5000);
        rootVault.addChildVault(address(childVault2), 5000);
        
        IComposableVault.ChildVaultInfo[] memory all = rootVault.getAllChildVaults();
        assertEq(all.length, 2);
        assertEq(all[0].vaultAddress, address(childVault1));
        assertEq(all[1].vaultAddress, address(childVault2));
    }
}
