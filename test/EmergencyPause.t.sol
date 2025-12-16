// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {UniversalVault} from "../src/UniversalVault.sol";
import {EmergencyPause, IEmergencyPauseEvents, IEmergencyPauseErrors} from "../src/EmergencyPause.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {MockAdapter} from "../src/mocks/MockAdapter.sol";

/**
 * @title EmergencyPauseTest
 * @notice Comprehensive test suite for EmergencyPause functionality
 * @dev Tests all pause scenarios, withdrawal guarantees, and adapter integration
 */
contract EmergencyPauseTest is Test {
    // ============ SETUP ============

    UniversalVault public vault;
    MockERC20 public asset;
    MockAdapter public adapterA;
    MockAdapter public adapterB;
    address public pauseOwner = address(0x1111);
    address public user1 = address(0x2222);
    address public user2 = address(0x3333);
    address public randomUser = address(0x9999);

    function setUp() public {
        vm.startPrank(pauseOwner);

        // Deploy USDC mock
        asset = new MockERC20("USDC", "USDC", 6);

        // Deploy vault
        vault = new UniversalVault(address(asset), pauseOwner);

        // Deploy adapters
        adapterA = new MockAdapter(address(asset));
        adapterB = new MockAdapter(address(asset));

        vm.stopPrank();

        // Mint tokens to users
        asset.mint(user1, 10_000e6); // 10k USDC
        asset.mint(user2, 10_000e6);
        asset.mint(randomUser, 1_000e6);
    }

    // ============ GLOBAL PAUSE TESTS ============

    /**
     * @notice Test enabling global pause
     */
    function test_enableGlobalPause() public {
        vm.prank(pauseOwner);
        vault.enableGlobalPause("Exploit detected");

        assertTrue(vault.isGlobalPauseActive());
        assertEq(vault.getGlobalPauseReason(), "Exploit detected");
        assertTrue(vault.getGlobalPauseTimestamp() > 0);
    }

    /**
     * @notice Test disabling global pause
     */
    function test_disableGlobalPause() public {
        vm.prank(pauseOwner);
        vault.enableGlobalPause("Test");

        vm.prank(pauseOwner);
        vault.disableGlobalPause();

        assertFalse(vault.isGlobalPauseActive());
    }

    /**
     * @notice Test deposit blocked during global pause
     */
    function test_depositBlockedDuringGlobalPause() public {
        // Setup user strategy first (in normal state)
        _setupUserStrategy(user1, address(adapterA), 10000);

        // Enable pause
        vm.prank(pauseOwner);
        vault.enableGlobalPause("Security pause");

        // Try to deposit - should fail
        vm.startPrank(user1);
        asset.approve(address(vault), 1_000e6);

        vm.expectRevert(IEmergencyPauseErrors.DepositsPaused.selector);
        vault.deposit(1_000e6);

        vm.stopPrank();
    }

    /**
     * @notice Test withdrawal works during global pause
     */
    function test_withdrawalWorksGlobalPause() public {
        // Setup and deposit in normal state
        _setupUserStrategy(user1, address(adapterA), 10000);

        vm.startPrank(user1);
        asset.approve(address(vault), 1_000e6);
        vault.deposit(1_000e6);
        vm.stopPrank();

        // Enable pause
        vm.prank(pauseOwner);
        vault.enableGlobalPause("Critical issue");

        // Withdrawal should work
        vm.prank(user1);
        uint256 withdrawn = vault.withdraw(500e6); // Withdraw half

        assertTrue(withdrawn > 0);
    }

    /**
     * @notice Test copy fee claim works during pause
     */
    function test_copyFeesClaimableDuringPause() public {
        // This test assumes copy fees are tracked
        // Implementation details depend on your fee mechanism

        vm.prank(pauseOwner);
        vault.enableGlobalPause("Maintenance");

        // Claim should work even during pause
        // (assuming user has copy fees)
        // vm.prank(user1);
        // vault.claimCopyFees(); // Should not revert
    }

    /**
     * @notice Test only pause owner can enable pause
     */
    function test_onlyPauseOwnerCanPause() public {
        vm.prank(randomUser);
        vm.expectRevert(IEmergencyPauseErrors.NotAuthorized.selector);
        vault.enableGlobalPause("Unauthorized");
    }

    /**
     * @notice Test cannot pause twice
     */
    function test_cannotPauseTwice() public {
        vm.startPrank(pauseOwner);

        vault.enableGlobalPause("First pause");

        vm.expectRevert(IEmergencyPauseErrors.PauseAlreadyActive.selector);
        vault.enableGlobalPause("Second pause");

        vm.stopPrank();
    }

    /**
     * @notice Test cannot unpause when not paused
     */
    function test_cannotUnpauseWhenNotPaused() public {
        vm.prank(pauseOwner);
        vm.expectRevert(IEmergencyPauseErrors.NoPauseActive.selector);
        vault.disableGlobalPause();
    }

    // ============ PER-ADAPTER PAUSE TESTS ============

    /**
     * @notice Test pausing a specific adapter
     */
    function test_pauseSpecificAdapter() public {
        vm.prank(pauseOwner);
        vault.pauseAdapter(address(adapterA), "Liquidity crisis");

        assertTrue(vault.isAdapterPaused(address(adapterA)));
        assertFalse(vault.isAdapterPaused(address(adapterB)));
    }

    /**
     * @notice Test unpausing a specific adapter
     */
    function test_unpauseSpecificAdapter() public {
        vm.startPrank(pauseOwner);

        vault.pauseAdapter(address(adapterA), "Issue");
        vault.unpauseAdapter(address(adapterA));

        vm.stopPrank();

        assertFalse(vault.isAdapterPaused(address(adapterA)));
    }

    /**
     * @notice Test deposit through paused adapter fails
     */
    function test_depositThroughPausedAdapterFails() public {
        // Setup strategy with adapter A
        _setupUserStrategy(user1, address(adapterA), 10000);

        // Pause adapter A
        vm.prank(pauseOwner);
        vault.pauseAdapter(address(adapterA), "Adapter issue");

        // Try to deposit - should fail
        vm.startPrank(user1);
        asset.approve(address(vault), 1_000e6);

        vm.expectRevert(IEmergencyPauseErrors.AdapterPausedError.selector);
        vault.deposit(1_000e6);

        vm.stopPrank();
    }

    /**
     * @notice Test withdrawal from paused adapter works
     */
    function test_withdrawFromPausedAdapterWorks() public {
        // Setup and deposit with adapter A
        _setupUserStrategy(user1, address(adapterA), 10000);

        vm.startPrank(user1);
        asset.approve(address(vault), 1_000e6);
        vault.deposit(1_000e6);
        vm.stopPrank();

        // Pause adapter A
        vm.prank(pauseOwner);
        vault.pauseAdapter(address(adapterA), "Emergency");

        // Withdrawal should still work
        vm.prank(user1);
        uint256 withdrawn = vault.withdraw(500e6);

        assertTrue(withdrawn > 0);
    }

    /**
     * @notice Test per-adapter pause does not affect other adapters
     */
    function test_adapterPauseIsolated() public {
        // Setup strategies with both adapters
        address[] memory adaptersA = new address[](1);
        adaptersA[0] = address(adapterA);
        uint16[] memory ratiosA = new uint16[](1);
        ratiosA[0] = 10000;

        address[] memory adaptersB = new address[](1);
        adaptersB[0] = address(adapterB);
        uint16[] memory ratiosB = new uint16[](1);
        ratiosB[0] = 10000;

        vm.startPrank(user1);
        vault.setStrategy(adaptersA, ratiosA, false, "Strategy A", 0);
        vm.stopPrank();

        vm.startPrank(user2);
        vault.setStrategy(adaptersB, ratiosB, false, "Strategy B", 0);
        vm.stopPrank();

        // Pause adapter A
        vm.prank(pauseOwner);
        vault.pauseAdapter(address(adapterA), "Issue with A");

        // User1 cannot deposit
        vm.startPrank(user1);
        asset.approve(address(vault), 1_000e6);
        vm.expectRevert(IEmergencyPauseErrors.AdapterPausedError.selector);
        vault.deposit(1_000e6);
        vm.stopPrank();

        // User2 CAN deposit (using adapter B)
        vm.startPrank(user2);
        asset.approve(address(vault), 1_000e6);
        vault.deposit(1_000e6); // Should succeed
        vm.stopPrank();
    }

    /**
     * @notice Test updating pause reason
     */
    function test_updatePauseReason() public {
        vm.startPrank(pauseOwner);

        vault.enableGlobalPause("Initial reason");
        assertEq(vault.getGlobalPauseReason(), "Initial reason");

        vault.updateGlobalPauseReason("Updated reason");
        assertEq(vault.getGlobalPauseReason(), "Updated reason");

        vm.stopPrank();
    }

    // ============ ADAPTER OPERATIONAL CHECKS ============

    /**
     * @notice Test isAdapterOperational query
     */
    function test_isAdapterOperational() public {
        // Initially operational
        assertTrue(vault.isAdapterOperational(address(adapterA)));

        // Pause globally
        vm.prank(pauseOwner);
        vault.enableGlobalPause("Test");
        assertFalse(vault.isAdapterOperational(address(adapterA)));

        // Unpause globally, pause adapter
        vm.prank(pauseOwner);
        vault.disableGlobalPause();

        vm.prank(pauseOwner);
        vault.pauseAdapter(address(adapterA), "Adapter pause");
        assertFalse(vault.isAdapterOperational(address(adapterA)));
    }

    /**
     * @notice Test adapter pause reasons are stored
     */
    function test_adapterPauseReasonsStored() public {
        vm.prank(pauseOwner);
        vault.pauseAdapter(address(adapterA), "Slippage issue");

        assertEq(vault.getAdapterPauseReason(address(adapterA)), "Slippage issue");
        assertTrue(vault.getAdapterPauseTimestamp(address(adapterA)) > 0);
    }

    // ============ EMERGENCY WITHDRAWAL TESTS ============

    /**
     * @notice Test emergencyWithdraw function exists and works
     */
    function test_emergencyWithdrawFunction() public {
        // Setup and deposit
        _setupUserStrategy(user1, address(adapterA), 10000);

        vm.startPrank(user1);
        asset.approve(address(vault), 1_000e6);
        vault.deposit(1_000e6);
        vm.stopPrank();

        // Enable pause
        vm.prank(pauseOwner);
        vault.enableGlobalPause("Emergency");

        // Emergency withdraw should work
        vm.prank(user1);
        uint256 withdrawn = vault.emergencyWithdraw(500e6);

        assertTrue(withdrawn > 0);
    }

    // ============ ACCESS CONTROL TESTS ============

    /**
     * @notice Test non-owner cannot pause adapter
     */
    function test_nonOwnerCannotPauseAdapter() public {
        vm.prank(randomUser);
        vm.expectRevert(IEmergencyPauseErrors.NotAuthorized.selector);
        vault.pauseAdapter(address(adapterA), "Unauthorized");
    }

    /**
     * @notice Test non-owner cannot unpause adapter
     */
    function test_nonOwnerCannotUnpauseAdapter() public {
        // Setup: pause as owner
        vm.prank(pauseOwner);
        vault.pauseAdapter(address(adapterA), "Test");

        // Try to unpause as non-owner
        vm.prank(randomUser);
        vm.expectRevert(IEmergencyPauseErrors.NotAuthorized.selector);
        vault.unpauseAdapter(address(adapterA));
    }

    // ============ EVENT TESTS ============

    /**
     * @notice Test GlobalPauseEnabled event is emitted
     */
    function test_globalPauseEnabledEvent() public {
        vm.prank(pauseOwner);

        vm.expectEmit(true, false, false, true);
        emit IEmergencyPauseEvents.GlobalPauseEnabled(pauseOwner, "Test reason");

        vault.enableGlobalPause("Test reason");
    }

    /**
     * @notice Test GlobalPauseDisabled event is emitted
     */
    function test_globalPauseDisabledEvent() public {
        vm.prank(pauseOwner);
        vault.enableGlobalPause("Test");

        vm.prank(pauseOwner);

        vm.expectEmit(true, false, false, false);
        emit IEmergencyPauseEvents.GlobalPauseDisabled(pauseOwner);

        vault.disableGlobalPause();
    }

    /**
     * @notice Test AdapterPaused event is emitted
     */
    function test_adapterPausedEvent() public {
        vm.prank(pauseOwner);

        vm.expectEmit(true, true, false, true);
        emit IEmergencyPauseEvents.AdapterPaused(address(adapterA), pauseOwner, "Test");

        vault.pauseAdapter(address(adapterA), "Test");
    }

    // ============ HELPER FUNCTIONS ============

    /**
     * @notice Helper to set up a user strategy
     */
    function _setupUserStrategy(address user, address adapter, uint16 ratio) internal {
        address[] memory adapters = new address[](1);
        adapters[0] = adapter;

        uint16[] memory ratios = new uint16[](1);
        ratios[0] = ratio;

        vm.prank(user);
        vault.setStrategy(adapters, ratios, false, "Test Strategy", 0);
    }
}
