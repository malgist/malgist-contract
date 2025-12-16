// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title IAdapterWithPause
 * @notice Extended adapter interface that acknowledges pause functionality in vault
 * @dev Adapters themselves don't need to implement pause logic; the vault handles it
 *      This interface documents the contract guarantees
 */
interface IAdapterWithPause {
    /**
     * @notice Deposit tokens into the underlying protocol
     * @param amount Amount of base token to deposit
     * @return shares Amount of shares/receipt tokens received
     *
     * NOTE ON EMERGENCY CONTROL:
     * - The vault (caller) may pause deposits via EmergencyPause
     * - Adapters do NOT implement pause logic themselves
     * - The vault will NOT call this function if paused (blocked at vault level)
     * - Adapter implementers should NOT add pause checks here
     */
    function deposit(uint256 amount) external returns (uint256 shares);

    /**
     * @notice Withdraw tokens from the underlying protocol
     * @param amount Amount of base token to withdraw
     * @return withdrawn Actual amount withdrawn (may differ due to fees/slippage)
     *
     * NOTE ON EMERGENCY CONTROL:
     * - Withdrawals are NEVER paused (vault design requirement)
     * - Adapters MUST allow withdrawal even if other vault functions are paused
     * - Adapter implementers should NOT add pause checks here
     * - Vault guarantees this function will always be callable
     */
    function withdraw(uint256 amount) external returns (uint256 withdrawn);

    /**
     * @notice Get the current balance in the underlying protocol
     * @return balance Current value in base tokens
     */
    function getBalance() external view returns (uint256 balance);

    /**
     * @notice Get the underlying asset address (e.g., USDC)
     * @return tokenAddress Address of the base token this adapter accepts
     */
    function token() external view returns (address tokenAddress);
}

// ============ ADAPTER IMPLEMENTATION PATTERN ============

/**
 * @title FusionXAdapterWithPauseSupport
 * @notice Example adapter showing how to properly handle pause system
 * @dev This adapter demonstrates:
 * - No pause logic in adapter itself
 * - Clean return value validation
 * - Proper event emissions
 * - Gas-efficient operations
 */
contract FusionXAdapterWithPauseSupport {
    using SafeERC20 for IERC20;

    // ============ STATE ============

    address public immutable VAULT;
    IERC20 public immutable ASSET;
    address public immutable UNISWAP_ROUTER;
    address public immutable LP_TOKEN;

    uint16 public constant DEFAULT_SLIPPAGE_BPS = 50; // 0.5%

    // ============ EVENTS ============

    event DepositExecuted(uint256 indexed amount, uint256 shares, uint16 slippage);
    event WithdrawalExecuted(uint256 indexed shares, uint256 withdrawn, uint16 slippage);

    // ============ ERRORS ============

    error OnlyVault();
    error DepositFailed();
    error WithdrawalFailed();
    error SlippageExceeded();
    error InvalidAmount();

    // ============ CONSTRUCTOR ============

    constructor(address _vault, address _asset, address _router, address _lpToken) {
        VAULT = _vault;
        ASSET = IERC20(_asset);
        UNISWAP_ROUTER = _router;
        LP_TOKEN = _lpToken;

        // Max approve router for efficiency
        ASSET.forceApprove(_router, type(uint256).max);
    }

    // ============ ADAPTER INTERFACE (CALLED BY VAULT) ============

    /**
     * @notice Deposit base asset into Uniswap V2 liquidity pool
     * @param amount Amount of base asset to deposit
     * @return shares Amount of LP tokens received
     *
     * IMPORTANT: This function is only called when vault has verified:
     * - Global pause is NOT active
     * - This adapter is NOT paused
     * Adapter does NOT need to check pause state
     */
    function deposit(uint256 amount) external returns (uint256 shares) {
        if (msg.sender != VAULT) revert OnlyVault();
        if (amount == 0) revert InvalidAmount();

        // Execute Uniswap V2 deposit logic
        shares = _depositToUniswapV2(amount, DEFAULT_SLIPPAGE_BPS);

        // CRITICAL: Validate deposit succeeded
        if (shares == 0) revert DepositFailed();

        emit DepositExecuted(amount, shares, DEFAULT_SLIPPAGE_BPS);
        return shares;
    }

    /**
     * @notice Withdraw base asset from Uniswap V2 liquidity pool
     * @param amount Amount of LP tokens to burn
     * @return withdrawn Amount of base asset received
     *
     * IMPORTANT: This function may be called even if vault is paused
     * Adapter MUST allow withdrawal regardless of vault pause state
     * Adapter does NOT check pause state (that's vault's responsibility)
     */
    function withdraw(uint256 amount) external returns (uint256 withdrawn) {
        if (msg.sender != VAULT) revert OnlyVault();
        if (amount == 0) revert InvalidAmount();

        // Execute Uniswap V2 withdrawal logic
        withdrawn = _withdrawFromUniswapV2(amount, DEFAULT_SLIPPAGE_BPS);

        // CRITICAL: Validate withdrawal succeeded
        if (withdrawn == 0) revert WithdrawalFailed();

        emit WithdrawalExecuted(amount, withdrawn, DEFAULT_SLIPPAGE_BPS);
        return withdrawn;
    }

    /**
     * @notice Get current balance of LP tokens held by adapter
     * @return balance Current LP token balance
     */
    function getBalance() external view returns (uint256 balance) {
        return IERC20(LP_TOKEN).balanceOf(address(this));
    }

    /**
     * @notice Get underlying asset address
     * @return tokenAddress Address of USDC or base asset
     */
    function token() external view returns (address tokenAddress) {
        return address(ASSET);
    }

    // ============ INTERNAL FUNCTIONS ============

    /**
     * @notice Internal function to deposit into Uniswap V2
     * @param amount Amount to deposit
     * @param slippageBps Slippage tolerance in basis points
     * @return shares LP tokens received
     */
    function _depositToUniswapV2(uint256 amount, uint16 slippageBps) internal returns (uint256 shares) {
        // Simplified logic - swap 50% for pair, add liquidity
        uint256 swapAmount = amount / 2;
        uint256 liquidityAmount = amount - swapAmount;

        // Execute swap and add liquidity (implementation details omitted)
        // This is pseudo-code for illustration
        shares = 0; // Replace with actual logic

        return shares;
    }

    /**
     * @notice Internal function to withdraw from Uniswap V2
     * @param lpAmount LP tokens to burn
     * @param slippageBps Slippage tolerance in basis points
     * @return withdrawn Base asset received
     */
    function _withdrawFromUniswapV2(uint256 lpAmount, uint16 slippageBps) internal returns (uint256 withdrawn) {
        // Remove liquidity, swap for base asset
        // This is pseudo-code for illustration
        withdrawn = 0; // Replace with actual logic

        return withdrawn;
    }
}

// ============ ADAPTER PATTERN DOCUMENTATION ============

/**
 * ADAPTER INTEGRATION GUIDE
 * ==========================
 *
 * WHAT THE VAULT HANDLES:
 * ✅ Pause state management (global + per-adapter)
 * ✅ Checking adapter operational status before deposit
 * ✅ Blocking deposits when paused
 * ✅ Ensuring withdrawals always work
 * ✅ Monitoring for adapter failures
 *
 * WHAT THE ADAPTER MUST DO:
 * ✅ Return non-zero shares on successful deposit
 * ✅ Return non-zero withdrawn on successful withdrawal
 * ✅ Allow withdraw() calls even when vault is paused (critical!)
 * ✅ Implement only: deposit(), withdraw(), getBalance(), token()
 * ❌ DO NOT implement pause logic
 * ❌ DO NOT check if vault is paused
 * ❌ DO NOT revert on deposits because vault is paused
 *
 * VAULT CALLING SEQUENCE:
 * 1. Vault checks isAdapterPaused(adapter) -> false
 * 2. Vault checks isGlobalPauseActive() -> false
 * 3. Vault calls adapter.deposit(amount)
 * 4. Adapter executes and returns shares
 * 5. Vault validates shares > 0
 *
 * EMERGENCY SCENARIO:
 * 1. Vault detects exploit in FusionX
 * 2. Guardian calls pauseAdapter(fusionXAddress, "Exploit detected")
 * 3. Vault blocks all NEW deposits through FusionX
 * 4. Users CAN still withdraw from FusionX (critical for safety)
 * 5. No funds are locked
 *
 * ADAPTER FAILURE SCENARIOS HANDLED BY VAULT:
 * - Return value = 0 (silent failure) -> caught by vault validation
 * - Revert during deposit -> caught by try/catch (can be added)
 * - Adapter is paused -> checked before calling adapter
 * - Global pause active -> checked before calling adapter
 */
