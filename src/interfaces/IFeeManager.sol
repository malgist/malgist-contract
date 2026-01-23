// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/*
 * @status ACTIVE
 * @network Mantle Sepolia
 * @used-by FeeManager.sol, UserVault.sol
 * @notes Interface for fee accounting modules.
 */

interface IFeeManager {
    /// @notice Charge fees on a gross yield amount previously transferred to the FeeManager
    /// @param strategyId Strategy identifier (opaque to FeeManager, passed for logging)
    /// @param grossYield Amount of yield (in base asset units) to charge fees on
    /// @param creator Address of the strategy creator to receive creator fee
    /// @param creatorFeeBps Creator fee in basis points (<= 1000)
    /// @return netYield Amount remaining after fees (in base asset units)
    function chargeFees(uint256 strategyId, uint256 grossYield, address creator, uint16 creatorFeeBps)
        external
        returns (uint256 netYield);

    /// @notice Governance: set protocol fee (bps)
    function setProtocolFeeBps(uint16 bps) external;

    /// @notice Governance: update treasury address
    function setTreasury(address treasury) external;

    /// @notice Authorize or revoke a vault address
    function setAuthorizedVault(address vault, bool authorized) external;
}
