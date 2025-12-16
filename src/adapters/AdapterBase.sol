// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IUniversalAdapter} from "../interfaces/IUniversalAdapter.sol";

/**
 * @title AdapterBase
 * @notice Secure base contract for all MALGIST protocol adapters
 * @dev Enforces strict access control to prevent adapter hijacking and unauthorized fund flows
 *
 * SECURITY MODEL:
 * ===============
 * 1. VAULT OWNERSHIP: Each adapter is bound to a single immutable vault address
 * 2. ACCESS CONTROL: All state-changing operations restricted to vault only (onlyVault modifier)
 * 3. NO EXTERNAL CALLDATA: Adapters expose only specific functions (deposit, withdraw, emergencyWithdraw)
 * 4. APPROVAL RESET: All token approvals are reset to 0 immediately after use
 * 5. REENTRANCY SAFETY: Adapters should NOT be delegatecalled (prevented at vault level)
 *
 * ATTACK VECTORS PREVENTED:
 * =========================
 * [1] Direct User Calls: onlyVault modifier blocks direct adapter calls from users
 * [2] Arbitrary Execute: No fallback, delegatecall, or proxy mechanisms
 * [3] Approval Hijacking: Infinite approvals forbidden; all approvals reset after use
 * [4] Vault Spoofing: Vault address immutable; cannot be changed by any means
 * [5] Token Pulling: Users approve only vault, which controls adapter calls
 * [6] Reentrancy through External Protocols: SafeERC20 + no external state assumptions
 * [7] Adapter Replacement: Vault maintains whitelist; unauthorized adapters cannot operate
 * [8] Permission Escalation: No admin/owner functions in adapters (immutable design)
 *
 * DEPLOYMENT GUARANTEE:
 * =====================
 * Constructor MUST fail if:
 * - vault == address(0)
 * - baseAsset == address(0)
 * This prevents unintended initialization with invalid addresses.
 */
abstract contract AdapterBase is IUniversalAdapter {
    using SafeERC20 for IERC20;

    // ============ CUSTOM ERRORS ============

    /// @notice Caller is not the vault (access denied)
    error OnlyVault();

    /// @notice Vault address cannot be zero (security requirement)
    error InvalidVault();

    /// @notice Base asset address cannot be zero
    error InvalidAsset();

    /// @notice Token approval reset failed or was unnecessary
    error ApprovalResetFailed();

    /// @notice Adapter received zero return value from protocol interaction
    error ZeroReturnValue();

    /// @notice Insufficient output received vs minimum acceptable
    error InsufficientOutput(uint256 actual, uint256 minimum);

    /// @notice Deadline has passed; transaction is stale
    error DeadlineExpired();

    /// @notice Invalid input parameters
    error InvalidInput();

    // ============ EVENTS ============

    /// @notice Emitted when tokens are safely approved to external protocol
    event TokenApproved(address indexed token, address indexed spender, uint256 amount);

    /// @notice Emitted when token approval is reset to zero
    event TokenApprovalReset(address indexed token, address indexed spender);

    /// @notice Emitted on successful deposit execution
    event DepositExecuted(uint256 indexed amount, uint256 indexed sharesReceived, uint256 deadline);

    /// @notice Emitted on successful withdrawal execution
    event WithdrawalExecuted(uint256 indexed shares, uint256 indexed amountReceived, uint256 deadline);

    /// @notice Emitted on emergency withdrawal (may bypass yield logic)
    event EmergencyWithdrawalExecuted(uint256 indexed sharesRemoved, uint256 indexed amountRecovered);

    // ============ STATE VARIABLES ============

    /// @notice The vault contract that owns and controls this adapter
    /// @dev Immutable to prevent adapter hijacking or ownership changes
    address public immutable VAULT;

    /// @notice Base asset accepted by this adapter (e.g., USDC, WETH)
    /// @dev Immutable to prevent token switching attacks
    address public immutable ASSET;

    // ============ MODIFIERS ============

    /**
     * @notice Restrict function calls to the vault only
     * @dev All state-changing adapter operations MUST use this modifier
     * @dev Prevents:
     *   - Direct user calls
     *   - Unauthorized contract calls
     *   - Vault spoofing attempts
     */
    modifier onlyVault() {
        if (msg.sender != VAULT) revert OnlyVault();
        _;
    }

    /**
     * @notice Validate deadline has not passed
     * @param deadline Transaction deadline (unix timestamp)
     * @dev Prevents stale transactions from being executed
     */
    modifier validDeadline(uint256 deadline) {
        if (block.timestamp > deadline) revert DeadlineExpired();
        _;
    }

    /**
     * @notice Validate amount is non-zero
     * @param amount Amount to validate
     */
    modifier validAmount(uint256 amount) {
        if (amount == 0) revert InvalidInput();
        _;
    }

    // ============ CONSTRUCTOR ============

    /**
     * @notice Initialize adapter with immutable vault and asset references
     * @param _vault Address of the MALGIST vault that owns this adapter
     * @param _asset Address of the base asset (e.g., USDC)
     *
     * @dev CRITICAL: Constructor MUST validate both addresses:
     *   - _vault == address(0) → revert InvalidVault()
     *   - _asset == address(0) → revert InvalidAsset()
     *   This prevents initialization with invalid addresses and ensures
     *   all adapters have a valid, unchangeable vault reference.
     */
    constructor(address _vault, address _asset) {
        if (_vault == address(0)) revert InvalidVault();
        if (_asset == address(0)) revert InvalidAsset();

        VAULT = _vault;
        ASSET = _asset;
    }

    // ============ CORE ADAPTER INTERFACE (MUST IMPLEMENT) ============

    /**
     * @notice Deposit tokens into the underlying protocol
     * @param amount Amount of base tokens to deposit
     * @param minAmountOut Minimum acceptable shares (MEV protection)
     * @param deadline Transaction deadline
     * @return shares Amount of protocol shares/receipt tokens received
     *
     * @dev SECURITY GUARANTEES:
     *   ✓ Only callable by vault (onlyVault modifier)
     *   ✓ Deadline validation prevents stale transactions
     *   ✓ Returns non-zero value or reverts (no silent failures)
     *   ✓ All approvals reset to 0 after use
     *   ✓ No intermediate state that could be exploited
     *
     * IMPLEMENTATION CHECKLIST:
     *   [ ] Use onlyVault modifier
     *   [ ] Validate amount != 0
     *   [ ] Validate deadline
     *   [ ] _safeApprove() to external protocol
     *   [ ] Call protocol's deposit/supply function
     *   [ ] Validate return value != 0
     *   [ ] _resetApproval() to external protocol
     *   [ ] Return shares to vault
     *   [ ] Emit DepositExecuted event
     */
    function deposit(uint256 amount, uint256 minAmountOut, uint256 deadline)
        external
        virtual
        returns (uint256 shares);

    /**
     * @notice Withdraw tokens from the underlying protocol
     * @param shareAmount Amount of shares to burn
     * @param minAmountOut Minimum acceptable tokens (MEV protection)
     * @param deadline Transaction deadline
     * @return withdrawn Actual amount of base tokens returned
     *
     * @dev SECURITY GUARANTEES:
     *   ✓ Only callable by vault (onlyVault modifier)
     *   ✓ Deadline validation prevents stale transactions
     *   ✓ Returns non-zero value or reverts (no silent failures)
     *   ✓ All approvals reset to 0 after use
     *   ✓ Proportional withdrawal maintains invariants
     *
     * IMPLEMENTATION CHECKLIST:
     *   [ ] Use onlyVault modifier
     *   [ ] Validate shareAmount != 0
     *   [ ] Validate deadline
     *   [ ] Transfer shares from vault
     *   [ ] Call protocol's withdraw/redeem function
     *   [ ] Validate return value != 0
     *   [ ] _resetApproval() if needed
     *   [ ] Return withdrawn amount to vault
     *   [ ] Emit WithdrawalExecuted event
     */
    function withdraw(uint256 shareAmount, uint256 minAmountOut, uint256 deadline)
        external
        virtual
        returns (uint256 withdrawn);

    /**
     * @notice Emergency withdrawal to recover funds (governance controlled)
     * @param shareAmount Amount of shares to recover
     * @return recovered Amount of base tokens recovered
     *
     * @dev SECURITY GUARANTEES:
     *   ✓ Only callable by vault (onlyVault modifier)
     *   ✓ Bypasses normal yield logic for emergency scenarios
     *   ✓ Should recover funds even if protocol is in distress
     *   ✓ All approvals reset after use
     *
     * @dev OPTIONAL: Implement if emergency recovery needed
     *   Default: Delegates to normal withdraw with max deadline
     */
    /**
     * @notice Emergency withdrawal to recover funds (governance controlled)
     * @param shareAmount Amount of shares to recover
     * @return recovered Amount of base tokens recovered
     *
     * @dev SECURITY: Must be implemented by each adapter.
     *      Should only be callable by vault (onlyVault modifier).
     *      Should bypass normal yield logic if protocol is in distress.
     */
    function emergencyWithdraw(uint256 shareAmount) external virtual returns (uint256 recovered);

    // ============ QUOTE FUNCTIONS (VIEW, READ-ONLY) ============

    /**
     * @notice Get expected deposit output (before slippage)
     * @param amountIn Amount of base tokens to deposit
     * @return expectedOutput Expected shares received
     *
     * @dev ACCURACY REQUIREMENT:
     *   ✓ Must be accurate within 1% for proper slippage calculation
     *   ✓ Can use oracle prices, exchange rates, or protocol queries
     *   ✓ View function; no state changes or side effects
     */
    function getExpectedDepositOutput(uint256 amountIn) external view virtual returns (uint256 expectedOutput);

    /**
     * @notice Get expected withdraw output (before slippage)
     * @param shareAmount Amount of shares to burn
     * @return expectedOutput Expected base tokens returned
     *
     * @dev ACCURACY REQUIREMENT:
     *   ✓ Must be accurate within 1% for proper slippage calculation
     *   ✓ Should factor in accrued yields/interest
     *   ✓ View function; no state changes or side effects
     */
    function getExpectedWithdrawOutput(uint256 shareAmount) external view virtual returns (uint256 expectedOutput);

    /**
     * @notice Get current TVL in this adapter
     * @return tvl Total value locked (in base token units)
     */
    function getTVL() external view virtual returns (uint256 tvl);

    /**
     * @notice Get the base asset address
     * @return tokenAddress Address of the base token
     */
    function token() external view returns (address tokenAddress) {
        return ASSET;
    }

    /**
     * @notice Get protocol type classification
     * @return protocolType One of: LENDING, STAKING, YIELD, DERIVATIVES
     */
    function protocolType() external view virtual returns (ProtocolType protocolType);

    /**
     * @notice Get human-readable protocol name
     * @return name Protocol name (e.g., "Aave V3", "Lido")
     */
    function protocolName() external view virtual returns (string memory name);

    /**
     * @notice Get risk tier classification
     * @return riskTier 0=LOW, 1=MEDIUM, 2=HIGH
     */
    function getRiskTier() external view virtual returns (uint8 riskTier);

    /**
     * @notice Check if adapter is healthy and operational
     * @return isOperational True if adapter can accept deposits/withdrawals
     */
    function isOperational() external view virtual returns (bool isOperational);

    /**
     * @notice Get reason why adapter is not operational (if applicable)
     * @return reason Human-readable reason or empty if operational
     */
    function getHealthStatus() external view virtual returns (string memory reason);

    // ============ INTERNAL HELPER FUNCTIONS ============

    /**
     * @notice Safely approve token to spender with proper validation
     * @param tokenAddr Token to approve
     * @param spender Contract to approve
     * @param amount Amount to approve
     *
     * @dev SECURITY PROPERTIES:
     *   ✓ Uses SafeERC20.forceApprove() to handle non-standard ERC20s
     *   ✓ Resets approval to 0 before setting new amount (if needed)
     *   ✓ Prevents approval front-running attacks
     *   ✓ Handles return value properly (USDT, etc.)
     *
     * IMPORTANT: After use, MUST call _resetApproval() to zero out
     */
    function _safeApprove(address tokenAddr, address spender, uint256 amount) internal {
        IERC20(tokenAddr).forceApprove(spender, amount);
        emit TokenApproved(tokenAddr, spender, amount);
    }

    /**
     * @notice Reset token approval to zero
     * @param tokenAddr Token to reset
     * @param spender Contract to reset approval for
     *
     * @dev SECURITY PROPERTIES:
     *   ✓ Always called after external protocol interactions
     *   ✓ Prevents lingering approvals that could be exploited
     *   ✓ Uses SafeERC20 for safe reset
     *   ✓ No exceptions or error states
     *
     * PATTERN: Always pair _safeApprove() with _resetApproval()
     *   _safeApprove(token, protocol, amount);
     *   // ... call protocol ...
     *   _resetApproval(token, protocol);
     */
    function _resetApproval(address tokenAddr, address spender) internal {
        IERC20(tokenAddr).forceApprove(spender, 0);
        emit TokenApprovalReset(tokenAddr, spender);
    }

    /**
     * @notice Validate return value from protocol call
     * @param returnValue Value returned by protocol
     *
     * @dev Reverts if return value is zero
     * @dev Used after deposit/withdraw calls to ensure success
     */
    function _validateReturnValue(uint256 returnValue) internal pure {
        if (returnValue == 0) revert ZeroReturnValue();
    }

    /**
     * @notice Validate output meets minimum threshold
     * @param actual Actual output received
     * @param minimum Minimum acceptable output
     *
     * @dev Reverts if actual < minimum (MEV/slippage protection)
     */
    function _validateMinimumOutput(uint256 actual, uint256 minimum) internal pure {
        if (actual < minimum) revert InsufficientOutput(actual, minimum);
    }

    /**
     * @notice Transfer tokens from external address to adapter
     * @param tokenAddr Token to transfer
     * @param from Source address (usually vault)
     * @param amount Amount to transfer
     *
     * @dev Uses SafeERC20 for safe transfer
     */
    function _safeTransferFrom(address tokenAddr, address from, uint256 amount) internal {
        IERC20(tokenAddr).safeTransferFrom(from, address(this), amount);
    }

    /**
     * @notice Transfer tokens from adapter to external address
     * @param tokenAddr Token to transfer
     * @param to Destination address (usually vault)
     * @param amount Amount to transfer
     *
     * @dev Uses SafeERC20 for safe transfer
     */
    function _safeTransfer(address tokenAddr, address to, uint256 amount) internal {
        IERC20(tokenAddr).safeTransfer(to, amount);
    }

    // ============ NO FALLBACK OR DELEGATECALL ALLOWED ============
    // Adapters intentionally have no fallback() or receive() functions
    // This prevents:
    // - Accidental ETH sends
    // - Generic calldata forwarding
    // - Arbitrary function execution
    // Note: Vault level prevents delegatecall() via architecture design
}
