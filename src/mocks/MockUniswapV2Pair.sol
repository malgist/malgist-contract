// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/*
 * @status TEST-ONLY
 * @network Local tests
 * @used-by SlippageProtection + adapter tests
 * @notes Mock pair for AMM simulations.
 */

import {MockERC20} from "./MockERC20.sol";

/**
 * @title MockUniswapV2Pair
 * @notice Mock LP token representing a Uniswap V2 pair
 * @dev Extends MockERC20 to simulate liquidity pool tokens
 */
contract MockUniswapV2Pair is MockERC20 {
    address public token0;
    address public token1;

    uint112 private reserve0;
    uint112 private reserve1;
    uint32 private blockTimestampLast;

    event Mint(address indexed sender, uint256 amount0, uint256 amount1);
    event Burn(address indexed sender, uint256 amount0, uint256 amount1, address indexed to);
    event Sync(uint112 reserve0, uint112 reserve1);

    constructor(address _token0, address _token1, string memory name, string memory symbol)
        MockERC20(name, symbol, 18)
    {
        token0 = _token0;
        token1 = _token1;
    }

    /**
     * @notice Get current reserves
     * @return _reserve0 Reserve of token0
     * @return _reserve1 Reserve of token1
     * @return _blockTimestampLast Last block timestamp
     */
    function getReserves() public view returns (uint112 _reserve0, uint112 _reserve1, uint32 _blockTimestampLast) {
        _reserve0 = reserve0;
        _reserve1 = reserve1;
        _blockTimestampLast = blockTimestampLast;
    }

    /**
     * @notice Mint LP tokens (called by router after liquidity is added)
     * @param to Address to mint LP tokens to
     * @param amount Amount of LP tokens to mint
     */
    function mintLiquidity(address to, uint256 amount) external {
        _mint(to, amount);
        emit Mint(msg.sender, 0, 0); // Simplified - amounts would be calculated in real implementation
    }

    /**
     * @notice Burn LP tokens and return underlying assets
     * @param to Address to send assets to
     * @param amount Amount of LP tokens to burn
     * @return amount0 Amount of token0 returned
     * @return amount1 Amount of token1 returned
     */
    function burnLiquidity(address to, uint256 amount) external returns (uint256 amount0, uint256 amount1) {
        // Burn LP tokens from this contract (they were transferred here by router)
        _burn(address(this), amount);

        // For testing, assume 1:1 return of what was deposited
        // In real implementation, this would be based on reserves
        amount0 = amount / 2;
        amount1 = amount / 2;

        emit Burn(msg.sender, amount0, amount1, to);
        return (amount0, amount1);
    }

    /**
     * @notice Update reserves (for testing)
     */
    function sync(uint112 _reserve0, uint112 _reserve1) external {
        reserve0 = _reserve0;
        reserve1 = _reserve1;
        blockTimestampLast = uint32(block.timestamp);
        emit Sync(reserve0, reserve1);
    }
}
