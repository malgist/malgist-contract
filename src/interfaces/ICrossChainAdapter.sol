// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title ICrossChainAdapter
 * @notice Extended interface for cross-chain capable adapters
 * @dev Extends IAdapter to support cross-chain operations while maintaining
 *      backward compatibility. Cross-chain adapters MUST handle latency,
 *      pending state, and bridge failures gracefully.
 *
 * CRITICAL PRINCIPLES:
 * 1. Never block withdrawals due to cross-chain delays
 * 2. Conservative accounting (never assume in-flight funds are settled)
 * 3. All cross-chain operations must be opt-in per strategy
 * 4. Bridge failures are contained within the adapter only
 */

interface ICrossChainAdapter {
    
    // ========================================================================
    // ENUMS & TYPES
    // ========================================================================

    /**
     * @dev Cross-chain bridge types
     * CANONICAL: Native bridge (e.g., Stargate for Ethereum ↔ Arbitrum)
     * MESSAGING: Message layer (LayerZero, CCIP, etc.)
     * MANUAL: External bridge requiring separate steps (for testing)
     */
    enum BridgeType { CANONICAL, MESSAGING, MANUAL }

    /**
     * @dev State of a cross-chain operation
     * PENDING: Initiated on source, waiting for bridge confirmation
     * CONFIRMED: Confirmed on destination chain (settled)
     * FAILED: Bridge delivery failed, funds returned to source
     * STUCK: Bridge halted or destination unavailable (emergency state)
     */
    enum CrossChainState { PENDING, CONFIRMED, FAILED, STUCK }

    /**
     * @dev Pending cross-chain operation
     */
    struct PendingCrossChainOp {
        uint256 operationId;              // Unique operation ID
        bytes32 bridgeId;                 // Bridge transaction hash/ID
        uint256 amount;                   // Amount in transit
        uint64 destinationChain;          // Destination chain ID
        address destinationAdapter;       // Adapter on destination
        CrossChainState state;            // Current state
        uint40 initiatedAt;               // Timestamp when initiated
        uint40 confirmedAt;               // Timestamp when confirmed (0 if pending)
    }

    // ========================================================================
    // CORE INTERFACE (extending IAdapter)
    // ========================================================================

    /**
     * @notice Deposit and bridge tokens to destination chain
     * @param amount Amount to deposit locally
     * @param destinationChain Target chain ID
     * @param destinationAdapter Adapter address on destination
     * @return operationId Pending cross-chain operation ID
     * @return deposited Amount locked locally (waiting for bridge confirmation)
     * 
     * NOTES:
     * - Funds are held in escrow on source chain during bridge
     * - Vault can still force-withdraw these funds if needed
     * - Returns operationId to track bridge status
     */
    function depositAndBridge(
        uint256 amount,
        uint64 destinationChain,
        address destinationAdapter
    ) external returns (uint256 operationId, uint256 deposited);

    /**
     * @notice Receive bridged tokens from another chain
     * @param sourceChain Source chain ID
     * @param sourceAdapter Adapter on source chain
     * @param amount Amount received
     * @return deposited Amount accepted
     * 
     * NOTES:
     * - Only callable by bridge/messaging relayer
     * - Must verify message authenticity
     * - Should never revert (bridge finality is guaranteed)
     */
    function receiveBridged(
        uint64 sourceChain,
        address sourceAdapter,
        uint256 amount
    ) external returns (uint256 deposited);

    /**
     * @notice Get current balance including pending cross-chain amounts
     * @return settled Confirmed balance on this chain
     * @return pending Amount in-flight across bridges
     * 
     * IMPORTANT: Vault MUST use only 'settled' for withdrawals
     */
    function getBalanceSplit() external view returns (uint256 settled, uint256 pending);

    /**
     * @notice Force-withdraw from cross-chain escrow (emergency)
     * @param operationId ID of pending operation
     * @return recovered Amount recovered to source chain
     * 
     * NOTES:
     * - Can be called by vault owner during emergency
     * - Releases escrowed funds back to local chain
     * - Marks operation as FAILED
     */
    function forceWithdrawCrossChain(uint256 operationId) external returns (uint256 recovered);

    /**
     * @notice Get status of a pending cross-chain operation
     * @param operationId Operation ID to check
     * @return operation Details of the pending operation
     */
    function getPendingOperation(uint256 operationId) 
        external 
        view 
        returns (PendingCrossChainOp memory operation);

    /**
     * @notice Get all pending cross-chain operations
     * @return operations Array of pending operations
     */
    function getAllPendingOperations() 
        external 
        view 
        returns (PendingCrossChainOp[] memory operations);

    /**
     * @notice Check if adapter is currently blocked due to bridge issues
     * @return isBlocked True if bridge is halted or stuck
     * @return reason Reason if blocked
     */
    function getBlockedStatus() external view returns (bool isBlocked, string memory reason);

    // ========================================================================
    // CONFIGURATION & SAFETY
    // ========================================================================

    /**
     * @notice Get bridge configuration for this adapter
     * @return bridgeType Type of bridge used
     * @return maxAllocationBps Max allocation % allowed for this adapter
     * @return maxPendingAmount Max amount that can be in-flight
     * @return supportedChains Array of supported destination chains
     */
    function getBridgeConfig() external view returns (
        BridgeType bridgeType,
        uint16 maxAllocationBps,
        uint256 maxPendingAmount,
        uint64[] memory supportedChains
    );

    /**
     * @notice Get risk metrics for cross-chain operations
     * @return bridgeRiskScore 0-10000 (higher = riskier)
     * @return avgBridgeLatencySeconds Typical bridge latency
     * @return failureRatePerMillionOps Empirical failure rate
     */
    function getRiskMetrics() external view returns (
        uint16 bridgeRiskScore,
        uint40 avgBridgeLatencySeconds,
        uint32 failureRatePerMillionOps
    );

    // ========================================================================
    // EVENTS
    // ========================================================================

    event CrossChainInitiated(
        uint256 indexed operationId,
        uint64 indexed destinationChain,
        address indexed destinationAdapter,
        uint256 amount,
        bytes32 bridgeId
    );

    event CrossChainConfirmed(
        uint256 indexed operationId,
        uint256 amount,
        uint40 confirmedAt
    );

    event CrossChainFailed(
        uint256 indexed operationId,
        string reason,
        uint256 amountRecovered
    );

    event BridgeBlocked(
        string reason,
        uint40 blockedAt
    );

    event ForceWithdrawCrossChain(
        uint256 indexed operationId,
        uint256 amount,
        string reason
    );

    event BridgeRecovered(
        uint256 indexed operationId,
        uint256 amount
    );
}
