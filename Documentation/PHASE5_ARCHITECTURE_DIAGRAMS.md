<!-- Documentation/PHASE5_ARCHITECTURE_DIAGRAMS.md -->

# Phase 5: Architecture Diagrams — ERC-4626 Compatibility

**Date:** December 17, 2025  
**Purpose:** Visual representations of ERC-4626 integration, adapter aggregation, and institutional interoperability

---

## DIAGRAM 1: ERC-4626 Share Accounting Flow

### Share Mechanics Visualization

```
┌─────────────────────────────────────────────────────────────────────┐
│                       USER DEPOSIT FLOW                             │
└─────────────────────────────────────────────────────────────────────┘

                              User
                               │
                   deposit(1000 USDC)
                               │
                               ▼
                    ┌──────────────────┐
                    │ Check balance    │
                    │ Approve transfer │
                    └────────┬─────────┘
                             │
                             ▼
                    ┌──────────────────┐
                    │ previewDeposit() │
                    │ = convert to     │
                    │   shares         │
                    └────────┬─────────┘
                             │
                    shares = (assets × supply) / totalAssets
                             │
                    Example: (1000 × 1000) / 10000 = 100 shares
                             │
                             ▼
                    ┌──────────────────────┐
                    │ Transfer USDC        │
                    │ from user to vault   │
                    │ (1000 USDC)          │
                    └────────┬─────────────┘
                             │
                             ▼
                    ┌──────────────────────┐
                    │ Mint shares          │
                    │ to user              │
                    │ (100 shares)         │
                    └────────┬─────────────┘
                             │
                             ▼
                    ┌──────────────────────┐
                    │ Emit Deposit event   │
                    │ (indexed for tools)  │
                    └────────┬─────────────┘
                             │
                             ▼
                    ┌──────────────────────┐
                    │ Delegate to adapters │
                    │ per strategy         │
                    │ (e.g., 600 to Aave, │
                    │  400 to Lendle)      │
                    └────────┬─────────────┘
                             │
                             ▼
                    ┌──────────────────────┐
                    │ Return shares        │
                    │ (100 to user)        │
                    └──────────────────────┘

───────────────────────────────────────────────────────────────────────

ACCOUNTING STATE AFTER DEPOSIT:

Before:
  totalSupply = 1000 shares
  totalAssets = 10000 USDC
  Share price = 10 USDC/share

After:
  totalSupply = 1100 shares
  totalAssets = 11000 USDC
  Share price = 10 USDC/share (unchanged ✓)

User's position: 100 shares = 1000 USDC

───────────────────────────────────────────────────────────────────────

SHARE PRICE INVARIANT:

share_price = totalAssets / totalSupply
            = 11000 / 1100
            = 10 USDC/share ✓

This never changes for proper conversions:
  • Yield increases totalAssets → share price rises
  • Fees decrease totalAssets → share price falls
  • New deposits at current price → share price stable
```

---

## DIAGRAM 2: Adapter Balance Aggregation

### How totalAssets() Works

```
┌──────────────────────────────────────────────────────────────────┐
│                  TOTAL ASSETS CALCULATION                        │
│                                                                  │
│  totalAssets() = vault_balance + adapter_1_balance + ...        │
└──────────────────────────────────────────────────────────────────┘

                        MalgistERC4626Vault
                               │
                    ┌──────────┴──────────┐
                    │                    │
                    ▼                    ▼
            ┌────────────────┐    ┌────────────────────┐
            │ Vault Balance  │    │ Adapter Balances   │
            │ (Direct hold)  │    │ (Delegated assets) │
            └────────┬───────┘    └──────────┬─────────┘
                     │                       │
                     │                       ├─ Aave Adapter.getBalance()
                     │                       ├─ Lendle Adapter.getBalance()
                     │                       ├─ Future Adapter.getBalance()
                     │                       └─ ...
                     │
            100 USDC │       ┌──────────────────────────────┐
                     │       │    Adapter Details           │
                     │       │                              │
                     │       │  Aave:   600 USDC            │
                     │       │  Lendle: 400 USDC            │
                     │       │  Others: 0 USDC              │
                     │       │  ───────────────             │
                     │       │  Total:  1000 USDC           │
                     │       └──────────────────────────────┘
                     │
                     └─ Sum = 100 + 1000 = 1100 USDC ✓
                               ↑
                        totalAssets()


DETAILED AGGREGATION:

function totalAssets() public view returns (uint256) {

    // Step 1: Get vault's direct balance
    uint256 total = IERC20(asset).balanceOf(address(this));
    //                                      ↓
    //                              100 USDC (shown above)

    // Step 2: Loop through all active adapters
    for (uint i = 0; i < activeAdapters.length; i++) {
        address adapter = activeAdapters[i];

        // Step 3: Query each adapter's total balance
        uint256 balance = IAdapter(adapter).totalBalance();
        //                           ↓
        //  Aave: calls aToken.balanceOf(this) = 600 USDC
        //  Lendle: calls aToken.balanceOf(this) = 400 USDC

        // Step 4: Accumulate
        total += balance;
    }

    // Step 5: Return total
    return total;
    //      ↓
    //      1100 USDC (from example above)
}


EXAMPLE EXECUTION TRACE:

Call: totalAssets()

  └─ total = 100 (vault balance from USDC.balanceOf)

  └─ Loop i=0: aaveAdapter
     └─ balance = aaveAdapter.totalBalance() = 600
     └─ total += 600 → total = 700

  └─ Loop i=1: lendleAdapter
     └─ balance = lendleAdapter.totalBalance() = 400
     └─ total += 400 → total = 1100

  └─ Return 1100 ✓


ARCHITECTURAL PRINCIPLE:

         Vault is Single Authority
                   │
        ┌──────────┴──────────┐
        │                    │
        ▼                    ▼
  Only Vault      Adapters Report
  Mints Shares    Asset Balances
        │                │
        │           totalAssets()
        │                │
        ├────────────────┘
        │
        ▼
  Share Price = totalAssets / totalSupply

  This ensures:
  ✓ Accounting is always correct
  ✓ No adapter can inflate share price
  ✓ Share price derived from real assets
  ✓ Users always get fair exchange
```

---

## DIAGRAM 3: Vault Lifecycle with ERC-4626

### State Machine of Vault Operations

```
┌─────────────────────────────────────────────────────────────────────┐
│                   VAULT LIFECYCLE STATE MACHINE                     │
└─────────────────────────────────────────────────────────────────────┘

                           INITIALIZED
                          (0 supply)
                               │
                    ┌──────────┴──────────┐
                    │                    │
            First Deposit        No users yet
            or Mint              (paused)
                    │                    │
                    └────────┬───────────┘
                             ▼
                         ACTIVE
                    (users depositing)
                        │    ▲
                        │    │
            ┌───────────┴────┴────────────┐
            │                            │
     Deposits/Yields              Time passes
            │                            │
            ▼                            ▼
        ┌────────────────────────────────────────┐
        │    Share Price Increases               │
        │    (Yields accumulate to totalAssets)   │
        │    APY = (price_t1 - price_t0) / price_t0
        │                                        │
        │    Example over 1 year:                │
        │    price_start: 1.00 USDC/share        │
        │    price_end:   1.12 USDC/share        │
        │    APY: 12% ✓                          │
        └────────────────────────────────────────┘
                             │
                ┌────────────┴────────────┐
                │                        │
         Normal operation           Governance votes
                │                   to pause (risk)
                │                        │
                ├────────────────────────┤
                │                        │
                ▼                        ▼
            HEALTHY                  PAUSED
        (operations active)    (new deposits blocked)
                │                        │
        Users can:             Users can:
        • Deposit ✓             • Withdraw ✓ (exit)
        • Withdraw ✓            • Redeem ✓ (exit)
        • Earn yield ✓          • Cannot deposit ✗
                                • Cannot mint ✗
                │                        │
                └────────────┬───────────┘
                             │
                    (governance resolves)
                             │
                        ┌────┴────┐
                        │         │
                   Resume     Deprecated
                   (↑ ACTIVE)  (↓ DEAD)
                        │         │
                        │         └── DEPRECATED
                        │         (vault closed)
                        │         (withdrawals only)
                        │
                └───────┘


STATE TRANSITIONS WITH FUNCTIONS:

INITIALIZED → ACTIVE
  ├─ trigger: first deposit() call
  ├─ totalSupply becomes non-zero
  ├─ share_price = 1.0 (first user sets price)
  └─ events: Transfer (mint), Deposit

ACTIVE → any time
  ├─ deposit(assets, receiver)
  │  ├─ mints shares at current price
  │  ├─ delegates to adapters
  │  └─ emits Deposit event
  │
  ├─ withdraw(assets, receiver)
  │  ├─ burns shares at current price
  │  ├─ pulls from adapters
  │  └─ emits Withdraw event
  │
  └─ mint(shares, receiver)
     ├─ user specifies shares, we calculate assets
     ├─ reverse of deposit()
     └─ emits Deposit event

ACTIVE → PAUSED
  ├─ trigger: governance.pause()
  ├─ deposits blocked
  ├─ withdrawals still work (emergency exit)
  └─ events: Paused

PAUSED → ACTIVE
  ├─ trigger: governance.unpause()
  ├─ deposits re-enabled
  ├─ operations resume
  └─ events: Unpaused

ACTIVE → DEPRECATED
  ├─ trigger: governance.deprecate()
  ├─ vault closed to new operations
  ├─ users must withdraw within window
  ├─ after window: governance can extract
  └─ similar to Yearn sunset process

DEPRECATED → DEAD
  ├─ trigger: deprecation window expires
  ├─ only governance can interact
  ├─ users lost opportunity to exit
  ├─ extreme measure (rarely done)
  └─ backup: governance can transfer assets


INVARIANTS MAINTAINED:

At ALL states:
  ✓ totalSupply = users' share balance sum
  ✓ totalAssets = vault balance + adapter sum
  ✓ share_price = totalAssets / totalSupply
  ✓ No share dilution possible
  ✓ Rounding always favors vault
```

---

## DIAGRAM 4: Institutional Wrapper Patterns

### How Institutions Use MALGIST (ERC-4626)

```
┌─────────────────────────────────────────────────────────────────────┐
│            INSTITUTIONAL INTEGRATION PATTERNS                       │
└─────────────────────────────────────────────────────────────────────┘

                          Institutional User
                         (e.g., Hedge Fund)
                               │
                               ▼
                    ┌──────────────────────┐
                    │   Portfolio Manager  │
                    │   (needs yield)      │
                    └──────────┬───────────┘
                               │
                ┌──────────────┼──────────────┐
                │              │              │
                ▼              ▼              ▼
           MALGIST         Other Vaults    Direct
           (ERC-4626)      (Yearn, etc)   Positions
                │              │              │
                │ deposit()     │              │
                │              │              │
                └──────────────┬───────────────┘
                               │
                               ▼
                    ┌──────────────────────────┐
                    │  Portfolio Dashboard     │
                    │  (via ERC-4626)          │
                    │  • TVL: 1M               │
                    │  • APY: 12%              │
                    │  • Exposure: 40%         │
                    └──────────┬───────────────┘
                               │
                    ┌──────────┴──────────┐
                    │                    │
                    ▼                    ▼
            Risk Compliance       Performance
            ├─ Max allocation OK  ├─ Earned yield
            ├─ Collateral OK      ├─ Fees paid
            ├─ Counterparty OK    └─ Rebalance needed?
            └─ Mark-to-market OK


PATTERN 1: Multi-Vault Portfolio

┌────────────────────────────────────────────────────────────────┐
│  Institutional PortfolioManager                               │
│  ├─ 40% in MALGIST (ERC-4626 vault)                          │
│  ├─ 30% in Yearn USDC (ERC-4626 vault)                       │
│  ├─ 20% in Lido wstETH (ERC-4626-compatible)                 │
│  └─ 10% in cash (USDC)                                       │
│                                                               │
│  Benefits with ERC-4626:                                      │
│  • Same interface for all vaults                              │
│  • Portfolio dashboard shows all                              │
│  • Risk scoring standardized                                  │
│  • No custom integration code needed                          │
└────────────────────────────────────────────────────────────────┘


PATTERN 2: Programmatic Treasury

┌────────────────────────────────────────────────────────────────┐
│  Corporation Treasury Smart Contract                          │
│  ├─ Receives revenue (stablecoins)                            │
│  ├─ Auto-compounds into MALGIST (ERC-4626)                   │
│  ├─ Maintains 10% in liquid USDC (for ops)                   │
│  ├─ Harvest yield monthly                                    │
│  └─ Rebalance weekly (via Balancer or 1inch)                │
│                                                               │
│  Smart contract uses:                                         │
│  • IERC4626.deposit() for auto-invest                        │
│  • IERC4626.redeem() for rebalance                           │
│  • IERC4626.convertToAssets() for reporting                  │
│  • Standard events for auditing                              │
└────────────────────────────────────────────────────────────────┘


PATTERN 3: Institutional Delegation

┌────────────────────────────────────────────────────────────────┐
│  Asset Manager (e.g., Ledger)                                 │
│  └─ Wraps MALGIST vault with:                                │
│     ├─ Access controls (only approved users)                  │
│     ├─ Rate limits (max withdrawals/day)                      │
│     ├─ Fee capture (management fee)                           │
│     ├─ Compliance checks (KYC/AML)                            │
│     └─ Multi-sig controls (withdraw approval)                 │
│                                                               │
│  Result:                                                      │
│  • Institutional-grade wrapper on ERC-4626                   │
│  • Underlying asset = MALGIST vault                           │
│  • No modification to MALGIST needed                          │
│  • Compliance layer on top                                    │
└────────────────────────────────────────────────────────────────┘


KEY BENEFIT: Composability

Without ERC-4626:
  Institution: "Does MALGIST work with our system?"
  MALGIST:    "No, custom interface"
  Result:     Months of integration work

With ERC-4626:
  Institution: "Does MALGIST implement ERC-4626?"
  MALGIST:    "Yes"
  Institution: "We use MALGIST today" ✓
  Result:     Same-day integration
```

---

## DIAGRAM 5: Migration Paths (Phase 1-4 → Phase 5)

### How Users Move from v1 to v2

```
┌─────────────────────────────────────────────────────────────────────┐
│                    MIGRATION TIMELINE                               │
└─────────────────────────────────────────────────────────────────────┘

TIME PERIOD:  |←─ Phase 1-4 ─→|←─ Phase 5 Launch ─→|←─ Gradual Migration ─→|

DEPLOYMENTS:  |  Only v1       |  v1 + v2 exist     |   Both deployed      |
              |                |  (parallel)        |   (indefinite)       |

GOVERNANCE:   |  Normal        |  Maintain both     |   Monitor TVL        |
              |                |  (no pressure)     |   Optional deprecate  |


SCENARIO: User has 1000 shares in v1

┌────────────────────────────────────────────────────────────────────┐
│              PRE-MIGRATION (Phase 1-4)                             │
│                                                                    │
│  User position:                                                    │
│  • 1000 v1 shares = 10,000 USDC (at 10x price)                    │
│  • Earning yield in v1                                            │
│  • Cannot use MALGIST with DeFi dashboards                        │
│                                                                    │
└────────────────────┬─────────────────────────────────────────────┘
                     │
        Phase 5 launches, v2 deployed
                     │
                     ▼
┌────────────────────────────────────────────────────────────────────┐
│              POST-LAUNCH (Both v1 and v2)                          │
│                                                                    │
│  Option A: Stay in v1                                              │
│  ├─ Still works ✓                                                 │
│  ├─ Continue earning yield                                        │
│  ├─ Manual migration anytime                                      │
│  └─ No pressure                                                   │
│                                                                    │
│  Option B: Migrate to v2 (recommended)                            │
│  ├─ Use standard ERC-4626 interface                               │
│  ├─ Work with DeFi tools                                          │
│  ├─ Institutional compatibility                                   │
│  └─ Future-proof                                                  │
│                                                                    │
└────────────────────────────────────────────────────────────────────┘


MIGRATION METHOD 1: Manual (User-Controlled)

Step 1: Approve v1 vault
  └─ user.approve(v1Vault, 1000 shares)

Step 2: Redeem from v1
  └─ uint256 assets = v1Vault.redeem(1000)
  └─ User receives: ~10,000 USDC
  └─ USDC moves to user wallet

Step 3: Approve v2 vault
  └─ user.approve(v2Vault, 10000 USDC)

Step 4: Deposit to v2
  └─ uint256 v2Shares = v2Vault.deposit(10000, user)
  └─ User receives: ~1000 v2 shares
  └─ (price may vary slightly if yield changed)

Result:
  • User had: 1000 v1 shares
  • User now: ~1000 v2 shares
  • Same economic exposure
  • Now ERC-4626 compatible ✓
  • Can use with DeFi tools ✓


MIGRATION METHOD 2: Atomic (One Transaction)

┌────────────────────────────────────────────────┐
│  MigrationHelper Contract                      │
│  ├─ Receives: 1000 v1 shares                  │
│  ├─ Calls: v1Vault.redeem(1000)               │
│  │          ├─ returns 10,000 USDC            │
│  ├─ Calls: v2Vault.deposit(10,000)            │
│  │          ├─ returns ~1000 v2 shares        │
│  ├─ Returns: ~1000 v2 shares to user          │
│  └─ Single tx, no manual steps                │
│                                                │
│  Benefits:                                     │
│  • One click migration                         │
│  • Atomic (all or nothing)                     │
│  • No intermediate token holding               │
│  • Protected by 1 contract ✓                   │
└────────────────────────────────────────────────┘


PRICE CONSIDERATIONS

Scenario 1: v2 price = v1 price (synchronized)
  v1 price: 10 USDC/share
  v2 price: 10 USDC/share

  Migration:
  1000 v1 shares = 10,000 USDC ≈ 1000 v2 shares ✓
  No slippage

Scenario 2: v2 price > v1 price (v2 accrued more yield)
  v1 price: 10 USDC/share
  v2 price: 12 USDC/share (started with 20% yield)

  Migration:
  1000 v1 shares = 10,000 USDC < 833 v2 shares
  User gets fewer shares (but same $)
  Fair if v2 price legitimately higher

Scenario 3: v2 price < v1 price (unlikely)
  Only if v2 has fees/losses that v1 doesn't
  User should analyze before migration


GOVERNANCE-COORDINATED MIGRATION

Phase 5.0: v2 deployed
├─ Both vaults operational
├─ Users choose which to use
└─ Governance: "v2 is recommended"

Phase 5.1: (6 months)
├─ Monitor v1 TVL decline
├─ Marketing campaign for v2
├─ Easy migration tools
├─ No timeline pressure

Phase 5.2: (Optional, year 1+)
├─ Governance votes: deprecate v1? (optional)
├─ Can vote NO → both coexist forever
├─ Vote YES → gives notice, deprecation window
└─ Users have 6+ months to migrate

Result: Smooth transition, no forced migration
```

---

## DIAGRAM 6: Ecosystem Integration Points

### How MALGIST Connects to DeFi Ecosystem

```
┌──────────────────────────────────────────────────────────────────┐
│               MALGIST in the MANTLE ECOSYSTEM                   │
│               (ERC-4626 as the integration layer)               │
└──────────────────────────────────────────────────────────────────┘

                   MALGIST ERC-4626 VAULT
                    (Central Hub)
                           │
        ┌──────────────────┼──────────────────┐
        │                  │                  │
        ▼                  ▼                  ▼
    Analytics         Aggregators        Protocols
        │                  │                  │
        │      ┌───────────┴────────────┐     │
        │      │                       │     │
        ▼      ▼                       ▼     ▼
    ┌──────────────────────────────────────────────┐
    │  INTEGRATION ECOSYSTEM                      │
    ├──────────────────────────────────────────────┤
    │                                              │
    │  DASHBOARDS & ANALYTICS:                   │
    │  ├─ Dune Analytics                         │
    │  │  └─ Query: SELECT * FROM erc4626_vaults│
    │  │     WHERE address = 0xMALGIST          │
    │  │     (automatic TVL, APY, user count)    │
    │  │                                          │
    │  ├─ Nansen                                  │
    │  │  └─ Tracks MALGIST position flows       │
    │  │     via standard Deposit events         │
    │  │                                          │
    │  ├─ Zerion                                  │
    │  │  └─ Shows MALGIST in portfolio          │
    │  │     alongside other assets              │
    │  │                                          │
    │  └─ DeBank                                  │
    │     └─ Calculates portfolio composition     │
    │        via convertToAssets()                │
    │                                              │
    │  AGGREGATORS & DEX ROUTERS:                │
    │  ├─ 1inch                                   │
    │  │  └─ Routes deposits to MALGIST          │
    │  │     as yield strategy option             │
    │  │                                          │
    │  ├─ Matcha                                  │
    │  │  └─ Can swap directly to/from            │
    │  │     MALGIST shares                       │
    │  │                                          │
    │  ├─ Balancer                                │
    │  │  └─ Creates liquidity pools with         │
    │  │     MALGIST shares as assets             │
    │  │                                          │
    │  └─ Uniswap v4                              │
    │     └─ Custom pools using MALGIST           │
    │        as hook asset                        │
    │                                              │
    │  LENDING PROTOCOLS:                         │
    │  ├─ Aave                                    │
    │  │  └─ Use MALGIST shares as collateral     │
    │  │     (with risk parameter)                │
    │  │                                          │
    │  ├─ Compound v3                             │
    │  │  └─ MALGIST as alternative collateral    │
    │  │                                          │
    │  └─ Spark                                   │
    │     └─ Integration for DeFi power users     │
    │                                              │
    │  YIELD PROTOCOLS:                           │
    │  ├─ Yearn                                   │
    │  │  └─ Wrap MALGIST as yield source         │
    │  │     for next-level composition           │
    │  │                                          │
    │  ├─ Lido                                    │
    │  │  └─ Compose MALGIST with staking         │
    │  │                                          │
    │  └─ Aura Finance                            │
    │     └─ Unlock Balancer pool yield           │
    │        via MALGIST integration              │
    │                                              │
    │  INSTITUTIONAL TOOLS:                       │
    │  ├─ Ledger Enterprise                       │
    │  │  └─ Wrap MALGIST for institutional       │
    │  │     governance & compliance               │
    │  │                                          │
    │  ├─ Fireblocks                              │
    │  │  └─ Include MALGIST in custody           │
    │  │     solutions (standard interface)        │
    │  │                                          │
    │  └─ StarkWare Integration                   │
    │     └─ Bridge MALGIST to StarkNet           │
    │        via standard (easier integration)     │
    │                                              │
    └──────────────────────────────────────────────┘


INTEGRATION FLOW EXAMPLE: Dune Dashboard

Timeline: Pre-ERC-4626 vs Post-ERC-4626

PRE-ERC-4626 (Custom interface):
  1. Dune asks: "What's MALGIST interface?"
  2. MALGIST provides custom ABI
  3. Dune builds custom queries (weeks of work)
  4. Other dashboards repeat work (duplication)
  5. If MALGIST changes, all break

POST-ERC-4626:
  1. Dune's standard ERC-4626 template works
  2. Query auto-generated from interface
  3. TVL, APY, user count: automatic
  4. Other dashboards use same queries (no duplication)
  5. If MALGIST changes, standard interface handles it


BENEFITS PER CATEGORY:

For Users:
  ✓ One-click portfolio tracking
  ✓ Yield earned is auto-calculated
  ✓ Can compose with other strategies
  ✓ Institutional-grade tools available

For Developers:
  ✓ Standard interface (no custom code)
  ✓ Existing libraries work
  ✓ Lower risk integration
  ✓ Community-maintained tools

For MALGIST:
  ✓ Ecosystem adoption
  ✓ Reduced custom integration burden
  ✓ Institutional credibility
  ✓ TVL growth through partnerships
```

---

## DIAGRAM 7: Rounding & Precision Mechanics

### Protecting Against Exploits

```
┌─────────────────────────────────────────────────────────────────────┐
│        ROUNDING STRATEGY: ALWAYS FAVOR THE VAULT                   │
└─────────────────────────────────────────────────────────────────────┘

PRINCIPLE: Vault always wins ties

Example 1: Converting Assets to Shares

assets = 100 USDC
supply = 100 shares
totalAssets = 999 USDC (happens after yield loss/fee)

correct_shares = (100 × 100) / 999 = 10.010...

Options:
  ❌ Round UP:   shares = 11 (user gets more, vault loses)
  ✓ Round DOWN:  shares = 10 (user gets fair, vault protected)

Code:
  shares = (assets * supply) / totalAssets;  // Solidity: rounds down by default
  // Result: 10 shares ✓


Example 2: Converting Shares to Assets

shares = 10
supply = 100 shares
totalAssets = 1001 USDC

correct_assets = (10 × 1001) / 100 = 100.1 USDC

Options:
  ✓ Round DOWN:  assets = 100 USDC (user gets slightly less)
  ❌ Round UP:   assets = 101 USDC (vault loses)

Code:
  assets = (shares * totalAssets) / supply;  // Solidity: rounds down
  // Result: 100 USDC ✓


PROTECTION AGAINST INFLATION ATTACK:

Attacker strategy:
  1. Contribute 1 USDC, get 1 share
  2. Transfer 10,000 USDC directly to vault (inflate price)
  3. Next user deposits, should get 1 share but gets 0 (exploit!)

Mitigation with proper rounding:

Step 2 state: totalAssets = 10,001, supply = 1
Step 3 attacker: "Next deposit of 1 USDC gets how many shares?"
  previewDeposit(1) = (1 × 1) / 10,001 = 0.0000999...
  Rounds DOWN to 0 shares

But we require minimum deposits (e.g., 1000 wei):

previewDeposit(1000) = (1000 × 1) / 10,001 = 0.0999...
Rounds DOWN to 0

Set minimum to prevent this:
min_deposit = 1e10;  // Require 10 gwei minimum
require(assets >= min_deposit);

Now attacker can't exploit.


DUST PREVENTION:

Issue: Leftover dust causes precision loss

Scenario:
  User A: 1000 USDC → 999 shares (due to rounding)
  User B: 1000 USDC → 999 shares
  User C:    1 USDC → 0 shares (rounds to 0!)

  1 wei lost forever

Solution:
  1. Minimum deposit/mint enforced
  2. Vault accumulates small amounts
  3. Include in totalAssets() (next harvest)

Code:
  function deposit(uint256 assets) public returns (uint256 shares) {
      require(assets >= MIN_DEPOSIT);  // Prevent dust
      shares = convertToShares(assets);
      require(shares >= MIN_SHARES);    // Ensure meaningful size
      _mint(msg.sender, shares);
  }


PRECISION STANDARD (OpenZeppelin):

Use Math library for safety:

  using Math for uint256;

  function convertToAssets(uint256 shares) public view returns (uint256) {
      return shares.mulDiv(totalAssets(), totalSupply(), Math.Rounding.Down);
  }

  Benefits:
  ✓ Explicit rounding direction
  ✓ Overflow protection
  ✓ Standard library
  ✓ Audited code


INVARIANT: No User Gets Exploited

For deposit(assets):
  • share_price_before = totalAssets / totalSupply
  • shares_minted = assets * share_price_before (rounded down)
  • share_price_after = (totalAssets + assets) / (totalSupply + shares_minted)
  • share_price_after >= share_price_before ✓

For withdraw(assets):
  • share_price_before = totalAssets / totalSupply
  • shares_burned = assets * share_price_before (rounded down)
  • share_price_after = (totalAssets - assets) / (totalSupply - shares_burned)
  • share_price_after >= share_price_before ✓

Result: Users never get worse terms than current price ✓
```

---

**End of Phase 5 Architecture Diagrams**

_Visual explanations of ERC-4626 integration, share mechanics, and ecosystem interoperability_
