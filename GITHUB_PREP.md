# Project Organization for GitHub

This document explains the project structure and what files to keep/exclude.

## 📁 Recommended Structure

```
Malgist/
├── README.md                    # ✅ Main documentation
├── LICENSE                      # ✅ MIT License
├── .gitignore                   # ✅ Git ignore rules
│
├── src/                         # ✅ Main contracts
│   ├── UserVault.sol
│   ├── adapters/
│   ├── interfaces/
│   └── mocks/
│
├── test/                        # ✅ Test files
│   └── UserVault.t.sol
│
├── script/                      # ✅ Deployment scripts
│   └── DeployUserVault.s.sol
│
├── deployments/                 # ✅ Deployed addresses
│   ├── addresses.env
│   └── mantle-sepolia.txt
│
├── docs/                        # ✅ Documentation
│   ├── DEPLOYMENT_SUCCESS.md
│   ├── DEPLOY_AND_VERIFY.md
│   ├── TROUBLESHOOTING.md
│   └── QUICKSTART.md
│
├── foundry.toml                 # ✅ Foundry config
└── .env.example                 # ✅ Environment template
```

## 🗑️ Files to Clean Up

### Old Contracts (.old files)
**Location:** `src/` and `test/`  
**Action:** Delete (already archived)
- UniversalVault.sol.old
- StrategyNFT.sol (deleted)
- Integration.t.sol.old
- etc.

### Helper Scripts
**Location:** Root directory  
**Action:** Move to `scripts/` folder or delete
- deploy-with-check.sh
- deploy-retry-rpc.sh
- deploy-final.sh
- setup-env.sh
- verify-all.sh
- verify-manual.sh

### Documentation Files
**Location:** Root directory  
**Action:** Keep in root or move to `docs/`

**Keep in Root:**
- README.md
- DEPLOYMENT_SUCCESS.md

**Move to docs/:**
- DEPLOY_AND_VERIFY.md
- TROUBLESHOOTING.md
- QUICKSTART.md
- PITCH_DECK.md
- TECHNICAL_DOCS.md
- RPC_ENDPOINTS.txt

## ✅ What to Commit to GitHub

### Must Include:
- [x] src/ (all .sol files except .old)
- [x] test/ (UserVault.t.sol)
- [x] script/ (DeployUserVault.s.sol)
- [x] README.md
- [x] .gitignore
- [x] .env.example
- [x] foundry.toml
- [x] lib/ (dependencies)

### Optional but Recommended:
- [x] deployments/ (addresses)
- [x] docs/ (documentation)
- [x] LICENSE

### Must Exclude (.gitignore):
- [ ] .env (contains private keys!)
- [ ] broadcast/ (deployment logs with private data)
- [ ] cache/
- [ ] out/
- [ ] node_modules/

## 🧹 Cleanup Commands

```bash
# 1. Delete old contract files
find src test script -name "*.old" -delete

# 2. Create docs directory
mkdir -p docs

# 3. Move documentation
mv DEPLOY_AND_VERIFY.md docs/
mv TROUBLESHOOTING.md docs/
mv QUICKSTART.md docs/
mv PITCH_DECK.md docs/
mv TECHNICAL_DOCS.md docs/
mv VERIFICATION.md docs/ 2>/dev/null || true
mv QUICK_DEPLOY.md docs/ 2>/dev/null || true
mv RPC_ENDPOINTS.txt docs/ 2>/dev/null || true

# 4. Move scripts to scripts/
mkdir -p scripts/helpers
mv deploy-*.sh scripts/helpers/ 2>/dev/null || true
mv setup-env.sh scripts/helpers/ 2>/dev/null || true
mv verify-*.sh scripts/helpers/ 2>/dev/null || true

# 5. Clean build artifacts
forge clean

# 6. Verify .gitignore
cat .gitignore
```

## 📝 Update .gitignore

Make sure your .gitignore includes:

```gitignore
# Foundry
cache/
out/
broadcast/

# Environment
.env
wallet

# IDE
.vscode/
.idea/

# OS
.DS_Store
Thumbs.db

# Node (if using)
node_modules/

# Logs
*.log
```

## 🚀 Ready for GitHub

After cleanup:

```bash
# Initialize git (if not already)
git init

# Add files
git add .

# Commit
git commit -m "feat: Deploy Malgist copy-trading platform to Mantle Sepolia"

# Add remote
git remote add origin https://github.com/yourusername/Malgist.git

# Push
git push -u origin main
```

## 📦 Optional: Create Release

After pushing to GitHub:

1. Go to GitHub repository
2. Click "Releases" → "Create a new release"
3. Tag: `v1.0.0-sepolia`
4. Title: "Malgist v1.0 - Mantle Sepolia Deployment"
5. Description:
   ```markdown
   ## Malgist Copy-Trading Platform - Testnet Launch
   
   First deployment of Malgist on Mantle Sepolia testnet.
   
   ### Deployed Contracts
   - UserVault: 0x65B43c257c885259360b7165C2773e0d53053b68
   - LendleAdapter: 0xEEE09B03d9260C77404bc51146F7C1d58B439150
   - FusionXAdapter: 0x2F65BE78959DA2D49f250Cc28E01589490cCd029
   
   ### Features
   ✅ Copy-trading functionality
   ✅ Creator fees (0-0.5%)
   ✅ Multi-protocol support
   ✅ USDC-optimized
   
   [View on Explorer](https://sepolia.mantlescan.xyz/address/0x65B43c257c885259360b7165C2773e0d53053b68)
   ```

## 🎯 Final Checklist

Before pushing to GitHub:

- [ ] README.md created with all info
- [ ] .env removed from tracking (.gitignore)
- [ ] Old files (.old) deleted
- [ ] Documentation organized in docs/
- [ ] Scripts organized in scripts/
- [ ] Clean build (forge clean)
- [ ] Tests passing (forge test)
- [ ] LICENSE file added
- [ ] .gitignore up to date
- [ ] Commit messages are clear

---

**Your project is now GitHub-ready!** 🎉
