# Emergency Control System - Quick Reference Card

## 📋 Modifiers Cheat Sheet

```solidity
@whenDepositsNotPaused          // Block if globalPause active
@whenStrategyExecutionNotPaused // Block if globalPause active
@whenAdapterNotPaused(adapter)  // Block if adapter paused
@withdrawalAlwaysPermitted      // No pause checks (documentation)
@onlyPauseOwner                 // Only pauseOwner can call
```

**Apply To:**

```
✅ deposit()                 → @whenDepositsNotPaused
✅ setStrategy()            → @whenStrategyExecutionNotPaused
✅ copyStrategy()           → @whenStrategyExecutionNotPaused
✅ withdraw()               → @withdrawalAlwaysPermitted
✅ emergencyWithdraw()      → @withdrawalAlwaysPermitted
✅ claimCopyFees()          → (no modifier - always allowed)
✅ enableGlobalPause()      → @onlyPauseOwner
✅ disableGlobalPause()     → @onlyPauseOwner
✅ pauseAdapter()           → @onlyPauseOwner
✅ unpauseAdapter()         → @onlyPauseOwner
```

---

## 🎮 Admin Functions (pauseOwner only)

```solidity
// ENABLE/DISABLE GLOBAL PAUSE
vault.enableGlobalPause("Exploit in deposit()");
vault.disableGlobalPause();
vault.updateGlobalPauseReason("Updated: Still investigating");

// PAUSE/UNPAUSE SPECIFIC ADAPTER
vault.pauseAdapter(0xFusionX, "Flash loan detected");
vault.unpauseAdapter(0xFusionX);
```

---

## 📊 Query Functions (Anyone can call)

```solidity
// GLOBAL PAUSE STATUS
vault.isGlobalPauseActive()           → true/false
vault.getGlobalPauseReason()          → "Exploit detected"
vault.getGlobalPauseTimestamp()       → 1702800000

// ADAPTER PAUSE STATUS
vault.isAdapterPaused(0xFusionX)      → true/false
vault.getAdapterPauseReason(0xFusionX) → "Liquidity crisis"
vault.getAdapterPauseTimestamp(0xFusionX) → 1702800000

// CONVENIENCE QUERIES
vault.isAdapterOperational(0xFusionX) → true/false
vault.getPauseStatus()                → (globalPaused, pausedAdapters)
```

---

## 🚨 Revert Errors

```solidity
// User tries to deposit during pause
revert DepositsPaused()

// User tries to update strategy during pause
revert StrategyExecutionPaused()

// Deposit through paused adapter
revert AdapterPaused()

// Non-owner tries to pause
revert NotAuthorized()

// Try to pause twice
revert PauseAlreadyActive()

// Try to unpause when not paused
revert NoPauseActive()

// Invalid adapter address
revert InvalidAdapter()

// Adapter returns 0 shares
revert AdapterDepositFailed()

// Adapter returns 0 withdrawn
revert AdapterWithdrawFailed()
```

---

## 📈 Event Log Monitoring

```solidity
// Parse these events for alerts
event GlobalPauseEnabled(
    address indexed guardian,
    string reason
);

event GlobalPauseDisabled(
    address indexed guardian
);

event AdapterPaused(
    address indexed adapter,
    address indexed guardian,
    string reason
);

event AdapterUnpaused(
    address indexed adapter,
    address indexed guardian
);

event PauseReasonUpdated(
    string newReason
);
```

---

## 🔍 Incident Response Flowchart

```
EXPLOIT DETECTED
    ↓
Was it adapter-specific?
    ├─ YES: pauseAdapter(exploited_adapter)
    │   ├─ Other adapters continue
    │   ├─ Users can withdraw
    │   └─ Patch in isolation
    │
    └─ NO: enableGlobalPause("Description")
        ├─ All deposits blocked
        ├─ Users can withdraw
        ├─ Investigate & patch
        └─ disableGlobalPause()
```

---

## 🎯 Deployment Checklist

```
□ Set pauseOwner = Multisig address
□ pauseOwner is immutable (verify in constructor)
□ isGlobalPauseActive() == false (initially)
□ Test deposit blocked during pause
□ Test withdraw works during pause
□ Test adapter-specific pause
□ Monitor events are emitted
□ Set up off-chain alerting
```

---

## ⚡ Critical Guarantees

```
✅ GUARANTEE 1: Withdrawals NEVER fail due to pause
   → withdraw() has NO pause checks
   → User funds always accessible

✅ GUARANTEE 2: Copy fees ALWAYS claimable
   → claimCopyFees() has NO pause checks
   → User earnings always accessible

✅ GUARANTEE 3: Only Owner Can Pause
   → pauseOwner is immutable
   → Every pause function requires @onlyPauseOwner

✅ GUARANTEE 4: Adapter Pause is Safe
   → Doesn't affect withdrawals
   → Doesn't affect other adapters
   → Can be reversed instantly

✅ GUARANTEE 5: Pause Reason is Logged
   → Every pause includes reason string
   → Can be updated for transparency
   → Stored on-chain (queryable)
```

---

## 💰 Gas Costs

```
ADMIN OPERATIONS:
- enableGlobalPause()     ~5,000 gas
- disableGlobalPause()    ~5,000 gas
- pauseAdapter()          ~8,000 gas
- unpauseAdapter()        ~5,000 gas

USER OPERATIONS:
- deposit() + check       +500 gas (pause check overhead)
- withdraw()              +0 gas (no checks)
- claimCopyFees()         +0 gas (no checks)
```

---

## 🔗 Integration Quick Links

### Files to Create/Modify

```
CREATE:
  src/EmergencyPause.sol              (400 LOC, copy-paste)
  test/EmergencyPause.t.sol           (400 LOC, copy-paste)

MODIFY:
  src/UserVault.sol                   (~20 lines added)
  src/adapters/FusionXAdapter.sol     (~5 lines added, optional)
  src/adapters/LendleAdapter.sol      (~5 lines added, optional)
```

### Integration Steps

```
1. Copy EmergencyPause.sol to src/
2. Add inheritance to UserVault: "is ReentrancyGuard, EmergencyPause"
3. Update constructor with pauseOwner parameter
4. Add @whenDepositsNotPaused to deposit()
5. Add @whenStrategyExecutionNotPaused to setStrategy()
6. Add @withdrawalAlwaysPermitted to withdraw()
7. Verify no pause checks in withdraw() or claimCopyFees()
8. Run tests
9. Deploy with multisig as pauseOwner
```

---

## 🆘 Emergency Commands

```solidity
// IMMEDIATE: Stop all deposits
vault.enableGlobalPause("Exploit detected - investigating");

// IMMEDIATE: Stop specific adapter
vault.pauseAdapter(0xFusionX, "Flash loan exploit");

// RECOVERY: Resume operations (after fix)
vault.disableGlobalPause();
vault.unpauseAdapter(0xFusionX);

// UPDATE: Inform users about status
vault.updateGlobalPauseReason("Still investigating - ETA 30 mins");
```

---

## 🎓 Key Concepts

### Global Pause

- Blocks: deposit(), setStrategy(), copyStrategy()
- Allows: withdraw(), claimCopyFees()
- Use case: Critical vault vulnerability

### Per-Adapter Pause

- Blocks: Deposits through that adapter
- Allows: Withdrawals from that adapter
- Use case: Adapter-specific issue

### Adapter Operational Check

- Runs BEFORE calling adapter.deposit()
- Verifies both global + adapter pause state
- Pattern: `_checkAdapterOperational(adapter)`

### Withdrawal Always Permitted

- No pause checks in withdraw()
- Guaranteed access to user funds
- Critical safety property

---

## 📱 Mobile Quick Reference

```
PAUSE SYSTEM STATES:

┌─────────────────┐
│  NORMAL (default)
├─────────────────┤
│ ✅ Deposits OK
│ ✅ Withdrawals OK
│ ✅ Strategy ops OK
└─────────────────┘

┌─────────────────┐
│  GLOBAL PAUSE
├─────────────────┤
│ ❌ Deposits BLOCKED
│ ✅ Withdrawals OK
│ ❌ Strategy ops BLOCKED
└─────────────────┘

┌─────────────────┐
│  ADAPTER PAUSED
├─────────────────┤
│ ❌ This adapter: no deposits
│ ✅ This adapter: withdrawals OK
│ ✅ Other adapters: normal
└─────────────────┘
```

---

## 🔐 Security Checklist

```
BEFORE MAINNET:
□ pauseOwner = Multisig (not EOA)
□ Multisig requires 3-of-5 signatures
□ withdraw() has NO pause modifiers
□ claimCopyFees() has NO pause modifiers
□ All pause modifiers applied correctly
□ Adapter checks before deposit() calls
□ Return value validation on adapter calls
□ Events logged and monitored
□ Incident response team trained
□ UI shows pause status
□ No silent failures possible
```

---

## 📞 Common Scenarios

### Scenario 1: Flash Loan Attack

```
pauseAdapter(0xFusionX, "Flash loan detected")
→ Blocks new FusionX deposits
→ Users can withdraw
→ Fixes applied to FusionX
→ unpauseAdapter(0xFusionX)
```

### Scenario 2: Oracle Manipulation

```
pauseAdapter(0xLendle, "Price manipulation")
→ Blocks new Lendle deposits
→ Users exit Lendle
→ Wait for oracle fix
→ unpauseAdapter(0xLendle)
```

### Scenario 3: Critical Vulnerability

```
enableGlobalPause("Reentrancy bug found")
→ All deposits blocked
→ Users can withdraw
→ Security patch & audit
→ disableGlobalPause()
```

---

## 🚀 Launch Command

```bash
# Compile
forge build

# Test
forge test test/EmergencyPause.t.sol

# Deploy (testnet)
forge create src/EmergencyPause.sol
forge create src/UserVault.sol \
  --constructor-args "0xUSDC" "0xMultisig"

# Verify
vault.pauseOwner() == 0xMultisig ✓
vault.isGlobalPauseActive() == false ✓
```

---

**v1.0 | Production-Ready | Dec 16, 2025**
