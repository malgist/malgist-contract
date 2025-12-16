// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IUniversalAdapter
 * @notice Standard interface for all protocol adapters in MALGIST Universal Vault
 * @dev Supports lending, staking, yield, and derivatives protocols
 * @dev All adapters must implement this interface for vault compatibility
 */
interface IUniversalAdapter {
    // ============ PROTOCOL TYPES ============
    // Used for risk classification and governance controls

    enum ProtocolType {
        LENDING,      // 0: Aave, Compound, Morpho
        STAKING,      // 1: Lido, Rocket Pool
        YIELD,        // 2: Yearn, Beefy, Convex, Aura
        DERIVATIVES   // 3: GMX, Gains, Pendle
    }

    // ============ CORE OPERATIONS ============

    /**
     * @notice Deposit tokens into the underlying protocol
     * @param amount Amount of base token to deposit
     * @param minAmountOut Minimum acceptable output (slippage protection)
     * @param deadline Transaction deadline (unix timestamp)
     * @return shares Amount of shares/receipt tokens received
     *
     * @dev MUST revert if:
     *   - amount == 0
     *   - actual output < minAmountOut (MEV protection)
     *   - block.timestamp > deadline
     *   - adapter is paused or disabled
     */
    function deposit(uint256 amount, uint256 minAmountOut, uint256 deadline) external returns (uint256 shares);

    /**
     * @notice Withdraw tokens from the underlying protocol
     * @param shareAmount Amount of shares to burn
     * @param minAmountOut Minimum acceptable output (slippage protection)
     * @param deadline Transaction deadline (unix timestamp)
     * @return withdrawn Actual amount withdrawn in base tokens
     *
     * @dev MUST revert if:
     *   - shareAmount == 0
     *   - actual output < minAmountOut (MEV protection)
     *   - block.timestamp > deadline
     *   - adapter is paused or disabled
     */
    function withdraw(uint256 shareAmount, uint256 minAmountOut, uint256 deadline) external returns (uint256 withdrawn);

    // ============ QUOTE FUNCTIONS (View, no state change) ============

    /**
     * @notice Get expected deposit output (before slippage)
     * @param amountIn Amount of base token to deposit
     * @return expectedOutput Expected amount of shares/receipt tokens
     *
     * @dev Used by vault to calculate minAmountOut with slippage tolerance
     * @dev MUST be accurate within 1% for proper slippage calculation
     * @dev Can use oracle prices or exchange rates
     */
    function getExpectedDepositOutput(uint256 amountIn) external view returns (uint256 expectedOutput);

    /**
     * @notice Get expected withdraw output (before slippage)
     * @param shareAmount Amount of shares to burn
     * @return expectedOutput Expected amount of base tokens
     *
     * @dev Used by vault to calculate minAmountOut with slippage tolerance
     * @dev MUST be accurate within 1% for proper slippage calculation
     */
    function getExpectedWithdrawOutput(uint256 shareAmount) external view returns (uint256 expectedOutput);

    /**
     * @notice Get current TVL in the adapter (in base token value)
     * @return tvl Total value locked in this adapter
     *
     * @dev Used by vault to track allocation ratios and risk exposure
     * @dev Should include accrued interest/rewards in calculation
     */
    function getTVL() external view returns (uint256 tvl);

    // ============ ADAPTER INFO ============

    /**
     * @notice Get the base asset address this adapter accepts
     * @return tokenAddress Address of the base token (e.g., USDC)
     */
    function token() external view returns (address tokenAddress);

    /**
     * @notice Get the protocol type for risk classification
     * @return protocolType One of: LENDING, STAKING, YIELD, DERIVATIVES
     */
    function protocolType() external view returns (ProtocolType protocolType);

    /**
     * @notice Get human-readable protocol name
     * @return name Protocol name (e.g., "Aave V3", "Lido", "GMX V2")
     */
    function protocolName() external view returns (string memory name);

    /**
     * @notice Get protocol risk tier
     * @return riskTier 0=LOW, 1=MEDIUM, 2=HIGH
     *
     * @dev Used by vault for:
     *   - Per-adapter allocation caps
     *   - Emergency pause eligibility
     *   - Insurance/slippage parameter adjustment
     */
    function getRiskTier() external view returns (uint8 riskTier);

    // ============ HEALTH CHECK ============

    /**
     * @notice Check if adapter is operational
     * @return isOperational True if adapter can accept deposits/withdrawals
     *
     * @dev Returns false if:
     *   - Protocol is in emergency/pause mode
     *   - Oracle feed is stale
     *   - Liquidity is insufficient
     *   - Adapter is disabled by governance
     */
    function isOperational() external view returns (bool isOperational);

    /**
     * @notice Get the reason why adapter is not operational (if applicable)
     * @return reason Human-readable reason code or empty if operational
     */
    function getHealthStatus() external view returns (string memory reason);
}
