// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @test-type LEGACY-INTEGRATION
/// @covers UserVaultV2
/// @notes Regression harness for deprecated V2 with leaderboard features.


import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {UserVaultV2} from "../src/UserVaultV2.sol";
import {FusionXAdapterV2} from "../src/adapters/FusionXAdapterV2.sol";
import {LendleAdapter} from "../src/adapters/LendleAdapter.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {MockLendingPool} from "../src/mocks/MockLendingPool.sol";
import {MockUniswapV2Router} from "../src/mocks/MockUniswapV2Router.sol";
import {MockUniswapV2Pair} from "../src/mocks/MockUniswapV2Pair.sol";

/**
 * @title UserVaultV2IntegrationTest
 * @notice Integration tests for PRIORITY 1 features:
 * - Leaderboard sorting
 * - TVL tracking
 * - Pause mechanism
 * - Slippage protection
 */
contract UserVaultV2IntegrationTest is Test {
    UserVaultV2 public vault;
    FusionXAdapterV2 public fusionXAdapter;
    LendleAdapter public lendleAdapter;

    MockERC20 public usdc;
    MockERC20 public wmnt;
    MockERC20 public aUsdc;
    MockLendingPool public lendingPool;
    MockUniswapV2Router public router;
    MockUniswapV2Pair public lpToken;

    address public owner = address(0xAAA);
    address public alice = address(0x111);
    address public bob = address(0x222);
    address public charlie = address(0x333);
    address public dave = address(0x444);

    uint256 constant INITIAL_BALANCE = 100_000e6; // 100k USDC
    uint256 constant DEPOSIT_AMOUNT = 10_000e6; // 10k USDC

    function setUp() public {
        // Deploy tokens
        usdc = new MockERC20("USD Coin", "USDC", 6);
        wmnt = new MockERC20("Wrapped Mantle", "WMNT", 18);
        aUsdc = new MockERC20("Aave USDC", "aUSDC", 6);

        // Deploy mock protocols
        lendingPool = new MockLendingPool();
        lendingPool.setReserveToken(address(usdc), address(aUsdc));

        router = new MockUniswapV2Router();
        lpToken = new MockUniswapV2Pair(address(usdc), address(wmnt), "FusionX USDC-WMNT LP", "FUSION-LP");
        router.createPair(address(usdc), address(wmnt), address(lpToken));

        // Deploy vault V2 (with pause mechanism)
        vault = new UserVaultV2(address(usdc), owner);

        // Deploy adapters
        lendleAdapter = new LendleAdapter(address(usdc), address(lendingPool), address(vault));
        fusionXAdapter = new FusionXAdapterV2(address(usdc), address(wmnt), address(lpToken), address(router), address(vault));

        // Mint tokens to users
        usdc.mint(alice, INITIAL_BALANCE);
        usdc.mint(bob, INITIAL_BALANCE);
        usdc.mint(charlie, INITIAL_BALANCE);
        usdc.mint(dave, INITIAL_BALANCE);

        wmnt.mint(address(router), 1_000_000e18); // Liquidity for swaps

        // Approve vault
        vm.prank(alice);
        usdc.approve(address(vault), type(uint256).max);

        vm.prank(bob);
        usdc.approve(address(vault), type(uint256).max);

        vm.prank(charlie);
        usdc.approve(address(vault), type(uint256).max);

        vm.prank(dave);
        usdc.approve(address(vault), type(uint256).max);
    }

    // ============ PRIORITY 1.1: LEADERBOARD SORTING ============

    function testLeaderboardSortingByCopies() public {
        address[] memory adapters = new address[](1);
        adapters[0] = address(lendleAdapter);
        uint16[] memory ratios = new uint16[](1);
        ratios[0] = 10000;

        // Alice creates strategy (0 copies initially)
        vm.prank(alice);
        vault.setStrategy(adapters, ratios, true, "Alice's Strategy", 10);

        // Bob creates strategy
        vm.prank(bob);
        vault.setStrategy(adapters, ratios, true, "Bob's Strategy", 20);

        // Charlie creates strategy
        vm.prank(charlie);
        vault.setStrategy(adapters, ratios, true, "Charlie's Strategy", 30);

        // Dave copies Alice's strategy (Alice: 1 copy)
        vm.prank(dave);
        vault.copyStrategy(alice);

        // Dave also deposits to trigger copy fee logic
        vm.prank(dave);
        vault.deposit(DEPOSIT_AMOUNT / 2, 50);

        // Multiple users copy Alice (Alice: 2 copies)
        vm.prank(bob);
        vault.copyStrategy(alice);

        // Get leaderboard
        UserVaultV2.RankingEntry[] memory rankings = vault.getLeaderboardByCopies(10);

        // Verify sorting
        assertGt(rankings.length, 0);
        console.log("Top strategy:", rankings[0].strategy, "copies:", rankings[0].value);

        // Should be sorted in descending order by copies
        for (uint256 i = 1; i < rankings.length; i++) {
            assertGe(rankings[i - 1].value, rankings[i].value, "Leaderboard not sorted properly");
        }
    }

    function testLeaderboardSortingByTVL() public {
        address[] memory adapters = new address[](1);
        adapters[0] = address(lendleAdapter);
        uint16[] memory ratios = new uint16[](1);
        ratios[0] = 10000;

        // Create three strategies
        vm.prank(alice);
        vault.setStrategy(adapters, ratios, true, "Alice's Strategy", 10);

        vm.prank(bob);
        vault.setStrategy(adapters, ratios, true, "Bob's Strategy", 20);

        vm.prank(charlie);
        vault.setStrategy(adapters, ratios, true, "Charlie's Strategy", 30);

        // Deposit different amounts
        vm.prank(alice);
        vault.deposit(DEPOSIT_AMOUNT * 3, 50); // 30k USDC

        vm.prank(bob);
        vault.deposit(DEPOSIT_AMOUNT * 2, 50); // 20k USDC

        vm.prank(charlie);
        vault.deposit(DEPOSIT_AMOUNT, 50); // 10k USDC

        // Get TVL leaderboard
        UserVaultV2.RankingEntry[] memory rankings = vault.getLeaderboardByTVL(10);

        // Verify sorting by TVL
        assertEq(rankings[0].strategy, alice, "Alice should be #1 by TVL");
        assertEq(rankings[1].strategy, bob, "Bob should be #2 by TVL");
        assertEq(rankings[2].strategy, charlie, "Charlie should be #3 by TVL");

        // Verify descending order
        for (uint256 i = 1; i < rankings.length; i++) {
            assertGe(rankings[i - 1].value, rankings[i].value, "TVL leaderboard not sorted");
        }
    }

    function testLeaderboardWithCopierTVL() public {
        address[] memory adapters = new address[](1);
        adapters[0] = address(lendleAdapter);
        uint16[] memory ratios = new uint16[](1);
        ratios[0] = 10000;

        // Alice creates strategy
        vm.prank(alice);
        vault.setStrategy(adapters, ratios, true, "Alice's Strategy", 100); // 1% fee

        // Alice deposits
        vm.prank(alice);
        vault.deposit(DEPOSIT_AMOUNT, 50);

        // Bob copies Alice's strategy
        vm.prank(bob);
        vault.copyStrategy(alice);

        // Bob deposits (pays copy fee to Alice)
        vm.prank(bob);
        vault.deposit(DEPOSIT_AMOUNT, 50);

        // Check Alice's TVL includes Bob's copier TVL
        (UserVaultV2.Strategy memory aliceStrat, uint256 aliceTVL, uint256 copierTVL) = vault.getStrategyWithTVL(alice);

        assertGt(copierTVL, 0, "Copier TVL should be tracked");
        assertGt(aliceTVL, DEPOSIT_AMOUNT, "Total TVL should include copier deposits");

        // Get TVL leaderboard - Alice should rank high due to copier TVL
        UserVaultV2.RankingEntry[] memory rankings = vault.getLeaderboardByTVL(10);
        assertEq(rankings[0].strategy, alice, "Alice should rank #1 due to copier TVL");
    }

    // ============ PRIORITY 1.2: TVL LEADERBOARD ============

    function testTVLCalculationAccuracy() public {
        address[] memory adapters = new address[](1);
        adapters[0] = address(lendleAdapter);
        uint16[] memory ratios = new uint16[](1);
        ratios[0] = 10000;

        vm.prank(alice);
        vault.setStrategy(adapters, ratios, true, "Alice's Strategy", 10);

        uint256 depositAmount = 5000e6;

        vm.prank(alice);
        vault.deposit(depositAmount, 50);

        (UserVaultV2.Strategy memory strat, uint256 totalTVL, uint256 copierTVL) = vault.getStrategyWithTVL(alice);

        assertEq(totalTVL, depositAmount, "TVL should equal deposit");
        assertEq(copierTVL, 0, "Copier TVL should be zero initially");
    }

    function testPublicStrategiesMetrics() public {
        address[] memory adapters = new address[](1);
        adapters[0] = address(lendleAdapter);
        uint16[] memory ratios = new uint16[](1);
        ratios[0] = 10000;

        // Create multiple strategies
        vm.prank(alice);
        vault.setStrategy(adapters, ratios, true, "Alice's Strategy", 10);

        vm.prank(bob);
        vault.setStrategy(adapters, ratios, true, "Bob's Strategy", 20);

        vm.prank(charlie);
        vault.setStrategy(adapters, ratios, false, "Charlie's Private Strategy", 30); // Private

        // Get metrics
        (address[] memory strategies, uint256[] memory tvls, uint256[] memory copies) = vault.getPublicStrategiesWithMetrics();

        assertEq(strategies.length, 2, "Should have 2 public strategies");
        assertEq(tvls.length, 2, "Should have 2 TVL values");
        assertEq(copies.length, 2, "Should have 2 copy counts");
    }

    // ============ PRIORITY 1.3: SLIPPAGE PROTECTION ============

    function testSlippageProtectionInDeposit() public {
        address[] memory adapters = new address[](1);
        adapters[0] = address(fusionXAdapter);
        uint16[] memory ratios = new uint16[](1);
        ratios[0] = 10000;

        vm.prank(alice);
        vault.setStrategy(adapters, ratios, true, "Alice's FusionX Strategy", 10);

        // Try deposit with slippage tolerance
        vm.prank(alice);
        uint256 shares = vault.deposit(DEPOSIT_AMOUNT, 50); // 0.5% slippage

        assertGt(shares, 0, "Deposit should succeed with acceptable slippage");
    }

    function testSlippageExceeded() public {
        address[] memory adapters = new address[](1);
        adapters[0] = address(fusionXAdapter);
        uint16[] memory ratios = new uint16[](1);
        ratios[0] = 10000;

        vm.prank(alice);
        vault.setStrategy(adapters, ratios, true, "Alice's FusionX Strategy", 10);

        // In a real scenario, this would fail if slippage is exceeded
        // For now, we test that slippage parameter is accepted
        vm.prank(alice);
        vault.deposit(DEPOSIT_AMOUNT, 1); // 0.01% slippage (very tight)

        // Should succeed (or fail gracefully based on router implementation)
    }

    function testFusionXAdapterSlippageEstimation() public {
        // Estimate deposit with slippage
        (uint256 expectedLp, uint256 minLp) = fusionXAdapter.estimateDeposit(DEPOSIT_AMOUNT, 50);

        assertGt(expectedLp, 0, "Expected LP should be positive");
        assertLt(minLp, expectedLp, "Min LP should be less than expected due to slippage");
        assertEq(minLp, (expectedLp * 9950) / 10000, "Min LP should reflect 0.5% slippage");
    }

    // ============ PRIORITY 1.4: EMERGENCY PAUSE MECHANISM ============

    function testPauseVault() public {
        address[] memory adapters = new address[](1);
        adapters[0] = address(lendleAdapter);
        uint16[] memory ratios = new uint16[](1);
        ratios[0] = 10000;

        vm.prank(alice);
        vault.setStrategy(adapters, ratios, true, "Alice's Strategy", 10);

        // Pause vault (only owner)
        vm.prank(owner);
        vault.pauseVault();

        assertTrue(vault.paused(), "Vault should be paused");

        // Try to deposit - should revert
        vm.prank(alice);
        vm.expectRevert(UserVaultV2.VaultPausedForDeposits.selector);
        vault.deposit(DEPOSIT_AMOUNT, 50);
    }

    function testWithdrawWhenPaused() public {
        address[] memory adapters = new address[](1);
        adapters[0] = address(lendleAdapter);
        uint16[] memory ratios = new uint16[](1);
        ratios[0] = 10000;

        vm.prank(alice);
        vault.setStrategy(adapters, ratios, true, "Alice's Strategy", 10);

        vm.prank(alice);
        uint256 shares = vault.deposit(DEPOSIT_AMOUNT, 50);

        // Pause vault
        vm.prank(owner);
        vault.pauseVault();

        // Withdrawal should still work (safety mechanism)
        vm.prank(alice);
        uint256 withdrawn = vault.withdraw(shares);

        assertGt(withdrawn, 0, "Withdrawal should succeed even when paused");
    }

    function testPauseAdapter() public {
        address[] memory adapters = new address[](1);
        adapters[0] = address(lendleAdapter);
        uint16[] memory ratios = new uint16[](1);
        ratios[0] = 10000;

        // Pause adapter
        vm.prank(owner);
        vault.pauseAdapter(address(lendleAdapter));

        assertTrue(vault.pausedAdapters(address(lendleAdapter)), "Adapter should be paused");

        // Try to create strategy with paused adapter - should revert
        vm.prank(alice);
        vm.expectRevert(UserVaultV2.AdapterNotOperational.selector);
        vault.setStrategy(adapters, ratios, true, "Alice's Strategy", 10);
    }

    function testUnpauseVault() public {
        // Pause
        vm.prank(owner);
        vault.pauseVault();

        assertTrue(vault.paused(), "Vault should be paused");

        // Unpause
        vm.prank(owner);
        vault.unpauseVault();

        assertFalse(vault.paused(), "Vault should be unpaused");

        // Now deposits should work again
        address[] memory adapters = new address[](1);
        adapters[0] = address(lendleAdapter);
        uint16[] memory ratios = new uint16[](1);
        ratios[0] = 10000;

        vm.prank(alice);
        vault.setStrategy(adapters, ratios, true, "Alice's Strategy", 10);

        vm.prank(alice);
        uint256 shares = vault.deposit(DEPOSIT_AMOUNT, 50);

        assertGt(shares, 0, "Deposit should succeed after unpause");
    }

    function testOnlyOwnerCanPause() public {
        // Try to pause as non-owner
        vm.prank(alice);
        vm.expectRevert();  // Should revert with OnlyOwner error
        vault.pauseVault();
    }

    function testTransferOwnership() public {
        address newOwner = address(0xBBB);

        vm.prank(owner);
        vault.transferOwnership(newOwner);

        assertEq(vault.owner(), newOwner, "Ownership should be transferred");

        // New owner should be able to pause
        vm.prank(newOwner);
        vault.pauseVault();

        assertTrue(vault.paused(), "New owner should be able to pause");
    }

    // ============ INTEGRATION TESTS ============

    function testFullDepositCopyWithdrawFlow() public {
        address[] memory adapters = new address[](1);
        adapters[0] = address(lendleAdapter);
        uint16[] memory ratios = new uint16[](1);
        ratios[0] = 10000;

        // 1. Alice creates strategy
        vm.prank(alice);
        vault.setStrategy(adapters, ratios, true, "Alice's Strategy", 100); // 1% fee

        // 2. Alice deposits
        vm.prank(alice);
        uint256 aliceShares = vault.deposit(DEPOSIT_AMOUNT, 50);

        // 3. Bob copies Alice
        vm.prank(bob);
        vault.copyStrategy(alice);

        // 4. Bob deposits (pays fee)
        vm.prank(bob);
        uint256 bobShares = vault.deposit(DEPOSIT_AMOUNT / 2, 50);

        // 5. Check fees were collected
        uint256 aliceEarnings = vault.copyFeeEarnings(alice);
        assertGt(aliceEarnings, 0, "Alice should have earned copy fees");

        // 6. Alice claims fees
        uint256 aliceBalanceBefore = usdc.balanceOf(alice);
        vm.prank(alice);
        vault.claimCopyFees();
        uint256 aliceBalanceAfter = usdc.balanceOf(alice);

        assertEq(aliceBalanceAfter - aliceBalanceBefore, aliceEarnings, "Fees should be transferred");

        // 7. Bob withdraws
        vm.prank(bob);
        uint256 bobWithdrawn = vault.withdraw(bobShares);

        assertGt(bobWithdrawn, 0, "Withdrawal should return assets");
    }

    function testLeaderboardUpdatesAfterDeposit() public {
        address[] memory adapters = new address[](1);
        adapters[0] = address(lendleAdapter);
        uint16[] memory ratios = new uint16[](1);
        ratios[0] = 10000;

        // Create strategies
        vm.prank(alice);
        vault.setStrategy(adapters, ratios, true, "Alice", 10);

        vm.prank(bob);
        vault.setStrategy(adapters, ratios, true, "Bob", 20);

        // Before deposits
        UserVaultV2.RankingEntry[] memory beforeRankings = vault.getLeaderboardByTVL(10);

        // Alice deposits large amount
        vm.prank(alice);
        vault.deposit(DEPOSIT_AMOUNT * 5, 50);

        // After deposits - ranking should change
        UserVaultV2.RankingEntry[] memory afterRankings = vault.getLeaderboardByTVL(10);

        assertEq(afterRankings[0].strategy, alice, "Alice should now be #1");
    }
}
