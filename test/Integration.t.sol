// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";

// Core contracts
import {UniversalVault} from "../src/UniversalVault.sol";
import {StrategyNFT} from "../src/StrategyNFT.sol";

// Adapters
import {LendleAdapter} from "../src/adapters/LendleAdapter.sol";
import {FusionXAdapter} from "../src/adapters/FusionXAdapter.sol";

// Mocks
import {MockERC20, MockLendingPool} from "../src/mocks/MockLendingPool.sol";
import {MockUniswapV2Pair} from "../src/mocks/MockUniswapV2Pair.sol";
import {MockUniswapV2Router} from "../src/mocks/MockUniswapV2Router.sol";

/**
 * @title IntegrationTest
 * @notice Comprehensive end-to-end integration tests for the entire Mantle Strategy Studio
 * @dev Tests multi-adapter strategies with real-world scenario simulations
 */
contract IntegrationTest is Test {
    // Core contracts
    UniversalVault public vault;
    StrategyNFT public strategyNFT;

    // Adapters
    LendleAdapter public lendleAdapter;
    FusionXAdapter public fusionXAdapter;

    // Mock protocols
    MockLendingPool public lendingPool;
    MockUniswapV2Router public dexRouter;

    // Tokens
    MockERC20 public usdc;
    MockERC20 public aUsdc;
    MockERC20 public mnt;
    MockUniswapV2Pair public lpToken;

    // Test accounts
    address public alice = address(0x1);
    address public bob = address(0x2);
    address public creator = address(0x3);

    // Constants
    uint256 constant INITIAL_BALANCE = 100000e6; // 100,000 USDC
    uint256 constant DEPOSIT_AMOUNT = 1000e6; // 1,000 USDC

    function setUp() public {
        console.log("=== INTEGRATION TEST SETUP ===");

        // Deploy tokens
        usdc = new MockERC20("USD Coin", "USDC", 6);
        aUsdc = new MockERC20("Aave USDC", "aUSDC", 6);
        mnt = new MockERC20("Mantle", "MNT", 18);

        console.log("Deployed tokens:");
        console.log("  USDC:", address(usdc));
        console.log("  aUSDC:", address(aUsdc));
        console.log("  MNT:", address(mnt));

        // Deploy lending pool
        lendingPool = new MockLendingPool();
        lendingPool.setReserveToken(address(usdc), address(aUsdc));
        console.log("Deployed Lendle Pool:", address(lendingPool));

        // Deploy DEX infrastructure
        lpToken = new MockUniswapV2Pair(
            address(usdc),
            address(mnt),
            "FusionX USDC-MNT LP",
            "FUSION-LP"
        );
        dexRouter = new MockUniswapV2Router();
        dexRouter.createPair(address(usdc), address(mnt), address(lpToken));
        console.log("Deployed DEX Router:", address(dexRouter));
        console.log("Deployed LP Token:", address(lpToken));

        // Deploy core contracts
        strategyNFT = new StrategyNFT();
        vault = new UniversalVault(address(usdc), address(strategyNFT));
        console.log("Deployed StrategyNFT:", address(strategyNFT));
        console.log("Deployed Vault:", address(vault));

        // Deploy adapters
        lendleAdapter = new LendleAdapter(
            address(usdc),
            address(lendingPool),
            address(vault)
        );
        fusionXAdapter = new FusionXAdapter(
            address(usdc),
            address(mnt),
            address(lpToken),
            address(dexRouter),
            address(vault)
        );
        console.log("Deployed LendleAdapter:", address(lendleAdapter));
        console.log("Deployed FusionXAdapter:", address(fusionXAdapter));

        // Whitelist adapters
        strategyNFT.setAdapterWhitelist(address(lendleAdapter), true);
        strategyNFT.setAdapterWhitelist(address(fusionXAdapter), true);

        // Mint tokens to users
        usdc.mint(alice, INITIAL_BALANCE);
        usdc.mint(bob, INITIAL_BALANCE);

        // Mint MNT to router for swaps
        mnt.mint(address(dexRouter), INITIAL_BALANCE * 100);

        // Approve vault
        vm.prank(alice);
        usdc.approve(address(vault), type(uint256).max);

        vm.prank(bob);
        usdc.approve(address(vault), type(uint256).max);

        console.log("Setup complete!\n");
    }

    /**
     * @notice Test end-to-end flow with 50% Lendle + 50% FusionX strategy
     */
    function testE2E_MultiAdapterStrategy() public {
        console.log("=== E2E TEST: 50% LENDLE + 50% FUSIONX ===\n");

        // Step 1: Create strategy
        address[] memory adapters = new address[](2);
        adapters[0] = address(lendleAdapter);
        adapters[1] = address(fusionXAdapter);

        uint16[] memory ratios = new uint16[](2);
        ratios[0] = 5000; // 50%
        ratios[1] = 5000; // 50%

        vm.prank(creator);
        uint256 strategyId = strategyNFT.mintStrategy(
            "Balanced Lending + DEX",
            adapters,
            ratios,
            100 // 1% creator fee
        );

        console.log("Strategy created:");
        console.log("  Strategy ID:", strategyId);
        console.log("  Creator:", creator);
        console.log("  Allocation: 50% Lendle, 50% FusionX\n");

        // Step 2: Check initial balances
        console.log("BEFORE DEPOSIT:");
        console.log("  Alice USDC balance:", usdc.balanceOf(alice));
        console.log("  Vault USDC balance:", usdc.balanceOf(address(vault)));
        console.log("  LendleAdapter aUSDC:", lendleAdapter.getBalance());
        console.log("  FusionXAdapter LP:", fusionXAdapter.getBalance());
        console.log("");

        // Step 3: Alice deposits
        vm.prank(alice);
        uint256 shares = vault.deposit(strategyId, DEPOSIT_AMOUNT);

        // Calculate expected values
        uint256 expectedFee = (DEPOSIT_AMOUNT * 1) / 100; // 1% fee
        uint256 expectedNet = DEPOSIT_AMOUNT - expectedFee;
        uint256 expectedPerAdapter = expectedNet / 2; // 50/50 split

        console.log("AFTER DEPOSIT:");
        console.log("  Deposited:", DEPOSIT_AMOUNT);
        console.log("  Creator fee (1%):", expectedFee);
        console.log("  Net to adapters:", expectedNet);
        console.log("  Expected per adapter:", expectedPerAdapter);
        console.log("");

        // Step 4: Verify balances
        uint256 aliceUsdcBalance = usdc.balanceOf(alice);
        uint256 vaultUsdcBalance = usdc.balanceOf(address(vault));
        uint256 lendleBalance = lendleAdapter.getBalance();
        uint256 fusionXBalance = fusionXAdapter.getBalance();
        uint256 aliceShares = vault.userShares(strategyId, alice);
        uint256 accumulatedFees = vault.accumulatedCreatorFees(strategyId);

        console.log("FINAL BALANCES:");
        console.log("  Alice USDC:", aliceUsdcBalance);
        console.log("  Alice shares:", aliceShares);
        console.log("  Vault USDC:", vaultUsdcBalance);
        console.log("  LendleAdapter aUSDC:", lendleBalance);
        console.log("  FusionXAdapter LP:", fusionXBalance);
        console.log("  Accumulated creator fees:", accumulatedFees);
        console.log("");

        // Assertions
        assertEq(
            aliceUsdcBalance,
            INITIAL_BALANCE - DEPOSIT_AMOUNT,
            "Alice should have spent deposit amount"
        );
        assertEq(shares, expectedNet, "Shares should equal net amount");
        assertEq(aliceShares, expectedNet, "Alice shares should be tracked");
        assertEq(vaultUsdcBalance, expectedFee, "Vault should hold creator fee");
        assertEq(accumulatedFees, expectedFee, "Creator fees should be accumulated");

        // Verify adapter balances (approximately 50% each)
        assertApproxEqRel(
            lendleBalance,
            expectedPerAdapter,
            0.01e18, // 1% tolerance
            "Lendle should have ~50% of net deposit"
        );
        assertGt(fusionXBalance, 0, "FusionX should have LP tokens");

        console.log("[PASS] All assertions passed!\n");
    }

    /**
     * @notice Test withdrawal from multi-adapter strategy
     */
    function testE2E_Withdrawal() public {
        console.log("=== E2E TEST: WITHDRAWAL ===\n");

        // Setup strategy
        address[] memory adapters = new address[](2);
        adapters[0] = address(lendleAdapter);
        adapters[1] = address(fusionXAdapter);

        uint16[] memory ratios = new uint16[](2);
        ratios[0] = 5000;
        ratios[1] = 5000;

        vm.prank(creator);
        uint256 strategyId = strategyNFT.mintStrategy("Test", adapters, ratios, 100);

        // Deposit
        vm.prank(alice);
        uint256 shares = vault.deposit(strategyId, DEPOSIT_AMOUNT);

        console.log("Deposited:", DEPOSIT_AMOUNT);
        console.log("Shares received:", shares);

        uint256 balanceBefore = usdc.balanceOf(alice);

        // Withdraw
        vm.prank(alice);
        uint256 withdrawn = vault.withdraw(strategyId, shares);

        uint256 balanceAfter = usdc.balanceOf(alice);
        uint256 received = balanceAfter - balanceBefore;

        console.log("Withdrawn:", withdrawn);
        console.log("Actually received:", received);

        // Verify
        assertGt(withdrawn, 0, "Should receive USDC back");
        assertEq(vault.userShares(strategyId, alice), 0, "Shares should be burned");
        assertEq(lendleAdapter.getBalance(), 0, "Lendle should be empty");
        assertEq(fusionXAdapter.getBalance(), 0, "FusionX should be empty");

        console.log("[PASS] Withdrawal successful!\n");
    }

    /**
     * @notice Test creator fee claiming
     */
    function testE2E_CreatorFeeClaim() public {
        console.log("=== E2E TEST: CREATOR FEE CLAIM ===\n");

        // Setup
        address[] memory adapters = new address[](1);
        adapters[0] = address(lendleAdapter);
        uint16[] memory ratios = new uint16[](1);
        ratios[0] = 10000;

        vm.prank(creator);
        uint256 strategyId = strategyNFT.mintStrategy("Test", adapters, ratios, 100);

        // Deposit
        vm.prank(alice);
        vault.deposit(strategyId, DEPOSIT_AMOUNT);

        uint256 expectedFee = (DEPOSIT_AMOUNT * 1) / 100;
        console.log("Expected creator fee:", expectedFee);

        uint256 creatorBalanceBefore = usdc.balanceOf(creator);

        // Claim fees
        vm.prank(creator);
        vault.claimCreatorFees(strategyId);

        uint256 creatorBalanceAfter = usdc.balanceOf(creator);
        uint256 feeReceived = creatorBalanceAfter - creatorBalanceBefore;

        console.log("Fee received:", feeReceived);

        assertEq(feeReceived, expectedFee, "Creator should receive correct fee");
        assertEq(
            vault.accumulatedCreatorFees(strategyId),
            0,
            "Accumulated fees should be reset"
        );

        console.log("[PASS] Creator fee claimed!\n");
    }

    /**
     * @notice Test multiple users depositing into same strategy
     */
    function testE2E_MultipleUsers() public {
        console.log("=== E2E TEST: MULTIPLE USERS ===\n");

        // Setup strategy
        address[] memory adapters = new address[](2);
        adapters[0] = address(lendleAdapter);
        adapters[1] = address(fusionXAdapter);

        uint16[] memory ratios = new uint16[](2);
        ratios[0] = 5000;
        ratios[1] = 5000;

        vm.prank(creator);
        uint256 strategyId = strategyNFT.mintStrategy("Multi-User", adapters, ratios, 100);

        // Alice deposits
        vm.prank(alice);
        uint256 aliceShares = vault.deposit(strategyId, DEPOSIT_AMOUNT);

        console.log("Alice deposited:", DEPOSIT_AMOUNT);
        console.log("Alice shares:", aliceShares);

        uint256 adapterBalanceAfterAlice = lendleAdapter.getBalance() + fusionXAdapter.getBalance();

        // Bob deposits (2x amount)
        vm.prank(bob);
        uint256 bobShares = vault.deposit(strategyId, DEPOSIT_AMOUNT * 2);

        console.log("Bob deposited:", DEPOSIT_AMOUNT * 2);
        console.log("Bob shares:", bobShares);

        uint256 adapterBalanceAfterBob = lendleAdapter.getBalance() + fusionXAdapter.getBalance();

        // Verify
        assertGt(bobShares, aliceShares, "Bob should have more shares");
        assertGt(
            adapterBalanceAfterBob,
            adapterBalanceAfterAlice,
            "Total in adapters should increase"
        );

        // Verify individual positions
        (uint256 alicePos, ) = vault.getUserPosition(strategyId, alice);
        (uint256 bobPos, uint256 totalShares) = vault.getUserPosition(strategyId, bob);

        console.log("Alice position:", alicePos);
        console.log("Bob position:", bobPos);
        console.log("Total shares:", totalShares);

        assertEq(alicePos, aliceShares, "Alice position should match");
        assertEq(bobPos, bobShares, "Bob position should match");
        assertEq(totalShares, aliceShares + bobShares, "Total should be sum");

        console.log("[PASS] Multiple users handled correctly!\n");
    }

    /**
     * @notice Test uneven adapter allocation (70/30 split)
     */
    function testE2E_UnevenAllocation() public {
        console.log("=== E2E TEST: UNEVEN ALLOCATION (70/30) ===\n");

        // Setup 70/30 strategy
        address[] memory adapters = new address[](2);
        adapters[0] = address(lendleAdapter);
        adapters[1] = address(fusionXAdapter);

        uint16[] memory ratios = new uint16[](2);
        ratios[0] = 7000; // 70%
        ratios[1] = 3000; // 30%

        vm.prank(creator);
        uint256 strategyId = strategyNFT.mintStrategy("70/30 Split", adapters, ratios, 100);

        // Deposit
        vm.prank(alice);
        vault.deposit(strategyId, DEPOSIT_AMOUNT);

        uint256 netDeposit = DEPOSIT_AMOUNT - (DEPOSIT_AMOUNT * 1) / 100;
        uint256 expected70 = (netDeposit * 7000) / 10000;
        uint256 expected30 = netDeposit - expected70; // Remainder to last adapter

        uint256 lendleBalance = lendleAdapter.getBalance();
        uint256 fusionXBalance = fusionXAdapter.getBalance();

        console.log("Net deposit:", netDeposit);
        console.log("Expected 70% to Lendle:", expected70);
        console.log("Expected 30% to FusionX:", expected30);
        console.log("Actual Lendle balance:", lendleBalance);
        console.log("Actual FusionX balance:", fusionXBalance);

        // Verify split
        assertApproxEqRel(
            lendleBalance,
            expected70,
            0.01e18,
            "Lendle should get ~70%"
        );

        console.log("[PASS] Uneven allocation works!\n");
    }

    /**
     * @notice Test strategy deactivation
     */
    function testE2E_StrategyDeactivation() public {
        console.log("=== E2E TEST: STRATEGY DEACTIVATION ===\n");

        // Setup
        address[] memory adapters = new address[](1);
        adapters[0] = address(lendleAdapter);
        uint16[] memory ratios = new uint16[](1);
        ratios[0] = 10000;

        vm.prank(creator);
        uint256 strategyId = strategyNFT.mintStrategy("Test", adapters, ratios, 100);

        // Deposit works
        vm.prank(alice);
        vault.deposit(strategyId, DEPOSIT_AMOUNT);

        console.log("Initial deposit successful");

        // Deactivate strategy
        vm.prank(creator);
        strategyNFT.deactivateStrategy(strategyId);

        console.log("Strategy deactivated");

        // Try to deposit again - should revert
        vm.prank(bob);
        vm.expectRevert(UniversalVault.StrategyNotActive.selector);
        vault.deposit(strategyId, DEPOSIT_AMOUNT);

        console.log("[PASS] Deposits blocked for inactive strategy!\n");
    }
}
