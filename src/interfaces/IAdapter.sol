// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IAdapter
 * @notice Standard interface for protocol adapters in the Mantle Strategy Studio
 * @dev All adapters must implement this interface to be compatible with the Universal Vault
 */
interface IAdapter {
    /**
     * @notice Deposit tokens into the underlying protocol
     * @param amount Amount of base token to deposit
     * @return shares Amount of shares/receipt tokens received
     */
    function deposit(uint256 amount) external returns (uint256 shares);
    
    /**
     * @notice Withdraw tokens from the underlying protocol
     * @param amount Amount of base token to withdraw
     * @return withdrawn Actual amount withdrawn (may differ due to fees/slippage)
     */
    function withdraw(uint256 amount) external returns (uint256 withdrawn);
    
    /**
     * @notice Get the current balance in the underlying protocol
     * @return balance Current value in base tokens
     */
    function getBalance() external view returns (uint256 balance);
    
    /**
     * @notice Get the underlying asset address (e.g., USDC)
     * @return tokenAddress Address of the base token this adapter accepts
     */
    function token() external view returns (address tokenAddress);
}
