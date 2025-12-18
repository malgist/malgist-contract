<!-- Documentation/INTEGRATION_GUIDE_STRATEGY_LEVEL_VAULTS.md -->

# Integration Guide: Strategy-Level Vaults (ERC4626)

**Target Audience:** Developers integrating MALGIST strategies  
**Updated:** December 17, 2025  
**Status:** Production Ready

---

## 📖 Table of Contents

1. [Quick Start](#quick-start)
2. [Creating a Strategy](#creating-a-strategy)
3. [Depositing to a Strategy](#depositing-to-a-strategy)
4. [Withdrawing Funds](#withdrawing-funds)
5. [Fee Collection](#fee-collection)
6. [Composing Strategies](#composing-strategies)
7. [API Reference](#api-reference)
8. [Common Patterns](#common-patterns)
9. [Troubleshooting](#troubleshooting)

---

## 🚀 Quick Start

### What Are Strategy-Level Vaults?

MALGIST uses **per-strategy ERC4626 vaults**. Each strategy is:

- ✅ A separate smart contract (ERC4626StrategyVault)
- ✅ Configured via immutable Strategy NFT
- ✅ Gas-optimized for isolated operations
- ✅ Standard-compliant (composable with DeFi)

### Before Integration

```solidity
// Old pattern (DEPRECATED)
UniversalVault vault;        // All strategies here
vault.deposit(strategy_id, amount);  // Custom interface

// New pattern (CURRENT)
ERC4626StrategyVault vault;  // One vault per strategy
vault.deposit(amount, recipient);  // Standard ERC4626
```

---

## 🛠️ Creating a Strategy

### Step 1: Prepare Strategy Parameters

```solidity
// Strategy configuration
address[] memory adapters = new address[](2);
adapters[0] = 0xFusionXAddr;  // DEX yield source
adapters[1] = 0xLendleAddr;   // Lending source

uint16[] memory ratios = new uint16[](2);
ratios[0] = 4000;  // 40% to FusionX
ratios[1] = 6000;  // 60% to Lendle

address creator = msg.sender;  // You (fee recipient)
uint16 creatorFeeBps = 1000;   // 10% of yield
uint8 riskLevel = 2;           // 1-5 scale
```

### Step 2: Mint Strategy NFT

```solidity
// Interface: IStrategyNFT
IStrategyNFT strategyNFT = IStrategyNFT(0xStrategyNFTAddr);

uint256 strategyId = strategyNFT.mintStrategy(
    adapters,
    ratios,
    creator,
    creatorFeeBps,
    riskLevel,
    "My Yield Strategy"  // Metadata
);

// strategyId is now your NFT token ID
// Strategy is immutable from this point
```

### Step 3: Deploy Strategy Vault

```solidity
// Interface: IVaultFactory
IVaultFactory factory = IVaultFactory(0xVaultFactoryAddr);

address vaultAddress = factory.deployVault(
    strategyId,
    address(USDC),  // Underlying token
    "MALGIST Strategy Share",
    "MGST-1"
);

// vaultAddress is your deployed ERC4626StrategyVault
```

### Validation (Automatic)

```solidity
// Before deployment, validators check:
✅ All adapters are whitelisted
✅ Ratios sum to 100% (10,000 bps)
✅ Creator fee is ≤ 50%
✅ Risk level is valid (1-5)
✅ Adapters support the asset (USDC)

// If validation fails: revert with reason
// Example: "Invalid adapter configuration"
```

---

## 💰 Depositing to a Strategy

### Standard ERC4626 Deposit

```solidity
// Step 1: Approve USDC
IERC20(USDC).approve(vaultAddress, 1000e6);  // 1000 USDC

// Step 2: Deposit
IErc4626 vault = IErc4626(vaultAddress);
uint256 sharesReceived = vault.deposit(
    1000e6,      // 1000 USDC
    msg.sender   // Receive shares
);

// Result: msg.sender receives sharesReceived amount
// sharesReceived = 1000e18 (1:1 for fresh vault)
```

### Preview Deposit (No State Change)

```solidity
// Check how many shares you'd get
uint256 shares = vault.previewDeposit(1000e6);
console.log("Will receive:", shares);

// Check how much USDC needed for X shares
uint256 assetsNeeded = vault.previewMint(1000e18);
console.log("Assets needed:", assetsNeeded);
```

### Internal Flow (What Happens)

```
1. Approve USDC to vault
   └─→ ERC20 approval mechanism

2. Call vault.deposit(1000e6, msg.sender)
   └─→ Vault transfers 1000 USDC from you
   └─→ Vault reads strategy config from NFT
   └─→ Routes to adapters:
       ├─→ 400 USDC to FusionXAdapter
       └─→ 600 USDC to LendleAdapter
   └─→ Adapters deploy to protocols
   └─→ Vault mints 1000 shares to you
   └─→ Shares stored in ERC20 balance

3. You can now:
   ├─→ Transfer shares to others
   ├─→ Use shares as collateral
   └─→ Redeem shares for USDC + yield
```

---

## 🏦 Withdrawing Funds

### Standard ERC4626 Withdrawal

```solidity
// Withdraw all funds
uint256 assets = vault.redeem(
    sharesOwned,  // Your share balance
    msg.sender,   // Receive USDC
    msg.sender    // Shares owner
);

// Result: msg.sender receives assets amount in USDC
// USDC includes original deposit + accrued yield
```

### Partial Withdrawal

```solidity
// Withdraw only 500 USDC worth
uint256 sharesToBurn = vault.previewWithdraw(500e6);
uint256 withdrawn = vault.withdraw(
    500e6,           // 500 USDC worth
    msg.sender,      // Receive here
    msg.sender       // Burn from here
);

// Remaining shares continue earning yield
```

### Preview Withdrawal (No State Change)

```solidity
// How many shares to burn for 500 USDC?
uint256 sharesCost = vault.previewWithdraw(500e6);

// How much USDC do I get for burning 100 shares?
uint256 assets = vault.previewRedeem(100e18);
```

### Withdrawal Flow

```
1. Call vault.withdraw(500e6, recipient, owner)
   └─→ Vault collects 500 USDC from adapters:
       ├─→ 200 from FusionXAdapter (40%)
       └─→ 300 from LendleAdapter (60%)
   └─→ Adapters withdraw from protocols
   └─→ Vault calculates shares to burn
   └─→ Shares removed from your balance
   └─→ 500 USDC transferred to recipient

2. Update loop
   ├─→ Remaining adapter balances rebalanced
   └─→ Ratios maintained (40/60)
```

---

## 💸 Fee Collection

### How Creator Fees Work

```solidity
// Creator earns fees from harvest yield

// Example:
// - You deposit 1000 USDC
// - Vault earns 100 USDC in yield (10%)
// - Your fee: 10% of 100 = 10 USDC (if creatorFeeBps = 1000)
// - Your net yield: 90 USDC
// - Total value: 1000 + 90 = 1090 USDC
```

### Claiming Creator Fees

```solidity
// Claim all accumulated fees
IFeeManager feeManager = IFeeManager(0xFeeManagerAddr);
uint256 claimed = feeManager.claimCopyFees(
    strategyId,  // Your strategy NFT ID
    msg.sender   // Fee recipient
);

// claimed is transferred to msg.sender as USDC
```

### Fee Transparency

```solidity
// Check pending fees
uint256 pendingFees = feeManager.pendingCopyFees(strategyId);
console.log("Fees to claim:", pendingFees);

// Check fee rates
(address creator, uint16 feeBps) = vault.strategyFeeConfig();
console.log("Creator:", creator);
console.log("Fee %:", uint256(feeBps) / 100);  // Convert to percent
```

---

## 🧩 Composing Strategies

### Vault-of-Vaults Pattern (ComposableVault)

```solidity
// Create a composite strategy that combines multiple strategies

IComposableVault rootVault = IComposableVault(0xComposableAddr);

// Add Strategy 1 (40% allocation)
rootVault.addChildVault(
    0xStrategyVault1,  // Strategy vault address
    40_00              // 40% of deposits
);

// Add Strategy 2 (60% allocation)
rootVault.addChildVault(
    0xStrategyVault2,  // Strategy vault address
    60_00              // 60% of deposits
);

// Now users can:
// - Deposit USDC to composite vault
// - Receives shares in composite vault
// - Auto-routed to child strategies
// - Yield from both strategies combined
```

### Composite Deposit Flow

```
User deposits 1000 USDC to ComposableVault
    │
    ├─→ 400 USDC to Strategy 1 (ERC4626StrategyVault)
    │   └─→ Routes to adapters per strategy 1 config
    │
    └─→ 600 USDC to Strategy 2 (ERC4626StrategyVault)
        └─→ Routes to adapters per strategy 2 config

Result:
- User holds composite vault shares
- Yield flows from both strategies
- Can redeem composite shares for all underlying USDC + yield
```

### Rebalancing Compositions

```solidity
// Adjust allocations (requires governance)
rootVault.updateChildAllocation(
    0xStrategyVault1,  // Change this vault's allocation
    50_00              // New: 50% (was 40%)
);

// Next deposits use new ratio
// Existing deposits: can rebalance if desired
```

---

## 📚 API Reference

### ERC4626StrategyVault Interface

```solidity
interface IERC4626 {
    // Core deposit/withdraw
    function deposit(uint256 assets, address receiver)
        external returns (uint256 shares);

    function withdraw(uint256 assets, address receiver, address owner)
        external returns (uint256 shares);

    function redeem(uint256 shares, address receiver, address owner)
        external returns (uint256 assets);

    // Preview functions (view, no state change)
    function previewDeposit(uint256 assets)
        external view returns (uint256 shares);

    function previewWithdraw(uint256 assets)
        external view returns (uint256 shares);

    function previewRedeem(uint256 shares)
        external view returns (uint256 assets);

    // Accounting
    function totalAssets() external view returns (uint256);
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function asset() external view returns (address);
}

// Extended MALGIST functions
function harvestYield() external returns (uint256 harvestedAmount);
function rebalanceAdapters() external returns (bool success);
function getAdapterBalances()
    external view returns (address[] memory, uint256[] memory);
```

### StrategyNFT Interface

```solidity
interface IStrategyNFT is IERC721 {
    // Create strategy
    function mintStrategy(
        address[] calldata adapters,
        uint16[] calldata ratios,
        address creator,
        uint16 creatorFeeBps,
        uint8 riskLevel,
        string calldata metadata
    ) external returns (uint256 strategyId);

    // Query strategy config
    function getStrategy(uint256 tokenId)
        external view returns (
            address[] memory adapters,
            uint16[] memory ratios,
            address creator,
            uint16 creatorFeeBps,
            uint8 riskLevel,
            bool isActive,
            uint40 createdAt,
            uint16 version
        );

    // Deactivate (creator-only)
    function deactivateStrategy(uint256 tokenId) external;
}
```

### FeeManager Interface

```solidity
interface IFeeManager {
    // Claim creator fees
    function claimCopyFees(uint256 strategyId, address recipient)
        external returns (uint256 amount);

    // Check pending fees
    function pendingCopyFees(uint256 strategyId)
        external view returns (uint256 amount);

    // Fee configuration
    function getStrategyFeeConfig(uint256 strategyId)
        external view returns (
            address creator,
            uint16 feeBps,
            uint256 accumulatedFees
        );
}
```

---

## 💡 Common Patterns

### Pattern 1: Simple Strategy (Copy Trading)

```solidity
// Creator deploys 1 strategy routing to 1 protocol
address[] memory adapters = new address[](1);
adapters[0] = lendleAdapter;

uint16[] memory ratios = new uint16[](1);
ratios[0] = 10000;  // 100% to Lendle

uint256 strategyId = strategyNFT.mintStrategy(
    adapters,
    ratios,
    creator,
    500,  // 5% fee
    1     // Low risk
);
```

### Pattern 2: Diversified Yield

```solidity
// Creator deploys strategy routing to multiple protocols
address[] memory adapters = new address[](3);
adapters[0] = fusionX;
adapters[1] = lendle;
adapters[2] = aave;

uint16[] memory ratios = new uint16[](3);
ratios[0] = 3334;   // ~33% to FusionX
ratios[1] = 3333;   // ~33% to Lendle
ratios[2] = 3333;   // ~33% to Aave

uint256 strategyId = strategyNFT.mintStrategy(
    adapters,
    ratios,
    creator,
    1000,  // 10% fee
    2      // Medium risk
);
```

### Pattern 3: High-Risk Leverage

```solidity
// Creator deploys strategy using leveraged adapter
address[] memory adapters = new address[](1);
adapters[0] = hardenedAaveV3;  // Leveraged lending

uint16[] memory ratios = new uint16[](1);
ratios[0] = 10000;

uint256 strategyId = strategyNFT.mintStrategy(
    adapters,
    ratios,
    creator,
    2000,  // 20% fee (higher risk, higher reward)
    5      // High risk
);
```

### Pattern 4: Cross-Chain Yield

```solidity
// Creator deploys strategy for cross-chain operations
address[] memory adapters = new address[](2);
adapters[0] = fusionX;         // Mantle yield
adapters[1] = layerZero;       // Cross-chain bridge

uint16[] memory ratios = new uint16[](2);
ratios[0] = 7000;  // 70% yield on Mantle
ratios[1] = 3000;  // 30% bridge to other chains

uint256 strategyId = strategyNFT.mintStrategy(
    adapters,
    ratios,
    creator,
    1500,  // 15% fee
    3      // Medium-high risk
);
```

---

## 🔍 Troubleshooting

### Problem: "Invalid adapter configuration"

**Cause:** Adapters don't support the asset (USDC)

**Solution:**

```solidity
// Check adapter compatibility
(address supportedAsset) = adapter.token();
require(supportedAsset == USDC, "Adapter mismatch");

// Only use adapters that support USDC
```

### Problem: "Ratios must sum to 10000"

**Cause:** Adapter allocation percentages don't add up to 100%

**Solution:**

```solidity
// Verify ratios sum to 10000 (100%)
uint256 total = 0;
for (uint256 i = 0; i < ratios.length; i++) {
    total += ratios[i];
}
require(total == 10000, "Ratios invalid");
```

### Problem: "Insufficient balance for withdrawal"

**Cause:** Adapter doesn't have enough liquidity to withdraw requested amount

**Solution:**

```solidity
// Check adapter balance before withdrawing
uint256 available = adapter.getBalance();
uint256 needed = (amount * ratio[i]) / 10000;
require(available >= needed, "Insufficient liquidity");

// Alternative: Withdraw less or wait for yield harvest
```

### Problem: "Adapter does not exist"

**Cause:** Adapter address not whitelisted or invalid

**Solution:**

```solidity
// Verify adapter is whitelisted
bool isValid = adapterRegistry.isWhitelisted(adapterAddress);
require(isValid, "Adapter not whitelisted");

// Use AdapterRegistry to find valid adapters
address[] memory validAdapters = adapterRegistry.listAdapters();
```

### Problem: "Reentrancy detected"

**Cause:** Calling vault functions recursively during withdrawal

**Solution:**

```solidity
// DON'T do this
function onReceiveUSDC() external {
    vault.withdraw(...);  // Reentrancy!
}

// DO this instead
function onReceiveUSDC() external {
    // Handle USDC, but don't call vault
    // Emit event for external handler
    emit ReceivedUSDC(amount);
}
```

---

## 🚨 Best Practices

### Security

- ✅ Always approve exact amounts: `approve(vault, amount)` not `approve(vault, MAX)`
- ✅ Verify strategy NFT authenticity before using
- ✅ Check adapter whitelist before adding to strategy
- ✅ Use preview functions before deposit/withdrawal
- ✅ Never call vault functions during reentrancy-susceptible operations

### Gas Optimization

- ✅ Batch multiple deposits/withdrawals in one transaction
- ✅ Use `previewDeposit` to check expected shares (gas-free)
- ✅ Rebalance adapters in batches, not individually
- ✅ Cache `totalAssets()` if calling multiple times

### User Experience

- ✅ Display share prices in terms of underlying asset (e.g., 1 share = 1.05 USDC)
- ✅ Show estimated yield before deposit
- ✅ Show fee impact (creator fee % of yield)
- ✅ Allow users to preview withdrawals
- ✅ Provide clear feedback on transaction status

---

## 📞 Getting Help

**Documentation:** See `/Documentation` folder  
**Deployment Status:** Check `/DEPLOYMENT_SUCCESS.md`  
**Implementation Plan:** See `/Documentation/implementation_plan.md`  
**GitHub Issues:** Report bugs and request features

---

**Last Updated:** December 17, 2025  
**Version:** 1.0 (Strategy-Level Vaults)  
**Maintainer:** MALGIST Development Team
