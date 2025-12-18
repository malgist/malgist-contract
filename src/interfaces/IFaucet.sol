// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IFaucet
 * @notice Interface for MALGIST testnet faucet
 * @dev NOT part of core protocol. Excluded from audit scope.
 */
interface IFaucet {
    // ============ EVENTS ============

    event Claimed(address indexed user, uint256 amount, uint256 timestamp);
    event ClaimAmountUpdated(uint256 newAmount);
    event CooldownUpdated(uint256 newCooldown);
    event Withdrawn(address indexed to, uint256 amount);

    // ============ FUNCTIONS ============

    /**
     * @notice Claim USDC tokens from faucet
     */
    function claim() external;

    /**
     * @notice Update claim amount per request
     * @param newAmount New claim amount in USDC (with 6 decimals)
     */
    function setClaimAmount(uint256 newAmount) external;

    /**
     * @notice Update cooldown period between claims
     * @param newCooldown New cooldown in seconds
     */
    function setCooldownPeriod(uint256 newCooldown) external;

    /**
     * @notice Withdraw tokens from faucet
     * @param recipient Address to receive tokens
     * @param amount Amount to withdraw
     */
    function withdraw(address recipient, uint256 amount) external;

    /**
     * @notice Get time until user can claim again
     * @param user Address to check
     * @return secondsUntilClaim Seconds until next claim (0 if ready)
     */
    function getTimeUntilClaim(address user) external view returns (uint256);

    /**
     * @notice Check if user can claim now
     * @param user Address to check
     * @return canClaim True if user can claim immediately
     */
    function canClaim(address user) external view returns (bool);

    /**
     * @notice Get faucet state snapshot
     * @return balance Current USDC balance
     * @return amount Claim amount per request
     * @return cooldown Cooldown period
     */
    function getFaucetState() external view returns (uint256 balance, uint256 amount, uint256 cooldown);
}
