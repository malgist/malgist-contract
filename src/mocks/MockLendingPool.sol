// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {MockERC20} from "./MockERC20.sol";

/**
 * @title MockLendingPool
 * @notice Mock implementation of Aave V3 / Lendle lending pool for testing
 * @dev Mimics the supply/withdraw interface with aToken mechanics
 */
contract MockLendingPool {
    using SafeERC20 for IERC20;

    /// @notice Mapping from underlying asset to its corresponding aToken
    mapping(address => address) public reserveTokens;

    /// @notice Emitted when a reserve token mapping is set
    event ReserveTokenSet(address indexed asset, address indexed aToken);

    /// @notice Emitted when tokens are supplied
    event Supply(address indexed asset, address indexed user, address indexed onBehalfOf, uint256 amount);

    /// @notice Emitted when tokens are withdrawn
    event Withdraw(address indexed asset, address indexed user, address indexed to, uint256 amount);

    /**
     * @notice Set the aToken address for a given reserve asset
     * @dev Admin function - in production this would be access controlled
     * @param asset The underlying asset address (e.g., USDC)
     * @param aToken The corresponding aToken address (e.g., aUSDC)
     */
    function setReserveToken(address asset, address aToken) external {
        reserveTokens[asset] = aToken;
        emit ReserveTokenSet(asset, aToken);
    }

    /**
     * @notice Supply assets to the lending pool and receive aTokens
     * @param asset The address of the underlying asset to supply
     * @param amount The amount to be supplied
     * @param onBehalfOf The address that will receive the aTokens
     * @param referralCode Code used to register the integrator (unused in mock)
     */
    function supply(address asset, uint256 amount, address onBehalfOf, uint16 referralCode) external {
        require(amount > 0, "Amount must be greater than 0");
        address aToken = reserveTokens[asset];
        require(aToken != address(0), "Reserve not initialized");

        // Transfer underlying asset from user to pool
        IERC20(asset).safeTransferFrom(msg.sender, address(this), amount);

        // Mint equivalent aTokens to onBehalfOf
        MockERC20(aToken).mint(onBehalfOf, amount);

        emit Supply(asset, msg.sender, onBehalfOf, amount);
    }

    /**
     * @notice Withdraw assets from the lending pool
     * @param asset The address of the underlying asset to withdraw
     * @param amount The amount to be withdrawn (type(uint256).max for max)
     * @param to The address that will receive the underlying asset
     * @return The final amount withdrawn
     */
    function withdraw(address asset, uint256 amount, address to) external returns (uint256) {
        address aToken = reserveTokens[asset];
        require(aToken != address(0), "Reserve not initialized");

        // Get user's aToken balance
        uint256 userBalance = IERC20(aToken).balanceOf(msg.sender);
        require(userBalance > 0, "No aTokens to withdraw");

        // Handle max withdrawal
        uint256 amountToWithdraw = amount;
        if (amount == type(uint256).max) {
            amountToWithdraw = userBalance;
        }

        require(amountToWithdraw <= userBalance, "Insufficient aToken balance");
        require(amountToWithdraw <= IERC20(asset).balanceOf(address(this)), "Insufficient pool liquidity");

        // Burn aTokens from user
        MockERC20(aToken).burn(msg.sender, amountToWithdraw);

        // Transfer underlying asset to recipient
        IERC20(asset).safeTransfer(to, amountToWithdraw);

        emit Withdraw(asset, msg.sender, to, amountToWithdraw);
        return amountToWithdraw;
    }

    /**
     * @notice Get the aToken address for a given asset
     * @param asset The underlying asset address
     * @return The corresponding aToken address
     */
    function getReserveToken(address asset) external view returns (address) {
        return reserveTokens[asset];
    }

    /**
     * @notice Get total liquidity for an asset
     * @param asset The underlying asset address
     * @return Total balance of asset in the pool
     */
    function getReserveLiquidity(address asset) external view returns (uint256) {
        return IERC20(asset).balanceOf(address(this));
    }
}


