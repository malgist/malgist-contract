// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/*
 * @status ACTIVE
 * @network Mantle Sepolia
 * @used-by DeployStrategyExecutor.s.sol, UserVault.sol
 * @notes Permissioned adapter executor coordinating fee routing and access checks.
 */

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title StrategyExecutor
 * @notice Modular strategy execution engine with dynamic call forwarding
 * @dev Separates adapter interaction logic from vault logic for better modularity
 *      Uses low-level calls for flexibility and future adapter compatibility
 *
 * DESIGN BENEFITS:
 * ✅ Modular: Can be upgraded without touching UserVault
 * ✅ Flexible: Supports any adapter interface via calldata encoding
 * ✅ Safe: Validates all call results and handles errors
 * ✅ Gas-optimized: Minimizes storage reads/writes
 */
contract StrategyExecutor is ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ============================================================================
    // CONSTANTS & IMMUTABLES
    // ============================================================================

    /// @notice Basis points denominator
    uint16 public constant TOTAL_BPS = 10000;

    /// @notice Base asset (USDC)
    IERC20 public immutable ASSET;

    /// @notice Authorized vault that can call execute functions
    address public immutable vault;

    // ============================================================================
    // STRUCTS
    // ============================================================================

    /**
     * @notice Execution parameters for deposit operation
     * @param adapters Array of adapter addresses to deposit to
     * @param ratios Allocation ratios in basis points (must sum to 10000)
     * @param amount Total amount to distribute
     * @param callData Optional custom calldata per adapter (if empty, uses default deposit)
     */
    struct DepositParams {
        address[] adapters;
        uint16[] ratios;
        uint256 amount;
        bytes[] callData;
    }

    /**
     * @notice Execution parameters for withdrawal operation
     * @param adapters Array of adapter addresses to withdraw from
     * @param ratios Proportion to withdraw from each adapter
     * @param amount Total asset-equivalent amount to withdraw
     * @param callData Optional custom calldata per adapter
     */
    struct WithdrawParams {
        address[] adapters;
        uint16[] ratios;
        uint256 amount;
        bytes[] callData;
    }

    /**
     * @notice Result of adapter execution
     * @param success Whether the call succeeded
     * @param returnData Bytes returned from the call
     * @param shares Decoded shares/amount returned (if applicable)
     */
    struct ExecutionResult {
        bool success;
        bytes returnData;
        uint256 shares;
    }

    // ============================================================================
    // EVENTS
    // ============================================================================

    event DepositExecuted(
        address indexed adapter,
        uint256 amount,
        uint256 shares,
        bool usedCustomCalldata
    );

    event WithdrawExecuted(
        address indexed adapter,
        uint256 requestedAmount,
        uint256 actualAmount,
        bool usedCustomCalldata
    );

    event AdapterCallFailed(
        address indexed adapter,
        bytes callData,
        bytes returnData
    );

    // ============================================================================
    // ERRORS
    // ============================================================================

    error UnauthorizedCaller();
    error InvalidArrayLength();
    error InvalidRatios();
    error AdapterCallFailed_Error();
    error ZeroSharesReturned();
    error InvalidAmount();

    // ============================================================================
    // MODIFIERS
    // ============================================================================

    modifier onlyVault() {
        if (msg.sender != vault) revert UnauthorizedCaller();
        _;
    }

    // ============================================================================
    // CONSTRUCTOR
    // ============================================================================

    /**
     * @notice Initialize executor with vault and asset
     * @param _vault Address of authorized vault
     * @param _asset Address of base asset (USDC)
     */
    constructor(address _vault, address _asset) {
        require(_vault != address(0), "Invalid vault");
        require(_asset != address(0), "Invalid asset");

        vault = _vault;
        ASSET = IERC20(_asset);
    }

    // ============================================================================
    // EXTERNAL FUNCTIONS - DEPOSIT EXECUTION
    // ============================================================================

    /**
     * @notice Execute deposit across multiple adapters with dynamic routing
     * @param params Deposit execution parameters
     * @return results Array of execution results per adapter
     * @dev Uses call forwarding for maximum flexibility
     *      Supports both standard IAdapter.deposit() and custom calldata
     */
    function executeDeposit(DepositParams calldata params)
        external
        nonReentrant
        onlyVault
        returns (ExecutionResult[] memory results)
    {
        // Validate parameters
        if (params.adapters.length == 0) revert InvalidArrayLength();
        if (params.adapters.length != params.ratios.length) revert InvalidArrayLength();
        if (params.amount == 0) revert InvalidAmount();

        // Validate ratios sum to 100%
        uint256 totalRatio;
        for (uint256 i = 0; i < params.ratios.length; i++) {
            totalRatio += params.ratios[i];
        }
        if (totalRatio != TOTAL_BPS) revert InvalidRatios();

        // Transfer assets from vault to executor
        ASSET.safeTransferFrom(vault, address(this), params.amount);

        // Execute deposits
        results = new ExecutionResult[](params.adapters.length);
        uint256 remaining = params.amount;

        for (uint256 i = 0; i < params.adapters.length; i++) {
            uint256 adapterAmount;

            // Last adapter gets remainder to handle rounding
            if (i == params.adapters.length - 1) {
                adapterAmount = remaining;
            } else {
                adapterAmount = (params.amount * params.ratios[i]) / TOTAL_BPS;
                remaining -= adapterAmount;
            }

            // Execute deposit using call forwarding
            bool useCustomCalldata = params.callData.length > i && params.callData[i].length > 0;

            if (useCustomCalldata) {
                // Use custom calldata provided by caller
                results[i] = _executeCustomCall(
                    params.adapters[i],
                    adapterAmount,
                    params.callData[i]
                );
            } else {
                // Use standard IAdapter.deposit(uint256) interface
                results[i] = _executeStandardDeposit(
                    params.adapters[i],
                    adapterAmount
                );
            }

            // Validate result
            if (!results[i].success) revert AdapterCallFailed_Error();
            if (results[i].shares == 0) revert ZeroSharesReturned();

            emit DepositExecuted(
                params.adapters[i],
                adapterAmount,
                results[i].shares,
                useCustomCalldata
            );
        }

        return results;
    }

    // ============================================================================
    // EXTERNAL FUNCTIONS - WITHDRAW EXECUTION
    // ============================================================================

    /**
     * @notice Execute withdrawal across multiple adapters with dynamic routing
     * @param params Withdrawal execution parameters
     * @return results Array of execution results per adapter
     * @dev Supports proportional withdrawal using ratios
     */
    function executeWithdraw(WithdrawParams calldata params)
        external
        nonReentrant
        onlyVault
        returns (ExecutionResult[] memory results)
    {
        // Validate parameters
        if (params.adapters.length == 0) revert InvalidArrayLength();
        if (params.adapters.length != params.ratios.length) revert InvalidArrayLength();
        if (params.amount == 0) revert InvalidAmount();

        results = new ExecutionResult[](params.adapters.length);
        uint256 totalWithdrawn = 0;

        for (uint256 i = 0; i < params.adapters.length; i++) {
            uint256 adapterAmount = (params.amount * params.ratios[i]) / TOTAL_BPS;

            if (adapterAmount == 0) {
                // Skip zero amount withdrawals
                results[i] = ExecutionResult({
                    success: true,
                    returnData: "",
                    shares: 0
                });
                continue;
            }

            // Execute withdrawal using call forwarding
            bool useCustomCalldata = params.callData.length > i && params.callData[i].length > 0;

            if (useCustomCalldata) {
                results[i] = _executeCustomCall(
                    params.adapters[i],
                    adapterAmount,
                    params.callData[i]
                );
            } else {
                // Use standard IAdapter.withdraw(uint256) interface
                results[i] = _executeStandardWithdraw(
                    params.adapters[i],
                    adapterAmount
                );
            }

            // Validate result
            if (!results[i].success) {
                emit AdapterCallFailed(
                    params.adapters[i],
                    params.callData.length > i ? params.callData[i] : bytes(""),
                    results[i].returnData
                );
                revert AdapterCallFailed_Error();
            }

            totalWithdrawn += results[i].shares;

            emit WithdrawExecuted(
                params.adapters[i],
                adapterAmount,
                results[i].shares,
                useCustomCalldata
            );
        }

        // Transfer withdrawn assets back to vault
        if (totalWithdrawn > 0) {
            ASSET.safeTransfer(vault, totalWithdrawn);
        }

        return results;
    }

    // ============================================================================
    // INTERNAL FUNCTIONS - CALL FORWARDING
    // ============================================================================

    /**
     * @notice Execute standard deposit call: IAdapter.deposit(uint256)
     * @param adapter Adapter address
     * @param amount Amount to deposit
     * @return result Execution result with decoded shares
     */
    function _executeStandardDeposit(address adapter, uint256 amount)
        internal
        returns (ExecutionResult memory result)
    {
        // Approve adapter
        ASSET.forceApprove(adapter, amount);

        // Encode calldata: deposit(uint256)
        bytes memory callData = abi.encodeWithSignature("deposit(uint256)", amount);

        // Execute low-level call
        (bool success, bytes memory returnData) = adapter.call(callData);

        // Reset approval
        ASSET.forceApprove(adapter, 0);

        // Decode result
        uint256 shares = 0;
        if (success && returnData.length >= 32) {
            shares = abi.decode(returnData, (uint256));
        }

        return ExecutionResult({
            success: success,
            returnData: returnData,
            shares: shares
        });
    }

    /**
     * @notice Execute standard withdraw call: IAdapter.withdraw(uint256)
     * @param adapter Adapter address
     * @param amount Amount to withdraw
     * @return result Execution result with decoded amount
     */
    function _executeStandardWithdraw(address adapter, uint256 amount)
        internal
        returns (ExecutionResult memory result)
    {
        // Encode calldata: withdraw(uint256)
        bytes memory callData = abi.encodeWithSignature("withdraw(uint256)", amount);

        // Execute low-level call
        (bool success, bytes memory returnData) = adapter.call(callData);

        // Decode result
        uint256 withdrawn = 0;
        if (success && returnData.length >= 32) {
            withdrawn = abi.decode(returnData, (uint256));
        }

        return ExecutionResult({
            success: success,
            returnData: returnData,
            shares: withdrawn
        });
    }

    /**
     * @notice Execute custom call with provided calldata
     * @param adapter Adapter address
     * @param amount Amount for approval (if needed)
     * @param callData Custom encoded calldata
     * @return result Execution result
     * @dev Caller is responsible for proper calldata encoding
     */
    function _executeCustomCall(
        address adapter,
        uint256 amount,
        bytes memory callData
    )
        internal
        returns (ExecutionResult memory result)
    {
        // Approve if amount > 0 (for deposit-like operations)
        if (amount > 0) {
            ASSET.forceApprove(adapter, amount);
        }

        // Execute low-level call with provided calldata
        (bool success, bytes memory returnData) = adapter.call(callData);

        // Reset approval
        if (amount > 0) {
            ASSET.forceApprove(adapter, 0);
        }

        // Try to decode uint256 result if available
        uint256 shares = 0;
        if (success && returnData.length >= 32) {
            shares = abi.decode(returnData, (uint256));
        }

        return ExecutionResult({
            success: success,
            returnData: returnData,
            shares: shares
        });
    }

    // ============================================================================
    // VIEW FUNCTIONS
    // ============================================================================

    /**
     * @notice Preview deposit distribution across adapters
     * @param adapters Adapter addresses
     * @param ratios Allocation ratios
     * @param totalAmount Total amount to deposit
     * @return amounts Array of amounts per adapter
     */
    function previewDepositDistribution(
        address[] calldata adapters,
        uint16[] calldata ratios,
        uint256 totalAmount
    )
        external
        pure
        returns (uint256[] memory amounts)
    {
        require(adapters.length == ratios.length, "Length mismatch");

        amounts = new uint256[](adapters.length);
        uint256 remaining = totalAmount;

        for (uint256 i = 0; i < adapters.length; i++) {
            if (i == adapters.length - 1) {
                amounts[i] = remaining;
            } else {
                amounts[i] = (totalAmount * ratios[i]) / TOTAL_BPS;
                remaining -= amounts[i];
            }
        }

        return amounts;
    }

    /**
     * @notice Encode standard deposit calldata
     * @param amount Amount to deposit
     * @return Encoded calldata for IAdapter.deposit(uint256)
     */
    function encodeDepositCalldata(uint256 amount)
        external
        pure
        returns (bytes memory)
    {
        return abi.encodeWithSignature("deposit(uint256)", amount);
    }

    /**
     * @notice Encode standard withdraw calldata
     * @param amount Amount to withdraw
     * @return Encoded calldata for IAdapter.withdraw(uint256)
     */
    function encodeWithdrawCalldata(uint256 amount)
        external
        pure
        returns (bytes memory)
    {
        return abi.encodeWithSignature("withdraw(uint256)", amount);
    }
}
