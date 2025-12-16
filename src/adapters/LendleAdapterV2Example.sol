// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IAdapterV2} from "../interfaces/IAdapterV2.sol";

/**
 * @title LendleAdapterV2Example
 * @notice MEV-resistant adapter for Lendle lending protocol
 * @dev Implements IAdapterV2 with slippage and deadline protection
 *
 * Integration Pattern:
 * ====================
 * 1. Adapts vault tokens (e.g., USDC) → Lendle supply positions
 * 2. Implements IAdapterV2: deposit/withdraw with (amount, minAmountOut, deadline)
 * 3. Provides quote functions: getExpectedDepositOutput/getExpectedWithdrawOutput
 * 4. Enforces slippage via minAmountOut floor
 * 5. Enforces deadline via block.timestamp check
 *
 * Threat Model:
 * =============
 * Threat: Oracle rate manipulation (lending rate attack)
 *   Attack: Attacker manipulates Lendle supply/borrow rates
 *   Defense: minAmountOut prevents accepting unfavorable rates, deadline prevents staleness
 *
 * Threat: Stale interest rate quote
 *   Attack: Quote from 1 hour ago when rates were 5%, execution at 2%
 *   Defense: deadline + minAmountOut prevent old quotes from executing
 *
 * Threat: Liquidation cascade on withdraw
 *   Attack: Withdraw during market stress, protocol reduces collateral factor
 *   Defense: minAmountOut ensures minimum withdrawal, deadline prevents staleness
 *
 * Expected Flow (Deposit):
 * =======================
 * 1. Vault calls: getExpectedDepositOutput(1000 USDC)
 * 2. Adapter: "Lendle shows 1050 USDC expected (5% APY accumulated)"
 * 3. Vault calculates: minAmountOut = 1050 * 9950 / 10000 = 1044.75
 * 4. Vault calls: deposit(1000, 1044.75, now+30min)
 * 5. Adapter: supply(1000 USDC) to Lendle
 * 6. Adapter: Receives position for 1000 USDC
 * 7. Adapter: Validates getBalance() = 1000 >= 1044.75? NO - REVERT
 * 8. (This example shows importance of realistic quote vs actual balance)
 *
 * Note: In lending, supplied amount = received amount (1:1)
 * The "slippage" is in form of interest rate changes/slashing risk
 */

contract LendleAdapterV2Example is IAdapterV2 {
    using SafeERC20 for IERC20;

    // ============ CONSTANTS ============

    uint256 public constant PRICE_PRECISION = 1e18;
    uint256 public constant SLIPPAGE_CHECK_PRECISION = 10000;

    // ============ STATE ============

    IERC20 public immutable asset; // e.g., USDC
    address public immutable lendlePool; // Lendle Pool contract
    address public immutable lToken; // Lendle lToken (e.g., lUSDC)

    // Interest rate oracle (simplified)
    uint256 public interestRateBps; // Interest rate in basis points
    uint256 public lastRateUpdate;

    // ============ CUSTOM ERRORS ============

    error DeadlineExpired(uint256 timestamp, uint256 deadline);
    error SlippageExceeded(uint256 actual, uint256 minimum);
    error InvalidAmount(uint256 amount);
    error SupplyFailed(uint256 amount);
    error WithdrawFailed(uint256 amount);

    // ============ EVENTS ============

    event AssetSupplied(
        uint256 indexed amountIn,
        uint256 lTokensReceived,
        uint256 minAmountOut,
        uint256 timestamp
    );

    event AssetWithdrawn(
        uint256 indexed lTokensBurned,
        uint256 assetReceived,
        uint256 minAmountOut,
        uint256 timestamp
    );

    event InterestRateUpdated(uint256 newRateBps, uint256 timestamp);

    // ============ INITIALIZATION ============

    /**
     * @notice Initialize Lendle adapter
     * @param _asset Asset token (USDC)
     * @param _lendlePool Lendle Pool address
     * @param _lToken Lendle lToken address
     */
    constructor(address _asset, address _lendlePool, address _lToken) {
        require(_asset != address(0), "Invalid asset");
        require(_lendlePool != address(0), "Invalid pool");
        require(_lToken != address(0), "Invalid lToken");

        asset = IERC20(_asset);
        lendlePool = _lendlePool;
        lToken = _lToken;

        interestRateBps = 500; // Default 5% APY
    }

    // ============ DEPOSIT WITH SLIPPAGE PROTECTION ============

    /**
     * @notice Supply asset to Lendle with MEV protection
     * @param amount Asset amount to supply
     * @param minAmountOut Minimum lToken acceptable (rate floor)
     * @param deadline Block timestamp deadline
     * @return shares lToken received
     *
     * Security Checks:
     * 1. Deadline: block.timestamp <= deadline
     * 2. Slippage: actualLToken >= minAmountOut
     * 3. Return validation: shares > 0
     *
     * Note: In lending, lToken amount ~= supplied amount (1:1 ratio)
     * minAmountOut protects against interest rate crashes
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

        // Get expected lToken output (same as amount in lending typically)
        uint256 expectedLToken = _getExpectedDepositOutput(amount);
        require(expectedLToken > 0, "Quote failed");

        // Validate minimum meets rate floor
        if (minAmountOut > expectedLToken) {
            revert SlippageExceeded(expectedLToken, minAmountOut);
        }

        // Transfer asset from caller
        asset.safeTransferFrom(msg.sender, address(this), amount);

        // Supply to Lendle pool
        shares = _supplyToLendle(amount);

        // Validate output meets minimum
        if (shares < minAmountOut) {
            revert SlippageExceeded(shares, minAmountOut);
        }

        // Validate non-zero return
        require(shares > 0, "Invalid deposit output");

        // Transfer lToken to caller
        IERC20(lToken).safeTransfer(msg.sender, shares); // lToken is address

        emit AssetSupplied(amount, shares, minAmountOut, block.timestamp);
    }

    // ============ WITHDRAW WITH SLIPPAGE PROTECTION ============

    /**
     * @notice Withdraw from Lendle with MEV protection
     * @param shareAmount lToken to burn
     * @param minAmountOut Minimum asset acceptable (slippage floor)
     * @param deadline Block timestamp deadline
     * @return withdrawn Asset amount received
     *
     * Security Checks:
     * 1. Deadline: block.timestamp <= deadline
     * 2. Slippage: actualAsset >= minAmountOut
     * 3. Return validation: withdrawn > 0
     *
     * Scenario: During market stress, withdrawal might return less if:
     * - Lending protocol has bad debt
     * - Collateral slashed due to oracle issue
     * - Emergency pause activates
     * minAmountOut prevents these bad outcomes from executing
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

        // Get expected asset output
        uint256 expectedAsset = _getExpectedWithdrawOutput(shareAmount);
        require(expectedAsset > 0, "Quote failed");

        // Validate minimum meets floor
        if (minAmountOut > expectedAsset) {
            revert SlippageExceeded(expectedAsset, minAmountOut);
        }

        // Transfer lToken from caller
        IERC20(lToken).safeTransferFrom(msg.sender, address(this), shareAmount);

        // Withdraw from Lendle pool
        withdrawn = _withdrawFromLendle(shareAmount);

        // Validate output meets minimum
        if (withdrawn < minAmountOut) {
            revert SlippageExceeded(withdrawn, minAmountOut);
        }

        // Validate non-zero return
        require(withdrawn > 0, "Invalid withdraw output");

        // Transfer asset to caller
        asset.safeTransfer(msg.sender, withdrawn);

        emit AssetWithdrawn(shareAmount, withdrawn, minAmountOut, block.timestamp);
    }

    // ============ QUOTE FUNCTIONS (For Vault Calculations) ============

    /**
     * @notice Get underlying asset token
     */
    function token() external view returns (address) {
        return address(asset);
    }

    /**
     * @notice Get expected lToken output for supply amount
     * @param amountIn Asset amount to supply
     * @return expectedLToken lToken expected to receive
     *
     * Used by vault to:
     * 1. Calculate minAmountOut = expectedLToken * (10000 - slippageBps) / 10000
     * 2. Pass minAmountOut to deposit(amount, minAmountOut, deadline)
     * 3. Detect adapter issues (lending pool frozen, etc)
     */
    function getExpectedDepositOutput(uint256 amountIn)
        external
        view
        override
        returns (uint256 expectedLToken)
    {
        require(amountIn > 0, "Invalid amount");
        return _getExpectedDepositOutput(amountIn);
    }

    /**
     * @notice Get expected asset output for lToken burn
     * @param lTokenAmount lToken to burn
     * @return expectedAsset Asset expected to receive
     *
     * Used by vault to:
     * 1. Calculate minAmountOut = expectedAsset * (10000 - slippageBps) / 10000
     * 2. Pass minAmountOut to withdraw(shares, minAmountOut, deadline)
     * 3. Detect pool issues (insolvency, emergency state)
     */
    function getExpectedWithdrawOutput(uint256 lTokenAmount)
        external
        view
        override
        returns (uint256 expectedAsset)
    {
        require(lTokenAmount > 0, "Invalid amount");
        return _getExpectedWithdrawOutput(lTokenAmount);
    }

    // ============ INTERNAL FUNCTIONS ============

    /**
     * @notice Internal quote for expected lToken output
     * @dev In lending: lToken amount = supplied amount (1:1 in most cases)
     */
    function _getExpectedDepositOutput(uint256 amountIn) internal view returns (uint256) {
        // Simplified: assume 1:1 ratio
        // In production: query Lendle pool exchange rate
        // rate = lendlePool.getExchangeRate(address(asset))
        // return (amountIn * rate) / PRICE_PRECISION
        return amountIn;
    }

    /**
     * @notice Internal quote for expected asset output
     * @dev In lending: asset amount = lToken amount * exchange rate
     */
    function _getExpectedWithdrawOutput(uint256 lTokenAmount) internal view returns (uint256) {
        // Simplified: assume 1:1 ratio
        // In production: query Lendle pool exchange rate
        // rate = lendlePool.getExchangeRate(address(asset))
        // return (lTokenAmount * rate) / PRICE_PRECISION
        return lTokenAmount;
    }

    /**
     * @notice Supply to Lendle pool (simplified placeholder)
     * @dev In production: Call LendlePool.supply(asset, amount, receiver, referralCode)
     */
    function _supplyToLendle(uint256 amount) internal returns (uint256) {
        // Placeholder: actual implementation calls LendlePool
        // Returns lToken amount (typically equals amount for USDC)
        return amount;
    }

    /**
     * @notice Withdraw from Lendle pool (simplified placeholder)
     * @dev In production: Call LendlePool.withdraw(asset, amount, receiver)
     */
    function _withdrawFromLendle(uint256 lTokenAmount) internal returns (uint256) {
        // Placeholder: actual implementation calls LendlePool
        // Returns asset amount
        return lTokenAmount;
    }

    // ============ INTEREST RATE MANAGEMENT ============

    /**
     * @notice Update interest rate (for testing)
     * @param newRateBps New rate in basis points (100 = 1%)
     */
    function updateInterestRate(uint256 newRateBps) external {
        require(newRateBps > 0, "Invalid rate");
        interestRateBps = newRateBps;
        lastRateUpdate = block.timestamp;
        emit InterestRateUpdated(newRateBps, block.timestamp);
    }

    /**
     * @notice Get current interest rate
     */
    function getCurrentRate() external view returns (uint256) {
        return interestRateBps;
    }
}
