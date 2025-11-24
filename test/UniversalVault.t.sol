// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../src/UniversalVault.sol";
import "../src/StrategyNFT.sol";
import "../src/mocks/MockERC20.sol";
import "../src/mocks/MockAdapter.sol";

contract UniversalVaultTest is Test {
    UniversalVault public vault;
    StrategyNFT public strategyNFT;
    MockERC20 public usdc;
    MockAdapter public adapterA;
    MockAdapter public adapterB;
    
    address public owner = address(this);
    address public alice = address(0x1);
    address public bob = address(0x2);
    address public creator = address(0x3);
    
    uint256 public strategyId;
    
    // Constants
    uint256 constant INITIAL_BALANCE = 1000e6; // 1000 USDC (6 decimals)
    uint256 constant DEPOSIT_AMOUNT = 100e6;   // 100 USDC
    
    function setUp() public {
        // Deploy mock USDC
        usdc = new MockERC20("USD Coin", "USDC", 6);
        
        // Deploy core contracts
        strategyNFT = new StrategyNFT();
        vault = new UniversalVault(address(usdc), address(strategyNFT));
        
        // Deploy mock adapters
        adapterA = new MockAdapter(address(usdc));
        adapterB = new MockAdapter(address(usdc));
        
        // Whitelist adapters
        strategyNFT.setAdapterWhitelist(address(adapterA), true);
        strategyNFT.setAdapterWhitelist(address(adapterB), true);
        
        // Create a 50/50 strategy
        address[] memory adapters = new address[](2);
        adapters[0] = address(adapterA);
        adapters[1] = address(adapterB);
        
        uint16[] memory ratios = new uint16[](2);
        ratios[0] = 5000; // 50%
        ratios[1] = 5000; // 50%
        
        vm.prank(creator);
        strategyId = strategyNFT.mintStrategy(
            "Balanced 50/50",
            adapters,
            ratios,
            10 // 0.1% creator fee (not used by vault yet)
        );
        
        // Mint USDC to test users
        usdc.mint(alice, INITIAL_BALANCE);
        usdc.mint(bob, INITIAL_BALANCE);
        
        // Approve vault to spend user tokens
        vm.prank(alice);
        usdc.approve(address(vault), type(uint256).max);
        
        vm.prank(bob);
        usdc.approve(address(vault), type(uint256).max);
    }
    
    /**
     * @notice Test that deposits are split correctly across adapters
     */
    function testDepositSplitsCorrectly() public {
        uint256 depositAmount = DEPOSIT_AMOUNT; // 100 USDC
        
        console.log("=== DEPOSIT TEST ===");
        console.log("Initial Alice balance:", usdc.balanceOf(alice));
        console.log("Deposit amount:", depositAmount);
        
        // Alice deposits 100 USDC
        vm.prank(alice);
        uint256 shares = vault.deposit(strategyId, depositAmount);
        
        // Calculate expected values
        uint256 expectedCreatorFee = (depositAmount * vault.CREATOR_FEE_BPS()) / vault.TOTAL_BPS();
        uint256 expectedNetDeposit = depositAmount - expectedCreatorFee;
        uint256 expectedPerAdapter = expectedNetDeposit / 2; // 50/50 split
        
        console.log("Creator fee (1%):", expectedCreatorFee);
        console.log("Net deposit:", expectedNetDeposit);
        console.log("Expected per adapter:", expectedPerAdapter);
        
        // Verify creator fee accumulated
        assertEq(
            vault.accumulatedCreatorFees(strategyId),
            expectedCreatorFee,
            "Creator fee should be 1% of deposit"
        );
        console.log("Actual creator fee:", vault.accumulatedCreatorFees(strategyId));
        
        // Verify adapter balances
        uint256 adapterABalance = adapterA.getBalance();
        uint256 adapterBBalance = adapterB.getBalance();
        
        console.log("Adapter A balance:", adapterABalance);
        console.log("Adapter B balance:", adapterBBalance);
        
        // Due to rounding, adapter B (last in loop) gets any remainder
        assertEq(adapterABalance, expectedPerAdapter, "Adapter A should receive ~49.5 USDC");
        assertEq(adapterBBalance, expectedPerAdapter, "Adapter B should receive ~49.5 USDC");
        
        // Verify total deposited to adapters
        uint256 totalInAdapters = adapterABalance + adapterBBalance;
        assertEq(totalInAdapters, expectedNetDeposit, "Total in adapters should equal net deposit");
        
        // Verify user shares
        assertEq(shares, expectedNetDeposit, "Shares should equal net deposit (1:1)");
        assertEq(
            vault.userShares(strategyId, alice),
            expectedNetDeposit,
            "Alice's shares should be tracked"
        );
        
        // Verify Alice's USDC balance decreased
        assertEq(
            usdc.balanceOf(alice),
            INITIAL_BALANCE - depositAmount,
            "Alice should have spent deposit amount"
        );
        
        console.log("Shares minted to Alice:", shares);
        console.log("Alice's final balance:", usdc.balanceOf(alice));
        console.log("=== TEST PASSED ===");
    }
    
    /**
     * @notice Test multiple deposits accumulate correctly
     */
    function testMultipleDeposits() public {
        // Alice deposits 100 USDC
        vm.prank(alice);
        vault.deposit(strategyId, DEPOSIT_AMOUNT);
        
        // Bob deposits 200 USDC
        vm.prank(bob);
        vault.deposit(strategyId, DEPOSIT_AMOUNT * 2);
        
        // Verify total shares
        uint256 aliceShares = vault.userShares(strategyId, alice);
        uint256 bobShares = vault.userShares(strategyId, bob);
        
        uint256 expectedAliceNet = DEPOSIT_AMOUNT - (DEPOSIT_AMOUNT * 1) / 100; // 1% fee
        uint256 expectedBobNet = (DEPOSIT_AMOUNT * 2) - ((DEPOSIT_AMOUNT * 2) * 1) / 100;
        
        assertEq(aliceShares, expectedAliceNet, "Alice shares incorrect");
        assertEq(bobShares, expectedBobNet, "Bob shares incorrect");
        
        // Verify total in adapters
        uint256 totalDeposited = expectedAliceNet + expectedBobNet;
        uint256 adapterATotal = adapterA.getBalance();
        uint256 adapterBTotal = adapterB.getBalance();
        
        assertEq(
            adapterATotal + adapterBTotal,
            totalDeposited,
            "Total in adapters should match deposits"
        );
    }
    
    /**
     * @notice Test withdrawal works correctly
     */
    function testWithdrawal() public {
        // Alice deposits
        vm.prank(alice);
        uint256 shares = vault.deposit(strategyId, DEPOSIT_AMOUNT);
        
        uint256 initialBalance = usdc.balanceOf(alice);
        
        // Alice withdraws all shares
        vm.prank(alice);
        uint256 assetsReceived = vault.withdraw(strategyId, shares);
        
        // Verify Alice received her share (minus the 1% fee that was deducted on deposit)
        uint256 expectedNet = DEPOSIT_AMOUNT - (DEPOSIT_AMOUNT * 1) / 100;
        assertEq(assetsReceived, expectedNet, "Should receive net deposit amount");
        
        // Verify balance increased
        assertEq(
            usdc.balanceOf(alice),
            initialBalance + assetsReceived,
            "Balance should increase by withdrawn amount"
        );
        
        // Verify shares burned
        assertEq(vault.userShares(strategyId, alice), 0, "Shares should be zero");
        
        // Verify adapters are empty
        assertEq(adapterA.getBalance(), 0, "Adapter A should be empty");
        assertEq(adapterB.getBalance(), 0, "Adapter B should be empty");
    }
    
    /**
     * @notice Test partial withdrawal
     */
    function testPartialWithdrawal() public {
        vm.prank(alice);
        uint256 totalShares = vault.deposit(strategyId, DEPOSIT_AMOUNT);
        
        uint256 withdrawShares = totalShares / 2; // Withdraw 50%
        
        vm.prank(alice);
        uint256 assetsReceived = vault.withdraw(strategyId, withdrawShares);
        
        // Verify remaining shares
        assertEq(
            vault.userShares(strategyId, alice),
            totalShares - withdrawShares,
            "Should have 50% shares remaining"
        );
        
        // Verify assets received is approximately 50%
        assertApproxEqRel(
            assetsReceived,
            totalShares / 2,
            0.01e18, // 1% tolerance
            "Should receive ~50% of assets"
        );
    }
    
    /**
     * @notice Test creator can claim fees
     */
    function testClaimCreatorFees() public {
        // Alice deposits
        vm.prank(alice);
        vault.deposit(strategyId, DEPOSIT_AMOUNT);
        
        uint256 expectedFee = (DEPOSIT_AMOUNT * 1) / 100; // 1% fee
        
        // Verify fee accumulated
        assertEq(
            vault.accumulatedCreatorFees(strategyId),
            expectedFee,
            "Fee should be accumulated"
        );
        
        uint256 creatorInitialBalance = usdc.balanceOf(creator);
        
        // Creator claims fees
        vm.prank(creator);
        vault.claimCreatorFees(strategyId);
        
        // Verify creator received fees
        assertEq(
            usdc.balanceOf(creator),
            creatorInitialBalance + expectedFee,
            "Creator should receive fees"
        );
        
        // Verify fees reset to zero
        assertEq(
            vault.accumulatedCreatorFees(strategyId),
            0,
            "Accumulated fees should be zero"
        );
    }
    
    /**
     * @notice Test non-creator cannot claim fees
     */
    function testRevertNonCreatorCannotClaimFees() public {
        vm.prank(alice);
        vault.deposit(strategyId, DEPOSIT_AMOUNT);
        
        vm.prank(alice); // Alice tries to claim creator fees
        vm.expectRevert(UniversalVault.NotStrategyCreator.selector);
        vault.claimCreatorFees(strategyId);
    }
    
    /**
     * @notice Test deposit to inactive strategy reverts
     */
    function testRevertDepositToInactiveStrategy() public {
        // Deactivate strategy
        vm.prank(creator);
        strategyNFT.deactivateStrategy(strategyId);
        
        // Try to deposit
        vm.prank(alice);
        vm.expectRevert(UniversalVault.StrategyNotActive.selector);
        vault.deposit(strategyId, DEPOSIT_AMOUNT);
    }
    
    /**
     * @notice Test zero deposit reverts
     */
    function testRevertZeroDeposit() public {
        vm.prank(alice);
        vm.expectRevert(UniversalVault.InvalidAmount.selector);
        vault.deposit(strategyId, 0);
    }
    
    /**
     * @notice Test withdrawal with insufficient shares reverts
     */
    function testRevertWithdrawInsufficientShares() public {
        vm.prank(alice);
        vault.deposit(strategyId, DEPOSIT_AMOUNT);
        
        vm.prank(bob); // Bob has no shares
        vm.expectRevert(UniversalVault.InsufficientShares.selector);
        vault.withdraw(strategyId, 100);
    }
    
    /**
     * @notice Test uneven ratio splits (60/40)
     */
    function testUnevenRatioSplit() public {
        // Create 60/40 strategy
        address[] memory adapters = new address[](2);
        adapters[0] = address(adapterA);
        adapters[1] = address(adapterB);
        
        uint16[] memory ratios = new uint16[](2);
        ratios[0] = 6000; // 60%
        ratios[1] = 4000; // 40%
        
        vm.prank(creator);
        uint256 newStrategyId = strategyNFT.mintStrategy("60/40 Mix", adapters, ratios, 10);
        
        // Deposit
        vm.prank(alice);
        vault.deposit(newStrategyId, DEPOSIT_AMOUNT);
        
        uint256 netDeposit = DEPOSIT_AMOUNT - (DEPOSIT_AMOUNT * 1) / 100;
        
        // Verify split
        uint256 expected60 = (netDeposit * 6000) / 10000;
        uint256 expected40 = netDeposit - expected60; // Remainder goes to last adapter
        
        assertEq(adapterA.getBalance(), expected60, "Adapter A should get 60%");
        assertEq(adapterB.getBalance(), expected40, "Adapter B should get 40%");
    }
    
    /**
     * @notice Test getUserPosition view function
     */
    function testGetUserPosition() public {
        vm.prank(alice);
        vault.deposit(strategyId, DEPOSIT_AMOUNT);
        
        (uint256 userShares_, uint256 totalShares_) = vault.getUserPosition(strategyId, alice);
        
        uint256 expectedShares = DEPOSIT_AMOUNT - (DEPOSIT_AMOUNT * 1) / 100;
        assertEq(userShares_, expectedShares, "User shares mismatch");
        assertEq(totalShares_, expectedShares, "Total shares mismatch");
    }
}
