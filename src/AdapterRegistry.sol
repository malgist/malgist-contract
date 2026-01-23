// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/*
 * @status ACTIVE
 * @network Mantle Sepolia + staging
 * @used-by DeployProtocolCore.s.sol, UserVault.sol
 * @notes Central adapter whitelist and metadata store for vault + executor.
 */

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title AdapterRegistry
 * @notice Centralized registry mapping protocol identifiers to adapter implementations
 * @dev This is the SINGLE SOURCE OF TRUTH for adapter resolution.
 *      By centralizing adapter registration, we achieve:
 *      1. Clean separation: UniversalVault never knows about concrete adapters
 *      2. Deployment flexibility: Switch between production and mock adapters without vault changes
 *      3. Audit cleanliness: No test conditionals in production code
 *      4. Determinism: Adapter resolution is deterministic and locked at deployment
 *
 * Architecture:
 * - AdapterRegistry is deployed ONCE per deployment scenario
 * - For production: maps AAVE → RealAaveAdapter, LIDO → RealLidoAdapter
 * - For demo: maps AAVE → MockAaveAdapter, LIDO → MockLidoAdapter
 * - UniversalVault queries registry to resolve adapters at construction time
 * - Vault stores resolved adapter addresses, never queries registry again
 * - This ensures deterministic, fixed adapter addresses throughout vault lifecycle
 */
contract AdapterRegistry is Ownable {
    // ============ Constants ============

    /// @notice Protocol identifier for Aave V3
    bytes32 public constant PROTOCOL_AAVE_V3 = keccak256("AAVE_V3");

    /// @notice Protocol identifier for Lido
    bytes32 public constant PROTOCOL_LIDO = keccak256("LIDO");

    /// @notice Protocol identifier for GMX
    bytes32 public constant PROTOCOL_GMX = keccak256("GMX");

    /// @notice Protocol identifier for FusionX
    bytes32 public constant PROTOCOL_FUSIONX = keccak256("FUSIONX");

    /// @notice Protocol identifier for Lendle
    bytes32 public constant PROTOCOL_LENDLE = keccak256("LENDLE");

    // ============ State Variables ============

    /// @notice Maps protocol identifier to adapter address
    /// @dev mapping(bytes32 protocolId => address adapterAddress)
    mapping(bytes32 => address) private _adapters;

    /// @notice Tracks all registered protocol IDs for iteration
    bytes32[] private _registeredProtocols;

    /// @notice Tracks if a protocol has been registered
    mapping(bytes32 => bool) private _isRegistered;

    // ============ Events ============

    /**
     * @notice Emitted when a new adapter is registered
     * @param protocolId Protocol identifier (e.g., PROTOCOL_AAVE_V3)
     * @param adapterAddress Address of the adapter implementation
     * @param isProduction True if production adapter, false if mock
     */
    event AdapterRegistered(bytes32 indexed protocolId, address indexed adapterAddress, bool isProduction);

    /**
     * @notice Emitted when an adapter is updated
     * @param protocolId Protocol identifier
     * @param oldAdapter Previous adapter address
     * @param newAdapter New adapter address
     */
    event AdapterUpdated(bytes32 indexed protocolId, address indexed oldAdapter, address indexed newAdapter);

    /**
     * @notice Emitted when adapter registration is locked (no more changes)
     * @param timestamp Block timestamp when locked
     */
    event RegistryLocked(uint256 indexed timestamp);

    // ============ Constructor ============

    /**
     * @notice Initialize adapter registry
     * @dev Registry starts unlocked to allow adapter registration
     *      After all adapters registered, owner should lock registry to prevent changes
     */
    constructor() Ownable(msg.sender) {}

    // ============ Public Functions ============

    /**
     * @notice Register or update an adapter implementation
     * @dev Only owner can register adapters (part of deployment)
     * @param protocolId Protocol identifier (use PROTOCOL_* constants)
     * @param adapterAddress Address of the adapter implementation
     * @param isProduction Whether this is a production adapter
     *
     * Example usage:
     *   // Production deployment
     *   registry.registerAdapter(PROTOCOL_AAVE_V3, realAaveAdapter, true);
     *
     *   // Demo deployment
     *   registry.registerAdapter(PROTOCOL_AAVE_V3, mockAaveAdapter, false);
     */
    function registerAdapter(bytes32 protocolId, address adapterAddress, bool isProduction) external onlyOwner {
        if (adapterAddress == address(0)) revert InvalidAdapterAddress();

        // If first registration of this protocol, add to registered list
        if (!_isRegistered[protocolId]) {
            _registeredProtocols.push(protocolId);
            _isRegistered[protocolId] = true;
        } else {
            // Update existing adapter
            address oldAdapter = _adapters[protocolId];
            emit AdapterUpdated(protocolId, oldAdapter, adapterAddress);
        }

        _adapters[protocolId] = adapterAddress;
        emit AdapterRegistered(protocolId, adapterAddress, isProduction);
    }

    /**
     * @notice Get adapter address for a specific protocol
     * @dev This is the ONLY way UniversalVault resolves adapters
     * @param protocolId Protocol identifier
     * @return Adapter address (reverts if protocol not registered)
     */
    function getAdapter(bytes32 protocolId) external view returns (address) {
        address adapter = _adapters[protocolId];
        if (adapter == address(0)) revert ProtocolNotRegistered(protocolId);
        return adapter;
    }

    /**
     * @notice Check if a protocol is registered
     * @param protocolId Protocol identifier
     * @return True if adapter is registered for this protocol
     */
    function isProtocolRegistered(bytes32 protocolId) external view returns (bool) {
        return _isRegistered[protocolId];
    }

    /**
     * @notice Get all registered protocols
     * @return Array of all protocol IDs that have adapters registered
     */
    function getRegisteredProtocols() external view returns (bytes32[] memory) {
        return _registeredProtocols;
    }

    /**
     * @notice Get count of registered protocols
     * @return Number of protocols with registered adapters
     */
    function getProtocolCount() external view returns (uint256) {
        return _registeredProtocols.length;
    }

    /**
     * @notice Get adapter for all registered protocols
     * @return protocols Array of protocol IDs
     * @return adapters Array of corresponding adapter addresses
     */
    function getAllAdapters() external view returns (bytes32[] memory protocols, address[] memory adapters) {
        uint256 count = _registeredProtocols.length;
        protocols = _registeredProtocols;
        adapters = new address[](count);

        for (uint256 i = 0; i < count; ++i) {
            adapters[i] = _adapters[_registeredProtocols[i]];
        }

        return (protocols, adapters);
    }

    // ============ Errors ============

    error InvalidAdapterAddress();
    error ProtocolNotRegistered(bytes32 protocolId);
}
