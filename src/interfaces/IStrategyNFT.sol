// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/*
 * @status ACTIVE
 * @network Mantle Sepolia
 * @used-by StrategyNFT.sol, StrategyVault.sol
 * @notes Interface to share strategy metadata with vaults.
 */

/// @notice Minimal Strategy NFT interface used by Vault/Registry
interface IStrategyNFT {
    function ownerOf(uint256 tokenId) external view returns (address);

    /// @notice Return canonical strategy id for a token (application-specific)
    function strategyIdOf(uint256 tokenId) external view returns (uint256);

    /// @notice Return active version for this token
    function versionOf(uint256 tokenId) external view returns (uint256);
}
