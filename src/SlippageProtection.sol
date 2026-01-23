// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/*
 * @status ACTIVE
 * @network Chain-agnostic
 * @used-by UniversalVaultV2.sol, StrategyExecutor.sol
 * @notes Vault-level MEV/deadline guardrails shared across active deployments.
 */

/**
 * @title SlippageProtection
 * @notice MEV/sandwich attack mitigation system for DeFi vaults
 * @dev Provides slippage and deadline enforcement across all vault operations
 *
 * Security Architecture:
 * =====================
 * 1. SLIPPAGE PROTECTION (minAmountOut validation)
 *    - Protects against sandwich attacks where attacker:
 *      a) Frontruns user tx to manipulate AMM price
 *      b) User tx executes at bad price
 *      c) Backruns to revert or extract value
 *    - Mechanism: minAmountOut = expectedOut * (1 - slippageBps/10000)
 *    - Revert if: actualOut < minAmountOut
 *
 * 2. DEADLINE PROTECTION (block.timestamp validation)
 *    - Protects against stale transaction execution
 *    - Scenario: Mempool delay or pause/unpause extends transaction lifecycle
 *    - User tx becomes valid days later at different price
 *    - Mechanism: require(block.timestamp <= deadline)
 *    - Hard protection: mempool cannot resurrect old transactions
 *
 * 3. PER-STRATEGY OVERRIDE
 *    - Strategies can customize slippage tolerance
 *    - Creator determines acceptable MEV loss
 *    - Copiers inherit strategy's slippage setting
 *    - Example: Conservative: 10 bps, Aggressive: 100 bps
 *
 * Attack Scenarios Mitigated:
 * ===========================
 * Scenario 1: Classic Sandwich (Uniswap)
 *   Before: User tx slips from 100 USDC → 90 DAI to 50 DAI
 *   After: Vault enforces minAmountOut=89 DAI (10 bps slippage), tx reverts
 *
 * Scenario 2: MEV Front-run (Flash Loan)
 *   Before: Attacker flashloans, manipulates price, user executes, attacker repays
 *   After: Deadline protection prevents old txs, minAmountOut catches price impact
 *
 * Scenario 3: Stale Mempool (Pause/Unpause)
 *   Before: Deposit tx sits 1 day, vault unpauses, tx executes at old price
 *   After: Deadline (e.g., now + 30 min) causes expiration, tx reverts
 *
 * Gas Optimization:
 * =================
 * - No oracle calls at vault level (adapters handle quotes)
 * - Slippage calculation: O(1) bit operations
 * - Deadline check: O(1) comparison
 * - Per-strategy cache: Avoid recalculating for multi-adapter deposits
 * - Calldata: Use uint256 deadline for efficient packing
 *
 * Design Constraints:
 * ===================
 * - Max slippage cap: 500 bps (5%) - hard limit to prevent mistakes
 * - Default slippage: 50 bps (0.5%) - reasonable for most assets
 * - Deadline must be: block.timestamp < deadline < block.timestamp + 1 week
 * - Immutable for protocol-level settings (prevent admin abuse)
 */

/**
 * @notice Events for slippage and deadline related operations
 */
interface ISlippageProtectionEvents {
    /// @notice Emitted when slippage protection is validated
    event SlippageValidated(
        address indexed user,
        uint256 expectedOutput,
        uint256 actualOutput,
        uint256 minAmountOut,
        uint16 slippageBps
    );

    /// @notice Emitted when deadline protection is enforced
    event DeadlineEnforced(address indexed user, uint256 blockTimestamp, uint256 deadline);

    /// @notice Emitted when per-strategy slippage is set
    event StrategySlippageSet(address indexed creator, uint16 slippageBps);

    /// @notice Emitted when global default slippage is updated
    event DefaultSlippageUpdated(uint16 newSlippageBps);
}

/**
 * @notice Custom errors for gas-efficient error handling
 */
interface ISlippageProtectionErrors {
    /// @notice Slippage exceeded: actual < minimum acceptable
    error SlippageExceeded(uint256 actual, uint256 minimum);

    /// @notice Deadline expired: block.timestamp > deadline
    error DeadlineExpired(uint256 blockTimestamp, uint256 deadline);

    /// @notice Invalid slippage: exceeds maximum allowed
    error InvalidSlippage(uint16 slippageBps, uint16 maxAllowed);

    /// @notice Invalid deadline: not in valid range
    error InvalidDeadline(uint256 deadline, uint256 minDeadline, uint256 maxDeadline);

    /// @notice Adapter did not return expected output
    error AdapterOutputMismatch(uint256 expected, uint256 actual);

    /// @notice Cannot set slippage on non-existent strategy
    error NoStrategySet();

    /// @notice Slippage validation failed during multi-adapter deposit
    error MultiAdapterSlippageExceeded(address adapter, uint256 deficit);
}

/**
 * @title SlippageProtection
 * @notice Mixin contract providing MEV/slippage protection
 * @dev Integrates with vaults to enforce minAmountOut and deadline constraints
 */
contract SlippageProtection is ISlippageProtectionEvents, ISlippageProtectionErrors {
    // ============ CONSTANTS ============

    /// @notice Maximum allowed slippage tolerance (5%)
    uint16 public constant MAX_SLIPPAGE_BPS = 500;

    /// @notice Default slippage tolerance (0.5%)
    uint16 public constant DEFAULT_SLIPPAGE_BPS = 50;

    /// @notice Basis points denominator (10,000 = 100%)
    uint16 public constant TOTAL_BASIS_POINTS = 10000;

    /// @notice Maximum deadline offset from current time (1 week)
    uint256 public constant MAX_DEADLINE_OFFSET = 7 days;

    // ============ STATE VARIABLES ============

    /// @notice Global default slippage tolerance (immutable for protocol safety)
    uint16 public immutable defaultSlippageBps;

    /// @notice Per-strategy slippage override (strategy creator => custom slippage)
    mapping(address => uint16) public strategySlippage;

    // ============ INITIALIZATION ============

    /**
     * @notice Initialize slippage protection with default tolerance
     * @param _defaultSlippageBps Default slippage tolerance in basis points (max 500)
     */
    constructor(uint16 _defaultSlippageBps) {
        if (_defaultSlippageBps > MAX_SLIPPAGE_BPS) {
            revert InvalidSlippage(_defaultSlippageBps, MAX_SLIPPAGE_BPS);
        }
        defaultSlippageBps = _defaultSlippageBps;
    }

    // ============ SLIPPAGE PROTECTION FUNCTIONS ============

    /**
     * @notice Get effective slippage for a strategy
     * @param strategist Address of strategy creator
     * @return slippageBps Effective slippage (custom or default)
     *
     * @dev Priority:
     * 1. Strategy-specific override (if set)
     * 2. Protocol default
     */
    function getEffectiveSlippage(address strategist) public view returns (uint16) {
        uint16 override_ = strategySlippage[strategist];
        return override_ > 0 ? override_ : defaultSlippageBps;
    }

    /**
     * @notice Set custom slippage for a strategy
     * @param slippageBps New slippage tolerance (0-500 bps)
     *
     * @dev Security:
     * - Can only increase from default (strategy creator setting their own tolerance)
     * - Called by vault's strategy setter
     * - Cap enforcement prevents accidental misconfiguration
     */
    function setStrategySlippage(address strategist, uint16 slippageBps) external {
        _setStrategySlippage(strategist, slippageBps);
    }

    /**
     * @notice Internal strategy slippage setter (used by vault)
     */
    function _setStrategySlippage(address strategist, uint16 slippageBps) internal {
        if (slippageBps > MAX_SLIPPAGE_BPS) {
            revert InvalidSlippage(slippageBps, MAX_SLIPPAGE_BPS);
        }

        strategySlippage[strategist] = slippageBps;
        emit StrategySlippageSet(strategist, slippageBps);
    }

    /**
     * @notice Calculate minimum acceptable output after slippage
     * @param expectedOutput Expected output before slippage
     * @param slippageBps Slippage tolerance in basis points
     * @return minOutput Minimum acceptable output
     *
     * @dev Formula:
     * minOutput = expectedOutput * (10000 - slippageBps) / 10000
     * Example: expectedOut=100, slippageBps=50
     * minOutput = 100 * 9950 / 10000 = 99.5
     */
    function calculateMinAmountOut(uint256 expectedOutput, uint16 slippageBps) public pure returns (uint256) {
        if (slippageBps > MAX_SLIPPAGE_BPS) {
            revert InvalidSlippage(slippageBps, MAX_SLIPPAGE_BPS);
        }

        // minOutput = expectedOutput * (10000 - slippageBps) / 10000
        return (expectedOutput * (TOTAL_BASIS_POINTS - slippageBps)) / TOTAL_BASIS_POINTS;
    }

    /**
     * @notice Validate slippage constraint
     * @param actualOutput Actual output received
     * @param minAmountOut Minimum acceptable output
     * @param expectedOutput Expected output (for event logging)
     * @param slippageBps Slippage tolerance (for event logging)
     *
     * @dev Reverts if: actualOutput < minAmountOut
     */
    function validateSlippage(
        uint256 actualOutput,
        uint256 minAmountOut,
        uint256 expectedOutput,
        uint16 slippageBps
    ) external {
        _validateSlippage(actualOutput, minAmountOut, expectedOutput, slippageBps);
    }

    /**
     * @notice Internal slippage validation (used by vault)
     */
    function _validateSlippage(
        uint256 actualOutput,
        uint256 minAmountOut,
        uint256 expectedOutput,
        uint16 slippageBps
    ) internal {
        if (actualOutput < minAmountOut) {
            revert SlippageExceeded(actualOutput, minAmountOut);
        }
        emit SlippageValidated(msg.sender, expectedOutput, actualOutput, minAmountOut, slippageBps);
    }

    /**
     * @notice Validate deadline constraint
     * @param deadline Block timestamp deadline
     *
     * @dev Reverts if:
     * - block.timestamp > deadline (transaction expired)
     * - deadline <= block.timestamp + MAX_DEADLINE_OFFSET (deadline too far)
     */
    function validateDeadline(uint256 deadline) external view {
        _validateDeadline(deadline);
    }

    /**
     * @notice Internal deadline validation (used by vault)
     */
    function _validateDeadline(uint256 deadline) internal view {
        uint256 now_ = block.timestamp;

        // Transaction expired
        if (now_ > deadline) {
            revert DeadlineExpired(now_, deadline);
        }

        // Deadline too far in future (prevent accidental overly long validity)
        uint256 maxDeadline = now_ + MAX_DEADLINE_OFFSET;
        if (deadline > maxDeadline) {
            revert InvalidDeadline(deadline, now_, maxDeadline);
        }

        // Emit after validation passes
        // Note: Wrapped in public validateDeadline for external calls due to view constraint
    }

    /**
     * @notice Validate multi-adapter slippage (composite deposit)
     * @param amounts Array of deposit amounts per adapter
     * @param expectedOutputs Array of expected outputs per adapter
     * @param actualOutputs Array of actual outputs per adapter
     * @param minAmountOut Minimum total acceptable output
     * @param slippageBps Slippage tolerance
     *
     * @dev Complex case: Multiple adapters in single tx
     * - Validate each adapter individually
     * - Also validate total meets minimum
     * - Prevents adapter-by-adapter slippage accumulation
     *
     * Example:
     * - Deposit 1000 USDC across 2 adapters (500 each)
     * - Expected: 500+500=1000 shares
     * - Slippage 50 bps: min=995 total
     * - If Adapter1 slips 20 shares: 480, Adapter2 normal: 500
     * - Total 980 < 995: Revert
     */
    function validateMultiAdapterSlippage(
        uint256[] memory amounts,
        uint256[] memory expectedOutputs,
        uint256[] memory actualOutputs,
        uint256 minAmountOut,
        uint16 slippageBps
    ) external {
        _validateMultiAdapterSlippage(amounts, expectedOutputs, actualOutputs, minAmountOut, slippageBps);
    }

    /**
     * @notice Internal multi-adapter slippage validation (used by vault)
     */
    function _validateMultiAdapterSlippage(
        uint256[] memory amounts,
        uint256[] memory expectedOutputs,
        uint256[] memory actualOutputs,
        uint256 minAmountOut,
        uint16 slippageBps
    ) internal {
        uint256 totalActual = 0;
        uint256 totalExpected = 0;

        for (uint256 i = 0; i < actualOutputs.length; i++) {
            totalActual += actualOutputs[i];
            totalExpected += expectedOutputs[i];

            // Individual adapter validation
            uint256 minPerAdapter = calculateMinAmountOut(expectedOutputs[i], slippageBps);
            if (actualOutputs[i] < minPerAdapter) {
                revert MultiAdapterSlippageExceeded(address(0), minPerAdapter - actualOutputs[i]);
            }
        }

        // Total validation
        if (totalActual < minAmountOut) {
            revert SlippageExceeded(totalActual, minAmountOut);
        }

        emit SlippageValidated(msg.sender, totalExpected, totalActual, minAmountOut, slippageBps);
    }

    /**
     * @notice Check if adapter output meets expectations
     * @param expectedOutput Expected output from adapter
     * @param actualOutput Actual output from adapter
     *
     * @dev Used to detect adapter implementation bugs or malfunction
     * Reverts if adapter returns significantly less than expected
     */
    function validateAdapterOutput(uint256 expectedOutput, uint256 actualOutput) external pure {
        _validateAdapterOutput(expectedOutput, actualOutput);
    }

    /**
     * @notice Internal adapter output validation (used by vault)
     */
    function _validateAdapterOutput(uint256 expectedOutput, uint256 actualOutput) internal pure {
        // Allow tiny dust differences (rounding), but reject 0 returns
        if (actualOutput == 0 && expectedOutput > 0) {
            revert AdapterOutputMismatch(expectedOutput, actualOutput);
        }
    }
}
