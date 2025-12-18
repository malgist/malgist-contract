// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title MockUSDC
 * @notice Mintable USDC mock token for testnet/hackathon environments
 * @dev Only used on testnet. Not part of core protocol audit scope.
 */
contract MockUSDC is ERC20, Ownable {
    /// @notice USDC decimals (6)
    uint8 public constant DECIMALS = 6;

    error CallerNotMinter();

    /// @notice Authorized minters (e.g., Faucet contract)
    mapping(address => bool) public minters;

    event MinterAdded(address indexed minter);
    event MinterRemoved(address indexed minter);

    constructor() ERC20("Mock USDC", "USDC") Ownable(msg.sender) {}

    function decimals() public pure override returns (uint8) {
        return DECIMALS;
    }

    /**
     * @notice Grant minting rights to an address
     * @param minter Address allowed to mint tokens
     */
    function addMinter(address minter) external onlyOwner {
        if (minter == address(0)) revert();
        minters[minter] = true;
        emit MinterAdded(minter);
    }

    /**
     * @notice Revoke minting rights from an address
     * @param minter Address to revoke minting rights from
     */
    function removeMinter(address minter) external onlyOwner {
        minters[minter] = false;
        emit MinterRemoved(minter);
    }

    /**
     * @notice Mint tokens (only authorized minters)
     * @param to Recipient address
     * @param amount Amount to mint
     */
    function mint(address to, uint256 amount) external {
        if (!minters[msg.sender]) revert CallerNotMinter();
        _mint(to, amount);
    }

    /**
     * @notice Burn tokens from any address (for testing)
     * @param from Address to burn from
     * @param amount Amount to burn
     */
    function burn(address from, uint256 amount) external onlyOwner {
        _burn(from, amount);
    }
}
