// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IPerformanceTracking {
    struct Snapshot {
        uint64 timestamp;
        uint128 tvl;
    }

    function recordDeposit(uint256 strategyId, uint256 amount) external;
    function recordWithdrawal(uint256 strategyId, uint256 amount) external;
    function takeSnapshot(uint256 strategyId, uint128 tvl) external;

    function getSnapshots(uint256 strategyId) external view returns (Snapshot[] memory);
    function getLastSnapshot(uint256 strategyId) external view returns (Snapshot memory);
    function getStrategyTVL(uint256 strategyId) external view returns (uint128);
    function getStrategyROI(uint256 strategyId) external view returns (int256);
    function getStrategyLastUpdate(uint256 strategyId) external view returns (uint64);
}
