// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/*
 * @status LEGACY
 * @network Legacy only
 * @used-by UserVaultV2.sol
 * @notes Original pause mixin superseded by EmergencyPause but still needed for V2 archives.
 */

/**
 * @title Pausable
 * @notice Custom pausable implementation for Malgist vault
 * @dev Allows owner to pause vault operations while preserving withdrawals
 */
contract Pausable {
    // ============ STORAGE ============

    /// @notice Emergency pause state
    bool public paused;

    /// @notice Mapping of paused adapters
    mapping(address => bool) public pausedAdapters;

    /// @notice Owner/governance address
    address public owner;

    // ============ EVENTS ============

    event VaultPaused(address indexed by, uint256 timestamp);
    event VaultUnpaused(address indexed by, uint256 timestamp);
    event AdapterPaused(address indexed adapter, address indexed by, uint256 timestamp);
    event AdapterUnpaused(address indexed adapter, address indexed by, uint256 timestamp);
    event OwnerChanged(address indexed oldOwner, address indexed newOwner);

    // ============ ERRORS ============

    error OnlyOwner();
    error VaultIsPaused();
    error AdapterIsPaused();
    error ZeroAddress();

    // ============ MODIFIERS ============

    modifier onlyOwner() {
        if (msg.sender != owner) revert OnlyOwner();
        _;
    }

    modifier whenNotPaused() {
        if (paused) revert VaultIsPaused();
        _;
    }

    modifier whenAdapterNotPaused(address adapter) {
        if (pausedAdapters[adapter]) revert AdapterIsPaused();
        _;
    }

    // ============ CONSTRUCTOR ============

    constructor(address _owner) {
        if (_owner == address(0)) revert ZeroAddress();
        owner = _owner;
    }

    // ============ GOVERNANCE FUNCTIONS ============

    /**
     * @notice Pause vault operations (emergency only)
     * @dev Deposits & strategy execution blocked; withdrawals allowed
     */
    function pauseVault() external onlyOwner {
        paused = true;
        emit VaultPaused(msg.sender, block.timestamp);
    }

    /**
     * @notice Unpause vault operations
     */
    function unpauseVault() external onlyOwner {
        paused = false;
        emit VaultUnpaused(msg.sender, block.timestamp);
    }

    /**
     * @notice Pause specific adapter
     * @param adapter Address of adapter to pause
     */
    function pauseAdapter(address adapter) external onlyOwner {
        if (adapter == address(0)) revert ZeroAddress();
        pausedAdapters[adapter] = true;
        emit AdapterPaused(adapter, msg.sender, block.timestamp);
    }

    /**
     * @notice Unpause specific adapter
     * @param adapter Address of adapter to unpause
     */
    function unpauseAdapter(address adapter) external onlyOwner {
        if (adapter == address(0)) revert ZeroAddress();
        pausedAdapters[adapter] = false;
        emit AdapterUnpaused(adapter, msg.sender, block.timestamp);
    }

    /**
     * @notice Transfer ownership
     * @param newOwner Address of new owner
     */
    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert ZeroAddress();
        address oldOwner = owner;
        owner = newOwner;
        emit OwnerChanged(oldOwner, newOwner);
    }

    // ============ VIEW FUNCTIONS ============

    /**
     * @notice Check if vault is operational
     * @return true if vault is not paused
     */
    function isOperational() external view returns (bool) {
        return !paused;
    }

    /**
     * @notice Check if adapter is operational
     * @param adapter Address of adapter
     * @return true if adapter is not paused
     */
    function isAdapterOperational(address adapter) external view returns (bool) {
        return !pausedAdapters[adapter];
    }
}
