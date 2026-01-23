# Smart Contract Deployment Readiness Checklist
**Date**: January 23, 2026  
**Network**: Mantle Sepolia Testnet (Chain ID: 5003)

---

## 🔍 Current Deployment Status

### ✅ Already Deployed (Dec 9, 2024)

| Contract | Address | Status | Notes |
|----------|---------|--------|-------|
| UserVault | `0x65B43c257c885259360b7165C2773e0d53053b68` | ✅ Live | Copy-trading vault |
| LendleAdapter | `0xEEE09B03d9260C77404bc51146F7C1d58B439150` | ✅ Live | Aave V3 integration |
| FusionXAdapter | `0x2F65BE78959DA2D49f250Cc28E01589490cCd029` | ✅ Live | DEX LP provider |
| Mock Tokens | See mantle-sepolia.txt | ✅ Live | USDC, WMNT, etc. |

### 🔄 NEW Contracts (Not Yet Deployed)

| Contract | Path | Status | Deployment Order |
|----------|------|--------|-------------------|
| StrategyNFT | `src/StrategyNFT.sol` | 🆕 NEW | **1st** - Core dependency |
| AIStrategyValidator | `src/validators/AIStrategyValidator.sol` | 🆕 NEW | **2nd** - Used by StrategyNFT |
| StrategyExecutor | `src/StrategyExecutor.sol` | 🆕 NEW | **3rd** - Routes to adapters |
| AdapterGovernance | `src/governance/AdapterGovernance.sol` | 🆕 NEW | **4th** - Timelock control |
| PriceOracle | `src/oracles/PriceOracle.sol` | 🆕 NEW | **5th** - Optional but recommended |

### 🔧 MODIFIED Contracts (Need Redeployment)

| Contract | Changes | Impact | Priority |
|----------|---------|--------|----------|
| **UserVault** | +Fee tracking per adapter<br>+Enhanced events<br>+New internal functions | **BREAKING** | 🔴 HIGH |

---

## 📊 Change Analysis

### UserVault.sol Changes

**New Additions:**
- `AdapterFeeEntry` struct for fee history tracking
- `adapterFeeHistory` mapping - tracks fees per adapter per creator
- `feesByAdapter` mapping - accumulated fees by adapter
- `totalFeeEvents` counter
- `CopyFeeCollectedDetailed` event
- `CopyFeesClaimedDetailed` event
- `_recordAdapterFees()` internal function
- Enhanced fee distribution logic

**Compatibility:**
- ✅ No state variable removals
- ✅ No function signature changes to public methods
- ✅ No breaking changes to existing logic
- ⚠️ BUT: New storage variables require fresh deployment (cannot upgrade via proxy)

**Gas Impact:**
- Slightly increased due to additional mappings
- ~10-15% more storage per fee collection

---

## 🚀 Deployment Strategy

### OPTION A: Fresh Deployment (RECOMMENDED)

**Why:** New storage variables in UserVault require clean state

**Steps:**
```bash
# 1. Deploy NEW contracts first (no dependencies on UserVault)
forge script script/DeployStrategyNFT.s.sol --broadcast --verify

# 2. Deploy AIStrategyValidator (used by StrategyNFT)
forge script script/DeployAIValidator.s.sol --broadcast --verify

# 3. Deploy StrategyExecutor
forge script script/DeployStrategyExecutor.s.sol --broadcast --verify

# 4. Deploy governance
forge script script/DeployAdapterGovernance.s.sol --broadcast --verify

# 5. Deploy NEW UserVault with enhanced features
forge script script/DeployUserVaultV2.s.sol --broadcast --verify

# 6. Migrate user data (manual process)
# - Transfer admin to new UserVault
# - Update strategy references
```

**Pros:**
- ✅ Clean state
- ✅ No migration risks
- ✅ Full backward compatibility

**Cons:**
- ⚠️ Need to migrate existing user strategies
- ⚠️ Liquidity needs to be withdrawn and redeposited

### OPTION B: Keep Old UserVault + Deploy New Parallel System

**Why:** Minimize disruption to existing users

**Steps:**
```bash
# 1. Deploy all new contracts independently
# 2. Create UserVaultV2 with all enhancements
# 3. Allow users to migrate gradually
# 4. Eventually sunset old vault
```

**Pros:**
- ✅ Zero downtime for existing users
- ✅ Gradual migration path

**Cons:**
- ⚠️ Liquidity fragmented across 2 vaults
- ⚠️ More complex for users

---

## 📋 Pre-Deployment Checklist

### Code Quality
- [ ] Build compiles without errors
- [ ] All tests pass (forge test)
- [ ] Coverage > 90%
- [ ] No hardcoded addresses in contracts
- [ ] All contracts use same Solidity version (^0.8.20)

### Security
- [ ] No console.log or debug statements
- [ ] Proper access controls on all functions
- [ ] Reentrancy guards where needed
- [ ] Safe math operations
- [ ] No uninitialized storage variables

### Configuration
- [ ] RPC endpoint verified
- [ ] Private key available and funded
- [ ] Gas limit set appropriately
- [ ] Etherscan API key for verification (if needed)

### Documentation
- [ ] Contract addresses documented
- [ ] Deployment script tested locally
- [ ] Integration guide updated
- [ ] Event signatures documented

---

## 🔢 Gas Estimation

### Deployment Costs (Mantle Sepolia)

| Contract | Estimated Gas | Est. Cost @ 0.02 Gwei |
|----------|---------------|----------------------|
| StrategyNFT | 1,500,000 | $0.03 |
| AIStrategyValidator | 800,000 | $0.016 |
| StrategyExecutor | 900,000 | $0.018 |
| AdapterGovernance | 600,000 | $0.012 |
| PriceOracle | 700,000 | $0.014 |
| UserVaultV2 | 2,000,000 | $0.04 |
| **TOTAL** | **~6.5M** | **~$0.13** |

**vs Ethereum Mainnet**: Would cost ~$3,250 on ETH! 💰

---

## ✅ Recommendations

### IMMEDIATE (Required):
1. **Build & Test Contracts** ← DO THIS FIRST
   ```bash
   cd /Users/macbookair/Documents/Malgist-Labs/malgist-contract
   rm -rf lib/
   forge install
   forge build
   forge test
   ```

2. **Create Deployment Scripts**
   - `script/DeployStrategyNFT.s.sol`
   - `script/DeployAIValidator.s.sol`
   - `script/DeployStrategyExecutor.s.sol`
   - `script/DeployAdapterGovernance.s.sol`
   - `script/DeployUserVaultV2.s.sol`

3. **Test Deployments** on local fork
   ```bash
   forge script script/DeployStrategyNFT.s.sol --fork-url $MANTLE_SEPOLIA_RPC
   ```

4. **Execute Deployments** to testnet
   ```bash
   forge script script/DeployStrategyNFT.s.sol \
     --broadcast \
     --rpc-url $MANTLE_SEPOLIA_RPC \
     --verify
   ```

### AFTER DEPLOYMENT:
1. Save all addresses to `deployments/mantle-sepolia.txt`
2. Verify contracts on MantleScan
3. Update .env and frontend configuration
4. Smoke test on frontend
5. Document migration path for users

---

## 🎯 Decision Matrix

**Do you need to redeploy UserVault?**

| Scenario | Redeploy? | Reason |
|----------|-----------|--------|
| Keep old vault, deploy new parallel system | ❌ No | Users keep existing liquidity |
| Migrate all users to new enhanced vault | ✅ **Yes** | Need clean state + new features |
| Only deploy new validator/executor contracts | ⚠️ Maybe | Depends on integration approach |

**RECOMMENDATION**: Deploy as **Option A** (Fresh Deployment)
- Cleanest approach
- All features available from day 1
- Easier to audit and test

---

## 📞 Next Steps

1. **Fix build** (resolve dependencies)
2. **Run tests** (verify all contracts)
3. **Choose deployment option** (A or B above)
4. **Create deployment scripts** (for chosen option)
5. **Test on local fork** (before mainnet)
6. **Execute deployment** (to Mantle Sepolia)
7. **Verify & document** (save addresses)

---

**Status**: 🟡 READY (pending build fix & final testing)
