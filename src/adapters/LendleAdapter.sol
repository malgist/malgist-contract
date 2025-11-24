// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IAdapter} from "../interfaces/IAdapter.sol";

/**
 * @title ILendingPool
 * @notice Minimal interface for Aave V3 / Lendle lending pool
 */
interface ILendingPool {
    function supply(
        address asset,
        uint256 amount,
        address onBehalfOf,
        uint16 referralCode
    ) external;

    function withdraw(
        address asset,
        uint256 amount,
        address to
    ) external returns (uint256);

    function getReserveToken(address asset) external view returns (address);
}

/**
 * @title LendleAdapter
 * @notice Production-ready adapter for Lendle (Aave V3 fork on Mantle)
 * @dev This adapter can work with real Lendle contracts with minimal changes
 */
contract LendleAdapter is IAdapter {
    using SafeERC20 for IERC20;

    /// @notice The underlying asset this adapter manages (e.g., USDC)
    IERC20 private immutable _ASSET;

    /// @notice The Lendle lending pool contract
    ILendingPool private immutable _LENDING_POOL;

    /// @notice The vault address that owns this adapter
    address private immutable _VAULT;

    /// @notice The aToken received from lending pool (e.g., aUSDC)
    address private immutable _A_TOKEN;

    /// @notice Emitted when tokens are deposited to Lendle
    event DepositedToLendle(uint256 amount, uint256 aTokensReceived);

    /// @notice Emitted when tokens are withdrawn from Lendle
    event WithdrawnFromLendle(uint256 amount, uint256 aTokensBurned);

    /// @dev Errors
    error OnlyVault();
    error InvalidAmount();
    error ReserveNotInitialized();

    modifier onlyVault() {
        if (msg.sender != _VAULT) revert OnlyVault();
        _;
    }

    /**
     * @notice Constructor
     * @param asset The underlying asset address (e.g., USDC)
     * @param lendingPool The Lendle lending pool address
     * @param vault The UniversalVault address that will call this adapter
     */
    constructor(address asset, address lendingPool, address vault) {
        _ASSET = IERC20(asset);
        _LENDING_POOL = ILendingPool(lendingPool);
        _VAULT = vault;

        // Get the aToken address from the pool
        address aToken = ILendingPool(lendingPool).getReserveToken(asset);
        if (aToken == address(0)) revert ReserveNotInitialized();
        _A_TOKEN = aToken;
    }

    /**
     * @notice Deposit assets into Lendle
     * @param amount Amount of underlying asset to deposit
     * @return shares Amount of aTokens received (1:1 in most cases)
     */
    function deposit(uint256 amount) external onlyVault returns (uint256 shares) {
        if (amount == 0) revert InvalidAmount();

        // Get balance before supply
        uint256 aTokenBalanceBefore = IERC20(_A_TOKEN).balanceOf(address(this));

        // Transfer tokens from vault to this contract
        _ASSET.safeTransferFrom(msg.sender, address(this), amount);

        // Approve lending pool to spend the asset
        _ASSET.forceApprove(address(_LENDING_POOL), amount);

        // Supply to Lendle (aTokens minted to this contract)
        _LENDING_POOL.supply(address(_ASSET), amount, address(this), 0);

        // Reset approval
        _ASSET.forceApprove(address(_LENDING_POOL), 0);

        // Calculate aTokens received
        uint256 aTokenBalanceAfter = IERC20(_A_TOKEN).balanceOf(address(this));
        shares = aTokenBalanceAfter - aTokenBalanceBefore;

        emit DepositedToLendle(amount, shares);
        return shares;
    }

    /**
     * @notice Withdraw assets from Lendle
     * @param amount Amount of underlying asset to withdraw
     * @return withdrawn Actual amount withdrawn
     */
    function withdraw(uint256 amount) external onlyVault returns (uint256 withdrawn) {
        if (amount == 0) revert InvalidAmount();

        // Get aToken balance before withdrawal
        uint256 aTokenBalanceBefore = IERC20(_A_TOKEN).balanceOf(address(this));

        // Approve lending pool to burn aTokens
        IERC20(_A_TOKEN).forceApprove(address(_LENDING_POOL), amount);

        // Withdraw from Lendle (sends underlying to vault)
        withdrawn = _LENDING_POOL.withdraw(address(_ASSET), amount, _VAULT);

        // Reset approval
        IERC20(_A_TOKEN).forceApprove(address(_LENDING_POOL), 0);

        // Calculate aTokens burned
        uint256 aTokenBalanceAfter = IERC20(_A_TOKEN).balanceOf(address(this));
        uint256 aTokensBurned = aTokenBalanceBefore - aTokenBalanceAfter;

        emit WithdrawnFromLendle(withdrawn, aTokensBurned);
        return withdrawn;
    }

    /**
     * @notice Get current balance of aTokens (represents deposited amount + accrued interest)
     * @return balance Current aToken balance
     */
    function getBalance() external view returns (uint256 balance) {
        return IERC20(_A_TOKEN).balanceOf(address(this));
    }

    /**
     * @notice Get the underlying asset address
     * @return tokenAddress The underlying asset this adapter manages
     */
    function token() external view returns (address tokenAddress) {
        return address(_ASSET);
    }

    /**
     * @notice Get the aToken address
     * @return The aToken address for this adapter
     */
    function getAToken() external view returns (address) {
        return _A_TOKEN;
    }

    /**
     * @notice Get the lending pool address
     * @return The Lendle lending pool address
     */
    function getLendingPool() external view returns (address) {
        return address(_LENDING_POOL);
    }
}
