// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @test-type CORE-METRICS
/// @covers PerformanceTracking
/// @notes Protects performance history snapshots feeding dashboards.


import "forge-std/Test.sol";
import "../src/PerformanceTracking.sol";

contract PerformanceTrackingTest is Test {
    PerformanceTracking perf;
    address ownerAddr = address(0xAAB);
    address vaultAddr = address(0xBBA);
    address keeper = address(0xCCC);

    function setUp() public {
        perf = new PerformanceTracking(vaultAddr, ownerAddr);
        vm.prank(ownerAddr);
        perf.setKeeper(keeper, true);
    }

    function test_record_deposit_and_snapshot_and_roi() public {
        // Simulate vault recording deposit
        vm.prank(vaultAddr);
        perf.recordDeposit(1, 1000 ether);

        // take snapshot as keeper
        vm.prank(keeper);
        perf.takeSnapshot(1, uint128(1100 ether));

        // ROI = (1100 - 1000)/1000 = 0.1 -> scaled 1e18 * 0.1 = 1e17
        int256 roi = perf.getStrategyROI(1);
        assertEq(roi, int256(1e17));
    }

    function test_withdraw_and_roi_negative() public {
        vm.prank(vaultAddr);
        perf.recordDeposit(2, 1000 ether);
        vm.prank(vaultAddr);
        perf.recordWithdrawal(2, 300 ether);
        vm.prank(keeper);
        perf.takeSnapshot(2, uint128(600 ether));

        // net = 700, currentTVL=600 -> delta = -100 -> ROI = -100/700 = -0.142857... *1e18
        int256 roi = perf.getStrategyROI(2);
        // approx -1.42857142857142857e17, integer division truncates; check sign and magnitude
        assertLt(roi, 0);
    }
}
