# MALGIST Audit Evidence Preparation Guide

**Version**: 1.0  
**Date**: December 17, 2025  
**Purpose**: Provide auditors with comprehensive technical documentation and analysis artifacts

---

## Section 1: Architecture & Design Documentation

### 1.1 Architecture Overview Document

**File**: `Documentation/ARCHITECTURE_DESIGN.md` (or equivalent)

**Must Include**:

1. **System Components**
   - UserVault: Core deposit/withdraw and strategy management
   - StrategyRegistry: Permissionless strategy creation + phase control
   - FeeManager: Fee calculation and distribution
   - EmergencyPause: Emergency pause mechanism
   - SlippageProtection: Slippage validation for swaps
   - Adapters: External protocol integration layer

2. **Data Flow Diagrams**
   ```
   User → Vault → Adapters → External Protocols
              ↓
        StrategyRegistry
   ```

3. **Component Interactions**
   - Vault → Registry: Strategy creation, version checks
   - Vault → Adapters: Deposit, withdraw, getBalance
   - Vault → FeeManager: Fee charging on yield
   - Vault → EmergencyPause: Pause state checks

4. **Deployment Architecture**
   - Contract addresses (placeholder for auditor review)
   - Proxy pattern (if used): UUPS, Transparent, or none
   - Ownership model: Single owner, multisig, timelock
   - Initialization sequence

5. **Call Sequences** (key user flows)
   ```
   DEPOSIT FLOW:
   1. User calls vault.deposit(amount)
   2. Vault transfers assets from user
   3. Vault splits funds across adapters (by ratio)
   4. Each adapter receives funds via IAdapter.deposit()
   5. Vault receives shares back from each adapter
   6. Vault mints shares for user
   7. Vault emits Deposited event

   STRATEGY CREATION:
   1. User calls vault.setStrategyWithRisk(adapters, ratios, ..., riskHash)
   2. Vault validates adapters, ratios sum, copyFee
   3. Vault calls registry.registerStrategy(strategyId, creator, riskLevel, riskHash)
   4. Registry enforces phase rules (Restricted→Limited→Permissionless)
   5. Registry checks per-creator limits, duplicate risk hashes
   6. Vault stores strategy config, emits StrategyCreated
   ```

---

### 1.2 Threat Model Document

**File**: `Documentation/THREAT_MODEL.md` (new, if needed)

**Content**:

```markdown
# MALGIST Threat Model

## External Threat Actors
1. **MEV Extractors**: Sandwich attacks, front-running deposits
2. **Social Engineers**: Trick users into copying risky strategies
3. **Rogue Adapter Operators**: Deploy malicious adapters to steal funds
4. **External Protocol Exploiters**: Exploit Aave/Lido/other protocols; drain adapter funds
5. **Governance Attackers**: Acquire governance tokens to change critical parameters

## Internal Threat Scenarios
1. **Reentrancy**: Recursive calls exploit state inconsistencies
2. **Precision Loss**: Rounding errors cause accounting mismatches
3. **Access Control Bypass**: Unguarded state modifications
4. **State Corruption**: Deposit/withdraw leaves vault in invalid state
5. **Sandwich Attacks**: MEV extraction during swap operations

## Mitigations Implemented
| Threat | Mitigation |
|--------|-----------|
| Reentrancy | ReentrancyGuard on all external state-changing functions |
| Precision Loss | Checked arithmetic, explicit remainder handling |
| Access Control | Owner-gated admin functions; role-based access (pause owner, registrar) |
| State Corruption | Invariant validation after each operation; reconciliation |
| Sandwich Attacks | Slippage checks (minAmountOut), deadline validation |

## Residual Risk (Accepted)
- **Adapter Counterparty Risk**: If external protocol fails, adapter funds at risk
- **Oracle Risk**: Adapter quotes are point-in-time; may be stale
- **MEV Residual**: Slippage checks mitigate but do not eliminate MEV
```

---

### 1.3 Trust Assumptions Document

**File**: `Documentation/TRUST_ASSUMPTIONS.md`

**Content**:

```markdown
# MALGIST Trust Assumptions

## Trusted Entities

### Owner / Governance
- Assumed to be **trusted** (multisig or timelock recommended)
- Responsibilities:
  - Register adapters
  - Manage phase transitions (Restricted → Limited → Permissionless)
  - Set protocol fees, TVL caps
  - Deploy emergency pause

### Pause Owner (Guardian)
- Assumed to be **trusted** (multisig or emergency multisig)
- Responsibilities:
  - Activate/deactivate emergency pause
  - Reconcile adapter balances

### Adapter Operators
- Assumed to be **trusted** (whitelist-only)
- Adapter code assumed to be **reviewed and non-malicious**
- But: May integrate with faulty external protocols

## External Untrusted Entities

### Users
- Assumed to be **economically rational** but not trusted with:
  - State modification (only vault owner can modify state)
  - Fund movement outside approved paths (only via deposit/withdraw)

### External Protocols (Aave, Lido, DEX, etc.)
- Assumed to be **non-malicious but may fail**:
  - May return fewer tokens than expected (revert on slippage)
  - May be exploited (external protocol hack)
  - May pause operations (upgrade, emergency)

### Off-Chain Actors (Bots, MEV Extractors)
- Assumed to be **adversarial**
- Mitigations: Slippage checks, deadline validation

## Implicit Trust on Standards Compliance

### ERC20 Compliance
- Assume all tokens implement ERC20 standard correctly
- **Known limitation**: Rebasing tokens, fee-on-transfer tokens will break vault accounting
- **Recommendation**: Whitelist token list explicitly; disable rebasing tokens

### Adapter Interface Compliance
- All adapters must implement IAdapter interface correctly
- Assume adapters return correct balance, handle deposits/withdrawals properly
- **Trust**: Adapter code reviewed by auditor + governance

---

## Failure Mode Analysis

### If Owner is Compromised
- Risk: Attacker can register malicious adapters, change parameters
- Mitigation: Timelock for critical changes; community governance override
- Recovery: Replace owner via governance vote

### If External Protocol is Exploited
- Risk: Funds in that adapter may be at risk
- Mitigation: Emergency pause to prevent further deposits
- Recovery: emergencyWithdraw() or direct adapter recovery

### If Adapter Code is Malicious
- Risk: Adapter can steal funds from vault
- Mitigation: Adapter whitelist-only; code review before registration
- Recovery: Remove adapter from strategies; user-initiated migration

```

---

## Section 2: Invariants & Specifications

### 2.1 Critical Invariants List

**File**: `Documentation/INVARIANTS.md`

**Must Include**:

```markdown
# MALGIST Critical Invariants

## Invariant 1: Total Shares Consistency
Property: totalShares == sum(userShares[user] for all users)
Validation Point: After every deposit/withdraw/transfer
Violation: Contract enters invalid state; vault is broken

## Invariant 2: Total Assets Lower Bound
Property: totalAssets >= sum(adapterCached[adapter] for all adapters)
Validation Point: After reconciliation
Violation: Vault insolvent; withdrawals may fail

## Invariant 3: Strategy Validity
Property: For each strategy: adapters.length == ratios.length > 0
           sum(ratios) == TOTAL_BPS (10000)
Validation Point: On setStrategy() call
Violation: Strategy execution produces undefined behavior

## Invariant 4: Adapter Balance Accuracy (Post-Reconciliation)
Property: adapterCached[adapter] == IAdapter(adapter).getBalance()
Validation Point: After reconcileAdapter() call
Violation: Vault accounting diverges from actual holdings

## Invariant 5: Pause Isolation
Property: If globalPause == true: deposits blocked, withdrawals allowed
           If adapterPaused[adapter] == true: only that adapter blocked
Validation Point: deposit() pre-check
Violation: User assets may be locked or accessible incorrectly

## Invariant 6: Phase Enforcement (Limited Phase)
Property: For strategies in Limited phase: totalDeposited[strategy] <= getLimitedCap(strategy)
Validation Point: deposit() enforcement
Violation: TVL cap bypassed; protocol risk exceeded

## Invariant 7: Fee Consistency
Property: creatorFee + protocolFee <= grossYield
Validation Point: FeeManager.chargeFees() calculation
Violation: User receives negative yield (rounding error)

## Invariant 8: Strategy Registry Integrity
Property: Each strategyId has at most one creator
           Duplicate riskDisclosureHash not allowed
           creatorStrategyCount[creator] <= maxStrategiesPerAddress
Validation Point: registerStrategy() call
Violation: Duplicate strategy registration or creator spam
```

---

### 2.2 Function Specification

**File**: `Documentation/FUNCTION_SPECIFICATIONS.md`

**Template**:

```markdown
## Function: UserVault.deposit(uint256 amount)

### Signature
external nonReentrant whenDepositsNotPaused returns (uint256 shares)

### Preconditions
- User has called ASSET.approve(address(vault), amount)
- amount > 0
- User has called setStrategy() at least once
- Global pause NOT active
- No adapter in user's strategy is paused
- User's adopted strategy version is NOT deprecated

### Postconditions
- User's share balance increased by `shares`
- totalShares increased by `shares`
- totalAssets increased by amount (net of copy fee)
- Vault's ASSET balance increased by amount
- Each adapter received proportional amount of assets
- Copy fee earned by original strategy creator (if applicable)
- Deposited event emitted

### Error Conditions
- InvalidAmount() if amount == 0
- NoStrategySet() if user has no strategy
- AdapterPausedError() if any adapter is paused
- DeprecatedStrategy() if strategy version is deprecated
- ExceedsLimitedTVL() if Limited phase cap exceeded
- DepositReturnedZero() if adapter returns 0 shares
- VaultPaused() if global pause active (EmergencyPause)

### Gas Efficiency Notes
- O(N) where N = number of adapters in strategy
- Caches adapter count to minimize SLOADs
- Uses unchecked increments in loop

### Reentrancy Protection
- ReentrancyGuard active; prevents recursive calls
- Checks-Effects-Interactions: All validation before transfers

### State Invariants Maintained
- totalShares == sum(userShares[user])
- totalAssets == sum(adapterCached[adapter])
- User shares always correspond to asset ownership
```

---

## Section 3: Automated Analysis Reports

### 3.1 Slither Static Analysis

**Command**:
```bash
slither . --json > slither-report.json
slither . --sarif > slither-report.sarif
```

**Deliverable**: 
- JSON output (machine-readable)
- SARIF output (IDE-compatible)
- HTML report (human-readable)

**Issues to Document**:
- [ ] No CRITICAL/HIGH issues
- [ ] All MEDIUM issues documented in severity tracker
- [ ] LOW/INFORMATIONAL issues prioritized

**Sample Output Section**:
```json
{
  "issues": [
    {
      "check_id": "reentrancy-eth",
      "impact": "HIGH",
      "confidence": "MEDIUM",
      "description": "...",
      "source": {"filename": "src/UserVault.sol", "start": 123}
    }
  ]
}
```

---

### 3.2 Coverage Report

**Command**:
```bash
forge coverage --report lcov --report html
```

**Deliverable**:
- `coverage/coverage.html` (browser-viewable)
- `coverage/coverage.lcov` (Codecov format)
- Summary statistics

**Target Metrics**:
- Line coverage: >= 85%
- Branch coverage: >= 80%
- Function coverage: >= 95%

**Sample Coverage Report**:
```
File                      | Stmts | Branch | Funcs | Lines |
--------------------------|-------|--------|-------|-------|
src/UserVault.sol         | 85%   | 78%    | 92%   | 86%   |
src/StrategyRegistry.sol  | 88%   | 82%    | 95%   | 89%   |
src/FeeManager.sol        | 92%   | 85%    | 100%  | 93%   |
TOTAL                     | 87%   | 81%    | 94%   | 87%   |
```

**Uncovered Code Identified**:
- [ ] Reason documented (e.g., "Error path that reverts")
- [ ] Non-critical paths marked as acceptable
- [ ] Critical paths require test case addition

---

### 3.3 Gas Benchmark Report

**Command**:
```bash
forge test --gas-report > gas-report.txt
forge test --gas-report --reporter json > gas-report.json
```

**Key Functions to Benchmark**:

| Function | Min Gas | Avg Gas | Max Gas | Purpose |
|----------|---------|---------|---------|---------|
| deposit | ~85k | ~350k | ~450k | User deposit (varies by adapter count) |
| withdraw | ~110k | ~135k | ~160k | User withdrawal |
| setStrategy | ~25k | ~250k | ~410k | Strategy setup (varies by adapter count) |
| registerStrategy | TBD | TBD | TBD | Strategy registration |

**Gas Optimizations Documented**:
- Storage packing reduces SLOAD costs
- Loop optimizations cache array lengths
- Custom errors instead of require strings
- Unchecked arithmetic where safe

---

### 3.4 Build Determinism Verification

**Command**:
```bash
forge build --verify
forge build --verify --build-info
shasum -a 256 out/UserVault.sol/UserVault.json
```

**Deliverable**:
- Build hash recorded: `[HASH]`
- Bytecode matches across clean builds
- Compiler version pinned: Solidity ^0.8.20

---

## Section 4: Test Documentation

### 4.1 Test Suite Overview

**File**: `test/TEST_DOCUMENTATION.md`

**Test Categories**:

```markdown
## Unit Tests (70% coverage)
- UserVault: deposit, withdraw, strategy setup, copy fee tracking
- StrategyRegistry: phase transitions, creator limits, duplicate detection
- FeeManager: fee calculation, distribution, authorization
- EmergencyPause: pause activation, isolation, emergency withdrawal

## Integration Tests (15% coverage)
- Full deposit → strategy → rebalance → withdraw flow
- Strategy copy → deposit → separate accounting
- Multi-adapter strategy execution
- Phase transitions and TVL cap enforcement

## Security Tests (10% coverage)
- Reentrancy detection (ReentrancyGuard validation)
- Access control verification
- Invariant violation tests (should revert)
- Slippage protection bypass attempts

## Fuzz Tests (5% coverage)
- Random deposit/withdraw sequences
- Random adapter configurations
- Random strategy parameters
- Edge case rounding error detection
```

---

### 4.2 Regression Test Specification

**Requirement**: Each audit finding must have a corresponding regression test

```markdown
## Regression Tests

### Test: test_no_reentrancy_on_deposit()
**Issue**: [If found] Reentrancy vulnerability in deposit
**Test Purpose**: Verify ReentrancyGuard blocks recursive calls
**Implementation**: Mock adapter that calls back into vault
**Expected**: Revert with reentrancy error

### Test: test_total_shares_invariant_after_deposit()
**Issue**: Total shares inconsistency
**Test Purpose**: Verify totalShares == sum(userShares) post-deposit
**Implementation**: Deposit from multiple users; check accounting
**Expected**: Invariant maintained

```

---

## Section 5: Pre-Audit Deliverables Checklist

Before sending to auditors, verify:

- [ ] **Documentation**
  - [ ] Architecture overview + diagrams
  - [ ] Threat model + mitigations
  - [ ] Trust assumptions
  - [ ] Invariants list
  - [ ] Function specifications
  
- [ ] **Code**
  - [ ] Feature-frozen (no active development)
  - [ ] Git tag created: `audit-v1.0`
  - [ ] Build verification: Deterministic bytecode confirmed
  - [ ] All tests passing: `forge test` → 0 failures
  
- [ ] **Analysis**
  - [ ] Slither report: No CRITICAL/HIGH issues
  - [ ] Coverage report: >= 85% line coverage
  - [ ] Gas report: Baseline metrics
  - [ ] Build info: Compiler version pinned
  
- [ ] **Artifacts**
  - [ ] ABI files: `out/UserVault.json`, etc.
  - [ ] Source flattened (optional): For easy auditor reading
  - [ ] Issue tracker template: Ready for findings
  - [ ] Risk acceptance template: Ready for MEDIUM decisions

---

## Section 6: Post-Audit Deliverables

### 6.1 Audit Report Publication

- [ ] Final audit report received from firm
- [ ] Executive summary published
- [ ] Technical findings published
- [ ] Accepted risks justified
- [ ] Timeline for deployment

### 6.2 Version Hash Tracking

**Contract Deployment**:
```solidity
contract UserVault {
    // Audit version and hash immutable for transparency
    string public constant AUDIT_VERSION = "1.0";
    bytes32 public constant AUDIT_HASH = keccak256("audit-v1.0");
}
```

**Event on Deployment**:
```solidity
event AuditVersionDeployed(
    string indexed version,
    bytes32 indexed auditHash,
    address indexed deployer,
    uint256 timestamp
);
```

---

**Last Updated**: December 17, 2025  
**Status**: Template Ready for Population  
**Next Step**: Populate with actual analysis reports before audit engagement
