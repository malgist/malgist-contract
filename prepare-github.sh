#!/bin/bash
# Automated GitHub preparation script
# This script organizes the Malgist project for GitHub publication

echo "========================================="
echo "Malgist GitHub Preparation"
echo "========================================="
echo ""

# 1. Create directories
echo "[1/7] Creating directory structure..."
mkdir -p docs
mkdir -p scripts/helpers
mkdir -p abis
echo "  ✓ Directories created"
echo ""

# 2. Move documentation files
echo "[2/7] Organizing documentation..."
mv DEPLOY_AND_VERIFY.md docs/ 2>/dev/null && echo "  ✓ Moved DEPLOY_AND_VERIFY.md" || echo "  - DEPLOY_AND_VERIFY.md not found"
mv TROUBLESHOOTING.md docs/ 2>/dev/null && echo "  ✓ Moved TROUBLESHOOTING.md" || echo "  - TROUBLESHOOTING.md not found"
mv QUICKSTART.md docs/ 2>/dev/null && echo "  ✓ Moved QUICKSTART.md" || echo "  - QUICKSTART.md not found"
mv PITCH_DECK.md docs/ 2>/dev/null && echo "  ✓ Moved PITCH_DECK.md" || echo "  - PITCH_DECK.md not found"
mv TECHNICAL_DOCS.md docs/ 2>/dev/null && echo "  ✓ Moved TECHNICAL_DOCS.md" || echo "  - TECHNICAL_DOCS.md not found"
mv VERIFICATION.md docs/ 2>/dev/null && echo "  ✓ Moved VERIFICATION.md" || echo "  - VERIFICATION.md not found"
mv QUICK_DEPLOY.md docs/ 2>/dev/null && echo "  ✓ Moved QUICK_DEPLOY.md" || echo "  - QUICK_DEPLOY.md not found"
mv "D EPLOY_QUICK.md" docs/ 2>/dev/null && echo "  ✓ Moved D EPLOY_QUICK.md" || echo "  - D EPLOY_QUICK.md not found"
mv RPC_ENDPOINTS.txt docs/ 2>/dev/null && echo "  ✓ Moved RPC_ENDPOINTS.txt" || echo "  - RPC_ENDPOINTS.txt not found"
mv GITHUB_PREP.md docs/ 2>/dev/null && echo "  ✓ Moved GITHUB_PREP.md" || true
echo ""

# 3. Move helper scripts
echo "[3/7] Organizing scripts..."
mv deploy-with-check.sh scripts/helpers/ 2>/dev/null && echo "  ✓ Moved deploy-with-check.sh" || true
mv deploy-retry-rpc.sh scripts/helpers/ 2>/dev/null && echo "  ✓ Moved deploy-retry-rpc.sh" || true
mv deploy-final.sh scripts/helpers/ 2>/dev/null && echo "  ✓ Moved deploy-final.sh" || true
mv setup-env.sh scripts/helpers/ 2>/dev/null && echo "  ✓ Moved setup-env.sh" || true
mv verify-all.sh scripts/helpers/ 2>/dev/null && echo "  ✓ Moved verify-all.sh" || true
mv verify-manual.sh scripts/helpers/ 2>/dev/null && echo "  ✓ Moved verify-manual.sh" || true
echo ""

# 4. Delete old contract files
echo "[4/7] Cleaning up old files..."
find src test script -name "*.old" -type f -delete 2>/dev/null && echo "  ✓ Deleted .old files" || echo "  - No .old files found"
echo ""

# 5. Generate ABIs
echo "[5/7] Generating contract ABIs..."
forge inspect src/UserVault.sol:UserVault abi > abis/UserVault.json 2>/dev/null && echo "  ✓ UserVault ABI generated" || echo "  ✗ Failed to generate UserVault ABI"
forge inspect src/adapters/LendleAdapter.sol:LendleAdapter abi > abis/LendleAdapter.json 2>/dev/null && echo "  ✓ LendleAdapter ABI generated" || echo "  ✗ Failed to generate LendleAdapter ABI"
forge inspect src/adapters/FusionXAdapter.sol:FusionXAdapter abi > abis/FusionXAdapter.json 2>/dev/null && echo "  ✓ FusionXAdapter ABI generated" || echo "  ✗ Failed to generate FusionXAdapter ABI"
echo ""

# 6. Clean build artifacts
echo "[6/7] Cleaning build artifacts..."
forge clean
echo "  ✓ Build artifacts cleaned"
echo ""

# 7. Final verification
echo "[7/7] Verifying structure..."
echo ""
echo "Project structure:"
tree -L 2 -I 'node_modules|cache|out|lib' . 2>/dev/null || ls -la
echo ""

echo "========================================="
echo "GitHub Preparation Complete!"
echo "========================================="
echo ""
echo "Next steps:"
echo "1. Review .gitignore (ensure .env is excluded)"
echo "2. Build: forge build"
echo "3. Test: forge test"
echo "4. Initialize git: git init"
echo "5. Add files: git add ."
echo "6. Commit: git commit -m 'Initial commit'"
echo "7. Push to GitHub"
echo ""
echo "See docs/GITHUB_PREP.md for detailed instructions"
echo ""
