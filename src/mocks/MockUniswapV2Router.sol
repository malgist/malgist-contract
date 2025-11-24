// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {MockERC20} from "./MockERC20.sol";
import {MockUniswapV2Pair} from "./MockUniswapV2Pair.sol";

/**
 * @title MockUniswapV2Router
 * @notice Mock implementation of Uniswap V2 Router for testing
 * @dev Simplified swap and liquidity logic - does not implement full xy=k
 */
contract MockUniswapV2Router {
    using SafeERC20 for IERC20;

    /// @notice Mapping of token pairs to their LP token addresses
    mapping(address => mapping(address => address)) public getPair;

    event PairCreated(address indexed token0, address indexed token1, address pair);
    event LiquidityAdded(
        address indexed tokenA, address indexed tokenB, uint256 amountA, uint256 amountB, uint256 liquidity
    );
    event LiquidityRemoved(
        address indexed tokenA, address indexed tokenB, uint256 liquidity, uint256 amountA, uint256 amountB
    );
    event Swap(address indexed tokenIn, address indexed tokenOut, uint256 amountIn, uint256 amountOut);

    /**
     * @notice Create a pair (admin sets the pair address)
     */
    function createPair(address tokenA, address tokenB, address pair) external {
        require(tokenA != tokenB, "Identical addresses");
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(getPair[token0][token1] == address(0), "Pair exists");

        getPair[token0][token1] = pair;
        getPair[token1][token0] = pair; // Bidirectional mapping

        emit PairCreated(token0, token1, pair);
    }

    /**
     * @notice Swap exact tokens for tokens (simplified 1:1 ratio for testing)
     * @param amountIn Amount of input tokens
     * @param amountOutMin Minimum amount of output tokens
     * @param path Array of token addresses representing swap path
     * @param to Address to receive output tokens
     * @param deadline Transaction deadline
     * @return amounts Array of amounts for each step in the path
     */
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts) {
        require(deadline >= block.timestamp, "Expired");
        require(path.length >= 2, "Invalid path");

        amounts = new uint256[](path.length);
        amounts[0] = amountIn;

        // Simplified: 1:1 swap ratio for testing
        for (uint256 i = 0; i < path.length - 1; i++) {
            amounts[i + 1] = amounts[i]; // 1:1 ratio
        }

        require(amounts[amounts.length - 1] >= amountOutMin, "Insufficient output");

        // Transfer input token from sender
        IERC20(path[0]).safeTransferFrom(msg.sender, address(this), amountIn);

        // "Burn" input (just hold it for simplicity)
        // Mint output token to recipient
        MockERC20(path[path.length - 1]).mint(to, amounts[amounts.length - 1]);

        emit Swap(path[0], path[path.length - 1], amountIn, amounts[amounts.length - 1]);

        return amounts;
    }

    /**
     * @notice Add liquidity to a pool
     * @param tokenA First token address
     * @param tokenB Second token address
     * @param amountADesired Desired amount of tokenA
     * @param amountBDesired Desired amount of tokenB
     * @param amountAMin Minimum amount of tokenA
     * @param amountBMin Minimum amount of tokenB
     * @param to Address to receive LP tokens
     * @param deadline Transaction deadline
     * @return amountA Actual amount of tokenA added
     * @return amountB Actual amount of tokenB added
     * @return liquidity Amount of LP tokens minted
     */
    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountA, uint256 amountB, uint256 liquidity) {
        require(deadline >= block.timestamp, "Expired");
        require(amountADesired >= amountAMin && amountBDesired >= amountBMin, "Insufficient amounts");

        // Get pair address
        address pair = getPair[tokenA][tokenB];
        require(pair != address(0), "Pair does not exist");

        // Transfer tokens from sender
        IERC20(tokenA).safeTransferFrom(msg.sender, address(this), amountADesired);
        IERC20(tokenB).safeTransferFrom(msg.sender, address(this), amountBDesired);

        // Calculate liquidity (simplified)
        liquidity = amountADesired + amountBDesired;

        // Mint LP tokens
        MockUniswapV2Pair(pair).mintLiquidity(to, liquidity);

        emit LiquidityAdded(tokenA, tokenB, amountADesired, amountBDesired, liquidity);

        return (amountADesired, amountBDesired, liquidity);
    }

    /**
     * @notice Remove liquidity from a pool
     * @param tokenA First token address
     * @param tokenB Second token address
     * @param liquidity Amount of LP tokens to burn
     * @param amountAMin Minimum amount of tokenA to receive
     * @param amountBMin Minimum amount of tokenB to receive
     * @param to Address to receive underlying tokens
     * @param deadline Transaction deadline
     * @return amountA Amount of tokenA received
     * @return amountB Amount of tokenB received
     */
    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountA, uint256 amountB) {
        require(deadline >= block.timestamp, "Expired");

        // Get pair
        address pair = getPair[tokenA][tokenB];
        require(pair != address(0), "Pair does not exist");

        // Transfer LP tokens to pair
        IERC20(pair).safeTransferFrom(msg.sender, pair, liquidity);

        // Burn LP tokens
        (amountA, amountB) = MockUniswapV2Pair(pair).burnLiquidity(address(this), liquidity);
        require(amountA >= amountAMin && amountB >= amountBMin, "Insufficient output");

        // Mint underlying tokens to recipient
        MockERC20(tokenA).mint(to, amountA);
        MockERC20(tokenB).mint(to, amountB);

        emit LiquidityRemoved(tokenA, tokenB, liquidity, amountA, amountB);

        return (amountA, amountB);
    }

    /**
     * @notice Get output amounts for a given input (simplified 1:1 for testing)
     * @param amountIn Input amount
     * @param path Token swap path
     * @return amounts Output amounts for each step
     */
    function getAmountsOut(uint256 amountIn, address[] calldata path) external pure returns (uint256[] memory amounts) {
        require(path.length >= 2, "Invalid path");
        amounts = new uint256[](path.length);
        amounts[0] = amountIn;

        // Simplified: 1:1 ratio
        for (uint256 i = 0; i < path.length - 1; i++) {
            amounts[i + 1] = amounts[i];
        }

        return amounts;
    }

    /**
     * @notice Quote liquidity amounts (simplified)
     */
    function quote(uint256 amountA, uint256 reserveA, uint256 reserveB) external pure returns (uint256 amountB) {
        require(amountA > 0, "Insufficient amount");
        require(reserveA > 0 && reserveB > 0, "Insufficient liquidity");

        // Simplified: maintain ratio
        amountB = (amountA * reserveB) / reserveA;
    }
}
