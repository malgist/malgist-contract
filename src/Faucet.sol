// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/*
 * @status ACTIVE
 * @network Mantle Sepolia
 * @used-by DeployProtocolCore.s.sol, scripts/deploy-faucet.sh
 * @notes Lightweight USDC faucet for integration and smoke tests.
 */

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title Faucet
 * @notice Testnet-only USDC faucet for MALGIST hackathon environment
 * @dev NOT part of core protocol. Excluded from audit scope.
 *      This contract is designed for testnet/demo usage only and is disabled on mainnet.
 *
 * SECURITY MODEL:
 * - Chainid check enforces testnet-only operation (Mantle testnet = 5003)
 * - Per-address rate limiting prevents abuse (1 claim per 24 hours)
 * - Maximum claim amount prevents vault griefing
 * - Reentrancy guard protects against callback attacks
 * - Faucet never mints to vault contracts, only to user wallets
 */
contract Faucet is Ownable, ReentrancyGuard {
    // ============ STATE VARIABLES ============

    /// @notice USDC token contract
    IERC20 public immutable USDC;

    /// @notice Testnet chain ID (Mantle testnet = 5003)
    uint256 public constant TESTNET_CHAIN_ID = 5003;

    /// @notice Default claim amount: 1000 USDC
    uint256 public claimAmount = 1000e6;

    /// @notice Default cooldown period: 24 hours
    uint256 public cooldownPeriod = 24 hours;

    /// @notice Last claim timestamp per address
    mapping(address => uint256) public lastClaimTime;

    /// @notice Total claimed amount per address (for analytics)
    mapping(address => uint256) public totalClaimed;

    // ============ EVENTS ============

    /// @notice Emitted when user successfully claims tokens
    event Claimed(address indexed user, uint256 amount, uint256 timestamp);

    /// @notice Emitted when admin updates claim amount
    event ClaimAmountUpdated(uint256 newAmount);

    /// @notice Emitted when admin updates cooldown period
    event CooldownUpdated(uint256 newCooldown);

    /// @notice Emitted when admin withdraws excess tokens
    event Withdrawn(address indexed to, uint256 amount);

    // ============ ERRORS ============

    error NotTestnet();
    error ClaimTooSoon();
    error ExceedsMaxClaimAmount();
    error InsufficientFaucetBalance();
    error ZeroAddress();
    error InvalidAmount();
    error WithdrawalFailed();

    // ============ MODIFIERS ============

    /**
     * @notice Enforce testnet-only operation
     * @dev Prevents accidental deployment on mainnet
     */
    modifier onlyTestnet() {
        if (block.chainid != TESTNET_CHAIN_ID) revert NotTestnet();
        _;
    }

    // ============ CONSTRUCTOR ============

    /**
     * @notice Initialize faucet with USDC token address
     * @param _usdc Address of MockUSDC token
     */
    constructor(address _usdc) Ownable(msg.sender) {
        if (_usdc == address(0)) revert ZeroAddress();
        USDC = IERC20(_usdc);
    }

    // ============ EXTERNAL FUNCTIONS ============

    /**
     * @notice Claim USDC tokens from faucet
     * @dev User must wait cooldownPeriod between claims
     *      Only callable on testnet (Mantle 5003)
     */
    function claim() external onlyTestnet nonReentrant {
        address user = msg.sender;

        // Check rate limit
        uint256 timeSinceLastClaim = block.timestamp - lastClaimTime[user];
        if (timeSinceLastClaim < cooldownPeriod) revert ClaimTooSoon();

        uint256 amount = claimAmount;

        // Verify faucet has sufficient balance
        if (USDC.balanceOf(address(this)) < amount) revert InsufficientFaucetBalance();

        // Update state before external call (checks-effects-interactions)
        lastClaimTime[user] = block.timestamp;
        totalClaimed[user] += amount;

        // Transfer tokens
        bool success = USDC.transfer(user, amount);
        if (!success) revert WithdrawalFailed();

        emit Claimed(user, amount, block.timestamp);
    }

    // ============ ADMIN FUNCTIONS ============

    /**
     * @notice Update claim amount per request
     * @param newAmount New claim amount in USDC (with 6 decimals)
     */
    function setClaimAmount(uint256 newAmount) external onlyOwner {
        if (newAmount == 0) revert InvalidAmount();
        if (newAmount > 10000e6) revert ExceedsMaxClaimAmount(); // Max 10k USDC per claim
        claimAmount = newAmount;
        emit ClaimAmountUpdated(newAmount);
    }

    /**
     * @notice Update cooldown period between claims
     * @param newCooldown New cooldown in seconds (e.g., 86400 for 24 hours)
     */
    function setCooldownPeriod(uint256 newCooldown) external onlyOwner {
        if (newCooldown == 0) revert InvalidAmount();
        if (newCooldown > 30 days) revert InvalidAmount(); // Max 30 day cooldown
        cooldownPeriod = newCooldown;
        emit CooldownUpdated(newCooldown);
    }

    /**
     * @notice Withdraw tokens from faucet
     * @param recipient Address to receive tokens
     * @param amount Amount to withdraw
     */
    function withdraw(address recipient, uint256 amount) external onlyOwner onlyTestnet {
        if (recipient == address(0)) revert ZeroAddress();
        if (amount == 0) revert InvalidAmount();

        uint256 balance = USDC.balanceOf(address(this));
        if (balance < amount) revert InsufficientFaucetBalance();

        bool success = USDC.transfer(recipient, amount);
        if (!success) revert WithdrawalFailed();

        emit Withdrawn(recipient, amount);
    }

    // ============ VIEW FUNCTIONS ============

    /**
     * @notice Get time until user can claim again
     * @param user Address to check
     * @return secondsUntilClaim Seconds until next claim is available (0 if ready)
     */
    function getTimeUntilClaim(address user) external view returns (uint256) {
        uint256 timeSinceLastClaim = block.timestamp - lastClaimTime[user];
        if (timeSinceLastClaim >= cooldownPeriod) {
            return 0;
        }
        return cooldownPeriod - timeSinceLastClaim;
    }

    /**
     * @notice Check if user can claim now
     * @param user Address to check
     * @return canClaim True if user can claim immediately
     */
    function canClaim(address user) external view returns (bool) {
        return block.timestamp - lastClaimTime[user] >= cooldownPeriod;
    }

    /**
     * @notice Get faucet state snapshot for frontend
     * @return balance Current USDC balance
     * @return amount Claim amount per request
     * @return cooldown Cooldown period
     */
    function getFaucetState() external view returns (uint256 balance, uint256 amount, uint256 cooldown) {
        return (USDC.balanceOf(address(this)), claimAmount, cooldownPeriod);
    }
}
