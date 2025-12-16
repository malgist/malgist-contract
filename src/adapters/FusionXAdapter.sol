// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IAdapter} from "../interfaces/IAdapter.sol";

/**
 * @title IUniswapV2Router
 * @notice Minimal interface for Uniswap V2 Router
 */
interface IUniswapV2Router {
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);

    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountA, uint256 amountB, uint256 liquidity);

    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountA, uint256 amountB);

    function getAmountsOut(uint256 amountIn, address[] calldata path) external view returns (uint256[] memory amounts);
}

/**
 * @title FusionXAdapter
 * @notice Zap adapter for FusionX DEX on Mantle Network
 * @dev Takes single-sided deposits (USDC) and provides liquidity to USDC/MNT pair
 *
 * Flow:
 * - Deposit: USDC → 50% swap to MNT → Add liquidity → Hold LP tokens
 * - Withdraw: Remove liquidity → Swap MNT to USDC → Return total USDC
 */
contract FusionXAdapter is IAdapter {
    using SafeERC20 for IERC20;

    /// @notice The base token for deposits/withdrawals (e.g., USDC)
    IERC20 public immutable TOKEN_A;

    /// @notice The paired token (e.g., MNT)
    IERC20 public immutable TOKEN_B;

    /// @notice The LP token representing liquidity position
    IERC20 public immutable LP_TOKEN;

    /// @notice The Uniswap V2 style router
    IUniswapV2Router public immutable ROUTER;

    /// @notice The vault address that owns this adapter
    address public immutable VAULT;

    /// @notice Slippage tolerance in basis points (e.g., 50 = 0.5%)
    uint16 public constant SLIPPAGE_BPS = 50;

    /// @notice Basis points constant
    uint16 public constant TOTAL_BPS = 10000;

    /// @notice Emitted when liquidity is added
    event LiquidityAdded(uint256 amountA, uint256 amountB, uint256 liquidity);

    /// @notice Emitted when liquidity is removed
    event LiquidityRemoved(uint256 liquidity, uint256 amountA, uint256 amountB);

    /// @notice Emitted when tokens are swapped
    event TokensSwapped(address indexed tokenIn, address indexed tokenOut, uint256 amountIn, uint256 amountOut);

    /// @dev Errors
    error OnlyVault();
    error InvalidAmount();
    error SlippageExceeded();

    modifier onlyVault() {
        if (msg.sender != VAULT) revert OnlyVault();
        _;
    }

    /**
     * @notice Constructor
     * @param tokenA The base token (e.g., USDC)
     * @param tokenB The paired token (e.g., MNT)
     * @param lpToken The LP token address
     * @param router The Uniswap V2 router address
     * @param vault The UniversalVault address
     */
    constructor(address tokenA, address tokenB, address lpToken, address router, address vault) {
        TOKEN_A = IERC20(tokenA);
        TOKEN_B = IERC20(tokenB);
        LP_TOKEN = IERC20(lpToken);
        ROUTER = IUniswapV2Router(router);
        VAULT = vault;
    }

    /**
     * @notice Deposit tokenA and zap into LP position
     * @dev Swaps 50% of tokenA to tokenB, then adds liquidity
     * @param amount Amount of tokenA to deposit
     * @return shares LP tokens received (represents position value)
     */
    function deposit(uint256 amount) external onlyVault returns (uint256 shares) {
        if (amount == 0) revert InvalidAmount();

        // Transfer tokenA from vault
        TOKEN_A.safeTransferFrom(msg.sender, address(this), amount);

        // Step 1: Swap 50% of tokenA for tokenB
        uint256 amountToSwap = amount / 2;
        uint256 amountRemaining = amount - amountToSwap;

        uint256 amountBReceived = _swapAForB(amountToSwap);

        // Step 2: Add liquidity with both tokens
        uint256 liquidity = _addLiquidity(amountRemaining, amountBReceived);

        emit LiquidityAdded(amountRemaining, amountBReceived, liquidity);

        return liquidity;
    }

    /**
     * @notice Withdraw by removing liquidity and converting everything to tokenA
     * @param amount Amount of LP tokens to burn
     * @return withdrawn Amount of tokenA returned to vault
     */
    function withdraw(uint256 amount) external onlyVault returns (uint256 withdrawn) {
        if (amount == 0) revert InvalidAmount();

        uint256 lpBalance = LP_TOKEN.balanceOf(address(this));
        if (amount > lpBalance) revert InvalidAmount();

        // Step 1: Remove liquidity to get back tokenA and tokenB
        (uint256 amountA, uint256 amountB) = _removeLiquidity(amount);

        emit LiquidityRemoved(amount, amountA, amountB);

        // Step 2: Swap all tokenB back to tokenA
        uint256 amountAFromSwap = _swapBForA(amountB);

        // Step 3: Calculate total tokenA to return
        withdrawn = amountA + amountAFromSwap;

        // Transfer all tokenA to vault
        TOKEN_A.safeTransfer(VAULT, withdrawn);

        return withdrawn;
    }

    /**
     * @notice Get current balance of LP tokens
     * @return balance LP token balance
     */
    function getBalance() external view returns (uint256 balance) {
        return LP_TOKEN.balanceOf(address(this));
    }

    /**
     * @notice Get the underlying token address
     * @return tokenAddress The base token (tokenA)
     */
    function token() external view returns (address tokenAddress) {
        return address(TOKEN_A);
    }

    /**
     * @notice Internal function to swap tokenA for tokenB
     * @param amountIn Amount of tokenA to swap
     * @return amountOut Amount of tokenB received
     */
    function _swapAForB(uint256 amountIn) internal returns (uint256 amountOut) {
        address[] memory path = new address[](2);
        path[0] = address(TOKEN_A);
        path[1] = address(TOKEN_B);

        // Calculate minimum output with slippage
        uint256[] memory amountsOut = ROUTER.getAmountsOut(amountIn, path);
        uint256 minAmountOut = (amountsOut[1] * (TOTAL_BPS - SLIPPAGE_BPS)) / TOTAL_BPS;

        // Approve router
        TOKEN_A.forceApprove(address(ROUTER), amountIn);

        // Execute swap
        uint256[] memory amounts =
            ROUTER.swapExactTokensForTokens(amountIn, minAmountOut, path, address(this), block.timestamp);

        amountOut = amounts[1];

        // Reset approval
        TOKEN_A.forceApprove(address(ROUTER), 0);

        emit TokensSwapped(address(TOKEN_A), address(TOKEN_B), amountIn, amountOut);

        return amountOut;
    }

    /**
     * @notice Internal function to swap tokenB for tokenA
     * @param amountIn Amount of tokenB to swap
     * @return amountOut Amount of tokenA received
     */
    function _swapBForA(uint256 amountIn) internal returns (uint256 amountOut) {
        if (amountIn == 0) return 0;

        address[] memory path = new address[](2);
        path[0] = address(TOKEN_B);
        path[1] = address(TOKEN_A);

        // Calculate minimum output with slippage
        uint256[] memory amountsOut = ROUTER.getAmountsOut(amountIn, path);
        uint256 minAmountOut = (amountsOut[1] * (TOTAL_BPS - SLIPPAGE_BPS)) / TOTAL_BPS;

        // Approve router
        TOKEN_B.forceApprove(address(ROUTER), amountIn);

        // Execute swap
        uint256[] memory amounts =
            ROUTER.swapExactTokensForTokens(amountIn, minAmountOut, path, address(this), block.timestamp);

        amountOut = amounts[1];

        // Reset approval
        TOKEN_B.forceApprove(address(ROUTER), 0);

        emit TokensSwapped(address(TOKEN_B), address(TOKEN_A), amountIn, amountOut);

        return amountOut;
    }

    /**
     * @notice Internal function to add liquidity
     * @param amountA Amount of tokenA
     * @param amountB Amount of tokenB
     * @return liquidity LP tokens received
     */
    function _addLiquidity(uint256 amountA, uint256 amountB) internal returns (uint256 liquidity) {
        // Calculate minimum amounts with slippage
        uint256 amountAMin = (amountA * (TOTAL_BPS - SLIPPAGE_BPS)) / TOTAL_BPS;
        uint256 amountBMin = (amountB * (TOTAL_BPS - SLIPPAGE_BPS)) / TOTAL_BPS;

        // Approve router for both tokens
        TOKEN_A.forceApprove(address(ROUTER), amountA);
        TOKEN_B.forceApprove(address(ROUTER), amountB);

        // Add liquidity
        (,, liquidity) = ROUTER.addLiquidity(
            address(TOKEN_A),
            address(TOKEN_B),
            amountA,
            amountB,
            amountAMin,
            amountBMin,
            address(this), // LP tokens go to this adapter
            block.timestamp
        );

        // Reset approvals
        TOKEN_A.forceApprove(address(ROUTER), 0);
        TOKEN_B.forceApprove(address(ROUTER), 0);

        return liquidity;
    }

    /**
     * @notice Internal function to remove liquidity
     * @param liquidity Amount of LP tokens to burn
     * @return amountA Amount of tokenA received
     * @return amountB Amount of tokenB received
     */
    function _removeLiquidity(uint256 liquidity) internal returns (uint256 amountA, uint256 amountB) {
        // Approve router to spend LP tokens
        LP_TOKEN.forceApprove(address(ROUTER), liquidity);

        // Remove liquidity (set min amounts to 0 for simplicity in testing)
        (amountA, amountB) = ROUTER.removeLiquidity(
            address(TOKEN_A),
            address(TOKEN_B),
            liquidity,
            0, // amountAMin - could calculate with slippage
            0, // amountBMin - could calculate with slippage
            address(this),
            block.timestamp
        );

        // Reset approval
        LP_TOKEN.forceApprove(address(ROUTER), 0);

        return (amountA, amountB);
    }

    /**
     * @notice Get the LP token address
     */
    function getLPToken() external view returns (address) {
        return address(LP_TOKEN);
    }

    /**
     * @notice Get the paired token address
     */
    function getTokenB() external view returns (address) {
        return address(TOKEN_B);
    }

    /**
     * @notice Get the router address
     */
    function getRouter() external view returns (address) {
        return address(ROUTER);
    }
}
