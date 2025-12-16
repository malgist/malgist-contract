// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IUniversalAdapter (Hardened)
 * @notice Security-hardened interface for MALGIST protocol adapters
 * @dev This interface defines ONLY the secure, vault-callable functions
 * @dev Explicit design prevents accidental security vulnerabilities
 *
 * DESIGN PRINCIPLES:
 * ══════════════════
 * 1. EXPLICIT OVER GENERIC
 *    ✓ Specific functions: deposit(), withdraw(), emergencyWithdraw()
 *    ✗ No generic: execute(), call(), delegatecall()
 *
 * 2. VAULT-CONTROLLED
 *    ✓ All state-changing functions are vault-callable
 *    ✓ Adapters implement onlyVault modifier
 *    ✗ No user-callable state changes
 *
 * 3. NO BACKDOORS
 *    ✓ No proxy patterns, no upgrades, no admin keys
 *    ✓ Immutable vault and asset references
 *    ✗ No fallback(), no receive(), no arbitrary forwarding
 *
 * 4. CLEAR SECURITY BOUNDARIES
 *    ✓ Each function has documented security guarantees
 *    ✓ Error cases are explicit (revert vs return 0)
 *    ✓ No silent failures or undefined behavior
 *
 * SECURITY ENFORCEMENT:
 * ═════════════════════
 * The security model is enforced through:
 *
 * 1. Interface Contract (this file)
 *    - Defines function signatures only
 *    - Does not enforce access control (done in implementation)
 *    - Documents expected security properties
 *
 * 2. AdapterBase Abstract Contract
 *    - Implements onlyVault modifier
 *    - Provides token approval helpers with reset logic
 *    - Validates return values and deadlines
 *
 * 3. Concrete Adapter Implementation (e.g., HardenedAaveV3Adapter)
 *    - Extends AdapterBase
 *    - Implements all interface functions
 *    - Uses onlyVault on all state-changing functions
 *    - Resets all token approvals after use
 *
 * 4. Vault Contract (UniversalVaultV3)
 *    - Maintains adapter whitelist
 *    - Calls adapters via normal external calls (not delegatecall)
 *    - Enforces ReentrancyGuard on deposit/withdraw
 *
 * 5. Test Suite (AdapterAccessControl.t.sol)
 *    - Verifies all 8 attack vectors are mitigated
 *    - Tests each security property independently
 *    - Catches regressions early
 */

interface IUniversalAdapter {
    // ============ ENUMS ============

    /**
     * @notice Protocol classification for risk management
     * Used by vault to apply different rules (allocation caps, pause controls, etc.)
     */
    enum ProtocolType {
        LENDING,      // 0: Aave V3, Compound V3, Morpho Blue
        STAKING,      // 1: Lido, Rocket Pool, Liquid staking
        YIELD,        // 2: Yearn, Beefy, Convex, Aura
        DERIVATIVES   // 3: GMX, Gains Network, Pendle Finance
    }

    // ============ CORE OPERATIONS (VAULT CALLABLE) ============

    /**
     * @notice Deposit tokens into the underlying protocol
     * @param amount Amount of base tokens to deposit
     * @param minAmountOut Minimum acceptable shares (MEV protection)
     * @param deadline Transaction deadline (unix timestamp, uint256.max for no deadline)
     * @return shares Amount of protocol shares/receipt tokens received
     *
     * SECURITY GUARANTEES:
     * ═══════════════════
     * [1] VAULT ONLY: Only callable by vault (onlyVault modifier)
     *     - Direct user calls REVERTED immediately
     *     - msg.sender != VAULT → revert OnlyVault()
     *
     * [2] IMMUTABLE VAULT: Cannot be bypassed or spoofed
     *     - Vault address set in constructor
     *     - Declared as immutable (cannot be changed)
     *     - Baked into adapter bytecode
     *
     * [3] NO INFINITE APPROVALS: All approvals are finite
     *     - Approve(token, protocol, amount) - exact amount only
     *     - Never approve(token, protocol, type(uint256).max)
     *     - Reset to 0 immediately after use (prevents hijacking)
     *
     * [4] RETURN VALUE VALIDATED: No silent failures
     *     - Returns 0 → revert ZeroReturnValue()
     *     - Actual < minAmountOut → revert InsufficientOutput()
     *     - Shares issued correctly or transaction reverts
     *
     * [5] DEADLINE ENFORCED: Stale transactions rejected
     *     - block.timestamp > deadline → revert DeadlineExpired()
     *     - Prevents MEV attacks from delayed execution
     *
     * IMPLEMENTATION CHECKLIST:
     * ════════════════════════
     * function deposit(...) external onlyVault { ... }
     *   [ ] Use onlyVault modifier
     *   [ ] Validate amount > 0
     *   [ ] Validate deadline not expired
     *   [ ] Transfer tokens from vault using safeTransferFrom
     *   [ ] _safeApprove(token, protocol, amount)
     *   [ ] Call protocol's deposit/supply function
     *   [ ] _resetApproval(token, protocol) ← CRITICAL
     *   [ ] Validate return value > 0
     *   [ ] Validate return >= minAmountOut
     *   [ ] Transfer shares to vault
     *   [ ] Emit event
     *   [ ] Return shares
     *
     * ATTACK VECTORS PREVENTED:
     * ═════════════════════════
     * ✗ Direct user calls: onlyVault
     * ✗ Vault spoofing: immutable VAULT
     * ✗ Approval hijacking: reset to 0
     * ✗ Silent failures: return value validated
     * ✗ Sandwich attacks: minAmountOut + deadline
     * ✗ Fund diversion: vault controls flow
     */
    function deposit(uint256 amount, uint256 minAmountOut, uint256 deadline)
        external
        returns (uint256 shares);

    /**
     * @notice Withdraw tokens from the underlying protocol
     * @param shareAmount Amount of shares to burn
     * @param minAmountOut Minimum acceptable tokens (MEV protection)
     * @param deadline Transaction deadline (unix timestamp)
     * @return withdrawn Actual amount of base tokens returned
     *
     * SECURITY GUARANTEES:
     * ═══════════════════
     * [1] VAULT ONLY: Only callable by vault (onlyVault modifier)
     *     - Direct user calls REVERTED
     *     - msg.sender != VAULT → revert OnlyVault()
     *
     * [2] IMMUTABLE VAULT: Cannot be hijacked or redirected
     *     - Vault address is permanent reference
     *     - Cannot be changed after deployment
     *
     * [3] RETURN VALUE VALIDATED: No silent failures
     *     - Returns 0 → revert ZeroReturnValue()
     *     - Actual < minAmountOut → revert InsufficientOutput()
     *     - Either withdraw succeeds or transaction reverts
     *
     * [4] DEADLINE ENFORCED: Stale transactions rejected
     *     - Prevents MEV attacks from delayed execution
     *     - User specifies acceptable time window
     *
     * [5] NO STATE LEFT: Approvals and allowances reset
     *     - Any approvals needed are reset after use
     *     - No lingering tokens in adapter
     *
     * IMPLEMENTATION CHECKLIST:
     * ════════════════════════
     * function withdraw(...) external onlyVault { ... }
     *   [ ] Use onlyVault modifier
     *   [ ] Validate shareAmount > 0
     *   [ ] Validate deadline not expired
     *   [ ] Transfer shares from vault using safeTransferFrom
     *   [ ] Call protocol's withdraw/redeem function
     *   [ ] Validate return value > 0
     *   [ ] Validate return >= minAmountOut
     *   [ ] Transfer tokens to vault using safeTransfer
     *   [ ] Emit event
     *   [ ] Return withdrawn amount
     *
     * ATTACK VECTORS PREVENTED:
     * ═════════════════════════
     * ✗ Direct user calls: onlyVault
     * ✗ Silent failures: return value validated
     * ✗ Sandwich attacks: minAmountOut + deadline
     * ✗ Fund theft: vault-controlled withdrawal
     * ✗ Protocol hijacking: immutable adapter references
     */
    function withdraw(uint256 shareAmount, uint256 minAmountOut, uint256 deadline)
        external
        returns (uint256 withdrawn);

    /**
     * @notice Emergency withdrawal to recover funds (governance-triggered)
     * @param shareAmount Amount of shares to recover
     * @return recovered Amount of base tokens recovered
     *
     * SECURITY GUARANTEES:
     * ═══════════════════
     * [1] VAULT ONLY: Only callable by vault (onlyVault modifier)
     *     - No user can trigger emergency withdrawal
     *     - Only vault (controlled by governance) can use this
     *
     * [2] RECOVERY FOCUSED: Bypasses normal yield logic if needed
     *     - May use simplified withdrawal path
     *     - Prioritizes fund recovery over yield optimization
     *     - Useful if protocol is in distress
     *
     * [3] IMMUTABLE SECURITY: Cannot be hijacked or redirected
     *     - Even in emergency, funds go to vault only
     *     - Cannot redirect to attacker address
     *
     * IMPLEMENTATION GUIDANCE:
     * ══════════════════════
     * Option A: Delegate to normal withdrawal
     *   function emergencyWithdraw(uint256 shareAmount) external onlyVault {
     *       return withdraw(shareAmount, 0, type(uint256).max);
     *   }
     *
     * Option B: Implement protocol-specific recovery logic
     *   function emergencyWithdraw(uint256 shareAmount) external onlyVault {
     *       // Direct protocol call, bypass normal yield logic
     *       // May use alternative withdrawal path
     *   }
     *
     * Both options must:
     * [ ] Use onlyVault modifier
     * [ ] Return tokens to vault (or return value)
     * [ ] Validate recovery amount > 0
     * [ ] Emit event for monitoring
     */
    function emergencyWithdraw(uint256 shareAmount) external returns (uint256 recovered);

    // ============ INFORMATION FUNCTIONS (VIEW ONLY) ============
    // These functions are read-only, no state changes, safe to call from anywhere

    /**
     * @notice Get expected deposit output (before slippage)
     * @param amountIn Amount of base tokens to deposit
     * @return expectedOutput Expected amount of shares
     *
     * USAGE: Vault uses this to calculate minAmountOut
     *   expectedShares = adapter.getExpectedDepositOutput(amount)
     *   minAmountOut = expectedShares * 9950 / 10000  // 50 bps tolerance
     *   Then calls: adapter.deposit(amount, minAmountOut, deadline)
     *
     * ACCURACY REQUIREMENT: Within 1% (required for proper slippage calculation)
     * NOTE: This is a VIEW function, safe to call from anywhere
     */
    function getExpectedDepositOutput(uint256 amountIn) external view returns (uint256 expectedOutput);

    /**
     * @notice Get expected withdraw output (before slippage)
     * @param shareAmount Amount of shares to burn
     * @return expectedOutput Expected amount of base tokens
     *
     * USAGE: Vault uses this to calculate minAmountOut for withdrawals
     *   expectedAmount = adapter.getExpectedWithdrawOutput(shares)
     *   minAmountOut = expectedAmount * 9950 / 10000  // 50 bps tolerance
     *   Then calls: adapter.withdraw(shares, minAmountOut, deadline)
     *
     * ACCURACY REQUIREMENT: Within 1% (includes accrued yield/interest)
     * NOTE: This is a VIEW function, safe to call from anywhere
     */
    function getExpectedWithdrawOutput(uint256 shareAmount) external view returns (uint256 expectedOutput);

    /**
     * @notice Get current total value locked (TVL) in this adapter
     * @return tvl Total value locked in base token units
     *
     * USAGE: Vault uses this to track allocation ratios and TVL caps
     *   totalTVL = sum(adapter.getTVL() for all adapters)
     *   allocation = adapterTVL / totalTVL
     *   if (allocation > MAX_HIGH_RISK_ALLOCATION) revert HighRiskAllocationExceeded()
     *
     * NOTE: This is a VIEW function, safe to call from anywhere
     */
    function getTVL() external view returns (uint256 tvl);

    /**
     * @notice Get the base asset address this adapter accepts
     * @return tokenAddress Address of the base token (e.g., USDC)
     */
    function token() external view returns (address tokenAddress);

    /**
     * @notice Get the protocol type for classification
     * @return ProtocolType enum value (LENDING, STAKING, YIELD, DERIVATIVES)
     *
     * USAGE: Vault uses this for risk classification
     *   if (protocolType == DERIVATIVES) {
     *       // Apply high-risk controls (20% cap, governance pause, etc.)
     *   }
     */
    function protocolType() external view returns (ProtocolType);

    /**
     * @notice Get human-readable protocol name
     * @return name Protocol name (e.g., "Aave V3", "Lido", "GMX V2")
     *
     * USAGE: For UI display, event logging, debugging
     */
    function protocolName() external view returns (string memory name);

    /**
     * @notice Get the risk tier classification
     * @return riskTier 0=LOW, 1=MEDIUM, 2=HIGH
     *
     * USAGE: Vault applies risk-specific controls
     *   if (riskTier == 2) {
     *       // HIGH risk: apply allocation cap, governance pause, slippage adjustment
     *   }
     */
    function getRiskTier() external view returns (uint8 riskTier);

    /**
     * @notice Check if adapter is operational and healthy
     * @return isOperational true if adapter can accept deposits/withdrawals
     *
     * USAGE: Vault checks before deposits
     *   require(adapter.isOperational(), "Adapter not operational");
     *
     * Returns false if:
     * - Protocol is in emergency/pause mode
     * - Oracle feed is stale
     * - Liquidity is insufficient
     * - Adapter is disabled by governance
     */
    function isOperational() external view returns (bool);

    /**
     * @notice Get reason why adapter is not operational (if applicable)
     * @return reason Human-readable reason code or empty if operational
     *
     * USAGE: For monitoring and debugging
     *   if (!adapter.isOperational()) {
     *       emit AdapterHealthWarning(adapter, adapter.getHealthStatus());
     *   }
     */
    function getHealthStatus() external view returns (string memory reason);

    // ============ NO FALLBACK OR DELEGATECALL ============
    // This interface intentionally does NOT include:
    //   - execute(bytes) ← Arbitrary calldata execution
    //   - call(address, bytes) ← Generic protocol interaction
    //   - delegatecall(bytes) ← Context switching
    //   - fallback() ← Unspecified behavior
    //   - receive() ← ETH acceptance
    //   - admin functions ← Centralized risk
    //
    // This design prevents accidental security vulnerabilities and ensures
    // adapters can ONLY be used in their intended way: vault-controlled fund flows.
}
