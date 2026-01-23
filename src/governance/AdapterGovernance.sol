// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/*
 * @status ACTIVE
 * @network Mantle Sepolia
 * @used-by DeployAdapterGovernance.s.sol
 * @notes Manages adapter approvals with guardian + timelock semantics.
 */

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title AdapterGovernance
 * @notice Staged rollout governance for protocol adapters with time-locks
 * @dev Implements multi-phase adapter approval with security time-delays
 *
 * DESIGN PHILOSOPHY:
 * - Progressive trust: Disabled → Staged → Approved
 * - Time-locks prevent instant malicious adapter activation
 * - Versioning enables safe adapter migrations
 * - Emergency blacklist for instant revocation
 * - Admin controls with timelock protection
 *
 * SECURITY BENEFITS:
 * ✅ 48-hour time-lock before adapter goes live
 * ✅ Versioning for backward compatibility
 * ✅ Emergency blacklist for compromised adapters
 * ✅ Transparent on-chain approval process
 * ✅ Prevents rug-pull via instant whitelisting
 */
contract AdapterGovernance is Ownable, ReentrancyGuard {

    // ============================================================================
    // ENUMS & STRUCTS
    // ============================================================================

    /**
     * @notice Adapter lifecycle phases
     * @param Disabled Adapter is not allowed (default state)
     * @param Staged Adapter is pending approval (time-locked)
     * @param Approved Adapter is fully approved and usable
     * @param Blacklisted Adapter is emergency-blacklisted (cannot be re-staged)
     */
    enum AdapterPhase {
        Disabled,      // 0: Not whitelisted
        Staged,        // 1: Pending time-lock
        Approved,      // 2: Fully approved
        Blacklisted    // 3: Emergency blacklist
    }

    /**
     * @notice Adapter metadata
     * @param phase Current lifecycle phase
     * @param version Adapter version (for tracking upgrades)
     * @param stagedAt Timestamp when adapter was staged
     * @param approvedAt Timestamp when adapter was approved
     * @param blacklistedAt Timestamp when adapter was blacklisted (if applicable)
     * @param identifier Unique identifier (e.g., keccak256("AAVE_V3"))
     * @param description Human-readable description
     */
    struct AdapterMetadata {
        AdapterPhase phase;
        uint16 version;
        uint48 stagedAt;
        uint48 approvedAt;
        uint48 blacklistedAt;
        bytes32 identifier;
        string description;
    }

    /**
     * @notice Adapter upgrade proposal
     * @param oldAdapter Address of old adapter version
     * @param newAdapter Address of new adapter version
     * @param proposedAt Timestamp of proposal
     * @param effectiveAt Timestamp when upgrade becomes effective
     * @param isExecuted Whether upgrade has been executed
     */
    struct AdapterUpgrade {
        address oldAdapter;
        address newAdapter;
        uint48 proposedAt;
        uint48 effectiveAt;
        bool isExecuted;
    }

    // ============================================================================
    // STATE VARIABLES
    // ============================================================================

    /// @notice Mapping from adapter address to metadata
    mapping(address => AdapterMetadata) public adapterMetadata;

    /// @notice Mapping from adapter address to phase
    mapping(address => AdapterPhase) public adapterPhase;

    /// @notice Mapping from adapter address to staged timestamp
    mapping(address => uint48) public stagedUntil;

    /// @notice Mapping from identifier to current adapter address
    mapping(bytes32 => address) public identifierToAdapter;

    /// @notice Mapping from old adapter to upgrade proposal
    mapping(address => AdapterUpgrade) public upgradeProposals;

    /// @notice Array of all staged adapters (for monitoring)
    address[] public stagedAdapters;

    /// @notice Array of all approved adapters
    address[] public approvedAdapters;

    /// @notice Array of all blacklisted adapters
    address[] public blacklistedAdapters;

    /// @notice Time-lock duration (default 48 hours)
    uint48 public constant TIMELOCK_DURATION = 2 days;

    /// @notice Minimum time-lock duration (cannot be reduced below this)
    uint48 public constant MIN_TIMELOCK = 1 days;

    /// @notice Maximum time-lock duration
    uint48 public constant MAX_TIMELOCK = 7 days;

    /// @notice Current time-lock duration (can be adjusted by governance)
    uint48 public timelockDuration = TIMELOCK_DURATION;

    /// @notice Emergency guardian address (can emergency blacklist)
    address public emergencyGuardian;

    // ============================================================================
    // EVENTS
    // ============================================================================

    event AdapterStaged(
        address indexed adapter,
        bytes32 indexed identifier,
        uint48 stagedUntil,
        uint16 version,
        string description
    );

    event AdapterApproved(
        address indexed adapter,
        bytes32 indexed identifier,
        uint48 approvedAt,
        uint16 version
    );

    event AdapterBlacklisted(
        address indexed adapter,
        bytes32 indexed identifier,
        address indexed by,
        string reason
    );

    event AdapterUpgradeProposed(
        address indexed oldAdapter,
        address indexed newAdapter,
        uint48 effectiveAt
    );

    event AdapterUpgradeExecuted(
        address indexed oldAdapter,
        address indexed newAdapter,
        uint48 executedAt
    );

    event TimelockDurationUpdated(uint48 oldDuration, uint48 newDuration);

    event EmergencyGuardianSet(address indexed oldGuardian, address indexed newGuardian);

    // ============================================================================
    // ERRORS
    // ============================================================================

    error InvalidAdapter();
    error AdapterAlreadyStaged();
    error AdapterNotStaged();
    error TimelockNotExpired();
    error AdapterIsBlacklisted();
    error InvalidPhaseTransition();
    error InvalidTimelock();
    error UpgradeNotReady();
    error UnauthorizedGuardian();
    error IdentifierTaken();

    // ============================================================================
    // MODIFIERS
    // ============================================================================

    modifier onlyGuardian() {
        if (msg.sender != emergencyGuardian && msg.sender != owner()) {
            revert UnauthorizedGuardian();
        }
        _;
    }

    // ============================================================================
    // CONSTRUCTOR
    // ============================================================================

    constructor(address _emergencyGuardian) Ownable(msg.sender) {
        require(_emergencyGuardian != address(0), "Invalid guardian");
        emergencyGuardian = _emergencyGuardian;
    }

    // ============================================================================
    // EXTERNAL FUNCTIONS - STAGED ROLLOUT
    // ============================================================================

    /**
     * @notice Stage an adapter for approval (starts time-lock)
     * @param adapter Adapter contract address
     * @param identifier Unique identifier (e.g., keccak256("AAVE_V3"))
     * @param version Adapter version number
     * @param description Human-readable description
     * @dev Initiates time-lock period before adapter can be approved
     */
    function stageAdapter(
        address adapter,
        bytes32 identifier,
        uint16 version,
        string calldata description
    )
        external
        onlyOwner
    {
        if (adapter == address(0)) revert InvalidAdapter();
        if (identifier == bytes32(0)) revert InvalidAdapter();

        AdapterPhase currentPhase = adapterPhase[adapter];

        // Cannot stage if already staged, approved, or blacklisted
        if (currentPhase == AdapterPhase.Staged) revert AdapterAlreadyStaged();
        if (currentPhase == AdapterPhase.Approved) revert InvalidPhaseTransition();
        if (currentPhase == AdapterPhase.Blacklisted) revert AdapterIsBlacklisted();

        // Check identifier is not already taken by another adapter
        address existingAdapter = identifierToAdapter[identifier];
        if (existingAdapter != address(0) && existingAdapter != adapter) {
            revert IdentifierTaken();
        }

        // Calculate staging end time
        uint48 stagedUntilTime = uint48(block.timestamp) + timelockDuration;

        // Update phase and metadata
        adapterPhase[adapter] = AdapterPhase.Staged;
        stagedUntil[adapter] = stagedUntilTime;

        adapterMetadata[adapter] = AdapterMetadata({
            phase: AdapterPhase.Staged,
            version: version,
            stagedAt: uint48(block.timestamp),
            approvedAt: 0,
            blacklistedAt: 0,
            identifier: identifier,
            description: description
        });

        // Map identifier to adapter
        identifierToAdapter[identifier] = adapter;

        // Add to staged list
        stagedAdapters.push(adapter);

        emit AdapterStaged(adapter, identifier, stagedUntilTime, version, description);
    }

    /**
     * @notice Approve a staged adapter (after time-lock expires)
     * @param adapter Adapter contract address
     * @dev Can only approve after time-lock period has passed
     */
    function approveAdapter(address adapter) external onlyOwner {
        if (adapterPhase[adapter] != AdapterPhase.Staged) revert AdapterNotStaged();
        if (block.timestamp < stagedUntil[adapter]) revert TimelockNotExpired();

        // Update phase
        adapterPhase[adapter] = AdapterPhase.Approved;

        AdapterMetadata storage metadata = adapterMetadata[adapter];
        metadata.phase = AdapterPhase.Approved;
        metadata.approvedAt = uint48(block.timestamp);

        // Add to approved list
        approvedAdapters.push(adapter);

        // Remove from staged list
        _removeFromStagedList(adapter);

        emit AdapterApproved(
            adapter,
            metadata.identifier,
            uint48(block.timestamp),
            metadata.version
        );
    }

    /**
     * @notice Emergency blacklist an adapter (instant, no time-lock)
     * @param adapter Adapter contract address
     * @param reason Reason for blacklisting
     * @dev Can be called by owner or emergency guardian
     *      Use this if adapter is compromised or malicious
     */
    function blacklistAdapter(address adapter, string calldata reason)
        external
        onlyGuardian
    {
        AdapterPhase currentPhase = adapterPhase[adapter];

        // Cannot blacklist if already blacklisted
        if (currentPhase == AdapterPhase.Blacklisted) revert AdapterIsBlacklisted();

        // Update phase
        adapterPhase[adapter] = AdapterPhase.Blacklisted;

        AdapterMetadata storage metadata = adapterMetadata[adapter];
        metadata.phase = AdapterPhase.Blacklisted;
        metadata.blacklistedAt = uint48(block.timestamp);

        // Add to blacklist
        blacklistedAdapters.push(adapter);

        // Remove from staged/approved lists
        if (currentPhase == AdapterPhase.Staged) {
            _removeFromStagedList(adapter);
        } else if (currentPhase == AdapterPhase.Approved) {
            _removeFromApprovedList(adapter);
        }

        emit AdapterBlacklisted(adapter, metadata.identifier, msg.sender, reason);
    }

    // ============================================================================
    // EXTERNAL FUNCTIONS - ADAPTER VERSIONING
    // ============================================================================

    /**
     * @notice Propose adapter upgrade (old version → new version)
     * @param oldAdapter Address of old adapter version
     * @param newAdapter Address of new adapter version
     * @param newVersion New version number
     * @param description Description of new version
     * @dev New adapter must go through staging process before activation
     */
    function proposeAdapterUpgrade(
        address oldAdapter,
        address newAdapter,
        uint16 newVersion,
        string calldata description
    )
        external
        onlyOwner
    {
        // Old adapter must be approved
        if (adapterPhase[oldAdapter] != AdapterPhase.Approved) {
            revert InvalidPhaseTransition();
        }

        // Get old adapter metadata
        AdapterMetadata memory oldMetadata = adapterMetadata[oldAdapter];

        // New version must be greater than old version
        require(newVersion > oldMetadata.version, "Version must increase");

        // Stage new adapter with same identifier
        bytes32 identifier = oldMetadata.identifier;

        // Stage new adapter
        uint48 stagedUntilTime = uint48(block.timestamp) + timelockDuration;

        adapterPhase[newAdapter] = AdapterPhase.Staged;
        stagedUntil[newAdapter] = stagedUntilTime;

        adapterMetadata[newAdapter] = AdapterMetadata({
            phase: AdapterPhase.Staged,
            version: newVersion,
            stagedAt: uint48(block.timestamp),
            approvedAt: 0,
            blacklistedAt: 0,
            identifier: identifier,
            description: description
        });

        stagedAdapters.push(newAdapter);

        // Create upgrade proposal
        uint48 effectiveAt = stagedUntilTime;

        upgradeProposals[oldAdapter] = AdapterUpgrade({
            oldAdapter: oldAdapter,
            newAdapter: newAdapter,
            proposedAt: uint48(block.timestamp),
            effectiveAt: effectiveAt,
            isExecuted: false
        });

        emit AdapterUpgradeProposed(oldAdapter, newAdapter, effectiveAt);
        emit AdapterStaged(newAdapter, identifier, stagedUntilTime, newVersion, description);
    }

    /**
     * @notice Execute adapter upgrade (after time-lock)
     * @param oldAdapter Address of old adapter version
     * @dev Approves new adapter and updates identifier mapping
     */
    function executeAdapterUpgrade(address oldAdapter) external onlyOwner {
        AdapterUpgrade storage upgrade = upgradeProposals[oldAdapter];

        require(upgrade.oldAdapter == oldAdapter, "No upgrade proposal");
        require(!upgrade.isExecuted, "Already executed");
        require(block.timestamp >= upgrade.effectiveAt, "Not yet effective");

        address newAdapter = upgrade.newAdapter;

        // Approve new adapter
        if (adapterPhase[newAdapter] != AdapterPhase.Staged) revert AdapterNotStaged();
        if (block.timestamp < stagedUntil[newAdapter]) revert TimelockNotExpired();

        adapterPhase[newAdapter] = AdapterPhase.Approved;

        AdapterMetadata storage newMetadata = adapterMetadata[newAdapter];
        newMetadata.phase = AdapterPhase.Approved;
        newMetadata.approvedAt = uint48(block.timestamp);

        approvedAdapters.push(newAdapter);
        _removeFromStagedList(newAdapter);

        // Update identifier mapping to point to new adapter
        bytes32 identifier = newMetadata.identifier;
        identifierToAdapter[identifier] = newAdapter;

        // Mark old adapter as disabled (but keep metadata for history)
        adapterPhase[oldAdapter] = AdapterPhase.Disabled;
        adapterMetadata[oldAdapter].phase = AdapterPhase.Disabled;
        _removeFromApprovedList(oldAdapter);

        // Mark upgrade as executed
        upgrade.isExecuted = true;

        emit AdapterUpgradeExecuted(oldAdapter, newAdapter, uint48(block.timestamp));
        emit AdapterApproved(newAdapter, identifier, uint48(block.timestamp), newMetadata.version);
    }

    // ============================================================================
    // EXTERNAL FUNCTIONS - GOVERNANCE
    // ============================================================================

    /**
     * @notice Set time-lock duration for adapter staging
     * @param newDuration New time-lock duration in seconds
     * @dev Must be between MIN_TIMELOCK and MAX_TIMELOCK
     */
    function setTimelockDuration(uint48 newDuration) external onlyOwner {
        if (newDuration < MIN_TIMELOCK || newDuration > MAX_TIMELOCK) {
            revert InvalidTimelock();
        }

        uint48 oldDuration = timelockDuration;
        timelockDuration = newDuration;

        emit TimelockDurationUpdated(oldDuration, newDuration);
    }

    /**
     * @notice Set emergency guardian address
     * @param newGuardian New guardian address
     */
    function setEmergencyGuardian(address newGuardian) external onlyOwner {
        require(newGuardian != address(0), "Invalid guardian");

        address oldGuardian = emergencyGuardian;
        emergencyGuardian = newGuardian;

        emit EmergencyGuardianSet(oldGuardian, newGuardian);
    }

    // ============================================================================
    // VIEW FUNCTIONS
    // ============================================================================

    /**
     * @notice Check if adapter is approved and usable
     * @param adapter Adapter address
     * @return isApproved True if adapter is approved
     */
    function isAdapterApproved(address adapter) external view returns (bool) {
        return adapterPhase[adapter] == AdapterPhase.Approved;
    }

    /**
     * @notice Get adapter metadata
     * @param adapter Adapter address
     * @return metadata Adapter metadata struct
     */
    function getAdapterMetadata(address adapter)
        external
        view
        returns (AdapterMetadata memory)
    {
        return adapterMetadata[adapter];
    }

    /**
     * @notice Get current adapter for an identifier
     * @param identifier Adapter identifier
     * @return adapter Current adapter address
     */
    function getAdapterByIdentifier(bytes32 identifier)
        external
        view
        returns (address)
    {
        return identifierToAdapter[identifier];
    }

    /**
     * @notice Get all approved adapters
     * @return adapters Array of approved adapter addresses
     */
    function getApprovedAdapters() external view returns (address[] memory) {
        return approvedAdapters;
    }

    /**
     * @notice Get all staged adapters
     * @return adapters Array of staged adapter addresses
     */
    function getStagedAdapters() external view returns (address[] memory) {
        return stagedAdapters;
    }

    /**
     * @notice Get all blacklisted adapters
     * @return adapters Array of blacklisted adapter addresses
     */
    function getBlacklistedAdapters() external view returns (address[] memory) {
        return blacklistedAdapters;
    }

    /**
     * @notice Get time remaining until adapter can be approved
     * @param adapter Adapter address
     * @return timeRemaining Seconds until approval is possible (0 if ready)
     */
    function getTimelockRemaining(address adapter) external view returns (uint48) {
        if (adapterPhase[adapter] != AdapterPhase.Staged) return 0;

        uint48 unlockTime = stagedUntil[adapter];
        if (block.timestamp >= unlockTime) return 0;

        return unlockTime - uint48(block.timestamp);
    }

    /**
     * @notice Get upgrade proposal for an adapter
     * @param oldAdapter Old adapter address
     * @return proposal Upgrade proposal struct
     */
    function getUpgradeProposal(address oldAdapter)
        external
        view
        returns (AdapterUpgrade memory)
    {
        return upgradeProposals[oldAdapter];
    }

    // ============================================================================
    // INTERNAL FUNCTIONS
    // ============================================================================

    /**
     * @notice Remove adapter from staged list
     * @param adapter Adapter address
     */
    function _removeFromStagedList(address adapter) internal {
        uint256 length = stagedAdapters.length;
        for (uint256 i = 0; i < length; i++) {
            if (stagedAdapters[i] == adapter) {
                stagedAdapters[i] = stagedAdapters[length - 1];
                stagedAdapters.pop();
                break;
            }
        }
    }

    /**
     * @notice Remove adapter from approved list
     * @param adapter Adapter address
     */
    function _removeFromApprovedList(address adapter) internal {
        uint256 length = approvedAdapters.length;
        for (uint256 i = 0; i < length; i++) {
            if (approvedAdapters[i] == adapter) {
                approvedAdapters[i] = approvedAdapters[length - 1];
                approvedAdapters.pop();
                break;
            }
        }
    }
}
