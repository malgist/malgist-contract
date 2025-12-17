# MALGIST Issue Severity Policy & Fix Workflow

**Version**: 1.0  
**Date**: December 17, 2025  
**Applies To**: External audit findings, internal security issues, and bug reports

---

## Part 1: Severity Classification

### 1.1 Severity Levels

#### **CRITICAL**

**Definition**: Issue can directly result in loss of user funds, complete system compromise, or violation of invariants.

**Examples**:

- Reentrancy allowing multiple withdrawals from same deposit
- Integer overflow in fee calculations
- Unguarded state modification allowing privilege escalation
- Complete bypass of access control (e.g., any address can call pause owner functions)
- Loss of funds due to logic error (e.g., incorrect withdrawal calculation)

**Handling**:

- ✗ **Cannot be deployed to mainnet**
- ✓ **Must be fixed**
- ✓ **Requires re-audit**
- ⏳ **Timeline**: Fix within 48 hours; re-audit within 1 week

**Escalation**: Immediate notification to Protocol Lead + Security Lead

---

#### **HIGH**

**Definition**: Issue allows an attacker to exploit protocol for gain or causes significant data inconsistency, but does not directly result in fund loss under normal conditions.

**Examples**:

- Sandwich attack vulnerability allowing MEV extraction
- Incorrect event emission preventing off-chain reconciliation
- Missing slippage checks on specific code paths
- Adapter bypass allowing unauthorized calls
- Insufficient balance checks on edge cases

**Handling**:

- ✗ **Cannot be deployed to mainnet**
- ✓ **Must be fixed**
- ✓ **Requires re-audit**
- ⏳ **Timeline**: Fix within 1 week; re-audit within 2 weeks

**Escalation**: Notify Protocol Lead + Security Lead within 24 hours

---

#### **MEDIUM**

**Definition**: Issue could lead to operational problems, user inconvenience, or suboptimal protocol behavior under specific conditions. May require manual intervention to resolve.

**Examples**:

- Missing validation on non-critical parameters
- Inefficient gas usage in specific scenarios
- Incorrect error messages (misleading but recoverable)
- Edge case where users must migrate strategies manually
- Rate limiting that can be bypassed but requires technical knowledge

**Handling**:

- ✓ **May be deployed if explicitly risk-accepted**
- ⚖ **Can be fixed OR risk-accepted in writing**
- ⏳ **Re-audit only if fixed** (not required if accepted)
- ⏳ **Timeline**: Decision within 3 days; fix within 1-2 weeks if chosen

**Risk Acceptance Process**:

1. Security Lead drafts risk justification (see template below)
2. Protocol Lead + Core Team reviews + approves
3. Justification signed and attached to audit report
4. Issue tracked with "ACCEPTED" status
5. Users informed of risk via disclosure

**Escalation**: Discuss with Protocol Lead within 3 days

---

#### **LOW**

**Definition**: Issue is a best-practice improvement or minor inefficiency. No security risk or functional impact.

**Examples**:

- Unused variable or import
- Suboptimal storage layout (non-critical impact)
- Redundant checks
- Minor documentation gaps
- Gas optimizations for rarely-used functions

**Handling**:

- ✓ **May be deployed without fix**
- ⚖ **Optional fix** (best-effort improvement)
- ✗ **Re-audit not required**
- ⏳ **Timeline**: Fix at next convenient opportunity

---

#### **INFORMATIONAL**

**Definition**: Observation or suggestion for code quality or architecture without any security or functional implication.

**Examples**:

- Naming convention suggestions
- Code style improvements
- Documentation clarifications
- Architecture refactoring ideas
- Comment suggestions

**Handling**:

- ✓ **No action required**
- ⚖ **Optional improvements** (defer to next release)
- ✗ **Re-audit not required**

---

## Part 2: Medium-Risk Justification Template

### 2.1 Risk Acceptance Document (For MEDIUM Issues)

**Template**:

```
# Risk Acceptance Justification

## Issue ID: AUD-XXX
**Title**: [Issue title]
**Component**: [Contract name]
**Severity**: MEDIUM
**Date Identified**: [Date]
**Decision Date**: [Date]
**Decision Maker**: [Name, Role]

---

## Issue Summary
[Description of the issue, impact, and conditions under which it manifests]

**Affected Code**:
[Specific function/lines of code]

**Root Cause**:
[Why does this issue exist?]

---

## Risk Analysis

### Likelihood
**Low / Medium / High** — [Justification]

### Impact Severity
**Low / Medium / High** — [Justification]

### Exploitability
**Ease of exploitation**: [Easy / Moderate / Difficult]
**Requirements**: [What preconditions must be met?]
**Detection**: [How would this be detected if exploited?]

---

## Mitigation Strategy

### Implemented Controls
- [Monitoring or procedural control that mitigates risk]
- [Off-chain safeguard]
- [User-facing warning or documentation]

### Post-Deployment Monitoring
- [How will the team detect if this risk materializes?]
- [Alert thresholds or conditions]
- [Incident response procedure]

### Timeline for Fix
- **If risk materializes**: Fix within [N days]
- **Planned fix date**: [Date if scheduled for future release]
- **Contingency**: [What happens if risk occurs before fix?]

---

## Cost-Benefit Analysis

### Fix Cost
- **Engineering effort**: [Estimated hours]
- **Gas impact**: [Estimated increase/decrease]
- **Regression risk**: [Low / Medium / High]

### Risk Cost (if not fixed)
- **Expected loss (unlikely)**: [Estimated max loss]
- **Probability**: [Rough percentage]
- **Detection complexity**: [Easy / Difficult to detect]

### Decision Rationale
[Why is accepting this risk preferable to fixing it?]

---

## Approval

| Role | Name | Signature | Date |
|------|------|-----------|------|
| Security Lead | [Name] | _____ | [Date] |
| Protocol Lead | [Name] | _____ | [Date] |
| Compliance/Legal | [Name] | _____ | [Date] |

---

## User Disclosure
This risk has been documented in the public audit report and in contract documentation:
- [ ] Audit report mentions risk (non-technical summary)
- [ ] Contract comments mention risk / limitation
- [ ] Website/docs disclose risk to users
- [ ] Governance forum discussed risk

---
```

### 2.2 Example Risk Acceptance: MEV Sandwich Attack Susceptibility

**Issue**: UserVault deposit operations may be sandwiched by MEV-extracting bots, resulting in worse-than-expected swap prices.

**Likelihood**: Medium (common on competitive networks)  
**Impact**: Low (users have slippage protection; loss bounded to specified tolerance)

**Risk Justification**:

- **Fix Cost**: 50+ hours (requires MEV-resistant architecture, mempool privacy)
- **Risk Cost**: Bounded by slippage tolerance parameter; users can set conservative limits
- **Controls**: Slippage checks, deadline validation, off-chain UI warnings
- **Monitoring**: Track swap slippage vs. quoted slippage; alert on outliers
- **Decision**: Accept for V1; address in post-mainnet governance if excessive MEV observed

---

## Part 3: Fix & Re-Audit Workflow

### 3.1 Issue Lifecycle

```
┌─────────────────────────────────────────────────────────┐
│                  AUDIT ISSUE LIFECYCLE                  │
└─────────────────────────────────────────────────────────┘

1. IDENTIFIED
   └─ Auditor reports issue
   └─ Add to issue tracker (ID, severity, description)
   └─ Assign to developer

2. ANALYZED
   └─ Root cause investigation
   └─ Impact assessment
   └─ Decision: Fix or Accept (if MEDIUM)
   └─ Document decision rationale

3. FIXED (if chosen)
   └─ Implement fix
   └─ Add regression test
   └─ Verify no new failures
   └─ Commit with message: "fix: AUD-XXX [issue title]"
   └─ Create PR for code review

4. REVIEWED
   └─ Code review by peer
   └─ Test review by QA
   └─ Gas impact assessment
   └─ Merge to main branch

5. RE-AUDITED (CRITICAL/HIGH/MEDIUM fixes only)
   └─ Submit fix + test + gas impact to auditor
   └─ Auditor verifies fix is correct
   └─ Auditor confirms no regressions
   └─ Issue marked CLOSED

6. CLOSED
   └─ If CRITICAL/HIGH: Re-audit passed ✓
   └─ If MEDIUM: Risk accepted & documented ✓
   └─ Issue removed from blocker list
   └─ Safe to deploy
```

---

### 3.2 Fix Workflow Template

**Step 1: Root Cause Analysis** (Developer + Security Lead)

```
Issue: [AUD-XXX]
Severity: [Level]
Date Identified: [Date]

ROOT CAUSE:
[Technical analysis of why the issue exists]
[Code flow that causes the bug]
[Assumption violation or design flaw]

AFFECTED CODE:
- File: src/[Contract].sol, line XXX
- Function: [function name]
- Execution path: [Condition that triggers bug]

RISK SURFACE:
[How many users/transactions affected?]
[Can issue be exploited repeatedly?]
```

**Step 2: Fix Implementation** (Developer)

```
FIX STRATEGY:
[Approach to resolve issue]
[Why this fix is correct]
[Trade-offs considered]

CHANGES MADE:
- File 1: [change description]
- File 2: [change description]

REGRESSION TESTS ADDED:
- Test: [test name] — Validates fix + prevents reoccurrence
- Test: [test name] — Edge case coverage
- Test: [test name] — Boundary conditions

GAS IMPACT:
- Function A: [+50 / -100] gas
- Function B: [no change]
- Overall: [+/- X% on typical transaction]

COMMIT HASH: [SHA]
```

**Step 3: Code Review** (Peer Reviewer)

```
CHECKLIST:
[ ] Fix correctly addresses root cause
[ ] Test cases cover the bug + edge cases
[ ] No new code smells introduced
[ ] Gas impact acceptable
[ ] Documentation updated
[ ] No regressions in other tests

APPROVED BY: [Reviewer name]
DATE: [Date]
```

**Step 4: Re-Audit Request** (Security Lead)

**For CRITICAL/HIGH issues**:

```
REAUDIT REQUEST
───────────────
Issue ID: AUD-XXX
Title: [Issue title]
Severity: CRITICAL / HIGH

SUMMARY:
[1-2 sentence description of fix]

FIX COMMIT: [commit hash]
FIX LINES: [line ranges in files]
TEST ADDED: [test file + test name]

GAS IMPACT: [+/- X gas]

Please verify:
1. Fix correctly addresses root cause
2. No new vulnerabilities introduced
3. Test coverage adequate
4. No regressions
```

**Step 5: Re-Audit Response** (Auditor)

```
REAUDIT COMPLETE
────────────────
Issue: AUD-XXX
Status: ✓ FIXED & VERIFIED

Auditor: [Auditor name]
Date: [Date]
Re-Audit Level: [Spot-check / Full review]

ASSESSMENT:
[Auditor confirms fix is correct]
[No new issues identified]
[Test coverage adequate]

APPROVED FOR DEPLOYMENT: [Date]
```

---

### 3.3 Issue Tracker Template

**Format**: Markdown table (version-controlled in Documentation/)

```markdown
# MALGIST Audit Issue Tracker

## CRITICAL Issues

| ID      | Component | Description           | Status | Fix Commit | Re-Audit     | Notes |
| ------- | --------- | --------------------- | ------ | ---------- | ------------ | ----- |
| AUD-001 | UserVault | Reentrancy in deposit | CLOSED | abc123     | ✓ 2025-01-15 | —     |

## HIGH Issues

| ID      | Component          | Description                  | Status | Fix Commit | Re-Audit     | Notes |
| ------- | ------------------ | ---------------------------- | ------ | ---------- | ------------ | ----- |
| AUD-002 | SlippageProtection | Missing check on path.length | CLOSED | def456     | ✓ 2025-01-16 | —     |

## MEDIUM Issues

| ID      | Component  | Description              | Status   | Risk Accepted | Re-Audit | Notes               |
| ------- | ---------- | ------------------------ | -------- | ------------- | -------- | ------------------- |
| AUD-003 | FeeManager | Event parameter ordering | ACCEPTED | 2025-01-10    | N/A      | See RISK_AUD_003.md |

## LOW Issues

| ID      | Component        | Description     | Status | Notes                   |
| ------- | ---------------- | --------------- | ------ | ----------------------- |
| AUD-004 | StrategyRegistry | Unused variable | CLOSED | Fixed in AUD-004 commit |
```

---

## Part 4: Timeline & Responsibilities

### 4.1 Issue Resolution Timeline

| Severity     | Analysis | Fix         | Re-Audit          | Total              |
| ------------ | -------- | ----------- | ----------------- | ------------------ |
| **CRITICAL** | 24h      | 48h         | 1 week            | ~2 weeks           |
| **HIGH**     | 2 days   | 1 week      | 2 weeks           | ~3 weeks           |
| **MEDIUM**   | 3 days   | 1-2 weeks   | N/A (if accepted) | ~1 week (decision) |
| **LOW**      | —        | Best-effort | N/A               | ~1 month           |

### 4.2 Responsibility Matrix

| Phase                       | Developer | Security Lead | Protocol Lead | Auditor | QA        |
| --------------------------- | --------- | ------------- | ------------- | ------- | --------- |
| Root Cause Analysis         | ✓ Lead    | ✓ Support     | —             | —       | —         |
| Fix Implementation          | ✓ Lead    | —             | —             | —       | ✓ Support |
| Regression Testing          | ✓ Support | —             | —             | —       | ✓ Lead    |
| Code Review                 | —         | ✓ Lead        | —             | —       | ✓ Support |
| Risk Acceptance (if MEDIUM) | —         | ✓ Draft       | ✓ Approve     | —       | —         |
| Re-Audit Request            | ✓ Support | ✓ Lead        | —             | —       | —         |
| Re-Audit Verification       | —         | —             | —             | ✓ Lead  | ✓ Support |

---

## Part 5: Escalation & Communication

### 5.1 Escalation Trigger

| Condition            | Action                              | Notification                            |
| -------------------- | ----------------------------------- | --------------------------------------- |
| CRITICAL issue found | Pause work; notify all leads        | Protocol Lead, Security Lead, Tech Lead |
| HIGH issue found     | Escalate in daily standup           | Protocol Lead, Security Lead            |
| Fix delayed > 50%    | Escalate to Protocol Lead           | Protocol Lead, Project Manager          |
| Re-audit blocked     | Escalate to Auditor + Protocol Lead | All parties                             |

### 5.2 Communication Template

**Issue Notification (All Severities)**:

```
Subject: [SEVERITY] Audit Issue AUD-XXX: [Title]

Issue ID: AUD-XXX
Severity: [CRITICAL / HIGH / MEDIUM / LOW]
Component: [Contract]
Identified: [Date]
Status: [OPEN / IN PROGRESS / RE-AUDITING]

Brief Description:
[1-2 sentence summary]

Assigned To: [Developer name]
Target Fix Date: [Date]

Next Update: [Date/Day]
```

---

## Appendix A: Severity Decision Flowchart

```
                    ISSUE REPORTED
                        |
                        v
        Does it cause DIRECT FUND LOSS?
                   /         \
                 YES           NO
                  |             |
                  v             v
         ┌─ CRITICAL ─┐   Can users lose money
         │  (MUST FIX) │   via exploitation?
         └─────────────┘   /        \
                         YES         NO
                          |           |
                          v           v
                    ┌─ HIGH ─┐   Does it violate an
                    │(MUST FIX)  │   INVARIANT or break
                    └──────────┘   STATE CONSISTENCY?
                                  /        \
                                YES         NO
                                 |           |
                                 v           v
                          ┌─ MEDIUM ─┐  ┌─ LOW ─┐
                          │(FIX/ACCEPT)│  │(OPTIONAL)│
                          └───────────┘  └────────┘
```

---

**Last Updated**: December 17, 2025  
**Version**: 1.0  
**Status**: Active
