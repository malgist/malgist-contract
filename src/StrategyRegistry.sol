// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IStrategyRegistry} from "./interfaces/IStrategyRegistry.sol";

/// @title StrategyRegistry
/// @notice Central registry recording strategy versions, adapters, risk level and deprecation state
/// @dev Governance (owner) can add versions and deprecate them. Vaults read from this registry.
contract StrategyRegistry is Ownable, IStrategyRegistry {

    // strategyId => versionId => VersionInfo
    mapping(uint256 => mapping(uint256 => VersionInfo)) internal versions;

    /// @notice Emitted when a new version is added
    event StrategyVersionAdded(uint256 indexed strategyId, uint256 indexed versionId, address[] adapters, uint16[] ratios, uint8 riskLevel);

    /// @notice Emitted when a version is deprecated
    event StrategyDeprecated(uint256 indexed strategyId, uint256 indexed versionId, uint256 deprecatedAt);

    /// @notice Emitted when a version is activated
    event StrategyVersionActivated(uint256 indexed strategyId, uint256 indexed versionId);

    error VersionAlreadyExists();
    error VersionNotFound();

    /// @notice Add a new strategy version. Only owner (governance).
    function addVersion(
        uint256 strategyId,
        uint256 versionId,
        address[] calldata adapters,
        uint16[] calldata ratios,
        uint8 riskLevel,
        bool active
    ) external onlyOwner {
        VersionInfo storage v = versions[strategyId][versionId];
        if (v.versionId != 0) revert VersionAlreadyExists();

        v.versionId = versionId;
        v.adapters = adapters;
        v.ratios = ratios;
        v.riskLevel = riskLevel;
        v.active = active;
        v.deprecated = false;
        v.deprecatedAt = 0;

        emit StrategyVersionAdded(strategyId, versionId, adapters, ratios, riskLevel);
    }

    /// @notice Deprecate an existing version (only owner).
    function deprecateVersion(uint256 strategyId, uint256 versionId) external onlyOwner {
        VersionInfo storage v = versions[strategyId][versionId];
        if (v.versionId == 0) revert VersionNotFound();
        v.deprecated = true;
        v.active = false;
        v.deprecatedAt = block.timestamp;
        emit StrategyDeprecated(strategyId, versionId, v.deprecatedAt);
    }

    /// @notice Activate or reactivate a version (only owner)
    function setVersionActive(uint256 strategyId, uint256 versionId, bool active) external onlyOwner {
        VersionInfo storage v = versions[strategyId][versionId];
        if (v.versionId == 0) revert VersionNotFound();
        v.active = active;
        if (active) emit StrategyVersionActivated(strategyId, versionId);
    }

    /// @notice Query a stored version
    function getVersion(uint256 strategyId, uint256 versionId) external view returns (VersionInfo memory) {
        VersionInfo memory v = versions[strategyId][versionId];
        if (v.versionId == 0) revert VersionNotFound();
        return v;
    }

    function isVersionDeprecated(uint256 strategyId, uint256 versionId) external view returns (bool) {
        return versions[strategyId][versionId].deprecated;
    }

    function isVersionActive(uint256 strategyId, uint256 versionId) external view returns (bool) {
        return versions[strategyId][versionId].active && !versions[strategyId][versionId].deprecated;
    }

    // --- Permissionless strategy creation additions ---

    // Phase model for progressive decentralization
    enum StrategyPhase { Restricted, Limited, Permissionless }

    // internal storage for phase (uint8); pack with other small types
    StrategyPhase internal _phase;

    // Per-strategy canonical metadata
    struct StrategyMeta {
        address creator;
        uint8 riskLevel; // 0=Low,1=Medium,2=High (user-supplied)
        bytes32 riskDisclosureHash; // IPFS CID or on-chain hash
        bool communityReviewed;
        bool exists;
    }

    // ======== STORAGE (packed) ========
    // Slot 1: _phase (1 byte, enum) + padding
    // Note: enums take 1 byte in storage but occupy full 32 bytes in slot due to storage alignment
    // Slot 2+: config values
    
    // strategyId => meta
    mapping(uint256 => StrategyMeta) public strategies;

    // duplicate risk hash protection
    mapping(bytes32 => bool) public usedRiskHashes;

    // Approved creators for Restricted phase
    mapping(address => bool) public approvedCreator;
    // approved registrars (e.g., Vault) that may register on behalf of creators
    mapping(address => bool) public approvedRegistrar;

    // Per-address strategy count, and limit (pack uint256 + uint256)
    mapping(address => uint256) public creatorStrategyCount;
    uint256 public maxStrategiesPerAddress;

    // Limits for Limited phase (pack two uint256 together for better packing)
    uint256 public limitedMaxTVLPerStrategy;
    uint256 public limitedMaxTVLPerReviewedStrategy;

    // Events
    event StrategyCreated(uint256 indexed strategyId, address indexed creator);
    event StrategyReviewed(uint256 indexed strategyId, bool reviewed);
    event StrategyRiskDisclosed(uint256 indexed strategyId, uint8 riskLevel, bytes32 riskDisclosureHash);

    error DuplicateRiskHash(bytes32 hash);
    error NotApprovedCreator(address creatorAddr);
    error StrategyAlreadyExists(uint256 strategyId);
    error EmptyRiskDisclosure();
    error ExceedsMaxPerAddress();
    error UnauthorizedRegistrar(address caller);

    constructor() Ownable(msg.sender) {
        // default to Restricted to be conservative
        _phase = StrategyPhase.Restricted;
        maxStrategiesPerAddress = 5;
        limitedMaxTVLPerStrategy = 1_000 ether; // sensible default for tests
        limitedMaxTVLPerReviewedStrategy = 10_000 ether;
    }

    // Strategy creation metadata: creator calls through vault when creating a strategy
    function registerStrategy(uint256 strategyId, address creator, uint8 riskLevel, bytes32 riskDisclosureHash) external {
        if (strategies[strategyId].exists) revert StrategyAlreadyExists(strategyId);
        if (riskDisclosureHash == bytes32(0)) revert EmptyRiskDisclosure();
        if (usedRiskHashes[riskDisclosureHash]) revert DuplicateRiskHash(riskDisclosureHash);

        // Authorization: caller must be the creator, owner (governance), or an approved registrar
        if (msg.sender != creator && msg.sender != owner() && !approvedRegistrar[msg.sender]) revert UnauthorizedRegistrar(msg.sender);

        // Phase checks (based on creator)
        if (_phase == StrategyPhase.Restricted) {
            if (!approvedCreator[creator]) revert NotApprovedCreator(creator);
        }

        // per-address limit
        if (creatorStrategyCount[creator] + 1 > maxStrategiesPerAddress) revert ExceedsMaxPerAddress();

        strategies[strategyId] = StrategyMeta({
            creator: creator,
            riskLevel: riskLevel,
            riskDisclosureHash: riskDisclosureHash,
            communityReviewed: false,
            exists: true
        });

        usedRiskHashes[riskDisclosureHash] = true;
        creatorStrategyCount[creator]++;

        emit StrategyCreated(strategyId, creator);
        emit StrategyRiskDisclosed(strategyId, riskLevel, riskDisclosureHash);
    }

    function setRegistrar(address who, bool ok) external onlyOwner {
        approvedRegistrar[who] = ok;
    }

    function setCommunityReviewed(uint256 strategyId, bool reviewed) external onlyOwner {
        strategies[strategyId].communityReviewed = reviewed;
        emit StrategyReviewed(strategyId, reviewed);
    }

    function setPhase(StrategyPhase __phase) external onlyOwner {
        _phase = __phase;
    }

    function phase() external view returns (uint8) {
        return uint8(_phase);
    }

    function approveCreator(address who, bool ok) external onlyOwner {
        approvedCreator[who] = ok;
    }

    function setMaxStrategiesPerAddress(uint256 max_) external onlyOwner {
        maxStrategiesPerAddress = max_;
    }

    function setLimitedCaps(uint256 defaultCap, uint256 reviewedCap) external onlyOwner {
        limitedMaxTVLPerStrategy = defaultCap;
        limitedMaxTVLPerReviewedStrategy = reviewedCap;
    }

    // read helpers
    function isCommunityReviewed(uint256 strategyId) external view returns (bool) {
        return strategies[strategyId].communityReviewed;
    }

    function getRiskDisclosure(uint256 strategyId) external view returns (uint8, bytes32) {
        StrategyMeta memory m = strategies[strategyId];
        return (m.riskLevel, m.riskDisclosureHash);
    }

    function getLimitedCap(uint256 strategyId) external view returns (uint256) {
        if (strategies[strategyId].communityReviewed) return limitedMaxTVLPerReviewedStrategy;
        return limitedMaxTVLPerStrategy;
    }
}

