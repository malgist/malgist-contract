# MALGIST Bug Bounty Readiness - Implementation Checklist

**Date**: December 17, 2025  
**Status**: 🚀 Ready for Implementation  
**Target**: Immunefi / HackenProof Programs

---

## Quick Reference Checklist

### ✅ Architecture & Design

- [x] BugBountyReadiness mixin contract created (src/BugBountyReadiness.sol)
- [x] Guardian role defined (separate from Owner)
- [x] Emergency pause system documented
- [x] Monitoring events standardized
- [x] Critical function annotations provided
- [x] Trust boundary definitions documented

### 🔄 Implementation Tasks (In Priority Order)

#### Phase 1: Core Integration (1-2 weeks)

- [ ] **Integrate BugBountyReadiness into UserVault**

  - [ ] Add `BugBountyReadiness` to UserVault inheritance chain
  - [ ] Call `super(guardian, registrar, auditHash)` in constructor
  - [ ] Update guardian management functions
  - [ ] Wire up monitoring events on critical functions

- [ ] **Add Critical Function Annotations**

  - [ ] Tag all Category A functions (deposit, withdraw)
  - [ ] Tag all Category B functions (adapter routing)
  - [ ] Tag all Category C functions (strategy management)
  - [ ] Tag all Category D functions (emergency controls)
  - Example: `/// @notice Critical function – bug bounty in scope`

- [ ] **Implement Large Deposit Monitoring**

  - [ ] Emit `LargeDeposit` event when amount >= threshold
  - [ ] Emit `LargeWithdrawal` event on large withdrawals
  - [ ] Make thresholds configurable by Guardian
  - [ ] Default: 1M USDC

- [ ] **Implement Slippage Monitoring**
  - [ ] Emit `SlippageWarning` (≥0.5% slippage)
  - [ ] Emit `CriticalSlippage` (≥1% slippage)
  - [ ] Track in adapter operations
  - [ ] Include thresholds in events

#### Phase 2: Event Emission (1 week)

- [ ] **Emit AdapterOperation events**

  - [ ] On every adapter.deposit() call
  - [ ] On every adapter.withdraw() call
  - [ ] Include operation type (0=deposit, 1=withdraw, 2=rebalance)
  - [ ] Include status (0=success, 1=partial, 2=failure)

- [ ] **Emit Fee Events**

  - [ ] FeeTransaction on copy fee charging
  - [ ] FeeTransaction on protocol fee charging
  - [ ] FeeTransaction on creator fee distribution
  - [ ] Include fee type, recipient, amount, strategyId

- [ ] **Emit Accounting Events**

  - [ ] AccountingReconciled after reconciliation
  - [ ] InvariantViolation if checks fail
  - [ ] TVL change warnings if >20% in single block

- [ ] **Emit Emergency Events**
  - [ ] EmergencyPauseTrigger on pause
  - [ ] EmergencyPauseLifted on unpause
  - [ ] AdapterHealthAlert on adapter failures

#### Phase 3: Monitoring Infrastructure (2 weeks)

- [ ] **Deploy TheGraph Subgraph**

  - [ ] Define event indexing schema
  - [ ] Deploy to TheGraph hosted service
  - [ ] Verify event capture in GraphQL queries

- [ ] **Setup Alerting System**

  - [ ] Configure alerts for LargeDeposit (>1M)
  - [ ] Configure alerts for SlippageWarning (>0.5%)
  - [ ] Configure alerts for CriticalSlippage (>1%)
  - [ ] Configure alerts for AdapterHealthAlert (all)
  - [ ] Configure critical alert for EmergencyPauseTrigger

- [ ] **Create Monitoring Dashboard**

  - [ ] TVL per adapter (real-time)
  - [ ] Recent deposits/withdrawals (last 24h)
  - [ ] Strategy leaderboard
  - [ ] Fee distribution transparency
  - [ ] Incident timeline (pause events)

- [ ] **Setup Incident Response**
  - [ ] Slack/Discord webhook for alerts
  - [ ] War room activation on CRITICAL events
  - [ ] Pagerduty integration (24/7 on-call)
  - [ ] Incident playbook documentation

#### Phase 4: Documentation & Publication (1 week)

- [ ] **Finalize Bug Bounty Policy**

  - [ ] Publish BUG_BOUNTY_POLICY.md to website
  - [ ] Publish scope document (detailed in-scope items)
  - [ ] Document severity tiers and bounty amounts
  - [ ] Document submission process

- [ ] **Setup Immunefi Profile**

  - [ ] Create Immunefi program page
  - [ ] Upload contract ABIs and source code
  - [ ] Define bounty tiers
  - [ ] Setup KYC/payout information

- [ ] **Setup HackenProof Profile**

  - [ ] Create HackenProof program page
  - [ ] Define scope and test cases
  - [ ] Setup communication channel
  - [ ] Configure automated payments

- [ ] **Community Announcements**
  - [ ] Announce on Discord
  - [ ] Announce on Twitter/X
  - [ ] Post on governance forum
  - [ ] Invite known whitehat groups

---

## Implementation Guide by Component

### UserVault Integration

```solidity
// BEFORE
contract UserVault is ReentrancyGuard, EmergencyPause {
    // ...
}

// AFTER
contract UserVault is ReentrancyGuard, EmergencyPause, BugBountyReadiness {
    constructor(
        address _asset,
        address _guardian,
        address _registrar,
        bytes32 _auditHash
    ) BugBountyReadiness(_guardian, _registrar, _auditHash) {
        ASSET = IERC20(_asset);
        // ...
    }
}
```

### Critical Function Annotation Example

```solidity
/**
 * @notice Deposit assets into vault and mint shares
 * @notice Critical function – bug bounty in scope
 * @dev Potential impacts: Share inflation, accounting mismatch, fund loss
 * @param amount Amount to deposit in base tokens
 * @return shares Shares minted to user
 *
 * Invariants:
 * - User receives proportional shares: shares = (amount / totalAssets) * totalShares
 * - Total shares must equal sum of user shares
 * - Vault balance must increase by amount
 */
function deposit(uint256 amount) external nonReentrant returns (uint256 shares) {
    // Implementation...

    // Emit monitoring event for large deposits
    if (_isLargeDeposit(amount)) {
        emit LargeDeposit(msg.sender, _strategyIdForUser(msg.sender), amount, shares, block.timestamp);
    }

    // Always emit critical function event
    emit CriticalFunctionCalled(
        deposit.selector,
        msg.sender,
        _strategyIdForUser(msg.sender),
        block.timestamp
    );
}
```

### Slippage Monitoring Example

```solidity
function _executeDeposit(
    address[] memory adapters,
    uint16[] memory ratios,
    uint256 amount
) internal {
    uint256 remaining = amount;

    for (uint256 i = 0; i < adapters.length; i++) {
        uint256 adapterAmount = ...;

        // Track expected vs actual
        uint256 expectedShares = estimateAdapterShares(adapters[i], adapterAmount);

        ASSET.forceApprove(adapters[i], adapterAmount);
        uint256 actualShares = IAdapter(adapters[i]).deposit(adapterAmount);

        // Check slippage
        (bool isWarning, bool isCritical) = _checkSlippage(expectedShares, actualShares);
        if (isWarning) {
            emit SlippageWarning(
                adapters[i],
                expectedShares,
                actualShares,
                _calculateSlippageBps(expectedShares, actualShares)
            );
        }
        if (isCritical) {
            emit CriticalSlippage(
                adapters[i],
                expectedShares,
                actualShares,
                _calculateSlippageBps(expectedShares, actualShares)
            );
        }

        // Emit adapter operation
        emit AdapterOperation(
            adapters[i],
            0, // deposit
            adapterAmount,
            actualShares,
            0  // success
        );

        adapterCached[adapters[i]] += actualShares;
    }
}
```

---

## Testing Checklist

### Unit Tests

- [ ] Test Guardian role assignment
- [ ] Test Guardian can trigger emergency pause
- [ ] Test Guardian cannot move funds
- [ ] Test Registrar role management
- [ ] Test large deposit events fire correctly
- [ ] Test slippage monitoring thresholds
- [ ] Test adapter operation tracking
- [ ] Test fee transparency events
- [ ] Test accounting reconciliation events
- [ ] Test invariant violation detection

### Integration Tests

- [ ] End-to-end deposit → withdraw flow
- [ ] Multi-adapter strategy execution
- [ ] Emergency pause and recovery
- [ ] Adapter failure handling
- [ ] Fee distribution transparency
- [ ] Strategy copy fee calculation
- [ ] Slippage protection on swaps
- [ ] Event emission on all critical operations

### Monitoring Tests

- [ ] TheGraph indexer correctly parses events
- [ ] Dashboard displays real-time data
- [ ] Alerts trigger on threshold crossing
- [ ] Slack/Discord notifications work
- [ ] War room activation on critical events

---

## Deployment Checklist

### Pre-Deployment

- [ ] All code reviewed and tested
- [ ] Audit completed and AUDIT_HASH verified
- [ ] Guardian multisig deployed and tested
- [ ] Registrar address finalized
- [ ] Monitoring infrastructure deployed and tested
- [ ] Incident response team trained
- [ ] Community notifications prepared

### Deployment Day

- [ ] Deploy BugBountyReadiness to Mantle
- [ ] Deploy updated UserVault to Mantle
- [ ] Verify events emit correctly (test transactions)
- [ ] Activate TheGraph subgraph indexing
- [ ] Enable monitoring and alerting
- [ ] Announce on social media
- [ ] Launch Immunefi program
- [ ] Launch HackenProof program

### Post-Deployment

- [ ] Monitor for first 24 hours continuously
- [ ] Verify all events appearing in subgraph
- [ ] Test incident response procedures
- [ ] Gather baseline metrics for dashboard
- [ ] Document any deployment issues
- [ ] Prepare security team briefing

---

## Success Criteria

### Immunefi / HackenProof Readiness

- ✅ All critical functions annotated
- ✅ Events emit deterministically
- ✅ Monitoring infrastructure operational
- ✅ Guardian role separate from Owner
- ✅ Emergency pause tested and documented
- ✅ Incident response procedures in place
- ✅ Bug bounty program published
- ✅ Community aware and engaged

### Monitoring Metrics

- ✅ 100% event capture rate (verified daily)
- ✅ <5s latency from on-chain to dashboard
- ✅ Alert system: 99.9% uptime
- ✅ TheGraph subgraph sync: <30s behind head
- ✅ Zero missed critical events (audit weekly)

### Community Engagement

- ✅ 10+ submissions in first month
- ✅ Zero false positives in monitoring system
- ✅ Documented response time for valid reports
- ✅ Transparent payout process
- ✅ Monthly security update blog post

---

## Questions & Support

**For Technical Questions**: security@malgist.com  
**For Bug Submissions**: Immunefi or HackenProof platform  
**For Program Updates**: Follow @MalgistOfficial on Twitter

---

**Status**: 🟢 Ready for Implementation  
**Last Updated**: December 17, 2025  
**Version**: 1.0
