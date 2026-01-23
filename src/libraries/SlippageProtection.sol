// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/*
 * @status EXPERIMENTAL
 * @network Prototype only
 * @used-by PriceOracle.sol consumers
 * @notes Dynamic slippage math for oracle-integrated swaps.
 */

/**
 * @title SlippageProtection
 * @notice Dynamic slippage calculation library with price oracle integration
 * @dev Provides MEV protection through trade-size-based slippage scaling
 *
 * DESIGN PHILOSOPHY:
 * - Larger trades = higher slippage tolerance (deeper into order book)
 * - Oracle-based expected output calculation
 * - Configurable slippage tiers
 * - Protection against sandwich attacks and MEV
 *
 * SECURITY FEATURES:
 * ✅ Dynamic slippage based on trade size
 * ✅ Oracle price validation
 * ✅ Minimum output enforcement
 * ✅ Configurable slippage tiers
 * ✅ MEV protection through scaling
 */

import {IPriceOracle} from "../interfaces/IPriceOracle.sol";

library SlippageProtection {

    // ============================================================================
    // STRUCTS
    // ============================================================================

    /**
     * @notice Slippage configuration for trade size tiers
     * @param smallTradeBps Slippage for trades < tier1Threshold (e.g., 0.5%)
     * @param mediumTradeBps Slippage for tier1 ≤ trades < tier2Threshold (e.g., 1%)
     * @param largeTradeBps Slippage for tier2 ≤ trades < tier3Threshold (e.g., 2%)
     * @param whaleTradeBps Slippage for trades ≥ tier3Threshold (e.g., 5%)
     * @param tier1Threshold Small → Medium threshold (e.g., $10k)
     * @param tier2Threshold Medium → Large threshold (e.g., $100k)
     * @param tier3Threshold Large → Whale threshold (e.g., $1M)
     */
    struct SlippageConfig {
        uint16 smallTradeBps;      // 0-10000 (0-100%)
        uint16 mediumTradeBps;     // 0-10000
        uint16 largeTradeBps;      // 0-10000
        uint16 whaleTradeBps;      // 0-10000
        uint256 tier1Threshold;    // USD value in 18 decimals
        uint256 tier2Threshold;    // USD value in 18 decimals
        uint256 tier3Threshold;    // USD value in 18 decimals
    }

    /**
     * @notice Swap parameters with slippage protection
     * @param tokenIn Input token address
     * @param tokenOut Output token address
     * @param amountIn Input amount
     * @param priceOracle PriceOracle contract address
     * @param config Slippage configuration
     */
    struct SwapParams {
        address tokenIn;
        address tokenOut;
        uint256 amountIn;
        address priceOracle;
        SlippageConfig config;
    }

    /**
     * @notice Calculated slippage result
     * @param expectedOutput Expected output from oracle price
     * @param minOutput Minimum acceptable output (after slippage)
     * @param slippageBps Applied slippage in basis points
     * @param tradeSizeTier Trade size tier (0=small, 1=medium, 2=large, 3=whale)
     */
    struct SlippageResult {
        uint256 expectedOutput;
        uint256 minOutput;
        uint16 slippageBps;
        uint8 tradeSizeTier;
    }

    // ============================================================================
    // CONSTANTS
    // ============================================================================

    uint16 public constant BPS = 10000;                    // 100% in basis points
    uint16 public constant MAX_SLIPPAGE_BPS = 1000;        // 10% max slippage
    uint8 public constant TIER_SMALL = 0;
    uint8 public constant TIER_MEDIUM = 1;
    uint8 public constant TIER_LARGE = 2;
    uint8 public constant TIER_WHALE = 3;

    // ============================================================================
    // ERRORS
    // ============================================================================

    error InvalidSlippageConfig();
    error OraclePriceZero();
    error SlippageTooHigh();
    error InsufficientOutput();
    error InvalidThresholds();

    // ============================================================================
    // CORE FUNCTIONS
    // ============================================================================

    /**
     * @notice Calculate dynamic slippage and minimum output
     * @param params Swap parameters with oracle and config
     * @return result Calculated slippage result
     * @dev Uses oracle to get expected output, applies dynamic slippage
     */
    function calculateSlippage(SwapParams memory params)
        internal
        view
        returns (SlippageResult memory result)
    {
        // Validate slippage config
        _validateConfig(params.config);

        // Get prices from oracle
        IPriceOracle oracle = IPriceOracle(params.priceOracle);
        uint256 priceIn = oracle.getPrice(params.tokenIn);
        uint256 priceOut = oracle.getPrice(params.tokenOut);

        if (priceIn == 0 || priceOut == 0) revert OraclePriceZero();

        // Calculate expected output based on oracle prices
        // expectedOutput = (amountIn * priceIn) / priceOut
        result.expectedOutput = (params.amountIn * priceIn) / priceOut;

        // Calculate trade value in USD (18 decimals)
        uint256 tradeValueUSD = (params.amountIn * priceIn) / 1e18;

        // Determine trade size tier and slippage
        (result.tradeSizeTier, result.slippageBps) = _getTierAndSlippage(
            tradeValueUSD,
            params.config
        );

        // Calculate minimum output after slippage
        // minOutput = expectedOutput * (BPS - slippageBps) / BPS
        result.minOutput = (result.expectedOutput * (BPS - result.slippageBps)) / BPS;

        return result;
    }

    /**
     * @notice Validate swap output against minimum threshold
     * @param actualOutput Actual output from swap
     * @param minOutput Minimum acceptable output
     * @dev Reverts if actual < minimum
     */
    function validateOutput(uint256 actualOutput, uint256 minOutput)
        internal
        pure
    {
        if (actualOutput < minOutput) revert InsufficientOutput();
    }

    /**
     * @notice Calculate minimum output with custom slippage
     * @param expectedOutput Expected output amount
     * @param slippageBps Slippage in basis points
     * @return minOutput Minimum acceptable output
     */
    function calculateMinOutput(uint256 expectedOutput, uint16 slippageBps)
        internal
        pure
        returns (uint256 minOutput)
    {
        if (slippageBps > MAX_SLIPPAGE_BPS) revert SlippageTooHigh();
        return (expectedOutput * (BPS - slippageBps)) / BPS;
    }

    /**
     * @notice Get expected output from oracle prices
     * @param amountIn Input amount
     * @param tokenIn Input token address
     * @param tokenOut Output token address
     * @param priceOracle PriceOracle contract address
     * @return expectedOutput Expected output based on oracle prices
     */
    function getExpectedOutput(
        uint256 amountIn,
        address tokenIn,
        address tokenOut,
        address priceOracle
    )
        internal
        view
        returns (uint256 expectedOutput)
    {
        IPriceOracle oracle = IPriceOracle(priceOracle);
        uint256 priceIn = oracle.getPrice(tokenIn);
        uint256 priceOut = oracle.getPrice(tokenOut);

        if (priceIn == 0 || priceOut == 0) revert OraclePriceZero();

        return (amountIn * priceIn) / priceOut;
    }

    /**
     * @notice Get dynamic slippage for a trade size
     * @param tradeValueUSD Trade value in USD (18 decimals)
     * @param config Slippage configuration
     * @return slippageBps Slippage in basis points
     */
    function getDynamicSlippage(uint256 tradeValueUSD, SlippageConfig memory config)
        internal
        pure
        returns (uint16 slippageBps)
    {
        (, slippageBps) = _getTierAndSlippage(tradeValueUSD, config);
        return slippageBps;
    }

    /**
     * @notice Get trade size tier for a trade value
     * @param tradeValueUSD Trade value in USD (18 decimals)
     * @param config Slippage configuration
     * @return tier Trade size tier (0-3)
     */
    function getTradeSizeTier(uint256 tradeValueUSD, SlippageConfig memory config)
        internal
        pure
        returns (uint8 tier)
    {
        (tier, ) = _getTierAndSlippage(tradeValueUSD, config);
        return tier;
    }

    // ============================================================================
    // HELPER FUNCTIONS - DEFAULT CONFIGS
    // ============================================================================

    /**
     * @notice Get conservative slippage configuration
     * @return config Conservative slippage config
     * @dev Low slippage tolerance for conservative strategies
     */
    function getConservativeConfig()
        internal
        pure
        returns (SlippageConfig memory config)
    {
        return SlippageConfig({
            smallTradeBps: 30,        // 0.3%
            mediumTradeBps: 50,       // 0.5%
            largeTradeBps: 100,       // 1%
            whaleTradeBps: 200,       // 2%
            tier1Threshold: 10_000e18,    // $10k
            tier2Threshold: 100_000e18,   // $100k
            tier3Threshold: 1_000_000e18  // $1M
        });
    }

    /**
     * @notice Get moderate slippage configuration
     * @return config Moderate slippage config
     * @dev Balanced slippage tolerance
     */
    function getModerateConfig()
        internal
        pure
        returns (SlippageConfig memory config)
    {
        return SlippageConfig({
            smallTradeBps: 50,        // 0.5%
            mediumTradeBps: 100,      // 1%
            largeTradeBps: 200,       // 2%
            whaleTradeBps: 300,       // 3%
            tier1Threshold: 10_000e18,    // $10k
            tier2Threshold: 100_000e18,   // $100k
            tier3Threshold: 1_000_000e18  // $1M
        });
    }

    /**
     * @notice Get aggressive slippage configuration
     * @return config Aggressive slippage config
     * @dev Higher slippage tolerance for aggressive strategies
     */
    function getAggressiveConfig()
        internal
        pure
        returns (SlippageConfig memory config)
    {
        return SlippageConfig({
            smallTradeBps: 100,       // 1%
            mediumTradeBps: 200,      // 2%
            largeTradeBps: 300,       // 3%
            whaleTradeBps: 500,       // 5%
            tier1Threshold: 10_000e18,    // $10k
            tier2Threshold: 100_000e18,   // $100k
            tier3Threshold: 1_000_000e18  // $1M
        });
    }

    // ============================================================================
    // INTERNAL HELPER FUNCTIONS
    // ============================================================================

    /**
     * @notice Determine trade size tier and corresponding slippage
     * @param tradeValueUSD Trade value in USD (18 decimals)
     * @param config Slippage configuration
     * @return tier Trade size tier (0-3)
     * @return slippageBps Slippage in basis points
     */
    function _getTierAndSlippage(uint256 tradeValueUSD, SlippageConfig memory config)
        private
        pure
        returns (uint8 tier, uint16 slippageBps)
    {
        if (tradeValueUSD >= config.tier3Threshold) {
            return (TIER_WHALE, config.whaleTradeBps);
        } else if (tradeValueUSD >= config.tier2Threshold) {
            return (TIER_LARGE, config.largeTradeBps);
        } else if (tradeValueUSD >= config.tier1Threshold) {
            return (TIER_MEDIUM, config.mediumTradeBps);
        } else {
            return (TIER_SMALL, config.smallTradeBps);
        }
    }

    /**
     * @notice Validate slippage configuration
     * @param config Slippage configuration to validate
     */
    function _validateConfig(SlippageConfig memory config)
        private
        pure
    {
        // Validate slippage values
        if (config.smallTradeBps > MAX_SLIPPAGE_BPS) revert InvalidSlippageConfig();
        if (config.mediumTradeBps > MAX_SLIPPAGE_BPS) revert InvalidSlippageConfig();
        if (config.largeTradeBps > MAX_SLIPPAGE_BPS) revert InvalidSlippageConfig();
        if (config.whaleTradeBps > MAX_SLIPPAGE_BPS) revert InvalidSlippageConfig();

        // Validate threshold ordering (tier1 < tier2 < tier3)
        if (config.tier1Threshold >= config.tier2Threshold) revert InvalidThresholds();
        if (config.tier2Threshold >= config.tier3Threshold) revert InvalidThresholds();

        // Validate slippage progression (small ≤ medium ≤ large ≤ whale)
        if (config.smallTradeBps > config.mediumTradeBps) revert InvalidSlippageConfig();
        if (config.mediumTradeBps > config.largeTradeBps) revert InvalidSlippageConfig();
        if (config.largeTradeBps > config.whaleTradeBps) revert InvalidSlippageConfig();
    }

    // ============================================================================
    // VIEW HELPERS
    // ============================================================================

    /**
     * @notice Preview slippage calculation without executing
     * @param params Swap parameters
     * @return result Slippage result preview
     * @dev Useful for front-end integration to show users expected slippage
     */
    function previewSlippage(SwapParams memory params)
        internal
        view
        returns (SlippageResult memory result)
    {
        return calculateSlippage(params);
    }

    /**
     * @notice Check if slippage config is valid
     * @param config Slippage configuration
     * @return isValid True if config is valid
     */
    function isValidConfig(SlippageConfig memory config)
        internal
        pure
        returns (bool isValid)
    {
        // Check slippage values
        if (config.smallTradeBps > MAX_SLIPPAGE_BPS) return false;
        if (config.mediumTradeBps > MAX_SLIPPAGE_BPS) return false;
        if (config.largeTradeBps > MAX_SLIPPAGE_BPS) return false;
        if (config.whaleTradeBps > MAX_SLIPPAGE_BPS) return false;

        // Check threshold ordering
        if (config.tier1Threshold >= config.tier2Threshold) return false;
        if (config.tier2Threshold >= config.tier3Threshold) return false;

        // Check slippage progression
        if (config.smallTradeBps > config.mediumTradeBps) return false;
        if (config.mediumTradeBps > config.largeTradeBps) return false;
        if (config.largeTradeBps > config.whaleTradeBps) return false;

        return true;
    }
}

// ============================================================================
// USAGE EXAMPLE (For Adapters)
// ============================================================================

/*
// Example: FusionXAdapter with dynamic slippage

import {SlippageProtection} from "../libraries/SlippageProtection.sol";
import {IPriceOracle} from "../interfaces/IPriceOracle.sol";

contract FusionXAdapter {
    using SlippageProtection for SlippageProtection.SwapParams;

    IPriceOracle public priceOracle;
    SlippageProtection.SlippageConfig public slippageConfig;

    constructor(address _priceOracle) {
        priceOracle = IPriceOracle(_priceOracle);
        slippageConfig = SlippageProtection.getModerateConfig();  // Default
    }

    function deposit(uint256 amount) external returns (uint256 shares) {
        // Calculate dynamic slippage
        SlippageProtection.SwapParams memory params = SlippageProtection.SwapParams({
            tokenIn: USDC,
            tokenOut: FUSION_TOKEN,
            amountIn: amount,
            priceOracle: address(priceOracle),
            config: slippageConfig
        });

        SlippageProtection.SlippageResult memory result =
            SlippageProtection.calculateSlippage(params);

        // Execute swap with dynamic minOutput
        uint256 tokensReceived = _swapUSDCToFusion(amount, result.minOutput);

        // Validate output
        SlippageProtection.validateOutput(tokensReceived, result.minOutput);

        // Stake tokens
        shares = _stakeFusionTokens(tokensReceived);

        return shares;
    }
}
*/
