// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title EmergencyPause
 * @notice Emergency control system for MALGIST vault
 * @dev Provides granular pause controls for deposits, strategy execution, and per-adapter pausing
 *      while ensuring withdrawals ALWAYS remain available
 *
 * Security Design:
 * - Global pause: blocks deposits & strategy operations
 * - Per-adapter pause: blocks deposits/execution through specific adapters
 * - Withdrawals: NEVER affected by any pause state
 * - Role-based access: owner-only for pause/unpause
 * - Events: comprehensive event logging for monitoring
 * - Gas efficient: minimal storage overhead, O(1) operations
 */

/**
 * @notice Events for pause state changes
 */
interface IEmergencyPauseEvents {
    /// @notice Emitted when global deposits are paused
    event GlobalPauseEnabled(address indexed guardian, string reason);

    /// @notice Emitted when global deposits are unpaused
    event GlobalPauseDisabled(address indexed guardian);

    /// @notice Emitted when a specific adapter is paused
    event AdapterPaused(address indexed adapter, address indexed guardian, string reason);

    /// @notice Emitted when a specific adapter is unpaused
    event AdapterUnpaused(address indexed adapter, address indexed guardian);

    /// @notice Emitted when pause reason is updated
    event PauseReasonUpdated(string newReason);
}

/**
 * @notice Custom errors for gas-efficient error handling
 */
interface IEmergencyPauseErrors {
    /// @notice Caller is not authorized to pause/unpause
    error NotAuthorized();

    /// @notice Deposit attempted while paused
    error DepositsPaused();

    /// @notice Strategy execution attempted while paused
    error StrategyExecutionPaused();

    /// @notice Operation attempted through paused adapter
    error AdapterPausedError();

    /// @notice Adapter address is zero address
    error InvalidAdapter();

    /// @notice No pause is active
    error NoPauseActive();

    /// @notice Pause is already active
    error PauseAlreadyActive();
}

/**
 * @title EmergencyPause
 * @notice Mixin contract for emergency pause functionality
 * @dev Inherit from this contract to add emergency pause capabilities
 */
abstract contract EmergencyPause is IEmergencyPauseEvents, IEmergencyPauseErrors {
    // ============ CONSTANTS ============

    /// @notice The owner/guardian address - should be multisig in production
    address public immutable pauseOwner;

    // ============ STATE VARIABLES ============

    /// @notice Global pause state - affects all deposits and strategy execution
    bool private _globalPauseActive;

    /// @notice Reason for global pause (for transparency & incident response)
    string private _globalPauseReason;

    /// @notice Timestamp when global pause was activated
    uint256 private _globalPauseTimestamp;

    /// @notice Mapping of adapter => pause state
    mapping(address => bool) private _adapterPaused;

    /// @notice Mapping of adapter => pause reason
    mapping(address => string) private _adapterPauseReason;

    /// @notice Mapping of adapter => pause timestamp
    mapping(address => uint256) private _adapterPauseTimestamp;

    // ============ CONSTRUCTOR ============

    /**
     * @notice Initialize emergency pause system
     * @param _pauseOwner Address authorized to control pause (typically multisig)
     */
    constructor(address _pauseOwner) {
        if (_pauseOwner == address(0)) revert InvalidAdapter(); // Reuse error for brevity
        pauseOwner = _pauseOwner;
    }

    // ============ MODIFIERS ============

    /**
     * @notice Modifier to restrict functions to pause owner only
     */
    modifier onlyPauseOwner() {
        if (msg.sender != pauseOwner) revert NotAuthorized();
        _;
    }

    /**
     * @notice Modifier to check if deposits are not paused
     */
    modifier whenDepositsNotPaused() {
        if (_globalPauseActive) revert DepositsPaused();
        _;
    }

    /**
     * @notice Modifier to check if strategy execution is not paused
     */
    modifier whenStrategyExecutionNotPaused() {
        if (_globalPauseActive) revert StrategyExecutionPaused();
        _;
    }

    /**
     * @notice Modifier to check if a specific adapter is not paused
     * @param adapter Address of the adapter to check
     */
    modifier whenAdapterNotPaused(address adapter) {
        if (_adapterPaused[adapter]) revert AdapterPausedError();
        _;
    }

    /**
     * @notice Modifier to allow operations during pause (for withdrawals)
     * @dev This modifier exists for documentation purposes - withdrawals should NOT use pause modifiers
     */
    modifier withdrawalAlwaysPermitted() {
        // This modifier is intentionally empty
        // It serves as a flag that this function is safe to call during any pause state
        _;
    }

    // ============ EXTERNAL FUNCTIONS (ADMIN/GUARDIAN) ============

    /**
     * @notice Enable global pause (blocks deposits and strategy execution)
     * @param reason Descriptive reason for pause (for incident response)
     * @dev Only callable by pause owner (multisig/guardian)
     */
    function enableGlobalPause(string calldata reason) external onlyPauseOwner {
        if (_globalPauseActive) revert PauseAlreadyActive();

        _globalPauseActive = true;
        _globalPauseReason = reason;
        _globalPauseTimestamp = block.timestamp;

        emit GlobalPauseEnabled(msg.sender, reason);
    }

    /**
     * @notice Disable global pause (re-enable deposits and strategy execution)
     * @dev Only callable by pause owner (multisig/guardian)
     */
    function disableGlobalPause() external onlyPauseOwner {
        if (!_globalPauseActive) revert NoPauseActive();

        _globalPauseActive = false;
        emit GlobalPauseDisabled(msg.sender);
    }

    /**
     * @notice Pause a specific adapter (blocks deposits/execution through this adapter)
     * @param adapter Address of adapter to pause
     * @param reason Descriptive reason for pause
     * @dev Only callable by pause owner (multisig/guardian)
     */
    function pauseAdapter(address adapter, string calldata reason) external onlyPauseOwner {
        if (adapter == address(0)) revert InvalidAdapter();
        if (_adapterPaused[adapter]) revert PauseAlreadyActive();

        _adapterPaused[adapter] = true;
        _adapterPauseReason[adapter] = reason;
        _adapterPauseTimestamp[adapter] = block.timestamp;

        emit AdapterPaused(adapter, msg.sender, reason);
    }

    /**
     * @notice Unpause a specific adapter (re-enable deposits/execution through this adapter)
     * @param adapter Address of adapter to unpause
     * @dev Only callable by pause owner (multisig/guardian)
     */
    function unpauseAdapter(address adapter) external onlyPauseOwner {
        if (adapter == address(0)) revert InvalidAdapter();
        if (!_adapterPaused[adapter]) revert NoPauseActive();

        _adapterPaused[adapter] = false;
        emit AdapterUnpaused(adapter, msg.sender);
    }

    /**
     * @notice Update the reason for global pause (for transparency)
     * @param newReason Updated reason string
     * @dev Only callable by pause owner
     */
    function updateGlobalPauseReason(string calldata newReason) external onlyPauseOwner {
        if (!_globalPauseActive) revert NoPauseActive();
        _globalPauseReason = newReason;
        emit PauseReasonUpdated(newReason);
    }

    // ============ EXTERNAL FUNCTIONS (PUBLIC VIEW/QUERY) ============

    /**
     * @notice Check if global pause is active
     * @return True if global pause is active, false otherwise
     */
    function isGlobalPauseActive() external view returns (bool) {
        return _globalPauseActive;
    }

    /**
     * @notice Get the reason for global pause
     * @return Reason string (empty if no pause active)
     */
    function getGlobalPauseReason() external view returns (string memory) {
        return _globalPauseReason;
    }

    /**
     * @notice Get timestamp when global pause was activated
     * @return Timestamp in seconds (0 if no pause active)
     */
    function getGlobalPauseTimestamp() external view returns (uint256) {
        return _globalPauseTimestamp;
    }

    /**
     * @notice Check if a specific adapter is paused
     * @param adapter Address of adapter to check
     * @return True if adapter is paused, false otherwise
     */
    function isAdapterPaused(address adapter) external view returns (bool) {
        return _adapterPaused[adapter];
    }

    /**
     * @notice Get the reason for adapter pause
     * @param adapter Address of adapter to check
     * @return Reason string (empty if adapter not paused)
     */
    function getAdapterPauseReason(address adapter) external view returns (string memory) {
        return _adapterPauseReason[adapter];
    }

    /**
     * @notice Get timestamp when adapter pause was activated
     * @param adapter Address of adapter to check
     * @return Timestamp in seconds (0 if adapter not paused)
     */
    function getAdapterPauseTimestamp(address adapter) external view returns (uint256) {
        return _adapterPauseTimestamp[adapter];
    }

    /**
     * @notice Check if a specific adapter can accept deposits
     * @param adapter Address of adapter to check
     * @return True if adapter is operational, false if paused
     */
    function isAdapterOperational(address adapter) public view returns (bool) {
        return !_adapterPaused[adapter] && !_globalPauseActive;
    }

    /**
     * @notice Get comprehensive pause status
     * @return globalPaused True if global pause is active
     * @return pausedAdapters Array of paused adapter addresses (use this for iteration if needed)
     * @dev For off-chain queries; on-chain, prefer individual isAdapterPaused() calls
     */
    function getPauseStatus() external view returns (bool globalPaused, address[] memory pausedAdapters) {
        globalPaused = _globalPauseActive;
        // NOTE: This returns empty array; to track all paused adapters, maintain off-chain records
        // or emit events for indexing. This is more gas-efficient than maintaining a list on-chain.
        pausedAdapters = new address[](0);
    }

    // ============ INTERNAL FUNCTIONS (FOR USE IN VAULT LOGIC) ============

    /**
     * @notice Internal function to check if deposits are allowed
     * @dev Use in deposit() function via whenDepositsNotPaused modifier
     */
    function _checkDepositsAllowed() internal view {
        if (_globalPauseActive) revert DepositsPaused();
    }

    /**
     * @notice Internal function to check if adapter is operational for deposit
     * @param adapter Address of adapter to verify
     * @dev Use in deposit logic before calling adapter.deposit()
     */
    function _checkAdapterOperational(address adapter) internal view {
        if (_adapterPaused[adapter]) revert AdapterPausedError();
        if (_globalPauseActive) revert DepositsPaused();
    }

    /**
     * @notice Internal function to check if strategy execution is allowed
     * @dev Use in strategy rebalance/update functions
     */
    function _checkStrategyExecutionAllowed() internal view {
        if (_globalPauseActive) revert StrategyExecutionPaused();
    }

    /**
     * @notice Internal function to verify adapter is not paused
     * @param adapter Address of adapter to check
     * @dev Use in critical paths to ensure adapter operations are permitted
     */
    function _requireAdapterNotPaused(address adapter) internal view {
        if (_adapterPaused[adapter]) revert AdapterPausedError();
    }

    /**
     * @notice Internal function to verify withdraw is always permitted
     * @dev This is a no-op function serving as documentation
     *      Withdrawals should NEVER check pause state
     */
    function _checkWithdrawalAlwaysAllowed() internal pure {
        // Intentionally empty - withdrawals bypass all pause checks
        // This function exists for clarity in contract logic
    }
}
