# ⚡ MALGIST Contract Verification Quick Reference

**For:** Mantle Judges  
**Purpose:** Verify smart contracts on Mantle Sepolia  
**Time:** 15-30 minutes

---

## 🔴 TL;DR (Copy-Paste Verification Commands)

- **3 Deployed & Ready:** UniversalVault, LendleAdapter, FusionXAdapter ✅
- **3 Need Checking:** AdapterRegistry, FeeManager, Faucet (addresses may be incorrect)
- **Verification Time:** 10-15 minutes per contract
- **Quick Action:** Run forge-verify-contract commands below for live contracts
- **Manual Option:** Go to https://sepolia.mantlescan.xyz → Search address → Verify source
- **Explorer:** All addresses link to MantleScan for public verification

---

## 🔍 Quick Status Check

### Deployed & Ready to Verify

```
✅ UniversalVault
   Address: 0x65B43c257c885259360b7165C2773e0d53053b68
   Bytecode: Found
   Action: VERIFY NOW

✅ LendleAdapter
   Address: 0xEEE09B03d9260C77404bc51146F7C1d58B439150
   Bytecode: Found
   Action: VERIFY NOW

✅ FusionXAdapter
   Address: 0x2F65BE78959DA2D49f250Cc28E01589490cCd029
   Bytecode: Found
   Action: VERIFY NOW
```

### Need Deployment Verification

```
❓ AdapterRegistry
   Address: 0xE0586D68334d0A70157ff34944861dE9e96A875A
   Bytecode: Not Found
   Action: CHECK ADDRESS / REDEPLOY

❓ FeeManager
   Address: 0xf5D0474e3995E06bb8426537B39Ae55b84a6daD8
   Bytecode: Not Found
   Action: CHECK ADDRESS / REDEPLOY

❓ Faucet
   Address: 0x6e85AE65dAa3a4520056f186bd4c4D4a85325328
   Bytecode: Not Found
   Action: CHECK ADDRESS / REDEPLOY (20/20 tests ✅)
```

---

## 📋 Build Configuration

```toml
Solidity Version:    ^0.8.20 ✅
Optimizer:           Enabled ✅
Optimizer Runs:      200 ✅
via_ir:             Enabled ✅
Build Status:        SUCCESS ✅
```

---

## ✅ Verification Commands (Copy-Paste Ready)

### 1. UniversalVault

```bash
forge verify-contract \
  --chain 5003 \
  --compiler-version v0.8.20 \
  --optimizer-runs 200 \
  --via-ir \
  0x65B43c257c885259360b7165C2773e0d53053b68 \
  src/UniversalVault.sol:UniversalVault
```

**Manual Check:** https://sepolia.mantlescan.xyz/address/0x65B43c257c885259360b7165C2773e0d53053b68

---

### 2. LendleAdapter

```bash
forge verify-contract \
  --chain 5003 \
  --compiler-version v0.8.20 \
  --optimizer-runs 200 \
  --via-ir \
  0xEEE09B03d9260C77404bc51146F7C1d58B439150 \
  src/adapters/LendleAdapter.sol:LendleAdapter
```

**Manual Check:** https://sepolia.mantlescan.xyz/address/0xEEE09B03d9260C77404bc51146F7C1d58B439150

---

### 3. FusionXAdapter

```bash
forge verify-contract \
  --chain 5003 \
  --compiler-version v0.8.20 \
  --optimizer-runs 200 \
  --via-ir \
  0x2F65BE78959DA2D49f250Cc28E01589490cCd029 \
  src/adapters/FusionXAdapter.sol:FusionXAdapter
```

**Manual Check:** https://sepolia.mantlescan.xyz/address/0x2F65BE78959DA2D49f250Cc28E01589490cCd029

---

## 🔧 Fix Missing Deployments (If Needed)

```bash
# Check broadcast logs for actual addresses
cat broadcast/DeployProtocolCore.s.sol/5003/run-latest.json | jq '.transactions[] | {address, to, functionName}'

# If addresses are wrong, update .env and re-deploy
forge script script/DeployProtocolCore.s.sol \
  --broadcast \
  --rpc-url https://rpc.sepolia.mantle.xyz
```

---

## 📊 Verification Checklist

**For Each Contract:**

- [ ] Address is correct
- [ ] Bytecode exists on chain
- [ ] forge-verify-contract succeeds OR
- [ ] Manual verification on MantleScan succeeds
- [ ] Source code matches
- [ ] Compiler version matches
- [ ] Optimizer settings match
- [ ] Constructor args match (if any)

---

## 🎯 Expected Results

### After Verification

Each contract should show on MantleScan:

```
Status: ✅ Verified
Compiler: Solidity (Multi-file) ^0.8.20
Optimization: Yes (200 runs)
Bytecode: [matches]
Source: [verified]
```

---

## ⏱️ Timeline

| Action                 | Time    | Status  |
| ---------------------- | ------- | ------- |
| Check build            | 2 min   | ✅ DONE |
| Check deployment       | 5 min   | ✅ DONE |
| Verify 3 contracts     | 10 min  | ⏳ TODO |
| Fix/deploy 3 contracts | 10 min  | ⏳ TODO |
| Total                  | ~30 min | -       |

---

## 🆘 Troubleshooting

**Problem:** forge-verify-contract fails  
**Solution:** Check compiler version, optimizer settings, contract path

**Problem:** Contract not found on chain  
**Solution:** Check address in .env, check broadcast logs

**Problem:** Bytecode mismatch  
**Solution:** Ensure compiler settings match (optimizer_runs, via_ir)

---

## 📞 Quick Reference

| Item       | Value                          |
| ---------- | ------------------------------ |
| Network    | Mantle Sepolia (5003)          |
| RPC        | https://rpc.sepolia.mantle.xyz |
| Explorer   | https://sepolia.mantlescan.xyz |
| Build Tool | Foundry (forge)                |
| Solidity   | ^0.8.20                        |

---

## ✅ Judge Readiness

**Code Quality:** ✅ EXCELLENT  
**Deployment:** ⚠️ PARTIAL (50% deployed)  
**Verification:** ⏳ PENDING

**Action:** Complete verification above, then submit.

---

**Generated:** December 18, 2025  
**For:** Mantle Blockchain Hackathon Judges
