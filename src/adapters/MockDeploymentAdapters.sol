// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IAdapterDeployment} from "../interfaces/IAdapterDeployment.sol";

/**
 * @title MockAdapterBase
 * @notice Base class for mock adapters used in demo/hackathon deployments
 * @dev Mock adapters implement IAdapterDeployment identically to production adapters.
 *      This allows switching between production and demo without vault changes.
 *      Demo deployments can use these mocks locally or on testnets.
 */
abstract contract MockAdapterBase is IAdapterDeployment {
    using SafeERC20 for IERC20;

    // ============ Immutable State ============

    address public immutable asset;

    // ============ State ============

    /// @notice Tracks deposited amounts (simulates protocol balance)
    mapping(address => uint256) public deposits;

    /// @notice Total simulated balance
    uint256 public totalBalance;

    /// @notice Multiplier for simulated yield (10000 = 1.0x, 10500 = 1.05x yield)
    uint16 public yieldMultiplier = 10000;

    // ============ Constructor ============

    constructor(address _asset) {
        asset = _asset;
    }

    // ============ IAdapterDeployment Implementation ============

    // Note: immutable public variable `asset` provides the asset() function automatically
    // No need to override

    /**
     * @notice Mock deposit: transfers asset to adapter, tracks balance
     * @dev In production, this would call a real protocol.
     *      In demo, we just track the balance and accumulate.
     */
    function deposit(uint256 amount, address recipient) external returns (uint256 shares) {
        // Transfer asset from vault to this adapter
        IERC20(asset).safeTransferFrom(msg.sender, address(this), amount);

        // In a real protocol, we'd get back protocol tokens
        // In mock, we just track the balance with yield multiplier applied
        uint256 sharesWithYield = (amount * yieldMultiplier) / 10000;
        deposits[recipient] += sharesWithYield;
        totalBalance += sharesWithYield;

        emit AdapterDeposit(recipient, amount, block.timestamp);
        return sharesWithYield;
    }

    /**
     * @notice Mock withdrawal: transfers asset back to recipient
     * @dev Simulates the protocol returning the asset with any accrued yield
     */
    function withdraw(uint256 amount, address recipient, address owner) external returns (uint256 withdrawn) {
        // In mock, withdrawal is direct (no protocol call)
        if (deposits[owner] < amount) {
            return 0; // Insufficient balance
        }

        deposits[owner] -= amount;
        totalBalance -= amount;

        // Transfer asset to recipient
        IERC20(asset).safeTransfer(recipient, amount);

        emit AdapterWithdraw(owner, amount, block.timestamp);
        return amount;
    }

    /**
     * @notice Return total simulated assets
     * @dev In production, queries real protocol balance
     *      In mock, returns tracked balance
     */
    function totalAssets() external view returns (uint256) {
        return totalBalance;
    }

    /**
     * @notice Mock adapters are always operational
     * @dev In production, would check protocol health
     *      In mock, always returns true for testing
     */
    function isOperational() external pure returns (bool) {
        return true;
    }

    function getAdapterMetadata() external pure virtual returns (string memory, string memory);

    // ============ Mock-Specific Functions ============

    /**
     * @notice Set yield multiplier for demo purposes
     * @param _multiplier Basis points (10000 = 1.0x, 10500 = 1.05x)
     */
    function setYieldMultiplier(uint16 _multiplier) external {
        yieldMultiplier = _multiplier;
    }
}

/**
 * @title MockAaveAdapter
 * @notice Mock Aave adapter for demo/hackathon deployment
 * @dev Implements IAdapterDeployment with simulated Aave behavior
 */
contract MockAaveAdapter is MockAdapterBase {
    constructor(address _asset) MockAdapterBase(_asset) {}

    function getAdapterMetadata() external pure override returns (string memory, string memory) {
        return ("MockAave", "1.0");
    }
}

/**
 * @title MockLidoAdapter
 * @notice Mock Lido adapter for demo/hackathon deployment
 * @dev Implements IAdapterDeployment with simulated Lido behavior
 */
contract MockLidoAdapter is MockAdapterBase {
    constructor(address _asset) MockAdapterBase(_asset) {}

    function getAdapterMetadata() external pure override returns (string memory, string memory) {
        return ("MockLido", "1.0");
    }
}

/**
 * @title MockGMXAdapter
 * @notice Mock GMX adapter for demo/hackathon deployment
 * @dev Implements IAdapterDeployment with simulated GMX behavior
 */
contract MockGMXAdapter is MockAdapterBase {
    constructor(address _asset) MockAdapterBase(_asset) {}

    function getAdapterMetadata() external pure override returns (string memory, string memory) {
        return ("MockGMX", "1.0");
    }
}

/**
 * @title MockFusionXAdapter
 * @notice Mock FusionX adapter for demo/hackathon deployment
 * @dev Implements IAdapterDeployment with simulated FusionX behavior
 */
contract MockFusionXAdapter is MockAdapterBase {
    constructor(address _asset) MockAdapterBase(_asset) {}

    function getAdapterMetadata() external pure override returns (string memory, string memory) {
        return ("MockFusionX", "1.0");
    }
}

/**
 * @title MockLendleAdapter
 * @notice Mock Lendle adapter for demo/hackathon deployment
 * @dev Implements IAdapterDeployment with simulated Lendle behavior
 */
contract MockLendleAdapter is MockAdapterBase {
    constructor(address _asset) MockAdapterBase(_asset) {}

    function getAdapterMetadata() external pure override returns (string memory, string memory) {
        return ("MockLendle", "1.0");
    }
}
