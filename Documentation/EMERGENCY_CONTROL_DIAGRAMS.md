# Emergency Control System - Architecture Diagrams

---

## System Architecture Overview

```
┌──────────────────────────────────────────────────────────────────┐
│                       UniversalVault                              │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │                   EmergencyPause (Mixin)                   │  │
│  │  ┌──────────────────────────────────────────────────────┐  │  │
│  │  │ STATE VARIABLES                                      │  │  │
│  │  │ ├─ pauseOwner (immutable)        : Multisig         │  │  │
│  │  │ ├─ _globalPauseActive           : bool             │  │  │
│  │  │ ├─ _globalPauseReason           : string           │  │  │
│  │  │ ├─ _globalPauseTimestamp        : uint256          │  │  │
│  │  │ ├─ _adapterPaused[]             : mapping          │  │  │
│  │  │ ├─ _adapterPauseReason[]        : mapping          │  │  │
│  │  │ └─ _adapterPauseTimestamp[]     : mapping          │  │  │
│  │  └──────────────────────────────────────────────────────┘  │  │
│  │  ┌──────────────────────────────────────────────────────┐  │  │
│  │  │ PUBLIC FUNCTIONS (onlyPauseOwner)                   │  │  │
│  │  │ ├─ enableGlobalPause(reason)                        │  │  │
│  │  │ ├─ disableGlobalPause()                             │  │  │
│  │  │ ├─ pauseAdapter(adapter, reason)                    │  │  │
│  │  │ ├─ unpauseAdapter(adapter)                          │  │  │
│  │  │ └─ updateGlobalPauseReason(newReason)              │  │  │
│  │  └──────────────────────────────────────────────────────┘  │  │
│  │  ┌──────────────────────────────────────────────────────┐  │  │
│  │  │ QUERY FUNCTIONS (Public View)                       │  │  │
│  │  │ ├─ isGlobalPauseActive()                            │  │  │
│  │  │ ├─ getGlobalPauseReason()                           │  │  │
│  │  │ ├─ getGlobalPauseTimestamp()                        │  │  │
│  │  │ ├─ isAdapterPaused(adapter)                         │  │  │
│  │  │ ├─ getAdapterPauseReason(adapter)                   │  │  │
│  │  │ ├─ getAdapterPauseTimestamp(adapter)                │  │  │
│  │  │ ├─ isAdapterOperational(adapter)                    │  │  │
│  │  │ └─ getPauseStatus()                                 │  │  │
│  │  └──────────────────────────────────────────────────────┘  │  │
│  │  ┌──────────────────────────────────────────────────────┐  │  │
│  │  │ MODIFIERS                                            │  │  │
│  │  │ ├─ @onlyPauseOwner                                  │  │  │
│  │  │ ├─ @whenDepositsNotPaused                           │  │  │
│  │  │ ├─ @whenStrategyExecutionNotPaused                  │  │  │
│  │  │ ├─ @whenAdapterNotPaused(adapter)                   │  │  │
│  │  │ └─ @withdrawalAlwaysPermitted                       │  │  │
│  │  └──────────────────────────────────────────────────────┘  │  │
│  └────────────────────────────────────────────────────────────┘  │
│                                                                   │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │                   Vault Core Functions                      │  │
│  │                                                             │  │
│  │  deposit(amount)        @whenDepositsNotPaused            │  │
│  │  withdraw(shares)       @withdrawalAlwaysPermitted        │  │
│  │  emergencyWithdraw()    @withdrawalAlwaysPermitted        │  │
│  │  setStrategy(...)       @whenStrategyExecutionNotPaused   │  │
│  │  copyStrategy(creator)  @whenStrategyExecutionNotPaused   │  │
│  │  claimCopyFees()        (no pause checks)                 │  │
│  │                                                             │  │
│  └────────────────────────────────────────────────────────────┘  │
│                                                                   │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │              Adapter Layer (External)                       │  │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐     │  │
│  │  │ FusionX      │  │ Lendle       │  │ Other        │     │  │
│  │  │ Adapter      │  │ Adapter      │  │ Adapters     │     │  │
│  │  │              │  │              │  │              │     │  │
│  │  │ deposit()    │  │ deposit()    │  │ deposit()    │     │  │
│  │  │ withdraw()   │  │ withdraw()   │  │ withdraw()   │     │  │
│  │  │ getBalance() │  │ getBalance() │  │ getBalance() │     │  │
│  │  └──────────────┘  └──────────────┘  └──────────────┘     │  │
│  │                                                             │  │
│  │  VAULT ENSURES:                                            │  │
│  │  • Adapter NOT called if paused                            │  │
│  │  • Adapter return values validated                         │  │
│  │  • Withdrawals always permitted from adapters             │  │
│  │                                                             │  │
│  └────────────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────────────┘
```

---

## State Machine Diagram

```
                    ┌─────────────────────────────────────┐
                    │      NORMAL STATE (default)          │
                    │  globalPauseActive = false          │
                    │  All adapters operational            │
                    │                                      │
                    │  ✅ Deposits: ALLOWED               │
                    │  ✅ Withdrawals: ALLOWED            │
                    │  ✅ Strategy ops: ALLOWED           │
                    └─────────────────────────────────────┘
                     ↑                                ↓
                     │                                │
              disableGlobalPause()          enableGlobalPause()
                     │                                │
                     ↑                                ↓
                    ┌─────────────────────────────────────┐
                    │    GLOBAL PAUSE STATE                │
                    │  globalPauseActive = true           │
                    │  All adapters operational            │
                    │                                      │
                    │  ❌ Deposits: BLOCKED               │
                    │  ✅ Withdrawals: ALLOWED            │
                    │  ❌ Strategy ops: BLOCKED           │
                    └─────────────────────────────────────┘

SEPARATE STATE MACHINE (Per-Adapter):

                    ┌─────────────────────────────────────┐
                    │   ADAPTER OPERATIONAL                 │
                    │  _adapterPaused[X] = false           │
                    │                                      │
                    │  ✅ Deposits through X: ALLOWED      │
                    │  ✅ Withdrawals from X: ALLOWED      │
                    └─────────────────────────────────────┘
                     ↑                                ↓
                     │                                │
               unpauseAdapter(X)              pauseAdapter(X)
                     │                                │
                     ↑                                ↓
                    ┌─────────────────────────────────────┐
                    │    ADAPTER PAUSED                    │
                    │  _adapterPaused[X] = true            │
                    │                                      │
                    │  ❌ Deposits through X: BLOCKED      │
                    │  ✅ Withdrawals from X: ALLOWED      │
                    └─────────────────────────────────────┘
```

---

## Call Flow: deposit() During Normal State

```
User calls: vault.deposit(1000e6)
    │
    ├─ ReentrancyGuard check
    │  └─ ✅ PASS (no reentrant call)
    │
    ├─ @whenDepositsNotPaused modifier
    │  ├─ Check: isGlobalPauseActive()?
    │  │  └─ NO (false) → Continue
    │  └─ ✅ PASS
    │
    ├─ Strategy retrieval
    │  └─ Get strategies[msg.sender]
    │
    ├─ Adapter operational validation (NEW)
    │  ├─ For each adapter in strategy:
    │  │  ├─ _checkAdapterOperational(adapter)
    │  │  │  ├─ Is adapter paused? NO
    │  │  │  ├─ Is global pause active? NO
    │  │  │  └─ ✅ PASS
    │  │  └─ Continue
    │
    ├─ Asset transfer
    │  ├─ ASSET.safeTransferFrom(user, vault, amount)
    │  └─ ✅ User funds received
    │
    ├─ Execute deposit
    │  ├─ For each adapter:
    │  │  ├─ Calculate allocation
    │  │  ├─ Approve adapter
    │  │  ├─ Call adapter.deposit(amount)
    │  │  ├─ Receive shares
    │  │  ├─ Validate: shares > 0 (NEW)
    │  │  │  └─ If shares == 0: revert AdapterDepositFailed()
    │  │  └─ ✅ Deposit successful
    │  │
    │  └─ ✅ All adapters processed
    │
    ├─ Share minting
    │  ├─ shares = netAmount
    │  ├─ strategies[user].shares += shares
    │  └─ ✅ Shares minted
    │
    ├─ Event emission
    │  └─ emit Deposited(user, amount, shares)
    │
    └─ Return shares to user
       └─ ✅ Deposit complete
```

---

## Call Flow: withdraw() During Global Pause

```
User calls: vault.withdraw(500e6)
    │
    ├─ ReentrancyGuard check
    │  └─ ✅ PASS (no reentrant call)
    │
    ├─ @withdrawalAlwaysPermitted modifier
    │  ├─ No-op (empty modifier)
    │  ├─ NO pause checks performed (intentional)
    │  └─ ✅ PASS (always allowed)
    │
    ├─ Validate share amount
    │  ├─ Is amount > 0? YES
    │  ├─ Is balance >= amount? YES
    │  └─ ✅ PASS
    │
    ├─ Execute withdrawal (from adapters)
    │  ├─ For each adapter:
    │  │  ├─ Calculate proportional withdrawal
    │  │  ├─ Call adapter.withdraw(amount)
    │  │  │  ├─ NOTE: Even if adapter is paused, withdrawal continues
    │  │  │  ├─ Adapter MUST allow this (design requirement)
    │  │  │  └─ ✅ Withdrawal processed
    │  │  │
    │  │  ├─ Receive withdrawn amount
    │  │  ├─ Validate: withdrawn > 0 (NEW)
    │  │  │  └─ If withdrawn == 0: revert AdapterWithdrawFailed()
    │  │  └─ Add to total
    │  │
    │  └─ ✅ All adapters processed (pause doesn't affect this)
    │
    ├─ Update share balance
    │  ├─ strategies[user].shares -= shareAmount
    │  └─ ✅ Shares burned
    │
    ├─ Transfer assets to user
    │  ├─ ASSET.safeTransfer(user, withdrawn)
    │  └─ ✅ Funds returned (PAUSE CAN'T BLOCK THIS)
    │
    ├─ Update TVL tracking
    │  ├─ If copier: decrement creator's totalCopierTVL
    │  └─ ✅ Accounting updated
    │
    ├─ Event emission
    │  └─ emit Withdrawn(user, shares, withdrawn)
    │
    └─ Return withdrawn amount
       └─ ✅ Withdrawal complete (even during pause!)
```

---

## Call Flow: deposit() During Global Pause

```
User calls: vault.deposit(1000e6)
    │
    ├─ ReentrancyGuard check
    │  └─ ✅ PASS
    │
    ├─ @whenDepositsNotPaused modifier
    │  ├─ Check: isGlobalPauseActive()?
    │  │  └─ YES (true) → STOP
    │  └─ ❌ REVERT: DepositsPaused
    │
    └─ ❌ DEPOSIT FAILED
       User's funds remain in wallet
       No state changes occurred
```

---

## Call Flow: Pause Activation

```
Guardian calls: vault.enableGlobalPause("Exploit detected")
    │
    ├─ OnlyPauseOwner check
    │  ├─ msg.sender == pauseOwner?
    │  │  └─ YES → Continue
    │  └─ ✅ PASS
    │
    ├─ Validation
    │  ├─ Is pause already active?
    │  │  └─ NO → Continue
    │  └─ ✅ PASS
    │
    ├─ State update
    │  ├─ _globalPauseActive = true
    │  ├─ _globalPauseReason = "Exploit detected"
    │  ├─ _globalPauseTimestamp = block.timestamp
    │  └─ ✅ State saved
    │
    ├─ Event emission
    │  └─ emit GlobalPauseEnabled(guardian, "Exploit detected")
    │     └─ Event indexed for monitoring
    │
    └─ ✅ Pause activated

       IMMEDIATE EFFECT:
       • New deposits: BLOCKED
       • Strategy operations: BLOCKED
       • Withdrawals: STILL ALLOWED
       • Copy fees: STILL CLAIMABLE
```

---

## Adapter Pause Flow (Surgical Control)

```
Guardian calls: vault.pauseAdapter(0xFusionX, "Flash loan bug")
    │
    ├─ OnlyPauseOwner check
    │  └─ ✅ PASS
    │
    ├─ Validation
    │  ├─ Is adapter address valid?
    │  │  └─ YES → Continue
    │  ├─ Is adapter already paused?
    │  │  └─ NO → Continue
    │  └─ ✅ PASS
    │
    ├─ State update
    │  ├─ _adapterPaused[0xFusionX] = true
    │  ├─ _adapterPauseReason[0xFusionX] = "Flash loan bug"
    │  ├─ _adapterPauseTimestamp[0xFusionX] = block.timestamp
    │  └─ ✅ State saved
    │
    ├─ Event emission
    │  └─ emit AdapterPaused(0xFusionX, guardian, "Flash loan bug")
    │
    └─ ✅ Adapter paused

       IMMEDIATE EFFECT:
       • FusionX deposits: BLOCKED
       • Lendle deposits: STILL ALLOWED (unaffected)
       • FusionX withdrawals: STILL ALLOWED
       • Other adapters: UNAFFECTED
```

---

## Emergency Response Timeline

```
T+0:00 EXPLOIT DETECTED
       └─ Unusual transaction pattern observed

T+0:30 CONFIRMED
       └─ Security team verifies exploit

T+1:00 DECISION MADE
       ├─ Type 1 (Adapter-specific):
       │  └─ pauseAdapter(0xFusionX, "Flash loan")
       │     └─ TX submitted to multisig
       │
       └─ Type 2 (Vault-wide):
          └─ enableGlobalPause("Reentrancy bug")
             └─ TX submitted to multisig

T+2:00 MULTISIG SIGNED
       └─ 3 of 5 guardians approve pause

T+2:30 PAUSE CONFIRMED
       └─ TX mined on-chain
       ├─ Deposits blocked
       ├─ Withdrawals still work
       └─ Event logged for monitoring

T+5:00 EXPLOITATION STOPPED
       └─ No new exploits possible
       ├─ Users can exit
       ├─ TVL protected from T+2:30 onward
       └─ Damage contained

T+30:00 PATCH VERIFIED
        └─ Code fix reviewed
        ├─ Security audit completed
        ├─ Testnet verified
        └─ Ready to resume

T+31:00 RESUME OPERATIONS
        └─ disableGlobalPause() or unpauseAdapter()
        ├─ Full functionality restored
        ├─ Event logged
        └─ Users notified

TIMELINE SUMMARY:
• Exploit window: 5 minutes (T+0 to T+5)
• No fund migration needed
• Zero vault redeploy needed
• Single transaction to resume
```

---

## Storage Layout

```
EmergencyPause Storage (Fixed):

Slot 0:  pauseOwner (address, immutable)           32 bytes
Slot 1:  _globalPauseActive (bool)                 1 byte + padding
Slot 2:  _globalPauseReason (string pointer)       32 bytes
Slot 3:  _globalPauseTimestamp (uint256)           32 bytes

Total Fixed: 128 bytes (4 slots)

Dynamic Storage (Mappings):
- _adapterPaused: keccak256(adapter || slot_number)
- _adapterPauseReason: keccak256(adapter || slot_number)
- _adapterPauseTimestamp: keccak256(adapter || slot_number)

Example:
pauseAdapter(0xFusionX)
├─ keccak256(0xFusionX || slot_for_adapterPaused) → new SSTORE
└─ Cost: ~20,000 gas for cold storage write

Update in same tx:
updateGlobalPauseReason()
├─ Slot 2 write (warm) → ~5,000 gas
└─ Total: ~5,000 gas per reason update
```

---

## Event Log Indexing

```
Off-chain Monitoring System:

Event: GlobalPauseEnabled(address indexed guardian, string reason)
  │
  ├─ Monitor filter: topic0 = GlobalPauseEnabled
  ├─ Indexed: guardian (can filter by multisig)
  └─ Data: reason string

  Action:
  ├─ Alert: "Vault paused by 0x[guardian]"
  ├─ Details: "Reason: Exploit detected"
  ├─ Severity: HIGH
  └─ Action: Notify users

Event: AdapterPaused(address indexed adapter, address indexed guardian, string reason)
  │
  ├─ Monitor filter: topic0 = AdapterPaused
  ├─ Indexed: adapter (can filter by adapter type)
  ├─ Indexed: guardian (can filter by multisig)
  └─ Data: reason string

  Action:
  ├─ Alert: "FusionX adapter paused"
  ├─ Details: "Reason: Flash loan exploit"
  ├─ Impact: "Deposits blocked, withdrawals allowed"
  └─ Action: User notification

Real-time Dashboard:
┌─────────────────────────────────────────┐
│ PAUSE STATUS                             │
├─────────────────────────────────────────┤
│ Global Pause:        NO                  │
│ Paused Adapters:     0                   │
│ Last Action:         None                │
│ Last Action Time:    -                   │
│ Guardian:            -                   │
└─────────────────────────────────────────┘

When paused:
┌─────────────────────────────────────────┐
│ ⚠️ PAUSE ACTIVE                         │
├─────────────────────────────────────────┤
│ Type:                Global               │
│ Reason:              Exploit detected    │
│ Guardian:            0x[multisig]        │
│ Activated:           2024-12-16 10:30 UTC│
│ Duration:            23 minutes          │
│ Deposits:            ❌ BLOCKED          │
│ Withdrawals:         ✅ ALLOWED          │
│ Est. Resolution:     30 minutes          │
└─────────────────────────────────────────┘
```

---

**Diagram Version:** 1.0  
**Last Updated:** December 16, 2025  
**Status:** Production-Ready
