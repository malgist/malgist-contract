# Deployment Status Report
**Generated**: January 23, 2026  
**Network**: Mantle Sepolia Testnet (Chain ID: 5003)  
**Status**: 🟢 **READY TO DEPLOY** (pending build fix + final testing)

---

## Executive Summary

**Question**: Apakah perlu deploy contract address ulang?

**Answer**: **YA, DENGAN 2 PILIHAN:**

1. **Option A (Recommended)**: Fresh Deployment - Deploy semua kontrak baru + UserVault baru dengan semua enhancement
2. **Option B**: Parallel System - Jaga old UserVault tetap live, deploy new system secara parallel

**Cost**: ~$0.13 on Mantle (vs $3,250 on Ethereum!)  
**Timeline**: ~4 hours setup + testing, 1-7 days user migration

---

## Current Deployment Status

### ✅ Already Live (Dec 9, 2024)

```
UserVault              0x65B43c257c885259360b7165C2773e0d53053b68 ✅
LendleAdapter          0xEEE09B03d9260C77404bc51146F7C1d58B439150 ✅
FusionXAdapter         0x2F65BE78959DA2D49f250Cc28E01589490cCd029 ✅
Mock Tokens            (USDC, WMNT, aUSDC, etc.)                  ✅
```

### 🆕 New Contracts (Not Yet Deployed - Jan 23, 2026)

```
StrategyNFT.sol              🆕 Need to deploy
AIStrategyValidator.sol      🆕 Need to deploy
StrategyExecutor.sol         🆕 Need to deploy
AdapterGovernance.sol        🆕 Need to deploy
PriceOracle.sol              🆕 Need to deploy (optional)
```

### 🔧 Modified Contracts (Requires Redeployment)

```
UserVault.sol                🔧 HAS CHANGES
  - New fee tracking per adapter
  - New events (CopyFeeCollectedDetailed, CopyFeesClaimedDetailed)
  - New internal functions (_recordAdapterFees)
  - New storage variables (adapterFeeHistory, feesByAdapter, totalFeeEvents)
```

---

## Detailed Change Analysis

### UserVault.sol Modifications

**New Storage Variables:**
- `AdapterFeeEntry` struct - Historical fee tracking per adapter
- `adapterFeeHistory` mapping - Complete fee history for analytics
- `feesByAdapter` mapping - Accumulated fees by adapter
- `totalFeeEvents` counter - Event count tracking

**New Events:**
- `CopyFeeCollectedDetailed` - Detailed fee breakdown on deposit
- `CopyFeesClaimedDetailed` - Detailed breakdown on fee claim

**New Internal Functions:**
- `_recordAdapterFees()` - Helper for enhanced fee tracking

**Impact Assessment:**
```
✅ No breaking changes to public API
✅ All existing external functions still work
✅ Backward compatible at function level
❌ Cannot be upgraded via proxy (if non-proxy deployed)
⚠️ Storage layout changed - requires fresh deployment
```

---

## Deployment Options Comparison

### Option A: FRESH DEPLOYMENT (RECOMMENDED ✅)

**What you do:**
1. Deploy all 5 new contracts
2. Deploy new UserVault with enhancements
3. Users migrate liquidity (withdraw from old, deposit to new)
4. Sunset old vault after 30 days

**Timeline:**
- Fix build & test: 1 hour
- Create scripts: 1 hour
- Test on fork: 1 hour
- Deploy to testnet: 0.5 hour
- Verify: 0.5 hour
- **Total: ~4 hours**

**User Migration:**
- Users trigger: 1-7 days (their choice)
- Keep old vault open: 30 days grace period
- Transparent, self-service process

**Pros:**
- ✅ Cleanest approach
- ✅ All features from day 1
- ✅ Easier to audit
- ✅ No technical debt
- ✅ Better for long-term

**Cons:**
- ⚠️ Users must manually migrate
- ⚠️ Brief periods of split liquidity

### Option B: PARALLEL SYSTEM (ZERO DOWNTIME)

**What you do:**
1. Keep old UserVault running
2. Deploy new system separately
3. Users gradually opt-in to new vault
4. Eventually deprecate old vault

**Timeline:**
- Same ~4 hours to setup
- Plus gradual 2-4 week rollout period

**Pros:**
- ✅ Zero downtime
- ✅ Gradual user migration
- ✅ Lower immediate impact

**Cons:**
- ⚠️ Fragmented liquidity
- ⚠️ More complex management
- ⚠️ Longer transition period

---

## Deployment Costs

### Gas Estimation (Mantle Sepolia @ 0.02 Gwei)

| Contract | Gas | USD Cost |
|----------|-----|----------|
| StrategyNFT | 1,500,000 | $0.03 |
| AIStrategyValidator | 800,000 | $0.016 |
| StrategyExecutor | 900,000 | $0.018 |
| AdapterGovernance | 600,000 | $0.012 |
| PriceOracle | 700,000 | $0.014 |
| UserVaultV2 | 2,000,000 | $0.04 |
| **TOTAL** | **6.5M** | **$0.13** |

**Comparison:**
- Same deployment on Ethereum: ~$3,250
- Mantle savings: **99.996%** 🎉

---

## Pre-Deployment Checklist

### CRITICAL (Must Complete)

- [ ] Fix build issues
  ```bash
  rm -rf lib/
  forge install
  forge build  # Must pass
  ```

- [ ] Run full test suite
  ```bash
  forge test -v              # All tests must pass
  forge coverage             # Must be >90%
  ```

- [ ] Verify Solidity versions
  ```bash
  grep -r "pragma solidity" src/  # All should be ^0.8.20
  ```

### IMPORTANT (Before Deployment)

- [ ] Create deployment scripts
  - DeployStrategyNFT.s.sol
  - DeployAIValidator.s.sol
  - DeployStrategyExecutor.s.sol
  - DeployAdapterGovernance.s.sol
  - DeployUserVaultV2.s.sol (if Option A)

- [ ] Test on local fork
  ```bash
  forge script script/DeployStrategyNFT.s.sol \
    --fork-url $MANTLE_SEPOLIA_RPC
  ```

- [ ] Verify RPC connectivity
  ```bash
  cast chain-id --rpc-url $MANTLE_SEPOLIA_RPC  # Should return 5003
  ```

### RECOMMENDED (For Safety)

- [ ] Remove debug statements
  ```bash
  grep -r "console\." src/  # Should be empty
  ```

- [ ] Verify access controls
  ```bash
  grep -r "onlyOwner\|onlyAdmin\|onlyVault" src/
  ```

- [ ] Check gas optimizations
  - Packed structs
  - Efficient storage layout
  - No unnecessary storage reads

---

## Deployment Steps (Option A Recommended)

### STEP 1: Prepare (15 minutes)

```bash
cd /Users/macbookair/Documents/Malgist-Labs/malgist-contract

# Fix dependencies
rm -rf lib/ && forge install

# Build
forge build

# Test
forge test -v && forge coverage
```

### STEP 2: Create Scripts (1 hour)

Create the following files in `script/`:
- `DeployStrategyNFT.s.sol`
- `DeployAIValidator.s.sol`
- `DeployStrategyExecutor.s.sol`
- `DeployAdapterGovernance.s.sol`
- `DeployUserVaultV2.s.sol`

Each should follow pattern:
```solidity
contract DeployStrategyNFT is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        
        StrategyNFT nft = new StrategyNFT(/* params */);
        
        vm.stopBroadcast();
        
        console.log("StrategyNFT deployed:", address(nft));
    }
}
```

### STEP 3: Test on Fork (1 hour)

```bash
# Test StrategyNFT deployment
forge script script/DeployStrategyNFT.s.sol \
  --fork-url $MANTLE_SEPOLIA_RPC \
  -v

# Test full deployment sequence
forge script script/Deploy*.s.sol \
  --fork-url $MANTLE_SEPOLIA_RPC \
  -v
```

### STEP 4: Deploy to Testnet (30 minutes)

```bash
# Export variables
export MANTLE_SEPOLIA_RPC=https://mantle-sepolia.g.alchemy.com/v2/hWStvrZu_Sw31tO2Hpjzv
export PRIVATE_KEY=$(cat .env | grep PRIVATE_KEY | cut -d'=' -f2)

# Deploy each contract
forge script script/DeployStrategyNFT.s.sol \
  --broadcast \
  --rpc-url $MANTLE_SEPOLIA_RPC \
  --verify

# Repeat for other contracts...
```

### STEP 5: Verify Deployment (30 minutes)

```bash
# Check all addresses deployed
cat broadcast/Deploy*/5003/run-latest.json | jq '.transactions[].contractAddress'

# Update deployments/mantle-sepolia.txt with new addresses

# Verify on MantleScan
# https://sepolia.mantlescan.xyz/address/<ADDRESS>
```

### STEP 6: Notify Users (1 hour)

- Create migration guide
- Announce new contract addresses
- Set grace period (7-30 days)
- Monitor old vault for remaining liquidity

---

## What Needs to Deploy

### NEW CONTRACTS (Always Deploy)

| Contract | Deploy Order | Priority |
|----------|:---:|:---:|
| StrategyNFT | 1st | HIGH |
| AIStrategyValidator | 2nd | HIGH |
| StrategyExecutor | 3rd | HIGH |
| AdapterGovernance | 4th | HIGH |
| PriceOracle | 5th | MEDIUM |

### MODIFIED CONTRACTS (Conditional)

| Contract | Deploy? | Reason |
|----------|:---:|:---:|
| UserVault | ✅ YES (Option A) | Storage changed, need fresh deployment |
| UserVault | ❌ NO (Option B) | Keep old + deploy parallel system |

### UNCHANGED CONTRACTS (No Redeploy Needed)

- LendleAdapter ✅
- FusionXAdapter ✅
- All mock tokens ✅
- EmergencyPause ✅
- FeeManager ✅

---

## Decision Framework

**Choose Option A if:**
- Want complete feature set immediately
- Users can accept brief downtime
- Want clean, auditable upgrade
- Prioritize simplicity

**Choose Option B if:**
- Need zero downtime
- Have active users on old vault
- Can manage 2 systems in parallel
- Want gradual rollout

---

## Risk Mitigation

### Before Deployment

- [ ] Test on mainnet fork locally
- [ ] Verify all addresses hardcoded correctly
- [ ] Check gas limits are reasonable
- [ ] Ensure RPC endpoint is reliable
- [ ] Have backup RPC endpoints ready

### During Deployment

- [ ] Deploy to testnet first
- [ ] Monitor transaction status
- [ ] Verify contract creation
- [ ] Check contract initialization

### After Deployment

- [ ] Verify contracts on explorer
- [ ] Run smoke tests
- [ ] Check event logs
- [ ] Monitor for any anomalies
- [ ] Keep 30-day grace period for migration

---

## Conclusion

### RECOMMENDATION: **Option A - Fresh Deployment**

**Why:**
- Cleanest approach
- All features available from day 1
- Only costs $0.13 on Mantle
- Better for long-term sustainability
- Easier to audit and verify

**Timeline:**
- Total time: ~4 hours (setup + deployment)
- User migration: 1-7 days (self-service)
- Grace period: 30 days

**Next Actions:**
1. Fix build (rm -rf lib/ && forge install)
2. Run tests (forge test)
3. Create deployment scripts
4. Test on fork
5. Deploy to Mantle Sepolia
6. Verify & document

---

## Additional Resources

- **Detailed Checklist**: See `DEPLOYMENT_CHECKLIST.md`
- **Contract Analysis**: See git diff for full changes
- **Architecture**: See `Documentation/ARCHITECTURE_DESIGN.md`
- **Deployment Guide**: See `Documentation/ADAPTER_WHITELIST_GOVERNANCE.md`

---

**Status**: 🟢 READY (pending build fix + tests)  
**Last Updated**: January 23, 2026  
**Prepared By**: GitHub Copilot  
