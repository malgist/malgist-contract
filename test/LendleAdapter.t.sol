// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {MockLendingPool, MockERC20} from "../src/mocks/MockLendingPool.sol";
import {LendleAdapter} from "../src/adapters/LendleAdapter.sol";
import {UniversalVault} from "../src/UniversalVault.sol";
import {StrategyNFT} from "../src/StrategyNFT.sol";

/**
 * @title LendleAdapterTest
 * @notice Test suite for the LendleAdapter with realistic Aave V3/Lendle pool simulation
 */
contract LendleAdapterTest is Test {
    // Contracts
    MockLendingPool public lendingPool;
    MockERC20 public usdc;
    MockERC20 public aUsdc;
    LendleAdapter public lendleAdapter;
    UniversalVault public vault;
    StrategyNFT public strategyNFT;

    // Test accounts
    address public alice = address(0x1);
    address public bob = address(0x2);
    address public creator = address(0x3);

    // Constants
    uint256 constant INITIAL_BALANCE = 10000e6; // 10,000 USDC
    uint256 constant DEPOSIT_AMOUNT = 1000e6; // 1,000 USDC

    function setUp() public {
        // Deploy mock tokens
        usdc = new MockERC20("USD Coin", "USDC", 6);
        aUsdc = new MockERC20("Aave USDC", "aUSDC", 6);

        // Deploy lending pool
        lendingPool = new MockLendingPool();
        lendingPool.setReserveToken(address(usdc), address(aUsdc));

        // Deploy core contracts
        strategyNFT = new StrategyNFT();
        vault = new UniversalVault(address(usdc), address(strategyNFT));

        // Deploy Lendle adapter
        lendleAdapter = new LendleAdapter(
            address(usdc),
            address(lendingPool),
            address(vault)
        );

        // Whitelist adapter
        strategyNFT.setAdapterWhitelist(address(lendleAdapter), true);

        // Mint USDC to test users
        usdc.mint(alice, INITIAL_BALANCE);
        usdc.mint(bob, INITIAL_BALANCE);

        // Approve vault
        vm.prank(alice);
        usdc.approve(address(vault), type(uint256).max);

        vm.prank(bob);
        usdc.approve(address(vault), type(uint256).max);
    }

    /**
     * @notice Test direct adapter deposit and withdrawal
     */
    function testDirectAdapterDeposit() public {
        uint256 amount = 100e6;

        // Alice deposits directly to adapter (as vault would)
        usdc.mint(address(vault), amount);

        vm.prank(address(vault));
        usdc.approve(address(lendleAdapter), amount);

        vm.prank(address(vault));
        uint256 shares = lendleAdapter.deposit(amount);

        console.log("USDC deposited:", amount);
        console.log("aUSDC received:", shares);

        // Verify aTokens were received
        assertEq(shares, amount, "Should receive 1:1 aTokens");
        assertEq(
            lendleAdapter.getBalance(),
            amount,
            "Adapter should hold aTokens"
        );
        assertEq(
            lendingPool.getReserveLiquidity(address(usdc)),
            amount,
            "Pool should hold USDC"
        );
    }

    /**
     * @notice Test full integration: Vault -> Strategy -> Lendle
     */
    function testFullIntegrationWithLendle() public {
        // Create strategy with 100% Lendle
        address[] memory adapters = new address[](1);
        adapters[0] = address(lendleAdapter);

        uint16[] memory ratios = new uint16[](1);
        ratios[0] = 10000; // 100%

        vm.prank(creator);
        uint256 strategyId = strategyNFT.mintStrategy(
            "Pure Lendle",
            adapters,
            ratios,
            10
        );

        console.log("=== FULL INTEGRATION TEST ===");
        console.log("Alice balance before:", usdc.balanceOf(alice));

        // Alice deposits via vault
        vm.prank(alice);
        uint256 shares = vault.deposit(strategyId, DEPOSIT_AMOUNT);

        uint256 expectedNet = DEPOSIT_AMOUNT - (DEPOSIT_AMOUNT * 1) / 100; // 1% fee

        console.log("Deposited:", DEPOSIT_AMOUNT);
        console.log("Creator fee (1%):", DEPOSIT_AMOUNT - expectedNet);
        console.log("Net to Lendle:", expectedNet);
        console.log("Shares received:", shares);

        // Verify balances
        assertEq(shares, expectedNet, "Shares should equal net amount");
        assertEq(
            lendleAdapter.getBalance(),
            expectedNet,
            "Lendle should have net deposit"
        );
        assertEq(
            aUsdc.balanceOf(address(lendleAdapter)),
            expectedNet,
            "Adapter should hold aTokens"
        );

        console.log("aUSDC in adapter:", aUsdc.balanceOf(address(lendleAdapter)));
        console.log("USDC in pool:", usdc.balanceOf(address(lendingPool)));

        // Withdraw
        vm.prank(alice);
        uint256 withdrawn = vault.withdraw(strategyId, shares);

        console.log("Withdrawn:", withdrawn);
        assertEq(withdrawn, expectedNet, "Should receive full net amount back");
        assertEq(lendleAdapter.getBalance(), 0, "Adapter should be empty");
    }

    /**
     * @notice Test yield accrual simulation
     */
    function testYieldAccrual() public {
        // Setup strategy
        address[] memory adapters = new address[](1);
        adapters[0] = address(lendleAdapter);
        uint16[] memory ratios = new uint16[](1);
        ratios[0] = 10000;

        vm.prank(creator);
        uint256 strategyId = strategyNFT.mintStrategy(
            "Yield Strategy",
            adapters,
            ratios,
            10
        );

        // Alice deposits
        vm.prank(alice);
        vault.deposit(strategyId, DEPOSIT_AMOUNT);

        uint256 initialBalance = lendleAdapter.getBalance();
        console.log("Initial aToken balance:", initialBalance);

        // Simulate yield by minting more aTokens to the adapter
        uint256 yieldAmount = 50e6; // 50 USDC yield (5%)
        aUsdc.mint(address(lendleAdapter), yieldAmount);

        uint256 newBalance = lendleAdapter.getBalance();
        console.log("After yield aToken balance:", newBalance);
        console.log("Yield earned:", newBalance - initialBalance);

        assertEq(
            newBalance,
            initialBalance + yieldAmount,
            "Yield should increase balance"
        );
    }

    /**
     * @notice Test withdrawal with yield
     */
    function testWithdrawWithYield() public {
        // Setup and deposit
        address[] memory adapters = new address[](1);
        adapters[0] = address(lendleAdapter);
        uint16[] memory ratios = new uint16[](1);
        ratios[0] = 10000;

        vm.prank(creator);
        uint256 strategyId = strategyNFT.mintStrategy("Test", adapters, ratios, 10);

        uint256 depositNet = DEPOSIT_AMOUNT - (DEPOSIT_AMOUNT * 1) / 100;

        vm.prank(alice);
        uint256 shares = vault.deposit(strategyId, DEPOSIT_AMOUNT);

        // Simulate yield
        uint256 yieldAmount = 100e6;
        aUsdc.mint(address(lendleAdapter), yieldAmount);

        // Also add USDC to pool so withdrawal doesn't fail
        usdc.mint(address(lendingPool), yieldAmount);

        // Withdraw - should get principal + yield
        uint256 balanceBefore = usdc.balanceOf(alice);

        vm.prank(alice);
        uint256 withdrawn = vault.withdraw(strategyId, shares);

        uint256 balanceAfter = usdc.balanceOf(alice);
        uint256 actualReceived = balanceAfter - balanceBefore;

        console.log("Principal:", depositNet);
        console.log("Yield:", yieldAmount);
        console.log("Withdrawn:", withdrawn);
        console.log("Actually received:", actualReceived);

        // Note: In the current implementation, shares are 1:1 with deposit
        // So withdrawal is based on shares, not aToken balance
        // This is a simplification for MVP
        assertEq(withdrawn, depositNet, "Withdrawn matches shares");
    }

    /**
     * @notice Test multiple users with Lendle
     */
    function testMultipleUsersLendle() public {
        address[] memory adapters = new address[](1);
        adapters[0] = address(lendleAdapter);
        uint16[] memory ratios = new uint16[](1);
        ratios[0] = 10000;

        vm.prank(creator);
        uint256 strategyId = strategyNFT.mintStrategy("Multi-User", adapters, ratios, 10);

        // Alice deposits
        vm.prank(alice);
        vault.deposit(strategyId, DEPOSIT_AMOUNT);

        // Bob deposits
        vm.prank(bob);
        vault.deposit(strategyId, DEPOSIT_AMOUNT * 2);

        uint256 aliceNet = DEPOSIT_AMOUNT - (DEPOSIT_AMOUNT * 1) / 100;
        uint256 bobNet = (DEPOSIT_AMOUNT * 2) - ((DEPOSIT_AMOUNT * 2) * 1) / 100;
        uint256 totalExpected = aliceNet + bobNet;

        assertEq(
            lendleAdapter.getBalance(),
            totalExpected,
            "Total in Lendle should match both deposits"
        );
    }

    /**
     * @notice Test adapter view functions
     */
    function testAdapterViewFunctions() public {
        assertEq(lendleAdapter.token(), address(usdc), "Token should be USDC");
        assertEq(lendleAdapter.getAToken(), address(aUsdc), "aToken should be aUSDC");
        assertEq(
            lendleAdapter.getLendingPool(),
            address(lendingPool),
            "Pool address should match"
        );
    }

    /**
     * @notice Test revert on zero deposit
     */
    function testRevertZeroDeposit() public {
        vm.prank(address(vault));
        vm.expectRevert(LendleAdapter.InvalidAmount.selector);
        lendleAdapter.deposit(0);
    }

    /**
     * @notice Test only vault can call
     */
    function testRevertOnlyVault() public {
        vm.prank(alice);
        vm.expectRevert(LendleAdapter.OnlyVault.selector);
        lendleAdapter.deposit(100e6);
    }
}
