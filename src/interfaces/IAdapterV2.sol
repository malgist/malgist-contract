// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/*
 * @status EXPERIMENTAL
 * @network Prototype only
 * @used-by UniversalVaultV2.sol
 * @notes V2 adapter surface kept for experimental vaults.
 */

/**
 * @title IAdapterV2
 * @notice Enhanced adapter interface with slippage and deadline protection
 * @dev Adapters implementing this interface support MEV/sandwich attack mitigation
 *
 * Security Features:
 * - minAmountOut: Protects against slippage and sandwich attacks
 * - deadline: Prevents stale transaction execution
 * - Return value validation: No silent failures
 *
 * Adapter Responsibilities:
 * - Execute swap/LP operations atomically
 * - Validate slippage constraints
 * - Revert on MEV/slippage violations
 * - Never silently fail or return 0
 */
interface IAdapterV2 {
    /**
     * @notice Deposit tokens with slippage protection
     * @param amount Amount of base token to deposit
     * @param minAmountOut Minimum acceptable output (after slippage)
     * @param deadline Block timestamp deadline for transaction validity
     * @return shares Amount of shares/receipt tokens received
     *
     * @dev Implementation must:
     * - Calculate expected output
     * - Apply slippage: actualOut >= (expectedOut * (10000 - slippageBps)) / 10000
     * - Revert if actualOut < minAmountOut
     * - Revert if block.timestamp > deadline
     * - Never return 0 for successful deposits
     */
    function deposit(uint256 amount, uint256 minAmountOut, uint256 deadline) external returns (uint256 shares);

    /**
     * @notice Withdraw tokens with slippage protection
     * @param shareAmount Amount of shares to burn
     * @param minAmountOut Minimum acceptable output (after slippage)
     * @param deadline Block timestamp deadline for transaction validity
     * @return withdrawn Actual amount withdrawn in base tokens
     *
     * @dev Implementation must:
     * - Calculate expected output
     * - Apply slippage protection
     * - Revert if actualOut < minAmountOut
     * - Revert if block.timestamp > deadline
     * - Never return 0 for successful withdrawals
     */
    function withdraw(uint256 shareAmount, uint256 minAmountOut, uint256 deadline) external returns (uint256 withdrawn);

    /**
     * @notice Get expected output for a deposit amount
     * @param amountIn Amount of base tokens to deposit
     * @return expectedOutput Expected amount of shares/LP tokens received
     * @dev Used by vault to calculate minAmountOut
     */
    function getExpectedDepositOutput(uint256 amountIn) external view returns (uint256 expectedOutput);

    /**
     * @notice Get expected output for a withdrawal amount
     * @param shareAmount Amount of shares to burn
     * @return expectedOutput Expected amount of base tokens received
     * @dev Used by vault to calculate minAmountOut
     */
    function getExpectedWithdrawOutput(uint256 shareAmount) external view returns (uint256 expectedOutput);
}
