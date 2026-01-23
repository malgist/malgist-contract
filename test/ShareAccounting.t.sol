// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @test-type CORE-ACCOUNTING
/// @covers UserVault
/// @notes Verifies share mint/burn + reconcile flows around adapters.


import "forge-std/Test.sol";
import "../src/mocks/MockERC20.sol";
import "../src/mocks/MockAdapter.sol";
import "../src/UserVault.sol";

contract ShareAccountingTest is Test {
    MockERC20 token;
    MockAdapter adapter;
    UserVault vault;

    address alice = address(0xA11ce);
    address bob = address(0xB0b);

    function setUp() public {
        token = new MockERC20("MockUSD", "MUSD", 6);
        adapter = new MockAdapter(address(token));
        // deploy vault with this test contract as pauseOwner so we can call reconcile
        vault = new UserVault(address(token), address(this));

        // Mint tokens to users
        token.mint(alice, 1_000_000 * 1e6);
        token.mint(bob, 1_000_000 * 1e6);

        // Give allowances in tests when needed
        vm.prank(alice);
        token.approve(address(vault), type(uint256).max);

        vm.prank(bob);
        token.approve(address(vault), type(uint256).max);
    }

    function test_deposit_and_reconcile_yield() public {
        // Alice sets a single-adapter strategy
        address[] memory adapters = new address[](1);
        adapters[0] = address(adapter);
        uint16[] memory ratios = new uint16[](1);
        ratios[0] = 10000;
        vm.prank(alice);
        vault.setStrategy(adapters, ratios, true, "Alice strat", 0);

        // Alice deposit 1_000 tokens
        uint256 amount = 1_000 * 1e6;
        vm.prank(alice);
        uint256 minted = vault.deposit(amount);

        assertEq(minted, amount);
        assertEq(vault.totalShares(), amount);
        assertEq(vault.userShares(alice), amount);
        assertEq(vault.totalAssets(), amount);

        // Simulate yield on adapter: mint 100 tokens
        adapter.mint(address(0xDEAD), 100 * 1e6);

        // Adapter reports increased TVL; reconcile as pauseOwner (this)
        vault.reconcileAdapter(address(adapter));

        // totalAssets should increase by 100
        assertEq(vault.totalAssets(), amount + 100 * 1e6);
        // user shares unchanged
        assertEq(vault.userShares(alice), amount);

        // Now withdraw half shares
        vm.prank(alice);
        uint256 withdrawn = vault.withdraw(amount / 2);
        // withdrawn should be roughly half of totalAssets pre-withdraw
        // Because we burned half of shares
        assertGe(withdrawn, 500 * 1e6);
        assertLe(withdrawn, 600 * 1e6);

        // totalShares should be reduced
        assertEq(vault.totalShares(), amount - (amount / 2));
    }

    function test_loss_and_reconcile() public {
        // Alice deposit again
        address[] memory adapters = new address[](1);
        adapters[0] = address(adapter);
        uint16[] memory ratios = new uint16[](1);
        ratios[0] = 10000;
        vm.prank(alice);
        vault.setStrategy(adapters, ratios, true, "Alice strat", 0);

        uint256 amount = 1_000 * 1e6;
        vm.prank(alice);
        vault.deposit(amount);

        // Simulate loss on adapter
        adapter.slash(200 * 1e6);

        // Reconcile should reduce totalAssets
        vault.reconcileAdapter(address(adapter));
        assertEq(vault.totalAssets(), amount - 200 * 1e6);
    }

    function test_multi_user_proportional_shares() public {
        // Alice strategy
        address[] memory adaptersA = new address[](1);
        adaptersA[0] = address(adapter);
        uint16[] memory ratiosA = new uint16[](1);
        ratiosA[0] = 10000;
        vm.prank(alice);
        vault.setStrategy(adaptersA, ratiosA, true, "Alice strat", 0);

        // Bob strategy
        address[] memory adaptersB = new address[](1);
        adaptersB[0] = address(adapter);
        uint16[] memory ratiosB = new uint16[](1);
        ratiosB[0] = 10000;
        vm.prank(bob);
        vault.setStrategy(adaptersB, ratiosB, true, "Bob strat", 0);

        // Alice deposits 1000
        vm.prank(alice);
        vault.deposit(1_000 * 1e6);

        // Bob deposits 500
        vm.prank(bob);
        vault.deposit(500 * 1e6);

        // Check share proportions: Alice should have double Bob
        assertEq(vault.userShares(alice), 2 * vault.userShares(bob));
    }
}
