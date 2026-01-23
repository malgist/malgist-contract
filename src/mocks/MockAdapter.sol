// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/*
 * @status TEST-ONLY
 * @network Local tests
 * @used-by test suite
 * @notes Mock adapter for Foundry + Echidna tests.
 */

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IAdapter} from "../interfaces/IAdapter.sol";

/**
 * @title MockAdapter
 * @notice Simple adapter for testing that accepts deposits and mints shares 1:1
 * @dev This is a mock implementation - real adapters would interact with actual DeFi protocols
 */
contract MockAdapter is IAdapter {
    using SafeERC20 for IERC20;

    IERC20 private immutable _TOKEN;

    /// @dev Track shares for each depositor
    mapping(address => uint256) public shares;

    /// @dev Total shares minted
    uint256 public totalShares;

    /// @dev Total assets held
    uint256 public totalAssets;

    /// @notice Emitted when a deposit is made
    event Deposited(address indexed user, uint256 assets, uint256 shares);

    /// @notice Emitted when a withdrawal is made
    event Withdrawn(address indexed user, uint256 assets, uint256 shares);

    /// @notice Emitted when yield is minted (for testing)
    event YieldMinted(address indexed to, uint256 amount);

    constructor(address asset) {
        _TOKEN = IERC20(asset);
    }

    /**
     * @notice Deposit tokens and receive shares 1:1
     * @param amount Amount of tokens to deposit
     * @return sharesIssued Amount of shares issued (1:1 for this mock)
     */
    function deposit(uint256 amount) external override returns (uint256 sharesIssued) {
        require(amount > 0, "Amount must be > 0");

        // Transfer tokens from caller
        _TOKEN.safeTransferFrom(msg.sender, address(this), amount);

        // Mint shares 1:1 (simplified for testing)
        sharesIssued = amount;
        shares[msg.sender] += sharesIssued;
        totalShares += sharesIssued;
        totalAssets += amount;

        emit Deposited(msg.sender, amount, sharesIssued);
        return sharesIssued;
    }

    /**
     * @notice Withdraw tokens by burning shares
     * @param amount Amount of tokens to withdraw
     * @return withdrawn Actual amount withdrawn
     */
    function withdraw(uint256 amount) external override returns (uint256 withdrawn) {
        require(amount > 0, "Amount must be > 0");
        require(shares[msg.sender] >= amount, "Insufficient shares");

        // Burn shares 1:1 (simplified)
        shares[msg.sender] -= amount;
        totalShares -= amount;
        totalAssets -= amount;

        // Transfer tokens back
        _TOKEN.safeTransfer(msg.sender, amount);

        emit Withdrawn(msg.sender, amount, amount);
        return amount;
    }

    /**
     * @notice Get current balance (returns total assets held)
     * @return balance Current balance in the adapter
     */
    function getBalance() external view override returns (uint256 balance) {
        return totalAssets;
    }

    /**
     * @notice Get the underlying token address
     * @return tokenAddress The asset this adapter accepts
     */
    function token() external view override returns (address tokenAddress) {
        return address(_TOKEN);
    }

    /**
     * @notice Simulate yield generation by minting tokens to the adapter
     * @dev For testing purposes - simulates protocol yield
     * @param to Address to credit the yield to
     * @param amount Amount of yield to generate
     */
    function mint(address to, uint256 amount) external {
        shares[to] += amount;
        totalShares += amount;
        totalAssets += amount;

        emit YieldMinted(to, amount);
    }

    /**
     * @notice Simulate loss by reducing total assets (for testing)
     * @param amount Amount to remove from totalAssets
     */
    function slash(uint256 amount) external {
        require(amount <= totalAssets, "Insufficient assets");
        totalAssets -= amount;
    }
}
