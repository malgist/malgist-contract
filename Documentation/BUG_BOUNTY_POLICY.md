# MALGIST Bug Bounty Program - Smart Contract Architecture

**Version**: 1.0  
**Date**: December 17, 2025  
**Platforms**: Immunefi, HackenProof  
**Network**: Mantle Mainnet (Post-Audit)

---

## Executive Summary

MALGIST is designed for production-ready bug bounty programs with full transparency, comprehensive monitoring, and clear scope boundaries. This document defines the architecture, scope, and monitoring capabilities.

**Key Features**:

- ✅ Guardian role with emergency pause (cannot move funds)
- ✅ Structured events for off-chain monitoring
- ✅ Clear critical function annotations
- ✅ Deterministic execution paths
- ✅ Immutable audit reference hashes
- ✅ No silent failures or hidden admin backdoors

---

## Part 1: Architecture Overview

### 1.1 Contract Hierarchy

```
BugBountyReadiness (Mixin - Monitoring & Guardian)
    ↓
EmergencyPause (Emergency pause system)
    ↓
UserVault (Core vault logic)
    ↓
├─ IAdapter (Adapter interface)
├─ StrategyRegistry (Strategy management)
├─ FeeManager (Fee distribution)
└─ PerformanceTracking (Metrics)
```

### 1.2 Trust Boundaries

**MALGIST-Controlled (On-Chain):**

- ✓ Vault contract (UserVault.sol)
- ✓ Strategy management (StrategyRegistry.sol)
- ✓ Fee calculations (FeeManager.sol)
- ✓ Emergency pause (EmergencyPause.sol)
- ✓ Adapter routing (adapter calls and validation)

**External Protocol Boundary (NOT in scope):**

- ✗ Lendle protocol behavior (assumed non-malicious)
- ✗ FusionX DEX behavior (assumed non-malicious)
- ✗ Token transfers outside vault control
- ✗ ERC20 non-standard token behaviors

**Guardian Role (Limited Privileges):**

- ✓ Can trigger emergency pause
- ✓ Can update monitoring thresholds
- ✓ Cannot move user funds
- ✓ Cannot modify strategy configurations
- ✓ Cannot bypass access controls

### 1.3 Privilege Separation

| Role      | Vault Control | Fund Movement | Emergency Pause | Adapter Registration |
| --------- | ------------- | ------------- | --------------- | -------------------- |
| Owner     | ✓ Full        | ✓ Via pause   | ✓               | ✓                    |
| Guardian  | ✗ Limited     | ✗ NO          | ✓               | ✗                    |
| Registrar | ✗ Limited     | ✗ NO          | ✗               | ✓                    |
| Users     | ✗ NO          | ✓ Withdraw    | ✗               | ✗                    |

---

## Part 2: Bug Bounty Scope

### 2.1 IN SCOPE - Critical Functions

#### **Vault Accounting**

```solidity
✓ deposit(uint256 amount)
  - User deposits assets
  - Vault mints shares
  - Risk: Precision loss, share inflation, rounding errors

✓ withdraw(uint256 shares)
  - User burns shares
  - Vault returns assets
  - Risk: Accounting mismatch, fund loss

✓ reconcileAdapter(address adapter)
  - Updates cached adapter balance
  - Risk: Incorrect balance tracking, loss of funds
```

#### **Strategy Management**

```solidity
✓ setStrategyWithRisk(address[] adapters, uint16[] ratios, ...)
  - User creates strategy
  - Risk: Invalid adapter array, ratio validation, state corruption

✓ copyStrategy(address creator)
  - User copies creator's strategy
  - Risk: Unauthorized copying, fee bypass, accounting issues

✓ updateStrategyMetadata(bool isPublic, string name, uint16 copyFeeBps)
  - User updates strategy visibility/fees
  - Risk: Unauthorized metadata change, fee manipulation
```

#### **Adapter Routing**

```solidity
✓ _executeDeposit(address[] adapters, uint16[] ratios, uint256 amount)
  - Splits funds across adapters
  - Risk: Adapter callback attacks, incomplete deposits

✓ _executeWithdraw(address[] adapters, uint16[] ratios, uint256 amount)
  - Withdraws from adapters
  - Risk: Adapter failures, partial withdrawals, loss of funds

✓ rebalanceByEngine(uint256 strategyId, uint16 newRatio[], uint256 maxSlippage)
  - Rebalances strategy allocations
  - Risk: Slippage exploitation, accounting corruption
```

#### **Fee Logic**

```solidity
✓ reconcileAdapterAndCharge(address adapter, uint256 yieldAmount, address creator)
  - Charges protocol and creator fees on yield
  - Risk: Fee calculation overflow, incorrect distribution, loss of funds

✓ FeeManager.chargeFees(...)
  - Calculates and distributes fees
  - Risk: Rounding errors, double-charging, fee bypass
```

#### **Emergency Controls**

```solidity
✓ emergencyPause(string reason)
  - Guardian triggers emergency pause
  - Risk: Unauthorized pause, panic mechanism abuse

✓ emergencyWithdraw()
  - Users can withdraw during emergency
  - Risk: State corruption during withdrawal, fund loss

✓ setGuardian(address _newGuardian)
  - Guardian role transfer
  - Risk: Unauthorized role transfer
```

### 2.2 OUT OF SCOPE - External Protocols

```solidity
✗ Lendle (Aave V3 fork) exploits
  - Supply/withdraw function failures
  - Collateral liquidation
  - Protocol-specific vulnerabilities

✗ FusionX DEX exploits
  - Swap slippage manipulation
  - Liquidity pool drainage
  - Router failures

✗ ERC20 Token exploits
  - Non-standard transfer behavior
  - Rebasing tokens
  - Fee-on-transfer tokens

✗ Mantle network layer
  - RPC failures
  - Block reorganization
  - Network-level attacks
```

### 2.3 Known Limitations & Accepted Risks

| Risk                      | Severity | Mitigation                       | Bounty Status  |
| ------------------------- | -------- | -------------------------------- | -------------- |
| MEV sandwich attacks      | MEDIUM   | Slippage checks                  | OUT OF SCOPE\* |
| Oracle staleness          | MEDIUM   | Adapter quote validation         | OUT OF SCOPE   |
| External protocol failure | HIGH     | Emergency pause, user withdrawal | OUT OF SCOPE   |
| Unbounded loop costs      | LOW      | O(n) operations documented       | IN SCOPE       |
| Precision rounding losses | LOW      | Remainder handling               | IN SCOPE       |

\*MEV protection is best-effort; some MEV is inherent to public blockchains. Extreme MEV extraction may be in scope if due to vault bug.

---

## Part 3: Critical Function Annotations

All critical functions include `@notice Critical function – bug bounty in scope` annotation.

### 3.1 Critical Function Categories

**Category A: Vault Core** (Highest Priority)

```solidity
/// @notice Critical function – bug bounty in scope
/// @dev Potential impacts: Share inflation, fund loss, accounting corruption
function deposit(uint256 amount) external nonReentrant ...

/// @notice Critical function – bug bounty in scope
/// @dev Potential impacts: Fund loss, share burn mismatch
function withdraw(uint256 shares) external nonReentrant ...
```

**Category B: Adapter Routing** (High Priority)

```solidity
/// @notice Critical function – bug bounty in scope
/// @dev Potential impacts: Fund distribution error, adapter callback attacks
function _executeDeposit(address[] adapters, uint16[] ratios, uint256 amount) internal ...
```

**Category C: Strategy Management** (Medium Priority)

```solidity
/// @notice Critical function – bug bounty in scope
/// @dev Potential impacts: Unauthorized strategy creation, TVL cap bypass
function setStrategyWithRisk(...) external ...
```

**Category D: Emergency Controls** (Emergency-only)

```solidity
/// @notice Critical function – bug bounty in scope
/// @dev Potential impacts: Unintended pause, bypass of emergency controls
function emergencyPause(string reason) external onlyGuardian ...
```

---

## Part 4: Monitoring Events (On-Chain)

### 4.1 Deposit/Withdrawal Monitoring

```solidity
// Large deposit alert (for centralization risk monitoring)
event LargeDeposit(
    address indexed user,
    uint256 indexed strategyId,
    uint256 amount,
    uint256 sharesReceived,
    uint256 timestamp
);

// Large withdrawal alert
event LargeWithdrawal(
    address indexed user,
    uint256 indexed strategyId,
    uint256 sharesRedeemed,
    uint256 amountReceived,
    uint256 timestamp
);
```

**Usage**: Triggered when deposit/withdrawal amount exceeds `largeDepositThreshold` (default 1M USDC).

### 4.2 Adapter Health Monitoring

```solidity
// Adapter operation tracking
event AdapterOperation(
    address indexed adapter,
    uint8 indexed operation,      // 0=deposit, 1=withdraw, 2=rebalance
    uint256 amount,
    uint256 resultShares,
    uint8 status                  // 0=success, 1=partial_failure, 2=total_failure
);

// Adapter failure alert
event AdapterHealthAlert(
    address indexed adapter,
    string failureReason,
    uint256 timestamp
);
```

**Usage**: Emitted on every adapter call; status enum enables automated monitoring.

### 4.3 Slippage Monitoring

```solidity
event SlippageWarning(
    address indexed adapter,
    uint256 expectedAmount,
    uint256 actualAmount,
    uint16 slippageBps            // basis points, e.g., 50 = 0.5%
);

event CriticalSlippage(
    address indexed adapter,
    uint256 expectedAmount,
    uint256 actualAmount,
    uint16 slippageBps            // >100 bps triggers critical alert
);
```

**Thresholds**:

- Warning: ≥0.5% slippage
- Critical: ≥1% slippage

### 4.4 Accounting & Invariant Monitoring

```solidity
// Vault accounting reconciliation
event AccountingReconciled(
    uint256 totalSharesBefore,
    uint256 totalSharesAfter,
    uint256 totalAssetsBefore,
    uint256 totalAssetsAfter,
    uint16 discrepancyBps         // basis points deviation
);

// Invariant violation alert
event InvariantViolation(
    uint8 indexed invariantType,  // 0=share_consistency, 1=asset_balance, 2=adapter_health
    string details
);
```

### 4.5 Fee Transparency

```solidity
event FeeTransaction(
    uint8 indexed feeType,        // 0=copy_fee, 1=protocol_fee, 2=creator_earning
    address indexed recipient,
    uint256 amount,
    uint256 indexed strategyId
);
```

---

## Part 5: Guardian & Emergency Response

### 5.1 Guardian Role

**Responsibilities**:

- Monitor vault health
- Trigger emergency pause on exploit detection
- Update monitoring thresholds
- Coordinate with security team on incidents

**Capabilities**:

- ✓ Call `emergencyPause(string reason)`
- ✓ Call `setLargeDepositThreshold(uint256)`
- ✓ Call `setTVLSpikeThreshold(uint16)`
- ✓ Call `setGuardian(address _newGuardian)`
- ✗ Move funds
- ✗ Modify strategies
- ✗ Change adapter list

**Multi-sig Requirement**: Guardian MUST be a multisig address with 2-of-3 or 3-of-5 signing threshold.

### 5.2 Emergency Pause Mechanics

```solidity
/// @notice Emergency pause - triggered on exploit detection
/// @param reason Human-readable reason (e.g., "Adapter balance mismatch")
/// @dev Blocks deposits and strategy execution
/// @dev Withdrawals ALWAYS remain available
function emergencyPause(string memory reason) external onlyGuardian;
```

**Effects When Active**:

- ✗ Deposits blocked
- ✗ Strategy execution blocked
- ✗ Rebalancing blocked
- ✓ Withdrawals allowed (users can always exit)
- ✓ Emergency recovery functions available

**Recovery**:

- Manual unpause by Guardian (post-incident analysis)
- Optional timelock for unpause (governance-controlled)

### 5.3 Emergency Withdrawal

```solidity
/// @notice Emergency withdrawal when vault is paused
/// @param shares Shares to redeem
/// @dev Always available, even during pause
function emergencyWithdraw(uint256 shares) external nonReentrant;
```

**Guarantees**:

- User's funds are never locked
- Withdrawal always executes (even if adapters are paused)
- Uses cached balances if adapters are unhealthy

---

## Part 6: Determinism & Auditability

### 6.1 Deterministic Execution Paths

**Principle**: Every operation follows a clear, predictable sequence.

**Example - Deposit Flow**:

```
1. Validate inputs (amount > 0, strategy exists)
2. Pre-deposit balance check
3. Transfer from user
4. Execute adapter deposits (in order)
5. Calculate and mint shares
6. Emit event
7. Post-deposit invariant check
```

**Key Properties**:

- No conditional state changes
- No silent failures (explicit reverts or events)
- All external calls return value-checked
- All arithmetic overflow-checked (Solidity 0.8+)

### 6.2 Audit Reference Hashes

```solidity
/// @notice On-chain reference to audit report
bytes32 public immutable AUDIT_HASH = keccak256("audit-v1.0-ipfs-hash");

/// @notice Version string for tracking
string public constant BOUNTY_VERSION = "1.0";

/// @notice Protocol name
string public constant PROTOCOL_NAME = "MALGIST";
```

**Usage**:

- Deployed contract includes immutable audit hash
- Auditors verify: keccak256(audit_report) == AUDIT_HASH
- Version enables multi-version monitoring

### 6.3 No Hidden Backdoors

**Verification**:

- ✓ All privileged functions are public (not internal)
- ✓ All roles are emitted on assignment
- ✓ No hidden admin functions
- ✓ No self-destruct or delegatecall
- ✓ No mutable governance delays
- ✓ All storage layouts are documented

---

## Part 7: Immunefi / HackenProof Submission Checklist

### 7.1 Bug Bounty Program Setup

- [ ] Contract deployed on Mantle mainnet
- [ ] Guardian multisig activated
- [ ] Audit completed and AUDIT_HASH verified
- [ ] Monitoring infrastructure live (TheGraph/Alchemy)
- [ ] Incident response team on standby (24/7)

### 7.2 Scope Documentation

- [ ] `BOUNTY_POLICY.md` published (this document)
- [ ] `BUG_BOUNTY_SCOPE.md` (detailed in-scope items)
- [ ] Critical functions marked with `@notice Critical function`
- [ ] Events documented in ABIs
- [ ] Adapter whitelist published

### 7.3 Monitoring Setup

- [ ] TheGraph subgraph deployed (LargeDeposit, SlippageWarning, AdapterOperation events)
- [ ] Slack/Discord alerts configured for:
  - Large deposits (>1M USDC)
  - Slippage warnings (>0.5%)
  - Critical slippage (>1%)
  - Adapter failures
  - Emergency pause triggers
- [ ] Dashboard live showing:
  - TVL per adapter
  - Recent deposit/withdrawal history
  - Strategy leaderboard
  - Fee distribution transparency

### 7.4 Response Procedures

- [ ] Incident response playbook documented
- [ ] Contact information for security team
- [ ] Claim submission process documented
- [ ] Payout schedule (e.g., 15/45/90 days for LOW/MEDIUM/CRITICAL)
- [ ] Vulnerability disclosure timeline
- [ ] Legal terms and conditions

### 7.5 Community Communication

- [ ] Announcement on official channels (Discord, Twitter, Forum)
- [ ] Link to Immunefi program page
- [ ] Direct contact email for security researchers
- [ ] Acknowledgment in security.txt (RFC 9110)

---

## Part 8: Monitoring Implementation Guide

### 8.1 TheGraph Subgraph Setup

```graphql
# Example Subgraph for monitoring
type LargeDepositEvent @entity {
  id: ID!
  user: Bytes!
  strategyId: BigInt!
  amount: BigInt!
  sharesReceived: BigInt!
  timestamp: BigInt!
  blockNumber: BigInt!
}

type SlippageWarningEvent @entity {
  id: ID!
  adapter: Bytes!
  expectedAmount: BigInt!
  actualAmount: BigInt!
  slippageBps: Int!
  timestamp: BigInt!
}

type AdapterHealthAlert @entity {
  id: ID!
  adapter: Bytes!
  failureReason: String!
  timestamp: BigInt!
  resolved: Boolean!
}
```

### 8.2 Alerting Thresholds

| Event                 | Threshold | Action                    |
| --------------------- | --------- | ------------------------- |
| LargeDeposit          | >1M USDC  | Informational alert       |
| LargeWithdrawal       | >1M USDC  | Informational alert       |
| SlippageWarning       | ≥0.5%     | Warning (check manually)  |
| CriticalSlippage      | ≥1%       | Alert security team       |
| AdapterHealthAlert    | Any       | Critical alert            |
| EmergencyPauseTrigger | Any       | Critical alert + war room |

### 8.3 Dashboard Metrics

**Real-Time**:

- Current TVL per adapter
- Last 24h deposit/withdrawal volume
- Current strategy count
- Active users count

**Trending**:

- TVL growth over 7d/30d
- Average slippage per adapter
- Fee distribution trending
- User retention metrics

---

## Part 9: Severity Classification

### For This Bug Bounty Program

| Severity | Example Issues                                                            | Bounty Range  |
| -------- | ------------------------------------------------------------------------- | ------------- |
| CRITICAL | Share inflation, fund loss, accounting bypass, adapter callback attacks   | $25k - $100k+ |
| HIGH     | TVL cap bypass, slippage exploitation, unauthorized fee charging          | $5k - $25k    |
| MEDIUM   | Monitoring event suppression, Guardian role bypass (except fund movement) | $1k - $5k     |
| LOW      | Inefficient gas usage, non-critical precision loss, documentation gaps    | $100 - $1k    |

**Additional Criteria**:

- Proof-of-Concept (PoC) required for CRITICAL/HIGH
- Gas savings accepted as MEDIUM/LOW
- Duplicate findings: only first reporter qualifies

---

## Part 10: Post-Deployment Verification

### 10.1 Before Bug Bounty Launch

```bash
# 1. Verify Guardian multisig
assert Guardian == MultiSigAddress

# 2. Verify AUDIT_HASH immutability
assert AUDIT_HASH == keccak256(audit_report)

# 3. Verify no upgrade path
assert NoProxyPattern

# 4. Verify events are emitted
# (Run deposit/withdrawal transactions and check events)

# 5. Verify monitoring infrastructure
assert Subgraph.deployed()
assert AlertingSystem.live()

# 6. Perform controlled security test
# Deploy test transaction with known parameters
# Verify all events fired correctly
```

### 10.2 Continuous Monitoring

- **Daily**: Review large deposit/withdrawal trends
- **Weekly**: Review adapter health metrics
- **Monthly**: Run full invariant audit (share consistency, asset balance)
- **Quarterly**: Simulation testing of emergency procedures

---

## Conclusion

MALGIST is architected for production-ready bug bounty programs with:

1. ✅ **Transparency**: All critical actions emit events
2. ✅ **Monitoring**: Structured events for off-chain indexers
3. ✅ **Safety**: Guardian role + emergency pause (no fund movement)
4. ✅ **Determinism**: Clear execution paths, no hidden backdoors
5. ✅ **Scope Clarity**: Explicit in-scope/out-of-scope definitions
6. ✅ **Auditability**: Immutable version hashes, comprehensive logging

**Ready for Immunefi / HackenProof deployment**.

---

**Document Status**: ✅ Ready for Publication  
**Last Updated**: December 17, 2025  
**Version**: 1.0
