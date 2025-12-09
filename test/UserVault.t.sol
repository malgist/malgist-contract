// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {UserVault} from "../src/UserVault.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {MockLendingPool} from "../src/mocks/MockLendingPool.sol";
import {LendleAdapter} from "../src/adapters/LendleAdapter.sol";

/**
 * @title UserVaultTest
 * @notice Test suite for UserVault copy-trading functionality
 */
contract UserVaultTest is Test {
    UserVault public vault;
    MockERC20 public usdc;
    MockERC20 public aUsdc;
    MockLendingPool public lendingPool;
    LendleAdapter public lendleAdapter;

    address public alice = address(0x1);
    address public bob = address(0x2);
    address public charlie = address(0x3);

    uint256 constant INITIAL_BALANCE = 10000e6; // 10,000 USDC
    uint256 constant DEPOSIT_AMOUNT = 1000e6; // 1,000 USDC

    function setUp() public {
        // Deploy mock tokens
        usdc = new MockERC20("USD Coin", "USDC", 6);
        aUsdc = new MockERC20("Aave USDC", "aUSDC", 6);

        // Deploy lending pool
        lendingPool = new MockLendingPool();
        lendingPool.setReserveToken(address(usdc), address(aUsdc));

        // Deploy vault
        vault = new UserVault(address(usdc));

        // Deploy adapter
        lendleAdapter = new LendleAdapter(
            address(usdc),
            address(lendingPool),
            address(vault)
        );

        // Mint tokens to users
        usdc.mint(alice, INITIAL_BALANCE);
        usdc.mint(bob, INITIAL_BALANCE);
        usdc.mint(charlie, INITIAL_BALANCE);

        // Approve vault
        vm.prank(alice);
        usdc.approve(address(vault), type(uint256).max);

        vm.prank(bob);
        usdc.approve(address(vault), type(uint256).max);

        vm.prank(charlie);
        usdc.approve(address(vault), type(uint256).max);
    }

    function testSetStrategy() public {
        address[] memory adapters = new address[](1);
        adapters[0] = address(lendleAdapter);

        uint16[] memory ratios = new uint16[](1);
        ratios[0] = 10000; // 100%

        vm.prank(alice);
        vault.setStrategy(adapters, ratios, true, "Alice's Safe Strategy", 10);

        UserVault.Strategy memory strategy = vault.getStrategy(alice);
        assertEq(strategy.adapters.length, 1);
        assertEq(strategy.adapters[0], address(lendleAdapter));
        assertEq(strategy.ratios[0], 10000);
        assertTrue(strategy.isPublic);
        assertEq(strategy.copyFeeBps, 10);
    }

    function testDeposit() public {
        // Alice creates strategy
        address[] memory adapters = new address[](1);
        adapters[0] = address(lendleAdapter);
        uint16[] memory ratios = new uint16[](1);
        ratios[0] = 10000;

        vm.prank(alice);
        vault.setStrategy(adapters, ratios, true, "Test Strategy", 10);

        // Alice deposits
        vm.prank(alice);
        uint256 shares = vault.deposit(DEPOSIT_AMOUNT);

        assertEq(shares, DEPOSIT_AMOUNT);
        assertEq(vault.getStrategy(alice).shares, DEPOSIT_AMOUNT);
        assertGt(lendleAdapter.getBalance(), 0);
    }

    function testCopyStrategy() public {
        // Alice creates public strategy
        address[] memory adapters = new address[](1);
        adapters[0] = address(lendleAdapter);
        uint16[] memory ratios = new uint16[](1);
        ratios[0] = 10000;

        vm.prank(alice);
        vault.setStrategy(adapters, ratios, true, "Alice's Strategy", 10);

        // Bob copies strategy
        vm.prank(bob);
        vault.copyStrategy(alice);

        UserVault.Strategy memory bobStrategy = vault.getStrategy(bob);
        assertEq(bobStrategy.adapters.length, 1);
        assertEq(bobStrategy.adapters[0], address(lendleAdapter));
        assertFalse(bobStrategy.isPublic); // Copy is private by default
    }

    function testCopyFee() public {
        // Alice creates strategy with 0.1% copy fee
        address[] memory adapters = new address[](1);
        adapters[0] = address(lendleAdapter);
        uint16[] memory ratios = new uint16[](1);
        ratios[0] = 10000;

        vm.prank(alice);
        vault.setStrategy(adapters, ratios, true, "Alice's Strategy", 10); // 0.1% fee

        // Bob copies and deposits
        vm.prank(bob);
        vault.copyStrategy(alice);

        uint256 aliceEarningsBefore = vault.copyFeeEarnings(alice);

        vm.prank(bob);
        vault.deposit(DEPOSIT_AMOUNT);

        uint256 aliceEarningsAfter = vault.copyFeeEarnings(alice);
        uint256 expectedFee = (DEPOSIT_AMOUNT * 10) / 10000; // 0.1%

        assertEq(aliceEarningsAfter - aliceEarningsBefore, expectedFee);
    }

    function testClaimCopyFees() public {
        // Setup: Alice creates strategy, Bob copies and deposits
        address[] memory adapters = new address[](1);
        adapters[0] = address(lendleAdapter);
        uint16[] memory ratios = new uint16[](1);
        ratios[0] = 10000;

        vm.prank(alice);
        vault.setStrategy(adapters, ratios, true, "Test", 10);

        vm.prank(bob);
        vault.copyStrategy(alice);

        vm.prank(bob);
        vault.deposit(DEPOSIT_AMOUNT);

        // Alice claims fees
        uint256 aliceBalanceBefore = usdc.balanceOf(alice);
        uint256 expectedFees = vault.copyFeeEarnings(alice);

        vm.prank(alice);
        vault.claimCopyFees();

        uint256 aliceBalanceAfter = usdc.balanceOf(alice);
        assertEq(aliceBalanceAfter - aliceBalanceBefore, expectedFees);
        assertEq(vault.copyFeeEarnings(alice), 0);
    }

    function testWithdraw() public {
        // Alice creates and deposits
        address[] memory adapters = new address[](1);
        adapters[0] = address(lendleAdapter);
        uint16[] memory ratios = new uint16[](1);
        ratios[0] = 10000;

        vm.prank(alice);
        vault.setStrategy(adapters, ratios, true, "Test", 0);

        vm.prank(alice);
        uint256 shares = vault.deposit(DEPOSIT_AMOUNT);

        // Alice withdraws
        uint256 balanceBefore = usdc.balanceOf(alice);

        vm.prank(alice);
        uint256 withdrawn = vault.withdraw(shares);

        uint256 balanceAfter = usdc.balanceOf(alice);
        assertEq(balanceAfter - balanceBefore, withdrawn);
        assertEq(vault.getStrategy(alice).shares, 0);
    }

    function testRevertCannotCopySelf() public {
        address[] memory adapters = new address[](1);
        adapters[0] = address(lendleAdapter);
        uint16[] memory ratios = new uint16[](1);
        ratios[0] = 10000;

        vm.prank(alice);
        vault.setStrategy(adapters, ratios, true, "Test", 0);

        vm.prank(alice);
        vm.expectRevert(UserVault.CannotCopySelf.selector);
        vault.copyStrategy(alice);
    }

    function testRevertCopyPrivateStrategy() public {
        address[] memory adapters = new address[](1);
        adapters[0] = address(lendleAdapter);
        uint16[] memory ratios = new uint16[](1);
        ratios[0] = 10000;

        vm.prank(alice);
        vault.setStrategy(adapters, ratios, false, "Private", 0); // Private

        vm.prank(bob);
        vm.expectRevert(UserVault.StrategyNotPublic.selector);
        vault.copyStrategy(alice);
    }

    function testRevertCopyFeeExceedsMax() public {
        address[] memory adapters = new address[](1);
        adapters[0] = address(lendleAdapter);
        uint16[] memory ratios = new uint16[](1);
        ratios[0] = 10000;

        vm.prank(alice);
        vm.expectRevert(UserVault.CopyFeeExceedsMax.selector);
        vault.setStrategy(adapters, ratios, true, "Test", 51); // 0.51% exceeds max
    }

    function testLeaderboard() public {
        // Alice creates public strategy
        address[] memory adapters = new address[](1);
        adapters[0] = address(lendleAdapter);
        uint16[] memory ratios = new uint16[](1);
        ratios[0] = 10000;

        vm.prank(alice);
        vault.setStrategy(adapters, ratios, true, "Alice's Strategy", 10);

        // Bob creates public strategy
        vm.prank(bob);
        vault.setStrategy(adapters, ratios, true, "Bob's Strategy", 20);

        (
            address[] memory users,
            uint256[] memory copies,
            string[] memory names
        ) = vault.getLeaderboardByCopies(10);

        assertEq(users.length, 2);
        assertTrue(users[0] == alice || users[0] == bob);
    }
}
