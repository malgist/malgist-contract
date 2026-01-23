// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/*
 * @status EXPERIMENTAL
 * @network Labs only
 * @used-by Adapter research
 * @notes Pending upgrade path for FusionX kept off-chain.
 */

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

    function getAmountsIn(uint256 amountOut, address[] calldata path) external view returns (uint256[] memory amounts);
}

/**
 * @title IUniswapV2Pair
 * @notice Interface for Uniswap V2 Pair to get reserves
 */
interface IUniswapV2Pair is IERC20 {
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);

    function token0() external view returns (address);

    function token1() external view returns (address);
}

/**
 * @title FusionXAdapterV2
 * @notice Production-grade FusionX DEX adapter with slippage protection
 * @dev Single-sided USDC deposit → optimal swap → liquidity provision with configurable slippage
 */
contract FusionXAdapterV2 is IAdapter {
    using SafeERC20 for IERC20;

    // ============ STATE VARIABLES ============

    /// @notice The base token for deposits/withdrawals (e.g., USDC)
    IERC20 private immutable _TOKEN_A;

    /// @notice The paired token (e.g., MNT/WMNT)
    IERC20 private immutable _TOKEN_B;

    /// @notice The LP token representing liquidity position
    IUniswapV2Pair private immutable _LP_TOKEN;

    /// @notice The Uniswap V2 style router
    IUniswapV2Router private immutable _ROUTER;

    /// @notice The vault address that owns this adapter
    address private immutable _VAULT;

    /// @notice Default slippage tolerance in basis points (50 = 0.5%)
    uint16 private constant DEFAULT_SLIPPAGE_BPS = 50;

    /// @notice Basis points constant
    uint16 private constant TOTAL_BPS = 10000;

    /// @notice Swap deadline offset (5 minutes)
    uint256 private constant SWAP_DEADLINE_OFFSET = 5 minutes;

    // ============ EVENTS ============

    event LiquidityAdded(
        uint256 indexed timestamp, uint256 amountA, uint256 amountB, uint256 liquidity, uint256 slippageTolerance
    );

    event LiquidityRemoved(uint256 indexed timestamp, uint256 liquidity, uint256 amountA, uint256 amountB);

    event TokensSwapped(
        address indexed tokenIn,
        address indexed tokenOut,
        uint256 amountIn,
        uint256 amountOut,
        uint256 minAmountOut,
        uint256 slippageTolerance
    );

    event SlippageExceeded(address indexed caller, uint256 amountOut, uint256 minAmountOut, uint256 timestamp);

    // ============ ERRORS ============

    error OnlyVault();
    error InvalidAmount();
    error InvalidSlippage();
    error SlippageExceededError();
    error LiquidityAdditionFailed();
    error LiquidityRemovalFailed();
    error SwapFailed();
    error DeadlineExpired();
    error InsufficientLiquidity();
    error ZeroAddress();

    // ============ MODIFIERS ============

    modifier onlyVault() {
        if (msg.sender != _VAULT) revert OnlyVault();
        _;
    }

    modifier validSlippage(uint16 slippage) {
        if (slippage > 1000) revert InvalidSlippage(); // Max 10%
        _;
    }

    // ============ CONSTRUCTOR ============

    /**
     * @notice Constructor
     * @param tokenA The base token (e.g., USDC)
     * @param tokenB The paired token (e.g., WMNT)
     * @param lpToken The LP token address
     * @param router The DEX router address
     * @param vault The vault address that owns this adapter
     */
    constructor(address tokenA, address tokenB, address lpToken, address router, address vault) {
        if (tokenA == address(0) || tokenB == address(0) || lpToken == address(0) || router == address(0)
            || vault == address(0)) {
            revert ZeroAddress();
        }

        _TOKEN_A = IERC20(tokenA);
        _TOKEN_B = IERC20(tokenB);
        _LP_TOKEN = IUniswapV2Pair(lpToken);
        _ROUTER = IUniswapV2Router(router);
        _VAULT = vault;
    }

    // ============ CORE ADAPTER FUNCTIONS ============

    /**
     * @notice Deposit single-sided USDC and provide liquidity with slippage protection
     * @param amount Amount of base token (USDC) to deposit
     * @return shares Amount of LP tokens received
     * @dev Uses default slippage of 50 bps (0.5%)
     */
    function deposit(uint256 amount) external onlyVault returns (uint256 shares) {
        return depositWithSlippage(amount, DEFAULT_SLIPPAGE_BPS);
    }

    /**
     * @notice Deposit single-sided USDC with custom slippage tolerance
     * @param amount Amount of base token (USDC) to deposit
     * @param slippageBps Maximum acceptable slippage in basis points
     * @return lpTokens Amount of LP tokens received
     */
    function depositWithSlippage(uint256 amount, uint16 slippageBps) public onlyVault validSlippage(slippageBps) returns (uint256 lpTokens) {
        if (amount == 0) revert InvalidAmount();

        // Step 1: Calculate optimal swap amount (50% of deposit)
        uint256 swapAmount = amount / 2;
        uint256 liquidityAmount = amount - swapAmount;

        // Step 2: Swap USDC to TOKEN_B with slippage protection
        uint256 tokenBAmount = _performSwap(_TOKEN_A, _TOKEN_B, swapAmount, slippageBps);

        // Step 3: Add liquidity with slippage protection
        lpTokens = _addLiquidityWithSlippage(liquidityAmount, tokenBAmount, slippageBps);

        emit LiquidityAdded(block.timestamp, liquidityAmount, tokenBAmount, lpTokens, slippageBps);
        return lpTokens;
    }

    /**
     * @notice Withdraw liquidity and return USDC with slippage protection
     * @param lpAmount Amount of LP tokens to burn
     * @return withdrawn Amount of USDC returned to user
     * @dev Uses default slippage of 50 bps (0.5%)
     */
    function withdraw(uint256 lpAmount) external onlyVault returns (uint256 withdrawn) {
        return withdrawWithSlippage(lpAmount, DEFAULT_SLIPPAGE_BPS);
    }

    /**
     * @notice Withdraw liquidity with custom slippage tolerance
     * @param lpAmount Amount of LP tokens to burn
     * @param slippageBps Maximum acceptable slippage in basis points
     * @return usdcOut Amount of USDC returned
     */
    function withdrawWithSlippage(uint256 lpAmount, uint16 slippageBps)
        public
        onlyVault
        validSlippage(slippageBps)
        returns (uint256 usdcOut)
    {
        if (lpAmount == 0) revert InvalidAmount();

        // Step 1: Remove liquidity with slippage protection
        (uint256 tokenAAmount, uint256 tokenBAmount) = _removeLiquidityWithSlippage(lpAmount, slippageBps);

        // Step 2: Swap TOKEN_B back to USDC with slippage protection
        uint256 swappedUsdc = _performSwap(_TOKEN_B, _TOKEN_A, tokenBAmount, slippageBps);

        // Step 3: Return total USDC (original + swapped)
        usdcOut = tokenAAmount + swappedUsdc;

        emit LiquidityRemoved(block.timestamp, lpAmount, tokenAAmount, tokenBAmount);
        return usdcOut;
    }

    /**
     * @notice Get current balance in LP tokens
     * @return balance Current LP token balance of this adapter
     */
    function getBalance() external view returns (uint256 balance) {
        return _LP_TOKEN.balanceOf(address(this));
    }

    /**
     * @notice Get underlying token address
     * @return tokenAddress Address of USDC
     */
    function token() external view returns (address tokenAddress) {
        return address(_TOKEN_A);
    }

    // ============ INTERNAL SLIPPAGE-PROTECTED FUNCTIONS ============

    /**
     * @notice Perform swap with strict slippage enforcement
     * @param tokenIn Input token
     * @param tokenOut Output token
     * @param amountIn Amount to swap
     * @param slippageBps Slippage tolerance in basis points
     * @return amountOut Actual amount received
     */
    function _performSwap(IERC20 tokenIn, IERC20 tokenOut, uint256 amountIn, uint16 slippageBps)
        internal
        returns (uint256 amountOut)
    {
        if (amountIn == 0) return 0;

        // Get expected output amount
        address[] memory path = new address[](2);
        path[0] = address(tokenIn);
        path[1] = address(tokenOut);

        uint256[] memory amounts = _ROUTER.getAmountsOut(amountIn, path);
        uint256 expectedAmount = amounts[1];

        // Calculate minimum acceptable amount with slippage
        uint256 minAmount = (expectedAmount * (TOTAL_BPS - slippageBps)) / TOTAL_BPS;

        // Approve and perform swap
        tokenIn.forceApprove(address(_ROUTER), amountIn);

        uint256[] memory swapResults =
            _ROUTER.swapExactTokensForTokens(amountIn, minAmount, path, address(this), block.timestamp + SWAP_DEADLINE_OFFSET);

        amountOut = swapResults[swapResults.length - 1];

        if (amountOut < minAmount) {
            revert SlippageExceededError();
        }

        emit TokensSwapped(address(tokenIn), address(tokenOut), amountIn, amountOut, minAmount, slippageBps);

        return amountOut;
    }

    /**
     * @notice Add liquidity with slippage protection
     * @param amountA Amount of TOKEN_A
     * @param amountB Amount of TOKEN_B
     * @param slippageBps Slippage tolerance
     * @return liquidity LP tokens received
     */
    function _addLiquidityWithSlippage(uint256 amountA, uint256 amountB, uint16 slippageBps)
        internal
        returns (uint256 liquidity)
    {
        if (amountA == 0 || amountB == 0) revert InvalidAmount();

        // Calculate minimum amounts with slippage
        uint256 minAmountA = (amountA * (TOTAL_BPS - slippageBps)) / TOTAL_BPS;
        uint256 minAmountB = (amountB * (TOTAL_BPS - slippageBps)) / TOTAL_BPS;

        // Approve tokens
        _TOKEN_A.forceApprove(address(_ROUTER), amountA);
        _TOKEN_B.forceApprove(address(_ROUTER), amountB);

        (uint256 addedA, uint256 addedB, uint256 lpTokens) = _ROUTER.addLiquidity(
            address(_TOKEN_A),
            address(_TOKEN_B),
            amountA,
            amountB,
            minAmountA,
            minAmountB,
            address(this),
            block.timestamp + SWAP_DEADLINE_OFFSET
        );

        if (lpTokens == 0) revert LiquidityAdditionFailed();

        // Clear approvals
        _TOKEN_A.forceApprove(address(_ROUTER), 0);
        _TOKEN_B.forceApprove(address(_ROUTER), 0);

        return lpTokens;
    }

    /**
     * @notice Remove liquidity with slippage protection
     * @param lpAmount LP tokens to burn
     * @param slippageBps Slippage tolerance
     * @return amountA Amount of TOKEN_A received
     * @return amountB Amount of TOKEN_B received
     */
    function _removeLiquidityWithSlippage(uint256 lpAmount, uint16 slippageBps)
        internal
        returns (uint256 amountA, uint256 amountB)
    {
        if (lpAmount == 0) revert InvalidAmount();

        // Get current reserves to estimate amounts
        (uint112 reserve0, uint112 reserve1,) = _LP_TOKEN.getReserves();

        // Calculate proportional amounts
        uint256 totalSupply = _LP_TOKEN.totalSupply();
        uint256 estimatedA = (uint256(reserve0) * lpAmount) / totalSupply;
        uint256 estimatedB = (uint256(reserve1) * lpAmount) / totalSupply;

        // Calculate minimum amounts with slippage
        uint256 minAmountA = (estimatedA * (TOTAL_BPS - slippageBps)) / TOTAL_BPS;
        uint256 minAmountB = (estimatedB * (TOTAL_BPS - slippageBps)) / TOTAL_BPS;

        // Approve and remove liquidity
        _LP_TOKEN.approve(address(_ROUTER), lpAmount);

        (amountA, amountB) = _ROUTER.removeLiquidity(
            address(_TOKEN_A), address(_TOKEN_B), lpAmount, minAmountA, minAmountB, address(this), block.timestamp + SWAP_DEADLINE_OFFSET
        );

        if (amountA < minAmountA || amountB < minAmountB) {
            revert SlippageExceededError();
        }

        return (amountA, amountB);
    }

    // ============ VIEW FUNCTIONS ============

    /**
     * @notice Estimate deposit output with slippage
     * @param amount Amount of USDC to deposit
     * @param slippageBps Slippage tolerance
     * @return expectedLpTokens Expected LP tokens received
     * @return minLpTokens Minimum LP tokens guaranteed
     */
    function estimateDeposit(uint256 amount, uint16 slippageBps)
        external
        view
        validSlippage(slippageBps)
        returns (uint256 expectedLpTokens, uint256 minLpTokens)
    {
        if (amount == 0) revert InvalidAmount();

        uint256 swapAmount = amount / 2;
        uint256 liquidityAmount = amount - swapAmount;

        // Estimate swap output
        address[] memory path = new address[](2);
        path[0] = address(_TOKEN_A);
        path[1] = address(_TOKEN_B);

        uint256[] memory amounts = _ROUTER.getAmountsOut(swapAmount, path);
        uint256 tokenBAmount = amounts[1];

        // Estimate LP tokens (simplified - actual calculation depends on reserves)
        // This is an approximation
        (uint112 reserve0, uint112 reserve1,) = _LP_TOKEN.getReserves();
        uint256 totalSupply = _LP_TOKEN.totalSupply();

        // Expected LP = min(amountA / (reserve0 / totalSupply), amountB / (reserve1 / totalSupply))
        uint256 lp0 = (liquidityAmount * totalSupply) / uint256(reserve0);
        uint256 lp1 = (tokenBAmount * totalSupply) / uint256(reserve1);
        expectedLpTokens = lp0 < lp1 ? lp0 : lp1;

        // Apply slippage
        minLpTokens = (expectedLpTokens * (TOTAL_BPS - slippageBps)) / TOTAL_BPS;

        return (expectedLpTokens, minLpTokens);
    }

    /**
     * @notice Estimate withdrawal output with slippage
     * @param lpAmount LP tokens to withdraw
     * @param slippageBps Slippage tolerance
     * @return expectedUsdc Expected USDC output
     * @return minUsdc Minimum USDC guaranteed
     */
    function estimateWithdrawal(uint256 lpAmount, uint16 slippageBps)
        external
        view
        validSlippage(slippageBps)
        returns (uint256 expectedUsdc, uint256 minUsdc)
    {
        if (lpAmount == 0) revert InvalidAmount();

        (uint112 reserve0, uint112 reserve1,) = _LP_TOKEN.getReserves();
        uint256 totalSupply = _LP_TOKEN.totalSupply();

        // Calculate TOKEN_A and TOKEN_B amounts
        uint256 amountA = (uint256(reserve0) * lpAmount) / totalSupply;
        uint256 amountB = (uint256(reserve1) * lpAmount) / totalSupply;

        // Estimate swap of TOKEN_B to USDC
        address[] memory path = new address[](2);
        path[0] = address(_TOKEN_B);
        path[1] = address(_TOKEN_A);

        uint256[] memory amounts = _ROUTER.getAmountsOut(amountB, path);
        uint256 swappedUsdc = amounts[1];

        expectedUsdc = amountA + swappedUsdc;
        minUsdc = (expectedUsdc * (TOTAL_BPS - slippageBps)) / TOTAL_BPS;

        return (expectedUsdc, minUsdc);
    }

    /**
     * @notice Get current LP token reserves
     * @return reserve0 Reserve of TOKEN_A
     * @return reserve1 Reserve of TOKEN_B
     */
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1) {
        (reserve0, reserve1,) = _LP_TOKEN.getReserves();
    }
}
