// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/*
 * @status LEGACY
 * @network Docs only
 * @used-by Architecture examples
 * @notes Static production adapter stubs retained for auditors.
 */

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IAdapterDeployment} from "../interfaces/IAdapterDeployment.sol";

/**
 * @title AaveV3ProductionAdapter
 * @notice Real Aave V3 adapter for production deployment
 * @dev This adapter implements IAdapterDeployment for real Aave protocol integration.
 *      Can be swapped for MockAaveAdapter without changing vault logic.
 */
interface IAavePool {
    function supply(address asset, uint256 amount, address onBehalfOf, uint16 referralCode) external;
    function withdraw(address asset, uint256 amount, address to) external returns (uint256);
    function getUserAccountData(address user) external view returns (
        uint256 totalCollateralBase,
        uint256 totalDebtBase,
        uint256 availableBorrowsBase,
        uint256 currentLiquidationThreshold,
        uint256 ltv,
        uint256 healthFactor
    );
}

interface IAaveToken is IERC20 {
    function balanceOf(address user) external view returns (uint256);
}

contract AaveV3ProductionAdapter is IAdapterDeployment {
    using SafeERC20 for IERC20;

    // ============ Immutable State ============

    /// @notice Underlying asset (USDC)
    address public immutable asset;

    /// @notice Aave aToken (aUSDC)
    IAaveToken public immutable aToken;

    /// @notice Aave Pool contract
    IAavePool public immutable aavePool;

    // ============ Constructor ============

    /**
     * @notice Initialize Aave adapter
     * @param _asset USDC token address
     * @param _aToken aUSDC token address
     * @param _aavePool Aave Pool contract address
     */
    constructor(address _asset, address _aToken, address _aavePool) {
        asset = _asset;
        aToken = IAaveToken(_aToken);
        aavePool = IAavePool(_aavePool);
    }

    // ============ IAdapterDeployment Implementation ============

    // Note: immutable public variable `asset` provides the asset() function automatically

    function deposit(uint256 amount, address recipient) external returns (uint256 shares) {
        // Transfer asset to this adapter
        IERC20(asset).safeTransferFrom(msg.sender, address(this), amount);

        // Approve Aave pool
        IERC20(asset).forceApprove(address(aavePool), amount);

        // Deposit into Aave (returns void, we get aTokens)
        aavePool.supply(asset, amount, recipient, 0);

        // Return amount as shares (1:1 for simplicity)
        shares = amount;

        emit AdapterDeposit(recipient, amount, block.timestamp);
    }

    function withdraw(uint256 amount, address recipient, address owner) external returns (uint256 withdrawn) {
        // Withdraw from Aave
        withdrawn = aavePool.withdraw(asset, amount, recipient);

        emit AdapterWithdraw(owner, withdrawn, block.timestamp);
    }

    function totalAssets() external view returns (uint256) {
        // Return balance of aTokens held by this adapter
        return aToken.balanceOf(address(this));
    }

    function isOperational() external view returns (bool) {
        // Simple check: Aave pool exists and has supply
        // In production, could check more comprehensive health metrics
        try aavePool.getUserAccountData(address(this)) {
            return true;
        } catch {
            return false;
        }
    }

    function getAdapterMetadata() external pure returns (string memory, string memory) {
        return ("Aave V3", "1.0");
    }
}

/**
 * @title LidoProductionAdapter
 * @notice Real Lido adapter for production deployment
 */
interface ILidoStETH is IERC20 {
    function submit(address referral) external payable returns (uint256);
    function balanceOf(address account) external view returns (uint256);
}

contract LidoProductionAdapter is IAdapterDeployment {
    using SafeERC20 for IERC20;

    // ============ Immutable State ============

    address public immutable asset;
    ILidoStETH public immutable stETH;

    // ============ Constructor ============

    constructor(address _asset, address _stETH) {
        asset = _asset;
        stETH = ILidoStETH(_stETH);
    }

    // ============ IAdapterDeployment Implementation ============

    // Note: immutable public variable `asset` provides the asset() function automatically

    function deposit(uint256 amount, address recipient) external returns (uint256 shares) {
        // Transfer WETH to adapter
        IERC20(asset).safeTransferFrom(msg.sender, address(this), amount);

        // In production, convert WETH to ETH, then stake in Lido
        // For this example, we assume WETH is staked directly
        // Actual implementation would unwrap WETH first

        shares = amount;
        emit AdapterDeposit(recipient, amount, block.timestamp);
    }

    function withdraw(uint256 amount, address recipient, address owner) external returns (uint256 withdrawn) {
        // Transfer stETH to recipient
        IERC20(address(stETH)).safeTransfer(recipient, amount);
        withdrawn = amount;

        emit AdapterWithdraw(owner, withdrawn, block.timestamp);
    }

    function totalAssets() external view returns (uint256) {
        return stETH.balanceOf(address(this));
    }

    function isOperational() external view returns (bool) {
        // Check if stETH contract is functional
        return address(stETH) != address(0);
    }

    function getAdapterMetadata() external pure returns (string memory, string memory) {
        return ("Lido", "1.0");
    }
}
