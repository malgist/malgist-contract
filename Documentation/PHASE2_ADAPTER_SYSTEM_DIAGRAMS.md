<!-- Documentation/PHASE2_ADAPTER_SYSTEM_DIAGRAMS.md -->

# Phase 2: Modular Adapter System — Architecture Diagrams & Visual Reference

**Date:** December 17, 2025  
**Purpose:** Visual representations of adapter architecture, risk isolation, and governance flows

---

## DIAGRAM 1: Adapter Pattern (Monolithic vs Modular)

```
╔════════════════════════════════════════════════════════════════════════╗
║                    ARCHITECTURE EVOLUTION                             ║
╚════════════════════════════════════════════════════════════════════════╝

BEFORE: Monolithic Vault (❌ Hard to scale)
────────────────────────────────────────

┌──────────────────────────────────────────────────────────┐
│                  ComposableVault                         │
│  ┌────────────────────────────────────────────────────┐  │
│  │                                                    │  │
│  │  Core Logic:                                       │  │
│  │  ├─ Deposit/Withdraw                              │  │
│  │  ├─ Share calculation                             │  │
│  │  ├─ ERC4626 compliance                            │  │
│  │                                                    │  │
│  │  + Aave Integration:                              │  │
│  │  ├─ Approve AAVE token                            │  │
│  │  ├─ Call lendingPool.deposit()                    │  │
│  │  ├─ Track aToken balance                          │  │
│  │                                                    │  │
│  │  + Uniswap Integration:                           │  │
│  │  ├─ Swap logic                                    │  │
│  │  ├─ Liquidity add/remove                          │  │
│  │  ├─ Track LP tokens                               │  │
│  │                                                    │  │
│  │  + Curve Integration:                             │  │
│  │  ├─ Pool deposit logic                            │  │
│  │  ├─ LP token tracking                             │  │
│  │                                                    │  │
│  │  + Lending Pool Integration:                      │  │
│  │  ├─ Custom approval flows                         │  │
│  │  ├─ Rate calculations                             │  │
│  │                                                    │  │
│  │  Problems:                                         │  │
│  │  ✗ 10k+ LOC in single contract                   │  │
│  │  ✗ Hard to audit (too many concerns)             │  │
│  │  ✗ New protocol = vault redeploy                 │  │
│  │  ✗ One bug = entire system affected              │  │
│  │  ✗ Complex governance (touch core contract)      │  │
│  │  ✗ Difficult to test (all integrated)            │  │
│  │                                                    │  │
│  └────────────────────────────────────────────────────┘  │
│                                                          │
└──────────────────────────────────────────────────────────┘


AFTER: Modular Vault + Adapters (✅ Easy to scale)
──────────────────────────────────────────────

┌──────────────────────────────────────────────────────────┐
│              ERC4626StrategyVault                        │
│  ┌────────────────────────────────────────────────────┐  │
│  │ Core Logic Only:                                   │  │
│  │ ├─ Deposit/Withdraw                               │  │
│  │ ├─ Share calculation                              │  │
│  │ ├─ ERC4626 compliance                             │  │
│  │ ├─ Access control                                 │  │
│  │ ├─ Risk management (pause/disable)                │  │
│  │ └─ Adapter routing                                │  │
│  │                                                    │  │
│  │ Just 845 LOC — focused, clean, auditable          │  │
│  └────────────────────────────────────────────────────┘  │
│                     ↓                                    │
│              IAdapter Interface                         │
│          (4-function standard contract)                 │
│                     ↓                                    │
│  ┌─────────────┬─────────────┬─────────────┐            │
│  │             │             │             │            │
│  ↓             ↓             ↓             ↓            │
│
│ ┌────────────┐ ┌────────────┐ ┌────────────┐           │
│ │   Aave     │ │  FusionX   │ │   Lendle   │           │
│ │  Adapter   │ │  Adapter   │ │  Adapter   │           │
│ │            │ │            │ │            │           │
│ │ 100 LOC    │ │ 100 LOC    │ │ 100 LOC    │           │
│ │ Isolated   │ │ Isolated   │ │ Isolated   │           │
│ │ Testing    │ │ Testing    │ │ Testing    │           │
│ │ Deploy     │ │ Deploy     │ │ Deploy     │           │
│ │            │ │            │ │            │           │
│ └────────────┘ └────────────┘ └────────────┘           │
│
│ Benefits:                                               │
│ ✓ Small contracts (easy to audit)                      │
│ ✓ New protocol = new adapter (no vault touch)          │
│ ✓ One adapter fails = others unaffected                │
│ ✓ Parallel development (teams work independently)      │
│ ✓ Simple governance (adapter whitelist votes)          │
│ ✓ Comprehensive testing (unit tests per adapter)       │
│                                                        │
└──────────────────────────────────────────────────────────┘
```

---

## DIAGRAM 2: Risk Isolation Mechanics

```
╔════════════════════════════════════════════════════════════════════════╗
║               RISK ISOLATION: Failure Containment                      ║
╚════════════════════════════════════════════════════════════════════════╝

Scenario: FusionX adapter exploited, loses 40M TVL

WITHOUT ISOLATION (Monolithic Vault):
──────────────────────────────────

  Vault TVL: 50M USDC
  ├─ 40M in FusionX (DEX liquidity)
  └─ 10M in Lendle (lending pool)

  EXPLOIT: FusionX hacked, 40M stolen
  ─────

  Impact Cascade:
  1. Vault tries to withdraw from FusionX
     → Returns 0 USDC (protocol drained)

  2. Vault accounting shows:
     Total = Lendle (10M) + FusionX (0) = 10M
     But promised 50M shares!

  3. Share price crashes:
     50M worth of shares backed by 10M
     → 80% loss for all users

  4. Death spiral:
     Users panic withdraw
     → Lendle drained next
     → Protocol collapses


WITH ISOLATION (Modular Vault + Adapters):
───────────────────────────────────────

  Vault TVL: 50M USDC
  ├─ 40M in FusionX Adapter (DEX liquidity, CAP: 45M)
  └─ 10M in Lendle Adapter (lending pool, CAP: 15M)

  EXPLOIT: FusionX adapter hacked, 40M stolen
  ──────

  Response:
  1. Governance detects exploit (on-chain monitor)

  2. Owner pauses FusionX adapter:
     pauseAdapter(FusionXAdapter)
     ✓ All new deposits blocked
     ✓ Existing deposits stuck (mitigated)

  3. Vault continues functioning:
     Total = Lendle (10M) + FusionX (0) = 10M
     ✗ Users in FusionX: lose 40M
     ✓ Users in Lendle: still earn yield, fully protected

  4. Damage assessment:
     ✗ Users proportionally exposed to FusionX: -80%
     ✓ Users only in Lendle: 0% loss
     ✓ Vault stays operational, other adapters survive

  5. Recovery options:
     a) Migrate FusionX users to Lendle (over time)
     b) Wait for FusionX recovery + re-enable
     c) Gradually disable adapter, settle users

  OUTCOME: 80% loss for FusionX users, 0% loss for Lendle users


QUANTIFIED COMPARISON:
─────────────────────

                  Monolithic          Modular (Isolated)
Total TVL         50M                 50M
FusionX Loss      40M (100%)          40M (FusionX only)
Lendle Protected  ✗ (No)              ✓ (Yes)
Vault Operations  ✗ (Frozen)          ✓ (Continues)
User Loss (avg)   40/50 = 80%         40/50 = 80%, but only FusionX users
User Loss (Lendle only) N/A            0%

KEY INSIGHT: Isolation doesn't prevent loss, but LIMITS IT
            Users choosing Lendle stay safe even if FusionX fails
            Vault itself survives (continues operating)
```

---

## DIAGRAM 3: Adapter Lifecycle & State Machine

```
╔════════════════════════════════════════════════════════════════════════╗
║              ADAPTER LIFECYCLE: Proposal → Active → Sunset             ║
╚════════════════════════════════════════════════════════════════════════╝

Timeline: From community interest to production deployment

WEEK 1: PROPOSAL PHASE
───────────────────────

  Community Interest
         │
         ├─ "Can we add Aave to MALGIST?"
         │
  Developer responds
         │
         ├─ "I'll write Aave adapter, send audit report"
         │
         ▼

  ┌──────────────────────────────┐
  │  1. Write Adapter Code       │
  │  ├─ Implement IAdapter       │
  │  ├─ Test locally             │
  │  ├─ Gas optimize             │
  │  └─ Security review          │
  │                              │
  │  Output: AaveAdapter.sol     │
  └──────────────┬───────────────┘
                 │
  ┌──────────────▼───────────────┐
  │  2. Security Audit           │
  │  ├─ Code review              │
  │  ├─ Test coverage check      │
  │  ├─ Vulnerability scan       │
  │  └─ Generate audit report    │
  │                              │
  │  Output: auditReport.pdf     │
  │           (hash: 0x...)      │
  └──────────────┬───────────────┘
                 │
  ┌──────────────▼───────────────┐
  │  3. Propose to DAO           │
  │  vault.proposeAdapter(       │
  │    aaveAdapter,              │
  │    0xauditHash               │
  │  )                           │
  │                              │
  │  Status: PROPOSED            │
  │  Time: Week 1, Day 1         │
  └──────────────┬───────────────┘
                 │
                 ▼
         STATE: PROPOSED


WEEK 2: REVIEW PHASE
────────────────────

  Community Review (48 hours)
         │
         ├─ "Let's evaluate Aave risks"
         ├─ "Check liquidity in protocol"
         ├─ "Review audit findings"
         ├─ "Estimate APY benefit"
         │
         ▼

  ┌──────────────────────────────┐
  │  Risk Assessment             │
  │  ├─ Aave protocol safety     │
  │  ├─ Liquidity depth check    │
  │  ├─ Adapter code review      │
  │  ├─ Test report validation   │
  │  └─ Set initial TVL cap      │
  │     (conservative: 5M USDC)  │
  └──────────────┬───────────────┘
                 │
  ┌──────────────▼───────────────┐
  │  Governance Discussion       │
  │  (Discord, Snapshot forum)   │
  │  ├─ Pro: Aave is battle-tested
  │  ├─ Pro: High APY (12% vs 8% Lendle)
  │  ├─ Con: Centralization risk (AAVE token)
  │  ├─ Decision: Proceed to vote
  │  │           (Pro votes > Con)
  └──────────────┬───────────────┘
                 │
  ┌──────────────▼───────────────┐
  │  Status: AUDITED             │
  │  Time: Week 2, Day 2         │
  └──────────────┬───────────────┘
                 │
                 ▼
         STATE: AUDITED


WEEK 2-3: GOVERNANCE PHASE
──────────────────────────

  DAO Vote (72 hours)
         │
         ├─ "Snapshot: Enable AaveAdapter?"
         ├─ Voting period: 3 days
         ├─ Quorum: 30% of MALGIST token holders
         ├─ Threshold: 50%+ approval
         │
         ▼

  ┌──────────────────────────────┐
  │  Governance Results          │
  │  ├─ For:    65% (PASSED ✓)   │
  │  ├─ Against: 30%             │
  │  ├─ Abstain: 5%              │
  │  └─ Quorum:  42% ✓           │
  └──────────────┬───────────────┘
                 │
  ┌──────────────▼───────────────┐
  │  Status: APPROVED            │
  │  Time: Week 3, Day 1         │
  │                              │
  │  Next: Owner enables adapter │
  │        vault.enableAdapter() │
  └──────────────┬───────────────┘
                 │
                 ▼
         STATE: APPROVED


WEEK 3-4: ACTIVATION PHASE
───────────────────────────

  Owner Activation
         │
         ├─ Timelock delay (12 hours)
         ├─ Wallet sign tx
         ├─ vault.enableAdapter(aaveAdapter)
         │
         ▼

  ┌──────────────────────────────┐
  │  Status: ACTIVE              │
  │  Time: Week 3, Day 2         │
  │  TVL Cap: 5M USDC            │
  │  Features:                   │
  │  ├─ Users can deposit        │
  │  ├─ Yield auto-generated     │
  │  ├─ Governance can pause     │
  │  └─ Owner can disable        │
  └──────────────┬───────────────┘
                 │
         ▼
         STATE: ACTIVE


MONITORING PHASE (30 days)
──────────────────────────

  Daily checks:
  ├─ Is APY as expected? (↓ from 12% to 8% = investigate)
  ├─ Is gas usage reasonable? (> 150k per tx = alert)
  ├─ Any unusual patterns? (sudden withdrawals = monitor)
  ├─ Aave protocol OK? (high slippage = pause)
  │
  If issues found:
  │
  PAUSE: vault.pauseAdapter(aaveAdapter)
  ├─ New deposits blocked
  ├─ Withdrawals continue
  ├─ Team investigates fix
  ├─ Re-enable after fix
  │
  DISABLE: vault.disableAdapter(aaveAdapter)
  ├─ Permanent removal
  ├─ Emergency response
  ├─ Migrate users to other adapters
  │
  OK: Continue normal operation
  └─ Move to next phase


LONG-TERM: SUNSET PHASE (6+ months)
────────────────────────────────────

  After monitoring period, one of:

  PROMOTED to PRIMARY:
  ├─ Expand TVL cap (5M → 20M)
  ├─ Feature in marketing
  ├─ Include in default strategy
  └─ Long-term adapter

  MAINTAINED:
  ├─ Keep TVL cap low (5M)
  ├─ Monitor for issues
  ├─ Useful for hedging
  └─ Optional adapter

  SUNSET / DEPRECATED:
  ├─ Better alternative found
  ├─ Protocol degradation detected
  ├─ Lower TVL cap (5M → 1M)
  ├─ Announce phase-out (3 month notice)
  ├─ Migrate users gradually
  └─ Eventually disable


STATE SUMMARY:
──────────────

  PROPOSED  ──[audit]──> AUDITED ──[vote]──> APPROVED ──[enable]──> ACTIVE
                                                                         │
                                                             ┌──────────┼──────────┐
                                                             │          │          │
                                                             ▼          ▼          ▼
                                                          MAINTAINED PROMOTED  SUNSET


GOVERNANCE CHECKPOINTS:
───────────────────────

  ✓ Week 1, Day 1: Propose with audit hash
  ✓ Week 2, Day 2: Community review complete
  ✓ Week 3, Day 1: DAO vote passed
  ✓ Week 3, Day 2: Owner activates (timelock)
  ✓ Week 4-8: Monitor (30 day check-in)
  ✓ Week 8+: Governance votes on long-term status
```

---

## DIAGRAM 4: Adapter Dispatch Flow (Execution)

```
╔════════════════════════════════════════════════════════════════════════╗
║        ADAPTER DISPATCH: How Vault Routes to Adapters                 ║
╚════════════════════════════════════════════════════════════════════════╝

User Calls: vault.deposit(1000 USDC)
────────────────────────────────────

  user
   │
   │ deposit(1000)
   │
   ▼
  ┌──────────────────────────────┐
  │   ERC4626StrategyVault       │
  │   deposit() function         │
  └──────────────┬───────────────┘
                 │
  ┌──────────────▼───────────────┐
  │   Step 1: VALIDATE INPUT     │
  │   ├─ amount > 0? ✓           │
  │   ├─ not paused? ✓           │
  │   ├─ slippage OK? ✓          │
  │   └─ user balance OK? ✓      │
  └──────────────┬───────────────┘
                 │
  ┌──────────────▼───────────────┐
  │   Step 2: TRANSFER FROM USER │
  │   USDC.transferFrom(         │
  │     msg.sender,              │
  │     address(this),           │
  │     1000                      │
  │   )                          │
  │   ✓ Vault now holds 1000 USDC│
  └──────────────┬───────────────┘
                 │
  ┌──────────────▼───────────────┐
  │   Step 3: CALCULATE SHARES   │
  │   shares = (1000 * totalSup) │
  │            / totalAssets     │
  │   = 1000 shares (first call) │
  └──────────────┬───────────────┘
                 │
  ┌──────────────▼───────────────────────────────┐
  │   Step 4: UPDATE VAULT STATE                 │
  │   totalShares += 1000                        │
  │   userShares[user] += 1000                   │
  │   ✓ State finalized (before external calls) │
  └──────────────┬───────────────────────────────┘
                 │
  ┌──────────────▼───────────────────────────────┐
  │   Step 5: DISPATCH TO ADAPTERS               │
  │                                              │
  │   Current strategy:                          │
  │   Adapters: [FusionX, Lendle]                │
  │   Ratios:   [5000, 5000]    (50/50)          │
  │                                              │
  │   Cache adapter count: length = 2            │
  │                                              │
  │   for (i = 0; i < 2; i++) {                 │
  │     if (!adapterEnabled[adapters[i]])        │
  │       continue;  // Skip disabled            │
  │     if (adapterPaused[adapters[i]])          │
  │       continue;  // Skip paused              │
  │     ...                                      │
  │   }                                          │
  └──────────────┬───────────────────────────────┘
                 │
        ┌────────┼────────┐
        │        │        │
        ▼        ▼        ▼
   (i=0)    (i=1)

   ┌─────────────────────┐    ┌──────────────────────┐
   │ Iteration 1: i=0    │    │  Iteration 2: i=1    │
   │ Adapter: FusionX    │    │  Adapter: Lendle     │
   └─────────────────────┘    └──────────────────────┘
        │                          │
   ┌────▼────────────────┐    ┌────▼─────────────────┐
   │ Check enabled? ✓    │    │ Check enabled? ✓     │
   │ Check paused? ✓     │    │ Check paused? ✓      │
   │ Check cap? ✓        │    │ Check cap? ✓         │
   │   balance + 500     │    │   balance + 500      │
   │   <= 10M? ✓         │    │   <= 10M? ✓          │
   └────┬────────────────┘    └────┬─────────────────┘
        │                          │
   ┌────▼────────────────┐    ┌────▼─────────────────┐
   │ Calculate share:     │    │ Calculate share:     │
   │ share = (1000 * 50%) │    │ share = (1000 * 50%) │
   │       = 500 USDC     │    │       = 500 USDC     │
   └────┬────────────────┘    └────┬─────────────────┘
        │                          │
   ┌────▼────────────────────────────────────────┐
   │ Call IAdapter interface                     │
   │ (Same for both, protocol-agnostic)          │
   │                                             │
   │ deposited = IAdapter(adapters[i])           │
   │            .deposit(500)                    │
   │                                             │
   │ Return: How much adapter actually accepted │
   └────┬───────────────────────────────────────┘
        │
   ┌────▼──────────────────┐    ┌───▼──────────────────┐
   │ FusionX.deposit(500)   │    │ Lendle.deposit(500)   │
   │                        │    │                       │
   │ 1. Swap 250 USDC → MNT │    │ 1. Approve 500 USDC   │
   │ 2. Add liq (250+250)   │    │ 2. Call pool.deposit()│
   │ 3. Receive LP token    │    │ 3. Receive lToken     │
   │ 4. Return: 500         │    │ 4. Return: 500        │
   └────┬──────────────────┘    └────┬──────────────────┘
        │                            │
   ┌────▼──────────────────┐    ┌────▼──────────────────┐
   │ Validate return       │    │ Validate return       │
   │ ├─ 500 <= 500? ✓      │    │ ├─ 500 <= 500? ✓      │
   │ ├─ 500 > 0? ✓        │    │ ├─ 500 > 0? ✓        │
   │ └─ Update balance:    │    │ └─ Update balance:    │
   │   fusionxBalance += 500    │   lendleBalance += 500
   │                       │    │                       │
   └───────────────────────┘    └─────────────────────┘

        ┌────────────────────────────────┐
        │                                │
        ▼
   ┌──────────────────────────────┐
   │  Step 6: EMIT EVENT          │
   │  Deposit(                    │
   │    user,                     │
   │    1000 USDC,                │
   │    1000 shares               │
   │  )                           │
   └──────────────┬───────────────┘
                  │
                  ▼
   ┌──────────────────────────────┐
   │  RETURN to user              │
   │  ✓ 1000 shares issued        │
   │  ✓ 500 in FusionX (LP token) │
   │  ✓ 500 in Lendle (lToken)    │
   │                              │
   │ User can now:                │
   │ ├─ See yield (6-12% APY)     │
   │ ├─ Check balance in UI       │
   │ ├─ Withdraw later            │
   │ └─ Claim rewards             │
   └──────────────────────────────┘


KEY SAFETY FEATURES:
────────────────────

1. STATE BEFORE CALLS (CEI pattern)
   ✓ All vault state updated before external calls
   ✓ Prevents reentrancy attacks

2. BOUNDED LOOPS
   ✓ Max 10 adapters (cache length once)
   ✓ Predictable gas cost (50-150k)
   ✓ No DoS vectors

3. ADAPTER VALIDATION
   ✓ Check enabled before calling
   ✓ Check paused before calling
   ✓ Check TVL cap before accepting
   ✓ Validate return value (≤ input)

4. ADAPTER ISOLATION
   ✓ If FusionX fails, skip and continue
   ✓ If Lendle fails, revert just that portion
   ✓ Vault continues for other adapters

5. CUSTOM ERRORS
   ✓ Gas efficient (no string messages)
   ✓ Clear error codes for debugging
   ✓ Auditor-friendly (predictable reverts)
```

---

## DIAGRAM 5: Risk Isolation Matrix

```
╔════════════════════════════════════════════════════════════════════════╗
║          RISK ISOLATION: Matrix of Failure Scenarios                  ║
╚════════════════════════════════════════════════════════════════════════╝

Vault State:
├─ User A: 50% FusionX, 50% Lendle (diversified)
├─ User B: 100% Lendle (conservative)
├─ User C: 100% FusionX (aggressive)
└─ Total TVL: 100M USDC across 2 adapters


SCENARIO 1: FusionX Adapter Fails (Bug in adapter code)
──────────────────────────────────────────────────────

  Failure Type: getBalance() returns incorrect value
  Impact: Vault accounting becomes wrong

  User A (50/50):
  ├─ FusionX portion:
  │  ├─ Status: ⚠️ Stuck (can't withdraw accurately)
  │  ├─ Balance: Shows wrong (50M appears as 30M)
  │  └─ Loss: Accounting error (not fund loss)
  ├─ Lendle portion:
  │  ├─ Status: ✓ OK (untouched)
  │  ├─ Balance: Shows correct (25M)
  │  └─ Loss: 0
  └─ Total Loss: 0 (accounting issue only)

  User B (100% Lendle):
  ├─ Status: ✓ UNAFFECTED
  ├─ Balance: Shows correct (25M)
  └─ Loss: 0

  User C (100% FusionX):
  ├─ Status: ⚠️ Stuck
  ├─ Balance: Shows wrong (50M appears as 30M)
  └─ Loss: Accounting error (actual funds safe in protocol)

  ISOLATION BENEFIT:
  ✓ User B completely protected (different adapter)
  ✓ User A's Lendle portion protected
  ✓ Only FusionX accounting affected (recoverable)

  GOVERNANCE RESPONSE:
  1. Pause FusionX adapter
  2. Fix adapter code (improve getBalance())
  3. Redeploy adapter (no vault change)
  4. Resume FusionX operations


SCENARIO 2: Lendle Protocol Gets Exploited (Not adapter fault)
──────────────────────────────────────────────────────────

  Failure Type: Lendle lending pool hacked, 50M stolen
  Impact: Protocol-level failure (not adapter code)

  User A (50% FusionX, 50% Lendle):
  ├─ FusionX portion:
  │  ├─ Status: ✓ SAFE
  │  ├─ Balance: 25M (unaffected)
  │  └─ Loss: 0
  ├─ Lendle portion:
  │  ├─ Status: ❌ EXPLOITED
  │  ├─ Balance: 25M → 0 (fund loss at protocol)
  │  └─ Loss: 25M (50% of user's stake)
  └─ Total Loss: 25M (50% of user's total)

  User B (100% Lendle):
  ├─ Status: ❌ EXPLOITED
  ├─ Balance: 25M → 0
  └─ Loss: 25M (100% of user's stake)

  User C (100% FusionX):
  ├─ Status: ✓ UNAFFECTED
  ├─ Balance: 50M (untouched)
  └─ Loss: 0

  ISOLATION BENEFIT:
  ✓ User C completely safe (different adapter)
  ✓ FusionX adapter continues operating
  ✓ Vault remains functional for other users

  GOVERNANCE RESPONSE:
  1. Pause Lendle adapter (stop new deposits)
  2. Announce to users: "Lendle exploit, checking recovery options"
  3. Monitor Lendle protocol recovery efforts
  4. If unrecoverable, disable adapter
  5. Users gradually withdraw from FusionX

  WITHOUT ISOLATION:
  ✗ All 50M stolen (users A, B, C all lose 100%)
  ✗ Vault frozen (accounting failure)


SCENARIO 3: Adapter Contract Compromised (Private key leak)
───────────────────────────────────────────────────────────

  Failure Type: Attacker gains signer on FusionX adapter
  Impact: Attacker can withdraw from adapter

  User A (50/50):
  ├─ FusionX portion:
  │  ├─ Status: ⚠️ AT RISK
  │  ├─ Balance: 25M vulnerable to theft
  │  └─ Loss: Depends on owner response time
  ├─ Lendle portion:
  │  ├─ Status: ✓ SAFE
  │  ├─ Balance: 25M protected
  │  └─ Loss: 0
  └─ Total potential loss: 25M (50% of stake)

  User B (100% Lendle):
  ├─ Status: ✓ UNAFFECTED
  └─ Loss: 0

  User C (100% FusionX):
  ├─ Status: ❌ AT RISK
  └─ Potential loss: 50M (100% of stake)

  ISOLATION BENEFIT:
  ✓ User B's funds 100% safe
  ✓ Vault core contract untouched
  ✓ Only FusionX adapter at risk

  GOVERNANCE RESPONSE:
  1. Detect unusual withdraw from FusionX (on-chain monitor)
  2. Owner immediately pauses FusionX adapter
  3. Prevent further withdrawals (1-2 minute delay)
  4. Investigate & identify attacker
  5. Redeploy adapter with new signer
  6. Resume operations

  WITHOUT ISOLATION:
  ✗ Attacker has access to 50M (could steal all)
  ✗ Vault core contract at risk


SUMMARY TABLE:
──────────────

┌─────────────────────────┬──────────────┬──────────────┬──────────────┐
│ Scenario                │ User A Loss  │ User B Loss  │ User C Loss  │
│                         │ (50/50)      │ (Lendle 100%)│ (Fusion 100%)│
├─────────────────────────┼──────────────┼──────────────┼──────────────┤
│ 1. Adapter bug          │ 0%           │ 0%           │ 0%           │
│    (accounting error)   │              │              │              │
├─────────────────────────┼──────────────┼──────────────┼──────────────┤
│ 2. Protocol exploit     │ 50%          │ 100%         │ 0%           │
│    (Lendle stolen)      │              │              │              │
├─────────────────────────┼──────────────┼──────────────┼──────────────┤
│ 3. Adapter compromised  │ 50%          │ 0%           │ 100%         │
│    (private key leak)   │              │              │              │
├─────────────────────────┼──────────────┼──────────────┼──────────────┤
│ WORST CASE (no isolation)               │ 100%         │ 100%         │
│ Both adapters fail                      │              │              │
└─────────────────────────────────────────┴──────────────┴──────────────┘

KEY INSIGHTS:

1. Diversification protects:
   - Users in other adapters safe
   - User A loses only 25M (50%), not 50M (100%)

2. Isolation limits blast radius:
   - Vault continues operating
   - Non-affected adapters earn yield
   - Affected adapters can be paused/disabled

3. Governance can respond quickly:
   - Pause adapter (1 transaction)
   - Disable adapter (1 transaction)
   - No vault redeployment needed
```

---

## DIAGRAM 6: Permissioned → Permissionless Roadmap

```
╔════════════════════════════════════════════════════════════════════════╗
║          DECENTRALIZATION ROADMAP: From Safe to Open                  ║
╚════════════════════════════════════════════════════════════════════════╝

MVP (NOW): Permissioned Adapters
──────────────────────────────

  Control Model: Whitelist
  ┌──────────────────────────┐
  │ MALGIST Owner/Governance │
  │ (centralized decision)   │
  └────────────┬─────────────┘
               │
               ├─ Add adapter: Yes/No
               ├─ Remove adapter: Yes/No
               ├─ Pause adapter: Yes/No
               └─ Set TVL caps: Yes/No

  Who can propose adapters?
  ├─ Anyone (create code, PR)
  ├─ Community votes on relevance
  ├─ Governance approves top choices
  └─ Only approved adapters can be added

  Benefits:
  ✓ Safe for MVP & hackathon
  ✓ Full control over protocol risk
  ✓ Easy to pause/remove bad actors
  ✓ Fast iteration (no DAO overhead)

  Risks:
  ✗ Centralized decision making
  ✗ Slow to add new protocols
  ✗ Single point of failure (owner key)


PHASE 2.1 (Month 1): DAO Governance
───────────────────────────────

  Control Model: DAO Multisig
  ┌────────────────────────────────────┐
  │ MALGIST DAO Treasury (Multisig)    │
  │ (3-of-5 signing required)          │
  └────────────────┬───────────────────┘
                   │
                   ├─ Add adapter
                   ├─ Remove adapter
                   ├─ Pause adapter
                   └─ Manage governance

  Governance flow:
  1. Community proposes adapter
  2. Snapshot vote (48 hours)
  3. If passed: Multisig executes
  4. Timelock delay (12 hours)
  5. Adapter activated

  Benefits:
  ✓ Decentralized decision making
  ✓ Community has voice
  ✓ Still emergency controls available
  ✓ Timelock prevents sudden changes

  Risks:
  ⚠️ Requires 3 signers present (coordination)
  ⚠️ Still centralized (5 people choose)


PHASE 2.2 (Month 2-3): Governance Token
─────────────────────────────────────

  Control Model: DAO Treasury (Time-lock Governance)
  ┌──────────────────────────────────┐
  │ MALGIST Governance Token (MAG)   │
  │ Token holders vote on adapters   │
  └────────────────┬─────────────────┘
                   │
                   ├─ Snapshot voting
                   ├─ On-chain governance
                   ├─ Timelock execution
                   └─ Veto controls (if needed)

  Governance flow:
  1. Community proposes adapter
  2. Snapshot vote (48 hours)
     - Quorum: 30% voting power
     - Threshold: 50%+ approval
  3. Snapshot passes? Yes
  4. On-chain Governance vote (7 days)
  5. If passed: Timelock (12 hours)
  6. Adapter activated

  Benefits:
  ✓ True decentralization (token = vote)
  ✓ Community controls protocol direction
  ✓ Transparent decision making
  ✓ Anyone with tokens can participate

  Risks:
  ⚠️ 48+ hour delays (slower response to exploits)
  ⚠️ Voter apathy (low participation)
  ⚠️ Token holder collusion (small group controls)


PHASE 2.3 (Month 4-6): On-Chain Validation
──────────────────────────────────────────

  Control Model: On-Chain Registry + Automated Scoring
  ┌─────────────────────────────────────┐
  │ IAdapterRegistry (Smart Contract)   │
  │ Automated validation & scoring      │
  └────────────────┬────────────────────┘
                   │
                   ├─ Audit attestation required
                   ├─ TVL caps enforced (code)
                   ├─ Yield floor checks
                   ├─ Liquidity requirements
                   └─ Auto-disable on failure

  Governance flow:
  1. Developer submits adapter + audit proof
  2. Registry checks:
     ✓ Code audit attestation (via auditor NFT)
     ✓ TVL cap matches proposal
     ✓ Estimated yield positive
     ✓ Liquidity > 1M reserves
  3. If checks pass: Adapter auto-registers
  4. TVL cap starts at 0 (must earn trust)
  5. After 30 days: DAO vote to increase cap

  Benefits:
  ✓ Reduces governance overhead
  ✓ Objective criteria (not opinion-based)
  ✓ Faster onboarding (if audit passes)
  ✓ Still requires community approval

  Risks:
  ⚠️ Audit attestation can be faked (requires NFT standard)
  ⚠️ Yield estimates unreliable (market changes)
  ⚠️ Liquidity requirements may exclude new protocols


PHASE 2.4 (Month 4-6 parallel): Community Validators
──────────────────────────────────────

  Control Model: Staked Validator Network
  ┌────────────────────────────────┐
  │ Staked Validators (100k+ MAG)  │
  │ Vote on adapter suitability    │
  └────────────────┬───────────────┘
                   │
                   ├─ Can approve/reject adapters
                   ├─ Stake slashed if wrong
                   ├─ Rewards for accuracy
                   └─ Reputation-based scoring

  Validator flow:
  1. Developer submits adapter
  2. Validators review code & audit
  3. Each validator stakes 100k+ MAG
  4. Votes: "This adapter is safe"
  5. Tally: 70%+ approval → adapter registered

  Scoring:
  ├─ Correct votes: +1 reputation
  ├─ Wrong votes: Stake slashed 10%
  ├─ Adapter exploited: -50 reputation
  ├─ Adapter performs well (6 mo): +10 reputation
  └─ Reputation affects voting weight

  Benefits:
  ✓ Decentralized expert network
  ✓ Financial incentive for correctness
  ✓ Scales to many adapters
  ✓ Community builds expertise

  Risks:
  ⚠️ New validators have no reputation (cold start)
  ⚠️ Collusion possible (validators coordinate)
  ⚠️ Requires minimum stake (excludes participation)


PHASE 3 (Q2 2026): Fully Permissionless
───────────────────────────────────────

  Control Model: Pure On-Chain Scoring + Community Veto
  ┌────────────────────────────────────────┐
  │ Any developer can propose adapter      │
  │ Auto-scored by system                  │
  │ No whitelist (only guardrails)         │
  └────────────────┬───────────────────────┘
                   │
                   ├─ Deploy adapter (no approval needed)
                   ├─ Start with 0 TVL cap
                   ├─ Earn cap based on:
                   │  ├─ Time in system (1 month = +5k TVL)
                   │  ├─ Performance (positive yield = +10k)
                   │  ├─ Community vote (+100k if loved)
                   │  └─ Validator approval (+50k)
                   ├─ Community can vote to disable
                   └─ If yield fails: auto-disabled

  Governance flow:
  1. Developer deploys adapter (no approval)
  2. Users can deposit (up to TVL cap: 0)
  3. Community monitors performance
  4. If good (30 days, +5% yield):
     ├─ TVL cap auto-increased
     ├─ Community gains confidence
  5. If bad (exploited, 0% yield):
     ├─ Community votes to disable
     ├─ TVL cap reduced to 0
     ├─ Adapter removed

  Safety mechanism:
  ├─ Each adapter isolated (can't fail vault)
  ├─ Start with 0 TVL (can't steal much)
  ├─ Earn TVL over time (community consensus)
  ├─ Auto-disable on performance failure
  └─ Community veto always available

  Benefits:
  ✓ True openness (anyone can participate)
  ✓ No governance overhead (automatic)
  ✓ Safety still intact (isolation + guardrails)
  ✓ Community decides through capital allocation

  Risks:
  ✗ Scam adapters possible (can steal small amounts)
  ✗ Requires excellent monitoring systems
  ✗ Community must be engaged


ROADMAP TIMELINE:
─────────────────

  NOW (Dec 2025)
  ├─ ✓ MVP: Permissioned adapters
  ├─ ✓ Hackathon submission ready
  └─ ✓ FusionX + Lendle active

  Week 4-8 (Dec 2025 - Jan 2026)
  ├─ Phase 2.1: DAO Multisig governance
  ├─ 3-of-5 signers control adapters
  └─ Snapshot voting for community input

  Month 2-3 (Jan - Feb 2026)
  ├─ Phase 2.2: Governance token launch
  ├─ MAG token voting on adapters
  ├─ Timelock governance contract
  └─ 48+ hour voting periods

  Month 4-6 (Feb - Apr 2026)
  ├─ Phase 2.3: On-chain validation registry
  ├─ Automated audit attestation
  ├─ TVL cap management
  └─ Parallel: Validator network launch

  Q2 2026 (May - Jun 2026)
  ├─ Phase 3: Fully permissionless
  ├─ Any adapter can deploy (0 TVL start)
  ├─ Auto-scoring based on performance
  └─ Community veto always available


TRANSITION GUARANTEES:
─────────────────────

At each phase, vault remains:
✓ Secure (risk isolation unchanged)
✓ Stable (existing adapters continue)
✓ Accessible (users unaffected)
✓ Auditable (clear governance rules)

User experience:
- Phase 1-2.2: Manual governance (slower)
- Phase 2.3-2.4: Hybrid (semi-automated)
- Phase 3: Community-driven (fastest)
```

---

**End of Adapter System Diagrams**

_All diagrams are production-ready for hackathon judge presentation._
