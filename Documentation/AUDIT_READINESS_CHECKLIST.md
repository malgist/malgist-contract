# MALGIST Audit Readiness Checklist

**Version**: 1.0  
**Date**: December 17, 2025  
**Status**: Pre-Audit (In Preparation)  
**Target Deployment**: Mainnet (Post-Audit)

---

## Executive Summary

This checklist ensures MALGIST meets professional audit standards before engaging external security auditors. All items must be verified before audit engagement.

**Audit Scope**: 
- Primary contracts: `UserVault.sol`, `StrategyRegistry.sol`, `FeeManager.sol`, `EmergencyPause.sol`, `SlippageProtection.sol`
- Secondary: Adapter interfaces, performance tracking, auto-rebalance engine
- Out of scope: OpenZeppelin libraries (assumed secure), mock contracts (test-only)

---

## Section 1: Code Quality & Readiness

### 1.1 Code Freeze & Versioning
- [ ] **Feature lock**: All planned features implemented and frozen
- [ ] **Git tag created**: `git tag -a audit-v1.0 -m "Pre-audit release"`
- [ ] **Commit hash recorded**: Audit scope commit = `[SHA-256 hash to be filled]`
- [ ] **Build determinism verified**: `forge build --verify` produces identical bytecode across builds
- [ ] **Compiler version locked**: Solidity ^0.8.20 (exact: 0.8.20 or 0.8.30)
- [ ] **All dependencies pinned**: foundry.toml specifies exact versions

**Responsibility**: Lead Developer  
**Deadline**: Pre-audit

---

### 1.2 Code Review & Documentation
- [ ] **Architecture documented**: See `ARCHITECTURE_DESIGN.md` (in Documentation/)
- [ ] **Function documentation**: All external functions have clear @param and @return comments
- [ ] **Invariants documented**: See Section 4 ("Invariants") below
- [ ] **Edge cases identified**: Logic branches for zero amounts, max values, rounding errors
- [ ] **Internal security assumptions**: Documented in `TRUST_ASSUMPTIONS.md`

**Responsibility**: Tech Lead  
**Deadline**: Pre-audit

---

### 1.3 Test Coverage & Quality
- [ ] **Unit test coverage >= 85%**: Run `forge coverage` and verify
- [ ] **Integration tests**: Multi-step scenarios (deposit → strategy → copy → withdraw)
- [ ] **Fuzz testing**: At least 1000 runs per fuzzing target
- [ ] **Regression tests**: All prior bugs have test cases to prevent reoccurrence
- [ ] **Security-focused tests**: 
  - [ ] Reentrancy guards tested
  - [ ] Access control verified
  - [ ] Slippage protection validated
  - [ ] Pause mechanism exercised

**Responsibility**: QA Lead / Test Engineer  
**Test Framework**: Foundry (forge test)  
**Deadline**: Pre-audit

---

### 1.4 Static Analysis & Tooling
- [ ] **Slither analysis run**: `slither . --json > slither-report.json`
  - [ ] No CRITICAL/HIGH issues
  - [ ] MEDIUM issues documented (see severity policy)
- [ ] **Mythril analysis**: Optional but recommended
  - [ ] Run `mythril analyze src/*.sol --solv 0.8.20`
  - [ ] No exploitable paths detected
- [ ] **Coverage report generated**: `forge coverage --report lcov` 
  - [ ] Minimum 85% line coverage
  - [ ] 80% branch coverage
- [ ] **Gas report baseline**: `forge test --gas-report` (see gas benchmark section)

**Responsibility**: Security Engineer  
**Deadline**: Pre-audit

---

### 1.5 Error Handling & Custom Errors
- [ ] **All revert conditions use custom errors** (no require strings in production)
- [ ] **Error parameter validation**: Revert on invalid inputs (addresses, amounts, ratios)
- [ ] **Error events logged**: Critical events emitted before reverting
- [ ] **Error messages unambiguous**: Clear intent for each error type

**Responsibility**: Smart Contract Developer  
**Deadline**: Pre-audit

---

## Section 2: Security & Access Control

### 2.1 Access Control Verification
- [ ] **Owner/governance identified**: Single owner for critical functions
- [ ] **Role-based access**: Pause owner, rebalance engine, registrar defined
- [ ] **Two-factor operations**: Time-locks for sensitive changes (optional, if implemented)
- [ ] **No unguarded state changes**: All state variables have setter guards
- [ ] **Initialize guards**: Constructors prevent initialization of already-initialized states

**Responsibility**: Smart Contract Security Lead  
**Deadline**: Pre-audit

---

### 2.2 Reentrancy & State Consistency
- [ ] **NonReentrant guards**: All external functions that modify state use `ReentrancyGuard`
- [ ] **Checks-Effects-Interactions order**: Verified in all fund-moving functions
- [ ] **Internal consistency**: State invariants maintained before/after transactions
- [ ] **No delegatecall or low-level calls**: Only safe patterns used
- [ ] **Safe contract calls**: All external calls use try/catch or revert on fail

**Responsibility**: Security Auditor  
**Deadline**: Pre-audit

---

### 2.3 External Protocol Risk Boundaries
- [ ] **Adapter validation**: Only whitelisted adapters accepted
- [ ] **Return value checks**: All external calls validate return values
- [ ] **Token standard compliance**: ERC20 assumed; non-standard tokens documented as known risk
- [ ] **Slippage protection**: All swaps/deposits have deadline + minAmountOut checks
- [ ] **Contagion containment**: Failed adapter does NOT corrupt vault state

**Responsibility**: Protocol Architect  
**Deadline**: Pre-audit

---

### 2.4 Strategy & Governance Security
- [ ] **Strategy creation gating**: Permissionless phases (Restricted → Limited → Permissionless) enforced
- [ ] **Risk disclosure mandatory**: riskDisclosureHash required for all strategies
- [ ] **Duplicate prevention**: Risk hash collision detection active
- [ ] **Per-creator limits**: maxStrategiesPerAddress enforced
- [ ] **Community review flag**: Cannot be abused for unauthorized TVL caps

**Responsibility**: Protocol Design Lead  
**Deadline**: Pre-audit

---

## Section 3: Emergency & Incident Readiness

### 3.1 Emergency Pause System
- [ ] **Global pause mechanism**: Can pause all deposits/strategy execution
- [ ] **Adapter-level pause**: Can pause individual adapters
- [ ] **Pause reason storage**: Each pause recorded with reason string + timestamp
- [ ] **Emergency withdrawal**: Users can always withdraw (even during global pause)
- [ ] **Pause owner identified**: Multisig or timelock recommended

**Responsibility**: Operations Lead  
**Deadline**: Pre-audit

---

### 3.2 Recovery Procedures
- [ ] **Emergency withdrawal tested**: Vault can recover funds even during global pause
- [ ] **Adapter failure recovery**: Vault unaffected if adapter becomes insolvent
- [ ] **Fund reconciliation**: Vault can reconcile adapter balances vs. cached state
- [ ] **Loss scenario documented**: Known limitations under extreme conditions

**Responsibility**: Incident Response Team  
**Deadline**: Pre-audit

---

## Section 4: Architecture & Invariants

### 4.1 Key Invariants (Must be maintained at all times)
1. **Total Shares Consistency**: 
   - `totalShares == sum(userShares[user] for all users)`
   - Invariant broken: Audit failure
   
2. **Total Assets Consistency**:
   - `totalAssets >= sum(userShares[user] / totalShares * totalAssets for all users)`
   - Rounding is allowed; equality may not hold due to precision loss
   
3. **Adapter Balance Accuracy**:
   - `adapterCached[adapter] == IAdapter(adapter).getBalance()` (post-reconciliation)
   - If diverged: reconciliation required
   
4. **Strategy Validity**:
   - All strategies have `adapters.length == ratios.length > 0`
   - `sum(ratios) == TOTAL_BPS (10000)`
   
5. **Phase Enforcement**:
   - Limited phase strategies cannot exceed TVL cap
   - Permissionless phase strategies have no cap
   - Restricted phase requires creator approval
   
6. **Emergency Pause Isolation**:
   - If global pause active: deposits blocked, withdrawals allowed
   - If adapter paused: only that adapter blocked

### 4.2 Threat Model Assumptions
- **External Protocols**: Assumed to be non-malicious but may be exploited or degraded
- **Token Standards**: ERC20 compliance assumed; rebasing tokens explicitly not supported
- **Governance**: Owner is trusted; timelock recommended for mainnet
- **Pause Owner**: Trusted guardian; can be multisig
- **Users**: Assumed to act rationally but may be socially engineered
- **Adapters**: Whitelist-only; rogue adapters can cause loss of funds to that strategy

### 4.3 Known Limitations
- **Sandwich Attacks**: Slippage checks protect but do not eliminate MEV
- **Oracle Risk**: Adapter quotes are point-in-time; stale quotes not detected
- **Contagion**: If external protocol fails, affected adapter's funds at risk
- **Strategy Lock-in**: Users who copied a flawed strategy must migrate manually
- **Governance**: No timelock by default (separate deployment option)

---

## Section 5: Audit Process & Scope

### 5.1 Auditor Selection
- [ ] **Audit firm #1 confirmed**: [To be filled]
- [ ] **Audit firm #2 (optional) confirmed**: [To be filled]
- [ ] **Scope document signed**: Audit scope agreed (see 5.2)
- [ ] **Timeline confirmed**: Start date, end date, and re-audit windows defined

**Responsibility**: Protocol Lead  
**Deadline**: Pre-audit engagement

---

### 5.2 Audit Scope (In-Scope)
**Primary Contracts**:
- `src/UserVault.sol` — Core vault logic, deposit/withdraw, strategy creation
- `src/StrategyRegistry.sol` — Strategy metadata, phased creation control
- `src/FeeManager.sol` — Fee calculation and distribution
- `src/EmergencyPause.sol` — Emergency pause mechanism
- `src/SlippageProtection.sol` — Slippage validation

**Secondary Contracts**:
- `src/AutoRebalanceEngine.sol` — Automated rebalancing (informational review)
- `src/PerformanceTracking.sol` — Performance metrics (non-critical)
- `src/Timelock.sol` — Governance timelock (if used)

**Adapter Interfaces**:
- `src/interfaces/IAdapter.sol` — Adapter specification
- Example implementations: `HardenedAaveV3Adapter.sol`

---

### 5.3 Out-of-Scope
- OpenZeppelin library contracts (assumed secure; referenced versions pinned)
- Mock contracts (test-only; not deployed)
- Frontend/off-chain components
- Economic model optimization (governance concern)

---

## Section 6: Pre-Audit Actions

### 6.1 Documentation Package for Auditors
- [ ] **Architecture Overview**: High-level design, component diagram, call flows
- [ ] **Contract Specification**: Per-function specification, preconditions, postconditions
- [ ] **Invariants List**: See Section 4.1
- [ ] **Trust Assumptions**: See Section 4.2
- [ ] **Known Issues**: Explicitly document any accepted risks or known limitations
- [ ] **Deployment Plan**: Mainnet configuration, pause owner identity, initial parameters

**Deliverable Format**: PDF or markdown; version-controlled in `Documentation/`

---

### 6.2 Automated Analysis Reports
- [ ] **Slither report**: JSON + HTML (identify and document all MED/HIGH/CRITICAL)
- [ ] **Coverage report**: HTML coverage visualization (>85% target)
- [ ] **Gas benchmarks**: Baseline gas costs for all critical functions
- [ ] **Build verification**: Deterministic build confirmed

**Deliverable**: Included in audit package

---

### 6.3 Test Suite Handover
- [ ] **All tests passing**: `forge test` produces 0 failures
- [ ] **Test documentation**: Describe each test's purpose and invariants validated
- [ ] **Fuzz targets**: Clear guidance on which functions are fuzzed
- [ ] **Test data**: Representative test scenarios (mainnet conditions) included

**Deliverable**: Source code + test harness

---

## Section 7: Issue Tracking & Resolution

### 7.1 Audit Issue Registry
**Format**: Spreadsheet or markdown table

| ID | Severity | Component | Description | Status | Fix Commit | Re-Audit |
|----|----------|-----------|-------------|--------|------------|----------|
| AUD-001 | CRITICAL | UserVault | [Issue description] | OPEN | — | — |
| AUD-002 | HIGH | StrategyRegistry | [Issue description] | FIXED | abc123 | ✓ |
| AUD-003 | MEDIUM | FeeManager | [Issue description] | ACCEPTED | — | N/A |

### 7.2 Fix Workflow (for each issue)
1. **Root Cause Analysis**: Document why issue occurred
2. **Fix Implementation**: Code change with regression test
3. **Testing**: Verify fix + no new failures
4. **Re-audit**: Submit fix + test + gas impact to auditor
5. **Closure**: Auditor confirms fix satisfactory

---

## Section 8: Post-Audit & Deployment

### 8.1 Audit Report Review
- [ ] **Report received**: Complete and signed
- [ ] **All CRITICAL/HIGH issues resolved**: Or explicitly out-of-scope
- [ ] **MEDIUM issues documented**: Risk acceptance signed or fixed
- [ ] **LOW/INFO issues addressed**: Where practical

---

### 8.2 Deployment Readiness
- [ ] **Pause owner identified**: Multisig address confirmed
- [ ] **Initial parameters set**: Governance, caps, fee percentages finalized
- [ ] **Mainnet configuration**: Network-specific settings (RPC, gas, etc.)
- [ ] **Upgrade path planned**: If applicable (proxy + timelock design)

---

### 8.3 Post-Deployment Monitoring
- [ ] **Incident response team**: On-call for first 30 days
- [ ] **Emergency pause procedure**: Tested and ready
- [ ] **Monitoring dashboards**: TVL, adapter health, error rates
- [ ] **Communication plan**: How to notify users of issues

---

## Section 9: Transparency & Disclosure

### 9.1 Public Audit Report
- [ ] **Report published**: On website + IPFS (immutable)
- [ ] **Executive summary**: Non-technical overview
- [ ] **Fixed issues summary**: List of all CRITICAL/HIGH fixes
- [ ] **Accepted risks**: Justify each MEDIUM risk acceptance

### 9.2 On-Chain Audit Hash
- [ ] **Emit AuditHash event**: On deployment with audit report CID
- [ ] **Contract version**: Include audit version in contract state

### 9.3 Governance Disclosure
- [ ] **Announce audit completion**: Publish on governance forum/Discord
- [ ] **Timeline for mainnet**: Public roadmap
- [ ] **Risk disclosure**: Be transparent about known limitations

---

## Checklist Completion Certification

| Section | Owner | Status | Completion Date |
|---------|-------|--------|-----------------|
| Section 1 (Code Quality) | Tech Lead | ⏳ Pending | — |
| Section 2 (Security) | Security Lead | ⏳ Pending | — |
| Section 3 (Emergency) | Ops Lead | ⏳ Pending | — |
| Section 4 (Invariants) | Protocol Lead | ✓ Complete | 2025-12-17 |
| Section 5 (Audit Process) | Protocol Lead | ⏳ Pending | — |
| Section 6 (Pre-Audit) | Security Lead | ⏳ Pending | — |
| Section 7 (Issue Tracking) | Project Manager | ⏳ Pending | — |
| Section 8 (Post-Audit) | Tech Lead | ⏳ Pending | — |
| Section 9 (Disclosure) | Protocol Lead | ⏳ Pending | — |

**Overall Status**: 1/9 sections complete (11%)  
**Target Completion**: TBD (set after audit engagement)

---

## Document Approval

| Role | Name | Signature | Date |
|------|------|-----------|------|
| Protocol Lead | [To be filled] | — | — |
| Security Lead | [To be filled] | — | — |
| Tech Lead | [To be filled] | — | — |
| Legal/Compliance | [To be filled] | — | — |

---

**Last Updated**: December 17, 2025  
**Version**: 1.0  
**Next Review**: Post-audit engagement
