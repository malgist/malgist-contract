// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title BugBountyReadiness
 * @notice Mixin contract providing comprehensive monitoring and transparency for bug bounty programs
 * @dev Implements monitoring hooks, Guardian role, and structured event emission for Immunefi / HackenProof
 *
 * DESIGN PRINCIPLES:
 * - No silent failures: all failures emit explicit events
 * - Complete transparency: all state-changing actions are logged
 * - Guardian separation: Guardian can trigger emergencyPause, but cannot move funds
 * - Deterministic: all operations follow clear, auditable paths
 * - Version-locked: immutable version hash for on-chain audit reference
 *
 * BUG BOUNTY SCOPE:
 * ✓ IN SCOPE: Vault accounting, adapter routing, strategy configuration, fee logic, slippage protections
 * ✗ OUT OF SCOPE: External protocol exploits, oracle manipulation, ERC20 non-standard behavior
 */

/**
 * @notice Structured monitoring events for off-chain indexers
 * @dev These events are designed to be machine-parseable by automated monitoring systems
 */
interface IBugBountyEvents {
    // ============ CRITICAL FUNCTION EVENTS ============

    /// @notice Emitted when critical function is called - indexed for fast filtering
    /// @param functionSelector keccak256 hash of function signature
    /// @param caller Address that invoked the function
    /// @param timestamp Block timestamp
    event CriticalFunctionCalled(
        bytes4 indexed functionSelector,
        address indexed caller,
        uint256 indexed strategyId,
        uint256 timestamp
    );

    // ============ DEPOSIT/WITHDRAWAL EVENTS ============

    /// @notice Emitted for large deposits (>threshold) to trigger monitoring alerts
    /// @param user User depositing
    /// @param strategyId Strategy receiving deposit
    /// @param amount Deposit amount in base tokens
    /// @param sharesReceived Shares minted
    /// @param timestamp Block timestamp
    event LargeDeposit(
        address indexed user,
        uint256 indexed strategyId,
        uint256 amount,
        uint256 sharesReceived,
        uint256 timestamp
    );

    /// @notice Emitted for large withdrawals (>threshold)
    /// @param user User withdrawing
    /// @param strategyId Strategy being withdrawn from
    /// @param sharesRedeemed Shares burned
    /// @param amountReceived Assets returned
    /// @param timestamp Block timestamp
    event LargeWithdrawal(
        address indexed user,
        uint256 indexed strategyId,
        uint256 sharesRedeemed,
        uint256 amountReceived,
        uint256 timestamp
    );

    // ============ ADAPTER & STRATEGY EVENTS ============

    /// @notice Emitted when adapter is called (deposit/withdraw/rebalance)
    /// @param adapter Adapter address
    /// @param operation Operation type: 0=deposit, 1=withdraw, 2=rebalance
    /// @param amount Operation amount
    /// @param resultShares Shares returned or amount withdrawn
    /// @param status Status: 0=success, 1=partial_failure, 2=total_failure
    event AdapterOperation(
        address indexed adapter,
        uint8 indexed operation,
        uint256 amount,
        uint256 resultShares,
        uint8 status
    );

    /// @notice Emitted on strategy TVL spike (>20% change in single block)
    /// @param strategyId Strategy ID
    /// @param oldTVL Previous TVL
    /// @param newTVL Current TVL
    /// @param percentageChange (newTVL - oldTVL) * 10000 / oldTVL
    event StrategyTVLSpike(
        uint256 indexed strategyId,
        uint256 oldTVL,
        uint256 newTVL,
        int256 percentageChange
    );

    // ============ SLIPPAGE & MEV EVENTS ============

    /// @notice Emitted when slippage exceeds warning threshold (>0.5%)
    /// @param adapter Adapter experiencing slippage
    /// @param expectedAmount Expected amount out
    /// @param actualAmount Actual amount received
    /// @param slippageBps Slippage in basis points
    event SlippageWarning(
        address indexed adapter,
        uint256 expectedAmount,
        uint256 actualAmount,
        uint16 slippageBps
    );

    /// @notice Emitted when slippage exceeds critical threshold (>1%)
    /// @param adapter Adapter
    /// @param expectedAmount Expected amount
    /// @param actualAmount Actual amount
    /// @param slippageBps Slippage in basis points (>100)
    event CriticalSlippage(
        address indexed adapter,
        uint256 expectedAmount,
        uint256 actualAmount,
        uint16 slippageBps
    );

    // ============ FEE & ACCOUNTING EVENTS ============

    /// @notice Emitted on all fee transactions (for transparency)
    /// @param feeType Type: 0=copy_fee, 1=protocol_fee, 2=creator_earning
    /// @param recipient Fee recipient
    /// @param amount Fee amount
    /// @param strategyId Related strategy
    event FeeTransaction(
        uint8 indexed feeType,
        address indexed recipient,
        uint256 amount,
        uint256 indexed strategyId
    );

    /// @notice Emitted when vault accounting is reconciled
    /// @param totalSharesBefore Total shares before reconciliation
    /// @param totalSharesAfter Total shares after
    /// @param totalAssetsBefore Cached assets before
    /// @param totalAssetsAfter Cached assets after
    /// @param discrepancyBps Discrepancy in basis points
    event AccountingReconciled(
        uint256 totalSharesBefore,
        uint256 totalSharesAfter,
        uint256 totalAssetsBefore,
        uint256 totalAssetsAfter,
        uint16 discrepancyBps
    );

    // ============ EMERGENCY & SECURITY EVENTS ============

    /// @notice Emitted when emergency pause is triggered
    /// @param guardian Address triggering pause
    /// @param reason Human-readable reason
    /// @param timestamp Block timestamp
    event EmergencyPauseTrigger(address indexed guardian, string reason, uint256 timestamp);

    /// @notice Emitted when emergency pause is lifted
    /// @param guardian Address lifting pause
    /// @param duration Time pause was active
    event EmergencyPauseLifted(address indexed guardian, uint256 duration);

    /// @notice Emitted when adapter fails or becomes unhealthy
    /// @param adapter Adapter address
    /// @param failureReason Reason for failure
    /// @param timestamp Block timestamp
    event AdapterHealthAlert(address indexed adapter, string failureReason, uint256 timestamp);

    /// @notice Emitted on invariant violation detection
    /// @param invariantType Type of invariant: 0=share_consistency, 1=asset_balance, 2=adapter_health
    /// @param details Description of violation
    event InvariantViolation(uint8 indexed invariantType, string details);
}

/**
 * @notice Role-based access control for bug bounty readiness
 */
interface IBugBountyRoles {
    /// @notice Emitted when Guardian role is set
    event GuardianSet(address indexed newGuardian, address indexed oldGuardian);

    /// @notice Emitted when Registrar role is set
    event RegistrarSet(address indexed newRegistrar, address indexed oldRegistrar);

    /// @notice Emitted when role is transferred
    event RoleTransferred(string indexed roleName, address indexed oldAddress, address indexed newAddress);
}

/**
 * @notice Abstract base contract for bug bounty readiness
 * @dev Contracts should inherit from this to enable full monitoring and Guardian capabilities
 */
abstract contract BugBountyReadiness is IBugBountyEvents, IBugBountyRoles {
    // ============ CONSTANTS ============

    /// @notice Current bug bounty contract version (immutable for audit reference)
    string public constant BOUNTY_VERSION = "1.0";

    /// @notice On-chain audit hash (keccak256 of audit report)
    bytes32 public immutable AUDIT_HASH;

    /// @notice Protocol name for identification
    string public constant PROTOCOL_NAME = "MALGIST";

    // ============ ROLES ============

    /// @notice Guardian role - can trigger emergency pause but NOT move funds
    /// @dev Should be a multisig address in production
    address public guardian;

    /// @notice Registrar role - can register new adapters
    /// @dev Should be governance-controlled
    address public registrar;

    // ============ MONITORING THRESHOLDS ============

    /// @notice TVL threshold for large deposit alert (in base tokens)
    uint256 public largeDepositThreshold = 1_000_000e6; // 1M USDC

    /// @notice TVL threshold for large withdrawal alert
    uint256 public largeWithdrawalThreshold = 1_000_000e6; // 1M USDC

    /// @notice TVL spike percentage threshold (basis points)
    uint16 public tvlSpikeThreshold = 2000; // 20%

    /// @notice Slippage warning threshold (basis points)
    uint16 public slippageWarningBps = 50; // 0.5%

    /// @notice Critical slippage threshold (basis points)
    uint16 public criticalSlippageBps = 100; // 1%

    /// @notice Accounting discrepancy threshold (basis points)
    uint16 public maxDiscrepancyBps = 10; // 0.1%

    // ============ CONSTRUCTOR ============

    /**
     * @notice Initialize bug bounty readiness
     * @param _guardian Guardian address (multisig recommended)
     * @param _registrar Registrar address (governance recommended)
     * @param _auditHash Keccak256 hash of audit report
     */
    constructor(address _guardian, address _registrar, bytes32 _auditHash) {
        require(_guardian != address(0), "Guardian cannot be zero");
        require(_registrar != address(0), "Registrar cannot be zero");

        guardian = _guardian;
        registrar = _registrar;
        AUDIT_HASH = _auditHash;

        emit GuardianSet(_guardian, address(0));
        emit RegistrarSet(_registrar, address(0));
    }

    // ============ GUARDIAN MANAGEMENT ============

    /**
     * @notice Set new guardian address
     * @dev Only current guardian can transfer role
     * @param _newGuardian New guardian address
     *
     * @notice Critical function – bug bounty in scope
     */
    function setGuardian(address _newGuardian) external {
        require(msg.sender == guardian, "Only guardian can set new guardian");
        require(_newGuardian != address(0), "Guardian cannot be zero");

        address _oldGuardian = guardian;
        guardian = _newGuardian;

        emit GuardianSet(_newGuardian, _oldGuardian);
        emit RoleTransferred("GUARDIAN", _oldGuardian, _newGuardian);
    }

    /**
     * @notice Set new registrar address
     * @dev Only current registrar can transfer role (or owner)
     * @param _newRegistrar New registrar address
     *
     * @notice Critical function – bug bounty in scope
     */
    function setRegistrar(address _newRegistrar) external {
        require(msg.sender == registrar, "Only registrar can set new registrar");
        require(_newRegistrar != address(0), "Registrar cannot be zero");

        address _oldRegistrar = registrar;
        registrar = _newRegistrar;

        emit RegistrarSet(_newRegistrar, _oldRegistrar);
        emit RoleTransferred("REGISTRAR", _oldRegistrar, _newRegistrar);
    }

    // ============ MONITORING THRESHOLD CONFIGURATION ============

    /**
     * @notice Update large deposit alert threshold
     * @param _newThreshold New threshold in base tokens
     */
    function setLargeDepositThreshold(uint256 _newThreshold) external onlyGuardian {
        require(_newThreshold > 0, "Threshold must be positive");
        largeDepositThreshold = _newThreshold;
    }

    /**
     * @notice Update TVL spike detection threshold
     * @param _newThresholdBps New threshold in basis points (e.g., 2000 = 20%)
     */
    function setTVLSpikeThreshold(uint16 _newThresholdBps) external onlyGuardian {
        require(_newThresholdBps > 0 && _newThresholdBps <= 10000, "Invalid threshold");
        tvlSpikeThreshold = _newThresholdBps;
    }

    /**
     * @notice Update slippage warning threshold
     * @param _newThresholdBps New threshold in basis points
     */
    function setSlippageWarningThreshold(uint16 _newThresholdBps) external onlyGuardian {
        require(_newThresholdBps < criticalSlippageBps, "Must be less than critical threshold");
        slippageWarningBps = _newThresholdBps;
    }

    // ============ HELPER MODIFIERS ============

    /// @notice Modifier to restrict function to guardian only
    modifier onlyGuardian() {
        require(msg.sender == guardian, "Only guardian");
        _;
    }

    /// @notice Modifier to restrict function to registrar only
    modifier onlyRegistrar() {
        require(msg.sender == registrar, "Only registrar");
        _;
    }

    // ============ INTERNAL MONITORING HELPERS ============

    /**
     * @notice Check if deposit amount exceeds large deposit threshold
     * @param amount Deposit amount
     * @return true if amount exceeds threshold
     */
    function _isLargeDeposit(uint256 amount) internal view returns (bool) {
        return amount >= largeDepositThreshold;
    }

    /**
     * @notice Check if withdrawal amount exceeds large withdrawal threshold
     * @param amount Withdrawal amount
     * @return true if amount exceeds threshold
     */
    function _isLargeWithdrawal(uint256 amount) internal view returns (bool) {
        return amount >= largeWithdrawalThreshold;
    }

    /**
     * @notice Calculate percentage change in basis points
     * @param oldValue Previous value
     * @param newValue Current value
     * @return percentageChangeBps Change in basis points (can be negative)
     */
    function _calculatePercentageChange(uint256 oldValue, uint256 newValue)
        internal
        pure
        returns (int256 percentageChangeBps)
    {
        if (oldValue == 0) return int256((newValue > 0) ? 10000 : 0);
        int256 change = int256(newValue) - int256(oldValue);
        percentageChangeBps = (change * 10000) / int256(oldValue);
    }

    /**
     * @notice Calculate slippage in basis points
     * @param expectedAmount Expected amount out
     * @param actualAmount Actual amount received
     * @return slippageBps Slippage in basis points
     */
    function _calculateSlippageBps(uint256 expectedAmount, uint256 actualAmount)
        internal
        pure
        returns (uint16 slippageBps)
    {
        if (expectedAmount == 0) return 0;
        if (actualAmount > expectedAmount) return 0; // No slippage if we got more

        uint256 slippageAmount = expectedAmount - actualAmount;
        slippageBps = uint16((slippageAmount * 10000) / expectedAmount);
    }

    /**
     * @notice Check if slippage is within acceptable range
     * @param expectedAmount Expected amount
     * @param actualAmount Actual amount
     * @return isWarning true if slippage is in warning range
     * @return isCritical true if slippage is critical
     */
    function _checkSlippage(uint256 expectedAmount, uint256 actualAmount)
        internal
        view
        returns (bool isWarning, bool isCritical)
    {
        uint16 slippageBps = _calculateSlippageBps(expectedAmount, actualAmount);

        if (slippageBps >= criticalSlippageBps) {
            isCritical = true;
        } else if (slippageBps >= slippageWarningBps) {
            isWarning = true;
        }
    }
}
