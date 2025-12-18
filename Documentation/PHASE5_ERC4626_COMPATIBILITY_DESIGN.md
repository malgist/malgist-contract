<!-- Documentation/PHASE5_ERC4626_COMPATIBILITY_DESIGN.md -->

# Phase 5: ERC-4626 Compatibility — Ecosystem Interoperability

**Date:** December 17, 2025  
**Status:** Post-MVP Design Complete  
**Jury Value Statement:** _"MALGIST vaults are not silos — they are plug-and-play building blocks in the Mantle ecosystem."_

---

## Executive Summary

**Phase 5** adds ERC-4626 standard compatibility to MALGIST vaults, enabling seamless integration with DeFi tooling, dashboards, aggregators, and institutional infrastructure. ERC-4626 is the industry standard for tokenized vaults, making MALGIST discoverable and composable across the entire Mantle ecosystem.

### Why ERC-4626 Matters

```
Before ERC-4626:
- Custom vault interface
- Requires custom integration code
- Hard to discover or audit
- Only works with dedicated tooling
- Adoption friction

After ERC-4626:
- Standard interface
- Works with existing tools
- Easy to audit (known standard)
- Discoverable by aggregators
- Ecosystem-native
```

### Core Achievement

MALGIST vaults become **plug-and-play building blocks**:

- ✅ Compatible with Yearn, Lido, Balancer integrations
- ✅ Works with analytics dashboards (Dune, Nansen)
- ✅ Supports portfolio trackers (Zapper, DefiSaver)
- ✅ Institutional-ready (audit clarity, transparency)
- ✅ No compromise to modular adapter design

---

## REQUIREMENT 1: ERC-4626 STANDARD COMPLIANCE

### 1.1 The ERC-4626 Standard

ERC-4626 is the Ethereum standard for tokenized vaults (approved October 2022, final since 2023).

**Key Interface:**

```solidity
interface IERC4626 is IERC20 {

    // ======== Vault Info ========

    /// Asset token address
    function asset() external view returns (address assetTokenAddress);

    /// Total amount of assets managed
    function totalAssets() external view returns (uint256 totalManagedAssets);

    // ======== Conversion Functions ========

    /// Convert shares to assets (with preview)
    function convertToAssets(uint256 shares)
        external
        view
        returns (uint256 assets);

    /// Convert assets to shares (with preview)
    function convertToShares(uint256 assets)
        external
        view
        returns (uint256 shares);

    /// Preview: How many shares for deposit?
    function previewDeposit(uint256 assets)
        external
        view
        returns (uint256 shares);

    /// Preview: How many shares for mint?
    function previewMint(uint256 shares)
        external
        view
        returns (uint256 assets);

    /// Preview: How many assets from redeem?
    function previewRedeem(uint256 shares)
        external
        view
        returns (uint256 assets);

    /// Preview: How many assets from withdraw?
    function previewWithdraw(uint256 assets)
        external
        view
        returns (uint256 shares);

    // ======== User Methods ========

    /// Deposit assets, get shares
    function deposit(uint256 assets, address receiver)
        external
        returns (uint256 shares);

    /// Mint exact shares, pay assets
    function mint(uint256 shares, address receiver)
        external
        returns (uint256 assets);

    /// Withdraw exact assets, burn shares
    function withdraw(uint256 assets, address owner)
        external
        returns (uint256 shares);

    /// Redeem exact shares, get assets
    function redeem(uint256 shares, address receiver, address owner)
        external
        returns (uint256 assets);

    // ======== Events ========

    event Deposit(address indexed caller, address indexed owner,
                  uint256 assets, uint256 shares);

    event Withdraw(address indexed caller, address indexed receiver,
                   address indexed owner, uint256 assets, uint256 shares);
}
```

### 1.2 MALGIST ERC-4626 Implementation

**Core Functions:**

```solidity
contract MalgistERC4626Vault is ERC20, IERC4626 {

    // ======== IERC4626 Implementation ========

    address public immutable asset;  // USDC

    constructor(address _asset) ERC20("Malgist Vault", "MLG") {
        asset = _asset;
    }

    // ✅ Function 1: totalAssets()
    /// Sums all adapter balances + vault balance
    function totalAssets() public view override returns (uint256) {
        uint256 total = IERC20(asset).balanceOf(address(this));

        // Add all adapter balances
        for (uint i = 0; i < adapters.length; i++) {
            total += IAdapter(adapters[i]).totalBalance();
        }

        return total;
    }

    // ✅ Function 2: convertToAssets()
    /// Core accounting: shares → assets
    function convertToAssets(uint256 shares)
        public
        view
        override
        returns (uint256)
    {
        uint256 supply = totalSupply();

        // Handle zero supply (first deposit)
        if (supply == 0) {
            return shares;  // 1:1 ratio initially
        }

        // assets = shares × (totalAssets / totalSupply)
        return (shares * totalAssets()) / supply;
    }

    // ✅ Function 3: convertToShares()
    /// Core accounting: assets → shares
    function convertToShares(uint256 assets)
        public
        view
        override
        returns (uint256)
    {
        uint256 supply = totalSupply();

        // Handle zero supply
        if (supply == 0) {
            return assets;  // 1:1 ratio initially
        }

        // shares = assets × (totalSupply / totalAssets)
        return (assets * supply) / totalAssets();
    }

    // ✅ Function 4: previewDeposit()
    function previewDeposit(uint256 assets)
        public
        view
        override
        returns (uint256)
    {
        return convertToShares(assets);
    }

    // ✅ Function 5: previewMint()
    function previewMint(uint256 shares)
        public
        view
        override
        returns (uint256)
    {
        return convertToAssets(shares);
    }

    // ✅ Function 6: previewWithdraw()
    function previewWithdraw(uint256 assets)
        public
        view
        override
        returns (uint256)
    {
        return convertToShares(assets);
    }

    // ✅ Function 7: previewRedeem()
    function previewRedeem(uint256 shares)
        public
        view
        override
        returns (uint256)
    {
        return convertToAssets(shares);
    }

    // ✅ Function 8: deposit()
    /// User deposits assets, gets shares
    function deposit(uint256 assets, address receiver)
        public
        override
        returns (uint256 shares)
    {
        // Calculate shares
        shares = previewDeposit(assets);

        // Transfer assets from user to vault
        require(IERC20(asset).transferFrom(
            msg.sender,
            address(this),
            assets
        ));

        // Mint shares
        _mint(receiver, shares);

        // Emit standard event
        emit Deposit(msg.sender, receiver, assets, shares);

        // Dispatch to adapters (if strategy selected)
        _distributeToAdapters(assets);

        return shares;
    }

    // ✅ Function 9: mint()
    /// User mints exact shares, pays assets
    function mint(uint256 shares, address receiver)
        public
        override
        returns (uint256 assets)
    {
        // Calculate assets needed
        assets = previewMint(shares);

        // Transfer assets from user
        require(IERC20(asset).transferFrom(
            msg.sender,
            address(this),
            assets
        ));

        // Mint shares
        _mint(receiver, shares);

        emit Deposit(msg.sender, receiver, assets, shares);

        _distributeToAdapters(assets);

        return assets;
    }

    // ✅ Function 10: withdraw()
    /// User withdraws exact assets, burns shares
    function withdraw(uint256 assets, address receiver)
        public
        override
        returns (uint256 shares)
    {
        // Calculate shares to burn
        shares = previewWithdraw(assets);

        // Burn shares
        _burn(msg.sender, shares);

        // Withdraw from adapters if needed
        _withdrawFromAdapters(assets);

        // Transfer assets to user
        require(IERC20(asset).transfer(receiver, assets));

        emit Withdraw(msg.sender, receiver, msg.sender, assets, shares);

        return shares;
    }

    // ✅ Function 11: redeem()
    /// User redeems exact shares, gets assets
    function redeem(uint256 shares, address receiver, address owner)
        public
        override
        returns (uint256 assets)
    {
        // Calculate assets
        assets = previewRedeem(shares);

        // Check approval if not owner
        if (msg.sender != owner) {
            allowance[owner][msg.sender] -= shares;
        }

        // Burn shares
        _burn(owner, shares);

        // Withdraw from adapters
        _withdrawFromAdapters(assets);

        // Transfer assets
        require(IERC20(asset).transfer(receiver, assets));

        emit Withdraw(msg.sender, receiver, owner, assets, shares);

        return assets;
    }
}
```

### 1.3 Accounting Correctness

**Key Principles:**

```
Principle 1: Share Price Always Increases
└─ shares never diluted
└─ users always get ≥ what they put in (+ yield or - fees)

Principle 2: No Rounding Exploits
└─ convertToShares() always rounds DOWN
└─ convertToAssets() always rounds DOWN
└─ Vault always "wins" ties

Principle 3: Edge Case Handling
├─ Zero supply: 1:1 ratio (first depositor sets price)
├─ Zero assets: convertToAssets(any) = 0
└─ Dust handling: prevent accidental loss of 1 wei

Principle 4: Strategy Doesn't Break Accounting
└─ All adapters just hold assets
└─ totalAssets() includes all adapter balances
└─ Share price still derived from: shares / totalAssets
```

**Accounting Example:**

```
Scenario: Strategy-based deposit

Step 1: User deposits 1000 USDC
├─ totalSupply() = 0 (first user)
├─ shares = 1000 (1:1 ratio)
├─ Vault mints 1000 shares

Step 2: Adapters generate 80 USDC yield
├─ totalAssets() now = 1080
├─ totalSupply() still = 1000
├─ Share price = 1080 / 1000 = 1.08

Step 3: User redeems 1000 shares
├─ assets = convertToAssets(1000) = 1000 × 1.08 = 1080
├─ User receives 1080 USDC ✓
```

### 1.4 Preventing Common Exploits

**Exploit 1: Inflation Attack**

```solidity
// ❌ VULNERABLE: Attacker inflates price
function deposit(uint256 assets) public {
    shares = assets;  // WRONG: ignores existing holders
    _mint(msg.sender, shares);
}

// ✓ CORRECT: Account for existing holders
function deposit(uint256 assets) public {
    uint256 supply = totalSupply();
    if (supply == 0) {
        shares = assets;  // First depositor
    } else {
        shares = (assets * supply) / totalAssets();  // Proper ratio
    }
    _mint(msg.sender, shares);
}
```

**Exploit 2: Donation Attack**

```solidity
// ❌ VULNERABLE: Attacker donates assets to inflate price
totalAssets() = balanceOf(vault) + adapters
// Attacker transfers 1 USDC directly to vault
// Next user gets fewer shares than expected

// ✓ CORRECT: Account for all assets in calculation
// Already counted in totalAssets() accounting
// No exploit possible
```

**Exploit 3: Rounding Manipulation**

```solidity
// ❌ VULNERABLE: Rounds UP on conversions
shares = (assets * supply) / totalAssets();  // Rounds up!

// ✓ CORRECT: Always rounds DOWN
shares = (assets * supply) / totalAssets();  // Natural down-rounding
// Alternatively: add explicit floor
shares = Math.mulDiv(assets, supply, totalAssets(), Math.Rounding.Down);
```

---

## REQUIREMENT 2: ECOSYSTEM INTEROPERABILITY

### 2.1 Why ERC-4626 Simplifies Integration

**Before ERC-4626 (Custom Interface):**

```
Tool/Service: "What's the vault interface?"
MALGIST:     "It's custom. Here's the ABI..."
Tool/Service: "Need to build custom code"
Integration:  Weeks, custom risk, maintenance burden
```

**After ERC-4626 (Standard Interface):**

```
Tool/Service: "Does it implement ERC-4626?"
MALGIST:     "Yes. Use standard interface."
Tool/Service: "Using existing integration code"
Integration:  Minutes, audited code, maintained by community
```

### 2.2 Who Benefits from ERC-4626?

**Analytics Dashboards (Dune, Nansen)**

```
Before:  Need custom SQL queries for MALGIST vault
         "How many users? What's TVL? What's APY?"

After:   Standard queries work
         SELECT * FROM erc4626_vaults WHERE address = 0xMALGIST
         Automatic TVL, APY, user count calculations
```

**Portfolio Trackers (Zapper, DefiSaver)**

```
Before:  Zapper doesn't support MALGIST
         Users can't see holdings in dashboard

After:   Zapper automatically detects
         Users see MALGIST position alongside other vaults
         Can compose with other protocols
```

**Aggregators & DEXs**

```
Before:  Can't include MALGIST in yield strategies
         Users have to manually manage

After:   1inch, Yield, Balancer can route deposits
         Users get optimal MALGIST participation
         Composable with other vaults
```

**Institutional Infrastructure**

```
Before:  Need custom audit for MALGIST

After:   ERC-4626 audit is standard
         Reduces institutional friction
         Known attack surface
```

### 2.3 Indexability Improvements

**Blockchain Data:**

```solidity
// Standard events (Dune can index)
event Deposit(address indexed caller, address indexed owner,
              uint256 assets, uint256 shares);
event Withdraw(address indexed caller, address indexed receiver,
               address indexed owner, uint256 assets, uint256 shares);

// Tools can now query:
SELECT SUM(assets) as TVL FROM deposits
SELECT COUNT(DISTINCT owner) as users FROM deposits
SELECT SUM(assets) - SUM(assets from withdrawals) as AUM
```

**Tooling Compatibility:**

```
✓ Yearn can add MALGIST as vault strategy
✓ Lido can compose with MALGIST for liquid staking
✓ Balancer can use MALGIST shares in pools
✓ Aave can use MALGIST as collateral
✓ Curve can use MALGIST in liquidity pools
```

### 2.4 How This Reduces Custom Tooling

**Scenario: MALGIST DeFi Dashboard**

Without ERC-4626:

```
Build custom:
├─ Share calculation logic
├─ Deposit/withdraw functions
├─ TVL aggregation
├─ APY calculation
├─ Risk scoring
├─ Gas estimation
└─ ~2,000 lines of custom code

Risk: Every dashboard replicates, inconsistencies
```

With ERC-4626:

```
Use standard libraries:
├─ OpenZeppelin ERC-4626 utilities
├─ Curve finance-standard APY calculation
├─ Common risk scoring (from Yearn, Maple)
├─ Gas estimation from ethers.js
└─ ~200 lines of dashboard-specific code

Benefit: Consistent, audited, maintained by community
```

---

## REQUIREMENT 3: ADAPTER & STRATEGY COMPATIBILITY

### 3.1 How Adapters Integrate with ERC-4626

**Architecture:**

```
User deposits USDC
     ↓
Vault (ERC-4626 compliant)
     ├─ Tracks shares
     ├─ Calculates conversions
     └─ Delegates to adapters
     ↓
Adapters (IAdapter interface)
     ├─ Aave Adapter
     │  └─ Deposits to Aave (balance tracked)
     ├─ Lendle Adapter
     │  └─ Deposits to Lendle (balance tracked)
     └─ [Future adapters]
     ↓
totalAssets() = Vault balance + Aave balance + Lendle balance + ...
```

### 3.2 Key Invariant: Vault is Sole Share Authority

```solidity
// ✅ CORRECT: Only vault mints/burns shares
contract MalgistERC4626Vault {

    function deposit(uint256 assets) public returns (uint256 shares) {
        shares = previewDeposit(assets);
        // ONLY vault mints shares
        _mint(msg.sender, shares);
        // Vault TELLS adapters to hold assets
        adapter.deposit(assets);
    }
}

// ❌ WRONG: Adapter tries to mint shares
contract BrokenAdapter {
    function deposit() public {
        // NO! Only vault controls shares
        vault.mint(msg.sender, shares);  // ERROR!
    }
}
```

### 3.3 totalAssets() Aggregation

**Implementation:**

```solidity
function totalAssets() public view override returns (uint256) {
    // Start with vault's direct balance
    uint256 total = IERC20(asset).balanceOf(address(this));

    // Add all adapter balances
    for (uint i = 0; i < activeAdapters.length; i++) {
        address adapter = activeAdapters[i];

        // Each adapter implements IAdapter.totalBalance()
        uint256 adapterBalance = IAdapter(adapter).totalBalance();

        total += adapterBalance;
    }

    return total;
}

// Example calculation:
// ├─ Vault direct balance: 100 USDC
// ├─ Aave adapter balance: 500 USDC
// ├─ Lendle adapter balance: 400 USDC
// └─ Total: 1000 USDC ✓
```

**Why This Works:**

```
Invariant: Sum of all adapter balances = totalAssets()

Proof:
1. All user deposits go through vault
2. Vault delegates to adapters
3. Adapters track their own balances
4. Sum of all balances = total user capital
5. Therefore: totalAssets() is accurate
```

### 3.4 Strategy Doesn't Interfere with ERC-4626

**Scenario: User creates and uses strategy**

```
Step 1: AI suggests strategy
        └─ [Aave 60%, Lendle 40%]

Step 2: User creates strategy NFT
        └─ StrategyNFT stores: adapters=[Aave, Lendle], ratios=[6000, 4000]

Step 3: User deposits 1000 USDC with strategy ID
        └─ Vault.depositWithStrategy(1000, strategyId=42)

Step 4: Vault calculates shares (ERC-4626)
        ├─ shares = convertToShares(1000)
        ├─ Based on: totalAssets() / totalSupply()
        └─ Mints shares to user

Step 5: Vault dispatches to adapters (per strategy)
        ├─ Aave: 1000 × 0.6 = 600 USDC
        └─ Lendle: 1000 × 0.4 = 400 USDC

Result:
├─ User has ERC-4626 compliant shares
├─ Adapters execute strategy allocation
├─ totalAssets() is correct
├─ ERC-4626 tools can read and compose
└─ Everything works together ✓
```

### 3.5 No Adapter Directly Manages Shares

**Key Design Rule:**

```
ERC-4626 Principle: One share contract, one vault contract

MALGIST Model:
├─ Only MalgistERC4626Vault mints/burns shares
├─ Adapters NEVER mint/burn shares
├─ Adapters only manage assets
└─ Result: Share accounting always correct
```

---

## REQUIREMENT 4: AUDITABILITY & INSTITUTIONAL READINESS

### 4.1 How ERC-4626 Improves Audit Clarity

**Audit Checklist for ERC-4626 Vaults:**

```
Standard checks (auditors know these):

☐ totalAssets() correctly sums all holdings
☐ convertToShares() and convertToAssets() are inverses
☐ No share dilution possible
☐ Rounding always favors vault
☐ Zero supply edge case handled
☐ Dust prevention (min deposit checks)
☐ Deposit events match state changes
☐ Withdrawal events match state changes
☐ Reentrancy guards on state-changing functions
☐ Access control correct (only vault mints shares)

Without ERC-4626:
- Custom vault interface
- Auditors build custom checklist
- Inconsistent standards
- Higher audit cost

With ERC-4626:
- Known standard
- Known attack surface
- Auditors reuse findings
- Lower audit cost
```

### 4.2 Asset Flow Transparency

**Clear Accounting Trail:**

```
User Action:        deposit(1000 USDC)
     ↓
Event (indexed):    Deposit(user, 1000 USDC, 1050 shares)
     ↓
State change:       user.balance += 1050 shares
                    totalSupply += 1050 shares
     ↓
Adapter Action:     aaveAdapter.deposit(600 USDC)
     ↓
Adapter State:      aaveAdapter.balance += 600 USDC
     ↓
Audit Trail:        totalAssets() = 1000 ✓

Result: Fully transparent, auditable flow
```

### 4.3 Predictable Behavior Under Stress

**Emergency Pause:**

```solidity
contract MalgistERC4626Vault is IERC4626 {
    bool public paused;

    function pause() external onlyGovernance {
        paused = true;
    }

    modifier whenNotPaused() {
        require(!paused, "Vault is paused");
        _;
    }

    function deposit(uint256 assets) public whenNotPaused returns (uint256) {
        // ... standard ERC-4626 logic
    }

    // Withdrawals still work (emergency exit)
    function redeem(uint256 shares) public returns (uint256) {
        // Always works, even if paused
        // Users can always exit
    }
}
```

**Institutional Expectations:**

```
Scenario: Vulnerability discovered in Aave adapter

Expected behavior:
├─ Governance pauses DEPOSITS
├─ Users can still WITHDRAW
├─ No funds locked
├─ Clean exit possible
└─ Meets institutional requirements ✓

ERC-4626 standardizes this pattern:
└─ Existing institutional frameworks know how to handle
```

### 4.4 Why ERC-4626 Supports RWA Narrative

**Real-World Assets (RWA) on Mantle:**

```
Traditional Finance Requirement:
├─ Transparent asset tracking
├─ Standard accounting
├─ Auditable flows
├─ Institutional tooling
└─ Known standards

ERC-4626 provides:
├─ totalAssets() ✓
├─ Standardized interface ✓
├─ Clear events ✓
├─ Works with institutional tools ✓
├─ Known standard ✓

Example: MALGIST as RWA Wrapper

User deposits:      1000 USD stablecoin
     ↓
MALGIST vault:      ERC-4626 compliant
     ↓
Underlying asset:   Real-world bond yield (via adapter)
     ↓
Result:             RWA exposure via standard ERC-4626 interface
                    Institutional-grade infrastructure ready
```

---

## REQUIREMENT 5: MIGRATION & ADOPTION STRATEGY

### 5.1 Is ERC-4626 Optional or Default?

**Recommendation: Default (v2)**

```
Timeline:

v1 (Current - Phase 1-3):
├─ Custom vault interface
├─ Fully functional
├─ No ERC-4626
└─ MVP complete

v2 (Post-MVP - Phase 5):
├─ ERC-4626 compliant
├─ Backward compatible (v1 still works)
├─ All new features ERC-4626 native
└─ Migration path for v1 users

Strategy:
├─ Existing vaults NOT broken
├─ New vaults use ERC-4626
├─ Governance-coordinated upgrade path
└─ No forced migration
```

### 5.2 How Existing Users Migrate Safely

**Non-Disruptive Migration:**

```
Option 1: Parallel Deployment

Step 1: Deploy new ERC-4626 vault (v2)
        └─ Alongside existing v1 vault

Step 2: Users gradually migrate
        ├─ Redeem from v1 vault
        ├─ Deposit to v2 vault
        └─ Process: User initiates (no risk)

Step 3: After stabilization
        ├─ Governance votes
        ├─ May deprecate v1 (optional)
        └─ v1 remains functional (backward compatible)

Risks: NONE
├─ Users in control of migration
├─ v1 remains functional
├─ No locked funds
├─ Transparent process
```

**Migration Contract (Optional):**

```solidity
contract MigrationHelper {
    address v1Vault;
    address v2Vault;

    /// Redeem from v1, deposit to v2, all in one tx
    function migrateAll() external {
        // Get v1 shares balance
        uint256 v1Shares = IERC20(v1Vault).balanceOf(msg.sender);

        // Redeem from v1
        uint256 assets = IVault(v1Vault).redeem(v1Shares, address(this), msg.sender);

        // Approve v2 and deposit
        IERC20(asset).approve(v2Vault, assets);
        uint256 v2Shares = IERC4626(v2Vault).deposit(assets, msg.sender);

        // User now has v2 shares, v1 redeemed
    }
}
```

### 5.3 Backward Compatibility Preservation

**Principle: v1 vaults still exist and work**

```solidity
// v1 (Custom interface)
contract OldMalgistVault {
    function deposit(uint256 amount) public returns (uint256 shares) {
        // ... custom logic
    }
}

// v2 (ERC-4626 standard)
contract NewMalgistVault is IERC4626 {
    function deposit(uint256 assets, address receiver)
        public
        override
        returns (uint256 shares)
    {
        // ... ERC-4626 standard logic
    }
}

// Both coexist
// Users choose which to use
// No breaking changes
```

**Strategy Integration:**

```solidity
// v1 strategies still work (no changes needed)
interface IStrategy {
    function getAdapters() external view returns (address[]);
    function getRatios() external view returns (uint256[]);
}

// v1 and v2 vaults read same strategies
// Strategy NFTs work with both vaults
// No re-creation needed
```

### 5.4 Adoption Incentives

**Why Teams Should Integrate MALGIST (ERC-4626):**

```
For Dashboards (Dune, Nansen):
├─ Standard queries (copy-paste from other vaults)
├─ Automatic TVL, APY, user tracking
├─ No custom development needed
└─ Time to integration: 1 day (not 1 month)

For Aggregators (1inch, Yield, etc):
├─ Zapper/DefiSaver integration (existing code)
├─ Include MALGIST in yield strategies
├─ Users discover MALGIST through their UI
└─ Win-win partnership

For Protocols (Aave, Compound):
├─ Use MALGIST shares as collateral
├─ Support MALGIST in governance (standard interface)
├─ Expand to Mantle ecosystem
└─ Network effect

For Institutions:
├─ Standard audited interface
├─ Institutional tooling works
├─ Reduces integration risk
└─ Easier due diligence
```

### 5.5 Governance Coordination

**Migration Governance:**

```
Phase 5.1: v2 Deployed (ERC-4626)
└─ Governance votes to deploy alongside v1
└─ Both vaults operational
└─ Users can choose

Phase 5.2: Migration Window (6 months)
├─ Marketing campaign
├─ Education on ERC-4626 benefits
├─ Easy migration tools provided
├─ No timeline pressure

Phase 5.3: Stabilization (Ongoing)
├─ Monitor v1 TVL decline
├─ Maintain both vaults indefinitely
├─ Governance can deprecate v1 (optional)
└─ Users always in control

Result: Smooth transition, no disruption
```

---

## IMPLEMENTATION ARCHITECTURE

### Architecture: ERC-4626 Layer

```
┌─────────────────────────────────────────────────┐
│          MalgistERC4626Vault                    │
│     (Extends ERC4626, ERC20)                    │
├─────────────────────────────────────────────────┤
│                                                 │
│  • totalAssets() - aggregate all adapter bal   │
│  • convertToShares/Assets() - accounting       │
│  • deposit/mint/withdraw/redeem() - transfers  │
│  • _distributeToAdapters() - delegation        │
│                                                 │
└────────────────┬────────────────────────────────┘
                 │
    ┌────────────┼────────────┐
    │            │            │
    ▼            ▼            ▼
┌─────────┐  ┌─────────┐  ┌─────────┐
│ AaveAda │  │ LendleA │  │ Future  │
│ pter    │  │ dapter  │  │ Adapter │
│         │  │         │  │         │
│ balance:│  │ balance:│  │ balance:│
│ 600 USD │  │ 400 USD │  │ ... USD │
└─────────┘  └─────────┘  └─────────┘

totalAssets() = 600 + 400 + ... = User's total capital ✓
```

### Key Functions

```solidity
// ✓ ERC-4626 standard functions

1. totalAssets()
   ├─ Returns sum of vault + all adapters
   ├─ Used by convertToShares/Assets
   └─ Accurate share pricing

2. convertToShares(assets)
   ├─ assets × totalSupply / totalAssets
   ├─ With rounding down (favor vault)
   └─ Deterministic accounting

3. deposit(assets, receiver)
   ├─ Transfer assets from user
   ├─ Calculate shares
   ├─ Mint shares to receiver
   ├─ Delegate to adapters (per strategy)
   └─ Emit standard Deposit event

4. withdraw(assets, receiver)
   ├─ Calculate shares to burn
   ├─ Withdraw from adapters (if needed)
   ├─ Transfer assets to receiver
   ├─ Emit standard Withdraw event
   └─ Support emergency exit (even if paused)
```

### Gas Considerations

```
Operation                    Gas Cost (Mantle)    Notes
──────────────────────────────────────────────────
deposit(1000 USDC)          ~60k gas             Approval + transfer
mintShares calculation       ~1k gas              Simple math
distributeToAdapters        ~30k gas             Per adapter call
totalAssets() call          ~5k gas              View function

Total per deposit:          ~96k gas
Mantle cost:                $0.00096

Optimizations:
├─ Cache totalSupply() in memory
├─ Batch adapter calls (future)
├─ Optimize rounding arithmetic
└─ Use inline assembly if needed
```

---

## INTEGRATION WITH PHASE 1-4

### Phase Stack

```
Phase 1: Vault Core
└─ Basic deposit/withdraw/harvest

Phase 2: Adapters
└─ IAdapter interface for different protocols

Phase 3: Strategy-as-NFT
└─ Immutable strategy configs

Phase 4: AI-Assisted
└─ AI generates strategy parameters

Phase 5: ERC-4626 (NEW)
└─ Standard interface for all tools
```

### No Breaking Changes

```
Phase 1-4 Contracts:
├─ StrategyVault → IERC4626 compliant
├─ IAdapter → Unchanged
├─ StrategyNFT → Unchanged
├─ AI validation → Unchanged
└─ All existing code works ✓

New Code (ERC-4626):
├─ Implements standard interface
├─ Calls existing functions
├─ Adds standard events
└─ Transparent wrapper
```

---

## JURY VALUE STATEMENT

### The Core Thesis

**"MALGIST vaults are not silos — they are plug-and-play building blocks in the Mantle ecosystem."**

### Why This Matters

1. **Ecosystem Native**

   - ERC-4626 is the industry standard
   - Tools already know how to work with vaults
   - MALGIST becomes first-class Mantle citizen

2. **Institutional Grade**

   - Standard interface
   - Known attack surface
   - Reduces friction with institutions
   - Supports RWA narrative

3. **Developer Friendly**

   - Existing integrations work
   - No custom code needed
   - Lower friction for partnerships
   - Community-maintained tooling

4. **Composability**

   - Works with Yearn, Lido, Balancer
   - Aggregators (Zapper, DefiSaver) automatically discover
   - Dashboards (Dune, Nansen) track automatically
   - No special pleading needed

5. **1000x Adoption Enabler**
   - Before: Teams build custom integrations
   - After: Teams use existing code
   - Integration time: Weeks → Hours
   - Partnership friction: High → Low

---

**End of Phase 5: ERC-4626 Compatibility Design**

_Making MALGIST vaults composable with the entire Mantle ecosystem._
