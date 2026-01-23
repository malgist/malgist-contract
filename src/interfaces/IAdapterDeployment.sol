// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/*
 * @status ACTIVE
 * @network Chain-agnostic
 * @used-by AdapterRegistry.sol, UniversalVaultDeploymentLayer.sol
 * @notes Interface describing adapter metadata for registries.
 */

/**
 * @title IAdapterDeployment
 * @notice Minimal, protocol-agnostic adapter interface for deployment-layer abstraction
 * @dev This interface is the ONLY contract interface that UniversalVault depends on.
 *      It allows switching between real and mock adapters at deployment time without
 *      modifying vault logic or adding test conditionals.
 *
 * Design Principles:
 * 1. Minimal: Only essential functions (deposit, withdraw, totalAssets)
 * 2. Protocol-agnostic: No assumptions about underlying protocol
 * 3. Deterministic: No timestamp-based or randomness-dependent logic
 * 4. Gas-efficient: No unnecessary state reads or loops
 * 5. Audit-ready: Clean, simple contract with no hidden logic
 */
interface IAdapterDeployment {
    /**
     * @notice Emitted when adapter receives a deposit
     * @param user User address depositing funds
     * @param amount Amount of underlying asset deposited
     * @param timestamp Block timestamp of deposit
     */
    event AdapterDeposit(address indexed user, uint256 amount, uint256 timestamp);

    /**
     * @notice Emitted when adapter executes a withdrawal
     * @param user User address withdrawing funds
     * @param amount Amount of underlying asset withdrawn
     * @param timestamp Block timestamp of withdrawal
     */
    event AdapterWithdraw(address indexed user, uint256 amount, uint256 timestamp);

    /**
     * @notice Get the underlying asset address (USDC, WETH, etc.)
     * @return The ERC20 token address this adapter works with
     */
    function asset() external view returns (address);

    /**
     * @notice Deposit underlying asset into the adapter's protocol integration
     * @dev This function MUST be deterministic (no randomness, no timestamp logic)
     * @param amount Amount of underlying asset to deposit
     * @param recipient Address that receives the shares/credit in the protocol
     * @return shares Amount of protocol-specific shares received (or equivalent credit)
     */
    function deposit(uint256 amount, address recipient) external returns (uint256 shares);

    /**
     * @notice Withdraw underlying asset from the adapter's protocol integration
     * @dev This function MUST be deterministic and always succeed if balance sufficient
     * @param amount Amount of underlying asset to withdraw
     * @param recipient Address that receives the withdrawn asset
     * @param owner Address of the account owning the protocol shares
     * @return withdrawn Amount of underlying asset actually withdrawn
     */
    function withdraw(uint256 amount, address recipient, address owner) external returns (uint256 withdrawn);

    /**
     * @notice Get total assets under management by this adapter
     * @dev This is the single source of truth for adapter's TVL
     *      Used for share price calculations and accounting
     * @return Total amount of underlying asset managed by this adapter
     */
    function totalAssets() external view returns (uint256);

    /**
     * @notice Check if adapter is operational (not paused, not in error state)
     * @dev This allows graceful degradation if an adapter has issues
     * @return True if adapter can process deposits/withdrawals, false if paused/errored
     */
    function isOperational() external view returns (bool);

    /**
     * @notice Get adapter metadata (protocol name, version, etc.)
     * @dev Used for monitoring and debugging, not critical for core logic
     * @return protocolName Human-readable protocol name (e.g., "Aave", "Lido")
     * @return protocolVersion Version identifier (e.g., "V3", "V2")
     */
    function getAdapterMetadata() external view returns (string memory protocolName, string memory protocolVersion);
}
