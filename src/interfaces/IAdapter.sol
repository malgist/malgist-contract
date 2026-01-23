// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/*
 * @status ACTIVE
 * @network Chain-agnostic
 * @used-by All adapters + vaults
 * @notes Primary adapter interface enforced across production code.
 */

/**
 * @title IAdapter
 * @notice Standard interface for protocol adapters in the Mantle Strategy Studio
 * @dev All adapters must implement this interface to be compatible with the Universal Vault
 */
interface IAdapter {
    /**
     * @notice Deposit tokens into the underlying protocol
     * @dev Implementations MUST return the asset-equivalent amount accepted by the adapter
     *      (i.e., value expressed in base tokens) so the vault can maintain a unified accounting
     * @param amount Amount of base token to deposit
     * @return deposited Amount (in base asset units) that the adapter recorded / added
     */
    function deposit(uint256 amount) external returns (uint256 deposited);

    /**
     * @notice Withdraw tokens from the underlying protocol
     * @dev `amount` is expressed in base-asset units; adapter should try to return that amount
     *      and return the actual withdrawn amount (may differ due to slippage/fees)
     * @param amount Amount of base token to withdraw
     * @return withdrawn Actual amount withdrawn (in base asset units)
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
