// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/*
 * @status EXPERIMENTAL
 * @network Examples only
 * @used-by Docs + demos
 * @notes Commented example for teams extending V2 adapter hooks.
 */

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IAdapterV2} from "../interfaces/IAdapterV2.sol";

/**
 * @title FusionXAdapterV2Example
 * @notice MEV-resistant adapter for FusionX DEX (AMM swap operations)
 * @dev Implements IAdapterV2 with slippage and deadline protection
 *
 * Integration Pattern:
 * ====================
 * 1. Adapts vault tokens (e.g., USDC) → FusionX LP positions
 * 2. Implements IAdapterV2: deposit/withdraw with (amount, minAmountOut, deadline)
 * 3. Provides quote functions: getExpectedDepositOutput/getExpectedWithdrawOutput
 * 4. Enforces slippage via minAmountOut floor
 * 5. Enforces deadline via block.timestamp check
 *
 * Threat Model:
 * =============
 * Threat: MEV/Sandwich on addLiquidity call
 *   Attack: Attacker manipulates FusionX pool reserves before user's addLiquidity
 *   Defense: minAmountOut prevents unfavorable execution, deadline prevents staleness
 *
 * Threat: Stale quote execution
 *   Attack: Quote from 1 hour ago used on execution, market moved 20%
 *   Defense: deadline + minAmountOut prevent old quotes from executing
 *
 * Threat: MEV back-running on withdraw
 *   Attack: Attacker backruns removeLiquidity, mints new position at low rate
 *   Defense: minAmountOut ensures fair withdrawal, deadline prevents staleness
 *
 * Expected Flow:
 * ==============
 * DEPOSIT:
 *   1. Vault calls: getExpectedDepositOutput(1000 USDC)
 *   2. Adapter: "FusionX shows 500 LP shares expected"
 *   3. Vault calculates: minAmountOut = 500 * 9950 / 10000 = 497.5
 *   4. Vault calls: deposit(1000, 497.5, now+30min)
 *   5. Adapter: addLiquidity(1000 USDC)
 *   6. Adapter: Receives 502 LP (good market)
 *   7. Adapter: Validates 502 >= 497.5 ✓
 *   8. Adapter: Returns 502 LP shares
 *
 * WITHDRAW:
 *   1. Vault calls: getExpectedWithdrawOutput(100 LP)
 *   2. Adapter: "Liquidating 100 LP should give ~1000 USDC"
 *   3. Vault calculates: minAmountOut = 1000 * 9950 / 10000 = 995
 *   4. Vault calls: withdraw(100, 995, now+30min)
 *   5. Adapter: removeLiquidity(100 LP)
 *   6. Adapter: Receives 1002 USDC (good market)
 *   7. Adapter: Validates 1002 >= 995 ✓
 *   8. Adapter: Returns 1002 USDC
 */

contract FusionXAdapterV2Example is IAdapterV2 {
    using SafeERC20 for IERC20;

    // ============ CONSTANTS ============

    uint256 public constant PRICE_PRECISION = 1e18;
    uint256 public constant SLIPPAGE_CHECK_PRECISION = 10000;

    // ============ STATE ============

    IERC20 public immutable asset; // e.g., USDC
    address public immutable fusionXRouter; // FusionX Router address
    address public immutable lpToken; // FusionX LP token

    // Price oracle (simplified - use Chainlink in production)
    mapping(uint256 => uint256) public assetPrice; // timestamp => price
    uint256 public lastPriceUpdate;

    // ============ CUSTOM ERRORS ============

    error DeadlineExpired(uint256 timestamp, uint256 deadline);
    error SlippageExceeded(uint256 actual, uint256 minimum);
    error InvalidAmount(uint256 amount);
    error InvalidDeadline(uint256 deadline);
    error PoolImbalance(uint256 expectedLiquidity, uint256 actualLiquidity);

    // ============ EVENTS ============

    event LiquidityAdded(
        uint256 indexed amountIn,
        uint256 lpTokensReceived,
        uint256 minAmountOut,
        uint256 timestamp
    );

    event LiquidityRemoved(
        uint256 indexed lpTokensBurned,
        uint256 assetReceived,
        uint256 minAmountOut,
        uint256 timestamp
    );

    // ============ INITIALIZATION ============

    /**
     * @notice Initialize FusionX adapter
     * @param _asset Asset token (USDC)
     * @param _fusionXRouter FusionX Router contract
     * @param _lpToken FusionX LP token
     */
    constructor(address _asset, address _fusionXRouter, address _lpToken) {
        require(_asset != address(0), "Invalid asset");
        require(_fusionXRouter != address(0), "Invalid router");
        require(_lpToken != address(0), "Invalid LP token");

        asset = IERC20(_asset);
        fusionXRouter = _fusionXRouter;
        lpToken = _lpToken;
    }

    // ============ DEPOSIT WITH SLIPPAGE PROTECTION ============

    /**
     * @notice Deposit asset and mint LP with MEV protection
     * @param amount Asset amount to deposit
     * @param minAmountOut Minimum LP tokens acceptable (slippage floor)
     * @param deadline Block timestamp deadline
     * @return shares LP tokens received
     *
     * Security Checks:
     * 1. Deadline: block.timestamp <= deadline
     * 2. Slippage: actualLPReceived >= minAmountOut
     * 3. Return validation: shares > 0
     */
    function deposit(uint256 amount, uint256 minAmountOut, uint256 deadline)
        external
        override
        returns (uint256 shares)
    {
        require(amount > 0, "Invalid amount");
        require(minAmountOut > 0, "Invalid minimum");

        // Validate deadline
        if (block.timestamp > deadline) {
            revert DeadlineExpired(block.timestamp, deadline);
        }

        // Get quote from oracle (in production: use Chainlink + Uniswap TWAP)
        uint256 expectedLPTokens = _getExpectedDepositOutput(amount);
        require(expectedLPTokens > 0, "Quote failed");

        // Validate minimum meets slippage tolerance
        if (minAmountOut > expectedLPTokens) {
            revert SlippageExceeded(expectedLPTokens, minAmountOut);
        }

        // Transfer asset from caller
        asset.safeTransferFrom(msg.sender, address(this), amount);

        // Add liquidity to FusionX (simplified - actual implementation depends on FusionX API)
        shares = _addLiquidityToFusionX(amount);

        // Validate output meets minimum (slippage check)
        if (shares < minAmountOut) {
            revert SlippageExceeded(shares, minAmountOut);
        }

        // Validate non-zero return
        require(shares > 0, "Invalid deposit output");

        // Transfer LP tokens to caller
        IERC20(lpToken).safeTransfer(msg.sender, shares); // lpToken is address

        emit LiquidityAdded(amount, shares, minAmountOut, block.timestamp);
    }

    // ============ WITHDRAW WITH SLIPPAGE PROTECTION ============

    /**
     * @notice Burn LP tokens and receive asset with MEV protection
     * @param shareAmount LP tokens to burn
     * @param minAmountOut Minimum asset acceptable (slippage floor)
     * @param deadline Block timestamp deadline
     * @return withdrawn Asset amount received
     *
     * Security Checks:
     * 1. Deadline: block.timestamp <= deadline
     * 2. Slippage: actualAssetReceived >= minAmountOut
     * 3. Return validation: withdrawn > 0
     */
    function withdraw(uint256 shareAmount, uint256 minAmountOut, uint256 deadline)
        external
        override
        returns (uint256 withdrawn)
    {
        require(shareAmount > 0, "Invalid amount");
        require(minAmountOut > 0, "Invalid minimum");

        // Validate deadline
        if (block.timestamp > deadline) {
            revert DeadlineExpired(block.timestamp, deadline);
        }

        // Get quote from oracle
        uint256 expectedAsset = _getExpectedWithdrawOutput(shareAmount);
        require(expectedAsset > 0, "Quote failed");

        // Validate minimum meets slippage tolerance
        if (minAmountOut > expectedAsset) {
            revert SlippageExceeded(expectedAsset, minAmountOut);
        }

        // Transfer LP tokens from caller
        IERC20(lpToken).safeTransferFrom(msg.sender, address(this), shareAmount);

        // Remove liquidity from FusionX
        withdrawn = _removeLiquidityFromFusionX(shareAmount);

        // Validate output meets minimum (slippage check)
        if (withdrawn < minAmountOut) {
            revert SlippageExceeded(withdrawn, minAmountOut);
        }

        // Validate non-zero return
        require(withdrawn > 0, "Invalid withdraw output");

        // Transfer asset to caller
        asset.safeTransfer(msg.sender, withdrawn);

        emit LiquidityRemoved(shareAmount, withdrawn, minAmountOut, block.timestamp);
    }

    // ============ QUERY FUNCTIONS (For Vault Calculations) ============

    /**
     * @notice Get underlying asset token
     */
    function token() external view returns (address) {
        return address(asset);
    }

    /**
     * @notice Get expected LP output for deposit amount (used by vault)
     * @param amountIn Asset amount to deposit
     * @return expectedLPTokens LP tokens expected to receive
     *
     * Used by vault to:
     * 1. Calculate minAmountOut = expectedLPTokens * (10000 - slippageBps) / 10000
     * 2. Pass minAmountOut to deposit(amount, minAmountOut, deadline)
     * 3. Detect if adapter is returning unexpected values
     *
     * Gas Efficiency:
     * - No state changes (view function)
     * - Uses cached price oracle
     * - O(1) calculation
     */
    function getExpectedDepositOutput(uint256 amountIn)
        external
        view
        override
        returns (uint256 expectedLPTokens)
    {
        require(amountIn > 0, "Invalid amount");
        return _getExpectedDepositOutput(amountIn);
    }

    /**
     * @notice Get expected asset output for LP burn (used by vault)
     * @param lpTokensAmount LP tokens to burn
     * @return expectedAsset Asset amount expected to receive
     *
     * Used by vault to:
     * 1. Calculate minAmountOut = expectedAsset * (10000 - slippageBps) / 10000
     * 2. Pass minAmountOut to withdraw(shares, minAmountOut, deadline)
     * 3. Detect if adapter is returning unexpected values
     *
     * Gas Efficiency:
     * - No state changes (view function)
     * - Uses cached price oracle
     * - O(1) calculation
     */
    function getExpectedWithdrawOutput(uint256 lpTokensAmount)
        external
        view
        override
        returns (uint256 expectedAsset)
    {
        require(lpTokensAmount > 0, "Invalid amount");
        return _getExpectedWithdrawOutput(lpTokensAmount);
    }

    // ============ INTERNAL FUNCTIONS ============

    /**
     * @notice Internal quote for expected LP output (simplified)
     * @dev In production: Query FusionX reserves + use TWAP oracle
     */
    function _getExpectedDepositOutput(uint256 amountIn) internal view returns (uint256) {
        // Simplified: assume 1:1 ratio (in production: use pool reserves)
        // actualPrice = FusionXRouter.quote(amountIn, asset, lpToken)
        return amountIn;
    }

    /**
     * @notice Internal quote for expected asset output (simplified)
     * @dev In production: Query FusionX reserves + use TWAP oracle
     */
    function _getExpectedWithdrawOutput(uint256 lpTokenAmount) internal view returns (uint256) {
        // Simplified: assume 1:1 ratio (in production: use pool reserves)
        // actualAsset = FusionXRouter.quote(lpTokenAmount, lpToken, asset)
        return lpTokenAmount;
    }

    /**
     * @notice Add liquidity to FusionX (simplified placeholder)
     * @dev In production: Call FusionXRouter.addLiquidity or addLiquidityETH
     */
    function _addLiquidityToFusionX(uint256 amount) internal returns (uint256) {
        // Placeholder: actual implementation calls FusionXRouter
        // Returns LP tokens received
        return amount; // Simplified 1:1 for example
    }

    /**
     * @notice Remove liquidity from FusionX (simplified placeholder)
     * @dev In production: Call FusionXRouter.removeLiquidity
     */
    function _removeLiquidityFromFusionX(uint256 lpTokenAmount) internal returns (uint256) {
        // Placeholder: actual implementation calls FusionXRouter
        // Returns asset tokens received
        return lpTokenAmount; // Simplified 1:1 for example
    }

    // ============ ORACLE MANAGEMENT ============

    /**
     * @notice Update asset price from oracle (simplified)
     * @param newPrice New price in PRICE_PRECISION units
     * @dev In production: Pull from Chainlink or Uniswap TWAP
     */
    function updatePrice(uint256 newPrice) external {
        require(newPrice > 0, "Invalid price");
        assetPrice[block.timestamp] = newPrice;
        lastPriceUpdate = block.timestamp;
    }

    /**
     * @notice Get latest asset price
     */
    function getLatestPrice() external view returns (uint256) {
        return assetPrice[lastPriceUpdate];
    }
}
