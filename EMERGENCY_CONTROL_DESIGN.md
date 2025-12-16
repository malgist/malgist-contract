# MALGIST Emergency Control System - Design Document

**Date:** December 16, 2025  
**Status:** Production-Grade Design  
**Scope:** EmergencyPause System for DeFi Vault

---

## Executive Summary

This document describes MALGIST's **Emergency Control System**, a production-grade pause mechanism designed to:

✅ **Stop exploits in real-time** - pause deposits/strategy execution within 1 transaction  
✅ **Protect user funds** - withdrawals ALWAYS work, even during emergency  
✅ **Granular control** - pause individual adapters without affecting others  
✅ **Incident response** - comprehensive event logging for monitoring  
✅ **Gas efficient** - O(1) operations, minimal storage overhead  
✅ **Auditable** - clear separation of concerns, no overengineering

---

## 1. Architecture Overview

### 1.1 System Components

```
┌─────────────────────────────────────────────────┐
│         UniversalVault (Inherits)               │
│  ┌───────────────────────────────────────────┐  │
│  │ EmergencyPause (Mixin Contract)           │  │
│  │ ────────────────────────────────────────  │  │
│  │ - Global pause state                      │  │
│  │ - Per-adapter pause tracking              │  │
│  │ - Access control (onlyPauseOwner)         │  │
│  │ - Modifiers for vault integration         │  │
│  └───────────────────────────────────────────┘  │
├─────────────────────────────────────────────────┤
│ Vault Functions                                 │
│ ├─ deposit()                → @whenDeposits...  │
│ ├─ withdraw()               → NO PAUSE CHECK    │
│ ├─ emergencyWithdraw()      → NO PAUSE CHECK    │
│ └─ claimCopyFees()          → NO PAUSE CHECK    │
├─────────────────────────────────────────────────┤
│ Adapter Layer                                   │
│ ├─ Vault checks adapter status BEFORE calling   │
│ └─ Adapters don't implement pause logic         │
└─────────────────────────────────────────────────┘
```

### 1.2 State Model

```
NORMAL STATE (default)
├─ globalPauseActive = false
├─ All adapters operational
└─ All vault functions: ✅ ALLOWED

GLOBAL PAUSE STATE (emergency)
├─ globalPauseActive = true
├─ deposit()                → ❌ BLOCKED
├─ setStrategy()            → ❌ BLOCKED
├─ copyStrategy()           → ❌ BLOCKED
├─ withdraw()               → ✅ ALLOWED (CRITICAL!)
├─ emergencyWithdraw()      → ✅ ALLOWED
└─ claimCopyFees()          → ✅ ALLOWED

PER-ADAPTER PAUSE STATE
├─ adapter[X].paused = true
├─ New deposits to adapter[X] → ❌ BLOCKED
├─ Other adapters          → ✅ ALLOWED
└─ Withdrawals from adapter[X] → ✅ ALLOWED
```

---

## 2. Core Contracts

### 2.1 EmergencyPause.sol

**Purpose:** Mixin contract providing all pause functionality  
**Size:** ~400 lines of code  
**Design Pattern:** Mixin (inherited by vault)  
**Gas Cost:** ~5k per pause/unpause, minimal per-function overhead

#### State Variables

```solidity
// Access control
address public immutable pauseOwner;          // Multisig/Guardian address

// Global pause state
bool private _globalPauseActive;              // Is global pause active?
string private _globalPauseReason;            // Why? (for transparency)
uint256 private _globalPauseTimestamp;        // When? (for analytics)

// Per-adapter pause state
mapping(address => bool) private _adapterPaused;
mapping(address => string) private _adapterPauseReason;
mapping(address => uint256) private _adapterPauseTimestamp;
```

#### Public Functions (Admin)

```solidity
// CONTROL FUNCTIONS (onlyPauseOwner)

enableGlobalPause(reason)
  - Activates global pause
  - Blocks deposits & strategy execution
  - Emits GlobalPauseEnabled
  - Gas: ~5,000 (1 SSTORE + 1 event)

disableGlobalPause()
  - Deactivates global pause
  - Re-enables deposits & strategy execution
  - Emits GlobalPauseDisabled
  - Gas: ~5,000

pauseAdapter(adapter, reason)
  - Pauses specific adapter
  - Blocks deposits through this adapter only
  - Other adapters unaffected
  - Emits AdapterPaused
  - Gas: ~8,000 (multiple SSTORE + event)

unpauseAdapter(adapter)
  - Unpauses specific adapter
  - Emits AdapterUnpaused
  - Gas: ~5,000

updateGlobalPauseReason(newReason)
  - Updates pause reason (for incident response updates)
  - Emits PauseReasonUpdated
  - Gas: ~3,000
```

#### Public View Functions (Query)

```solidity
isGlobalPauseActive()          → bool
getGlobalPauseReason()         → string
getGlobalPauseTimestamp()      → uint256
isAdapterPaused(adapter)       → bool
getAdapterPauseReason(adapter) → string
getAdapterPauseTimestamp(adapter) → uint256
isAdapterOperational(adapter)  → bool (convenience function)
getPauseStatus()               → (bool, address[]) (for UI queries)
```

#### Internal Functions (Used by Vault)

```solidity
_checkDepositsAllowed()
  - Reverts if global pause active
  - Used in: deposit(), setStrategy(), copyStrategy()

_checkAdapterOperational(adapter)
  - Checks both global pause AND adapter-specific pause
  - Used in: setStrategy() validation, before adapter.deposit()

_checkStrategyExecutionAllowed()
  - Reverts if global pause active
  - Used in: strategy update/rebalance functions

_requireAdapterNotPaused(adapter)
  - Checks if adapter is paused
  - Used as safety check in critical paths

_checkWithdrawalAlwaysAllowed()
  - No-op function (documentation only)
  - Signifies that withdrawal never checks pause
```

#### Modifiers

```solidity
// Vault uses these modifiers for clean integration

@onlyPauseOwner
  - Restricts function to pauseOwner only
  - Used for all pause/unpause functions

@whenDepositsNotPaused
  - Blocks function if globalPauseActive
  - Applied to: deposit(), setStrategy(), copyStrategy()

@whenStrategyExecutionNotPaused
  - Blocks function if globalPauseActive
  - Applied to: setStrategy(), copyStrategy(), rebalance()

@whenAdapterNotPaused(adapter)
  - Blocks function if adapter is paused
  - Can be applied to adapter-specific operations

@withdrawalAlwaysPermitted
  - Empty modifier (documentation only)
  - Signals to auditors that function bypasses pause checks
  - Applied to: withdraw(), emergencyWithdraw(), claimCopyFees()
```

### 2.2 UniversalVault.sol

**Purpose:** Example integration showing how vault uses EmergencyPause  
**Key Functions:**

```solidity
// Constructor - sets pause owner
constructor(address _asset, address _pauseOwner)
  EmergencyPause(_pauseOwner) { ... }

// DEPOSIT - Blocked during pause
function deposit(amount)
  external
  nonReentrant
  whenDepositsNotPaused  // ← Pause check
{
  // Before depositing to adapters:
  for each adapter:
    _checkAdapterOperational(adapter)  // ← Per-adapter check
}

// WITHDRAWAL - NEVER paused (critical!)
function withdraw(shareAmount)
  external
  nonReentrant
  withdrawalAlwaysPermitted  // ← Signals: no pause checks
{
  // Zero pause checks here - executes regardless of pause state
  _executeWithdrawWithoutPauseCheck(...)
}

// EMERGENCY WITHDRAWAL - Alias for withdraw()
function emergencyWithdraw(shareAmount)
  external
  nonReentrant
  withdrawalAlwaysPermitted
{
  return withdraw(shareAmount);
}

// COPY FEES - Always claimable
function claimCopyFees()
  external
  nonReentrant
  // NO pause check - earnings always accessible
{
  // Transfer fees to user
}
```

---

## 3. Emergency Response Workflow

### 3.1 Exploit Detected → Paused (5 minutes)

```
Timeline:
T+0:00s   Monitoring system detects exploit (unusual tx pattern)
T+0:30s   Security team confirms exploit in FusionX adapter
T+1:00s   Guardian submits pauseAdapter(0xFusionX) tx to multisig
T+2:00s   Multisig signers execute pause transaction
T+2:30s   Pause confirmed on-chain (1 block confirmation)
T+3:00s   No new deposits through FusionX accepted
T+5:00s   All future deposits blocked; users can STILL withdraw

Impact:
✅ Exploit window: ~3 minutes (until pause confirmed)
✅ User funds: Protected (can withdraw anytime)
❌ TVL at risk: Limited to 3 minutes of exploit activity
✅ Recovery: Adapter can be unpaused after fix verified
```

### 3.2 Global Pause (Critical Event)

```
Trigger: Major vulnerability in vault core logic

T+0s   Oracle/monitoring detects vault compromise
T+1s   Guardian calls enableGlobalPause("Exploit in deposit logic")
T+2s   All deposits + strategy operations blocked immediately
T+2s   Withdrawals continue unimpeded
T+N    Security team audits and patches vulnerability
T+N+1  After verification, call disableGlobalPause()

Events Emitted (for monitoring):
1. GlobalPauseEnabled(guardian, "Exploit in deposit logic")
2. Global pause reason: "Exploit in deposit logic"
3. Block timestamp: stored
```

### 3.3 Per-Adapter Pause (Surgical)

```
Scenario: LendleAdapter has liquidity risk, but FusionX is fine

T+0s   pauseAdapter(0xLendle, "Liquidity crisis - pause until fixed")

Impact:
❌ New deposits to Lendle: BLOCKED
✅ New deposits to FusionX: ALLOWED
✅ Withdrawals from Lendle: ALLOWED (users can exit)
✅ Withdrawals from FusionX: ALLOWED

Benefit: Minimize collateral damage, protect other protocols
```

---

## 4. Security Guarantees

### 4.1 Safety Properties (Invariants)

```
INVARIANT 1: Withdrawals Never Fail Due to Pause
  - withdraw() has NO pause checks
  - Enforced by: modifier @withdrawalAlwaysPermitted
  - Auditor verification: Search for pause checks in withdraw() → 0 found

INVARIANT 2: Copy Fees Always Accessible
  - claimCopyFees() has NO pause checks
  - Users can always collect earnings
  - Enforced by: no pause modifier on claimCopyFees()

INVARIANT 3: Adapter Pause is Advisory, Not Blocking
  - Vault checks adapter pause before deposit
  - Adapter itself has no pause logic
  - Withdrawals not blocked by adapter pause
  - Enforced by: adapter interface doesn't mention pause

INVARIANT 4: Only Owner Can Pause
  - All pause functions: @onlyPauseOwner
  - pauseOwner is immutable
  - Cannot be changed by user
  - Enforced by: modifier + immutable variable

INVARIANT 5: Pause Reason Always Logged
  - Every pause includes reason string
  - Reason can be updated via updateGlobalPauseReason()
  - Enables transparent incident response
  - Enforced by: event logging + state storage
```

### 4.2 Reentrancy Protection

```
Reentrancy Risk: LOW
- EmergencyPause functions are access-controlled (onlyPauseOwner)
- Owner is not user-controlled
- Vault uses ReentrancyGuard on deposits/withdrawals
- Pause state changes don't trigger external calls
```

### 4.3 Storage Layout Safety

```
EmergencyPause Storage:
- pauseOwner: immutable (32 bytes, can't be written)
- _globalPauseActive: 1 byte boolean
- _globalPauseReason: 32 bytes (string storage pointer)
- _globalPauseTimestamp: 32 bytes (uint256)
- _adapterPaused: mapping (no fixed storage)
- _adapterPauseReason: mapping (no fixed storage)
- _adapterPauseTimestamp: mapping (no fixed storage)

Storage Collision Risk: ZERO
- Uses private variables (name-mangled)
- Mappings are isolated by key
- No storage delegation/upgrade patterns
- No clash with UniversalVault storage
```

### 4.4 Access Control

```
pauseOwner (immutable)
  └─ Only entity that can:
     ├─ enableGlobalPause()
     ├─ disableGlobalPause()
     ├─ pauseAdapter(adapter)
     ├─ unpauseAdapter(adapter)
     └─ updateGlobalPauseReason()

Typical Design Pattern:
pauseOwner = Multisig Wallet (Gnosis Safe)
  └─ Requires 3-of-5 signatures for any pause
  └─ Prevents single point of failure
  └─ Enables transparent governance
```

---

## 5. Integration Guide

### 5.1 Step-by-Step Integration

```solidity
// STEP 1: Inherit from EmergencyPause
contract UniversalVault is ReentrancyGuard, EmergencyPause {

  // STEP 2: Pass pauseOwner to EmergencyPause constructor
  constructor(address _asset, address _pauseOwner)
    EmergencyPause(_pauseOwner)
  { ... }

  // STEP 3: Add pause check to deposit()
  function deposit(uint256 amount)
    external
    nonReentrant
    whenDepositsNotPaused  // ← Add this
  { ... }

  // STEP 4: Add adapter operational check before deposit
  function _executeDeposit(address[] memory adapters, ...) internal {
    for (uint256 i = 0; i < adapters.length; i++) {
      _checkAdapterOperational(adapters[i]);  // ← Add this
      // ...call adapter.deposit()
    }
  }

  // STEP 5: Explicitly document withdrawal has NO pause
  function withdraw(uint256 shareAmount)
    external
    nonReentrant
    withdrawalAlwaysPermitted  // ← Document: no pause
  { ... }

  // STEP 6: Add strategy operation checks
  function setStrategy(...)
    external
    whenStrategyExecutionNotPaused  // ← Add this
  {
    // Also validate all adapters are operational
    for (uint256 i = 0; i < adapters.length; i++) {
      _checkAdapterOperational(adapters[i]);
    }
  }
}
```

### 5.2 Deployment Configuration

```solidity
// Deployment Parameters

address PAUSE_OWNER = 0x... // Multisig Gnosis Safe address
address ASSET = 0x... // USDC address
address VAULT = 0x...

// Deploy
UniversalVault vault = new UniversalVault(ASSET, PAUSE_OWNER);

// Verify pause owner is set correctly
assert(vault.pauseOwner() == PAUSE_OWNER);

// Verify vault is operational (not paused)
assert(vault.isGlobalPauseActive() == false);
```

### 5.3 Testing Checklist

```solidity
// PAUSE FUNCTIONALITY TESTS

test_enableGlobalPause()
  - ✅ Call enableGlobalPause() from pauseOwner
  - ✅ Verify isGlobalPauseActive() returns true
  - ✅ Verify GlobalPauseEnabled event emitted
  - ✅ Verify reason stored correctly
  - ✅ Verify timestamp recorded

test_deposit_blocked_during_pause()
  - ✅ Enable global pause
  - ✅ Call deposit() → should revert with DepositsPaused
  - ✅ Verify funds are NOT transferred

test_withdraw_allowed_during_pause()
  - ✅ Deposit funds (normal state)
  - ✅ Enable global pause
  - ✅ Call withdraw() → should succeed
  - ✅ Verify funds are transferred to user

test_pauseAdapter()
  - ✅ Call pauseAdapter(fusionXAddress)
  - ✅ Verify isAdapterPaused() returns true
  - ✅ Verify AdapterPaused event emitted
  - ✅ Deposit with FusionX should fail
  - ✅ Deposit with Lendle should succeed

test_copy_fees_accessible_during_pause()
  - ✅ Enable global pause
  - ✅ Call claimCopyFees() → should succeed
  - ✅ Verify fees are transferred to user

test_only_pause_owner_can_pause()
  - ✅ Call enableGlobalPause() from random user → revert
  - ✅ Call pauseAdapter() from random user → revert
  - ✅ Verify NotAuthorized error

test_adapter_return_value_validation()
  - ✅ Mock adapter returning 0 shares
  - ✅ Deposit attempt should revert with AdapterCallFailed
  - ✅ Verify no partial state updates
```

---

## 6. Gas Analysis

### 6.1 Function Costs

```
PAUSE OPERATIONS (Admin):
- enableGlobalPause()      ~5,000 gas (1 SSTORE + event + timestamp)
- disableGlobalPause()     ~5,000 gas (1 SSTORE + event)
- pauseAdapter()           ~8,000 gas (3 SSTORE + event)
- unpauseAdapter()         ~5,000 gas (1 SSTORE + event)
- updatePauseReason()      ~3,000 gas (1 SSTORE + event)

REGULAR OPERATIONS (Users):
- deposit() + pause check  +500 gas (1 SLOAD to check pause state)
- withdraw()               +0 gas (no pause checks)
- claimCopyFees()          +0 gas (no pause checks)

ADAPTER CALLS:
- _checkAdapterOperational()  ~2,100 gas (2 SLOAD for global + adapter pause)
- isAdapterOperational()      ~2,100 gas (view function)

Optimization Notes:
- Use view functions (no SSTORE)
- Batch adapter checks if possible
- Pause state is minimally accessed (only on first op)
```

### 6.2 Storage Efficiency

```
State Variables:
- pauseOwner (immutable)             32 bytes (slot 0)
- _globalPauseActive                 1 byte (slot 1)
- _globalPauseReason                 32 bytes (string ref, slot 2)
- _globalPauseTimestamp              32 bytes (slot 3)
- _adapterPaused (mapping)           dynamic (uses keccak256)
- _adapterPauseReason (mapping)      dynamic (uses keccak256)
- _adapterPauseTimestamp (mapping)   dynamic (uses keccak256)

Total Fixed Storage: ~128 bytes (4 slots)
Mapping Storage: O(n) where n = number of paused adapters
  - Typical case: 1-2 paused adapters = ~2 SSTORE per pause op
  - Worst case: 100 adapters = ~100 SSTORE (unlikely)
```

---

## 7. Why This Design Improves Exploit Response

### 7.1 Time to Mitigation

```
Without Emergency Pause:
T+0m:00s  Exploit detected
T+5m:00s  Security review complete
T+10m:00s Deploy new vault contract
T+15m:00s Migrate user funds (risky!)
T+20m:00s Live again
Impact: 20 minutes, 100% fund migration required

With Emergency Pause:
T+0m:00s  Exploit detected
T+1m:00s  Guardian submits pause tx
T+2m:00s  Pause confirmed on-chain
T+2m:30s  No new exploits can happen
T+10m:00s Security review complete
T+N+1m:00s Unpause after patch verified
Impact: 2.5 minutes to stop exploit, NO fund migration needed
```

### 7.2 Incident Response Capabilities

```
BEFORE Emergency Pause:
✅ Redeploy vault
❌ Migration risk
❌ Liquidity fragmentation
❌ Adapter coordination required
❌ Time-consuming

WITH Emergency Pause:
✅ 1-click pause any operation
✅ Zero fund migration
✅ Surgical per-adapter control
✅ Immediate effect
✅ Transparently logged
✅ Easily reversible

Example Scenarios:

Scenario 1: FusionX has flash loan bug
  → pauseAdapter(0xFusionX, "Flash loan detected")
  → Users withdraw from FusionX
  → FusionX funds consolidated
  → Issue fixed
  → unpauseAdapter(0xFusionX)
  → Resume operations

Scenario 2: Oracle manipulation in Lendle
  → pauseAdapter(0xLendle, "Price manipulation")
  → Users can exit before damage
  → All funds safe
  → Wait for oracle fix
  → unpauseAdapter(0xLendle)

Scenario 3: Critical vault bug discovered
  → enableGlobalPause("reentrancy in deposit()")
  → All deposits blocked
  → Withdrawals work
  → Users can exit if desired
  → Security team patches
  → Code audit passed
  → disableGlobalPause()
  → Resume operations
```

### 7.3 Monitoring Integration

```
Pause events for real-time monitoring:

event GlobalPauseEnabled(address indexed guardian, string reason)
event GlobalPauseDisabled(address indexed guardian)
event AdapterPaused(address indexed adapter, address indexed guardian, string reason)
event AdapterUnpaused(address indexed adapter, address indexed guardian)
event PauseReasonUpdated(string newReason)

Integration with alerting:
1. Parse event logs
2. Query isGlobalPauseActive()
3. Query pause reason via getGlobalPauseReason()
4. Alert stakeholders
5. Update UI to show pause status
6. Display pause reason for users

Example Alert Message:
"⚠️ MALGIST PAUSED: Exploit in deposit logic detected"
"Withdrawals remain available"
"Status: Investigating | ETA: 30 mins"
```

---

## 8. Comparison: Alternative Designs

### 8.1 Why Not Time-Locked Pause?

```
Option 1: Time-locked pause (48 hours before effect)
❌ Too slow for exploit response
❌ Exploiter has 48 hours to drain vault
❌ Not suitable for emergency
✅ Good for governance changes, not security

Our Design: Immediate pause
✅ Instant effect
✅ Suitable for emergency response
✅ Can add timelock later for non-emergency pauses
```

### 8.2 Why Not Pausable Adapter (Adapter-side Pause)?

```
Option 2: Each adapter implements pause
❌ Inconsistent pause logic across adapters
❌ Adapters must know about pause mechanism
❌ Adds complexity to adapter interface
❌ Potential for bugs in adapter pause logic
❌ Hard to coordinate multiple adapter pauses

Our Design: Vault-side pause (adapters unaware)
✅ Single source of truth (vault)
✅ Adapters stay simple
✅ Easy to pause any adapter instantly
✅ No adapter code changes needed
✅ Vault can pause external/third-party adapters
```

### 8.3 Why Not Role-Based Pause (Guardian vs. Owner)?

```
Option 3: Multiple roles (Owner, Guardian, Timelock)
❌ More complex state machine
❌ More code → more bugs
❌ Hard to coordinate role changes
❌ Overkill for MVP

Our Design: Single pauseOwner (typically multisig)
✅ Simple, clear
✅ Single responsibility: pause/unpause
✅ Easy to audit
✅ Can still use multisig for decentralization
```

---

## 9. Deployment Checklist

### Pre-Deployment

```
□ Code review completed
□ Unit tests pass (100% coverage)
□ Integration tests pass
□ Gas analysis completed and approved
□ Pause owner address confirmed (multisig)
□ Event logging tested
□ Adapter integration verified
□ Withdrawal always-allowed verified (no pause checks)
□ Reentrancy guard in place
□ Access control checked
```

### Deployment

```
□ Deploy EmergencyPause (or include in vault)
□ Deploy UniversalVault with pause owner address
□ Verify pauseOwner is set correctly
□ Verify isGlobalPauseActive() == false
□ Verify all adapters operational
```

### Post-Deployment

```
□ Monitor isGlobalPauseActive() (should be false)
□ Verify event logging works
□ Test pause/unpause with testnet
□ Document pause owner address in DAO
□ Set up monitoring/alerting for pause events
□ Brief guardian on pause procedures
□ Add "Pause Status" to UI dashboard
```

---

## 10. FAQ & Troubleshooting

### Q: Can I pause withdrawals?

**A:** No, and by design. Withdrawals are always allowed because user funds are never locked. This is a core safety principle.

### Q: What if I accidentally pause everything?

**A:** Call `disableGlobalPause()` immediately. Only pauseOwner can do this, so secure your multisig signing process.

### Q: How long should I keep pause active?

**A:** As short as possible. Use pause only to stop active exploits, not as a long-term solution. After 24+ hours, consider whether vault is still safe.

### Q: Can adapters override pause?

**A:** No. Adapters don't know about pause. Vault checks pause state BEFORE calling adapter, so adapter code is never executed.

### Q: What if adapter returns 0 shares?

**A:** Vault reverts with `AdapterCallFailed()`. This prevents silent failures.

### Q: Can I pause a paused adapter again?

**A:** No. Calling `pauseAdapter()` on an already-paused adapter reverts with `PauseAlreadyActive()`.

### Q: Can users migrate during pause?

**A:** Yes! Withdrawals work, so users can exit even if globally paused. Only NEW deposits are blocked.

---

## 11. Conclusion

The Emergency Control System provides:

✅ **Immediate exploit response** (sub-minute)  
✅ **User fund protection** (withdrawals always work)  
✅ **Granular control** (per-adapter pause)  
✅ **Gas efficiency** (O(1) pause operations)  
✅ **Clear audit trail** (comprehensive events)  
✅ **Production-grade safety** (no overengineering)

This design balances **security** (fast response) with **usability** (always withdraw) and **simplicity** (minimal code surface area).

---

**Document Version:** 1.0  
**Last Updated:** December 16, 2025  
**Status:** Ready for Production
