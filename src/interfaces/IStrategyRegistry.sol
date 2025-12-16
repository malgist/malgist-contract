// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IStrategyRegistry {
    struct VersionInfo {
        uint256 versionId;
        address[] adapters;
        uint16[] ratios;
        uint8 riskLevel;
        bool active;
        bool deprecated;
        uint256 deprecatedAt;
    }

    function getVersion(uint256 strategyId, uint256 versionId) external view returns (VersionInfo memory);

    function isVersionDeprecated(uint256 strategyId, uint256 versionId) external view returns (bool);

    function isVersionActive(uint256 strategyId, uint256 versionId) external view returns (bool);

    // --- Permissionless additions ---
    function registerStrategy(uint256 strategyId, address creator, uint8 riskLevel, bytes32 riskDisclosureHash) external;

    function isCommunityReviewed(uint256 strategyId) external view returns (bool);

    function getRiskDisclosure(uint256 strategyId) external view returns (uint8, bytes32);

    function getLimitedCap(uint256 strategyId) external view returns (uint256);

    function phase() external view returns (uint8);

    // optional: allow vaults or registrars to register strategies on behalf of creators
    function setRegistrar(address who, bool ok) external;
}
