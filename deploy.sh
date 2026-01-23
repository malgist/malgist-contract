#!/bin/bash

# ════════════════════════════════════════════════════════════════════
# Mantle Contract Deployment Script
# Network: Mantle Sepolia (Chain ID: 5003)
# Status: Manual Deployment Guide
# ════════════════════════════════════════════════════════════════════

echo "🚀 MALGIST SMART CONTRACT DEPLOYMENT GUIDE"
echo "========================================="
echo ""
echo "Network: Mantle Sepolia Testnet (Chain ID: 5003)"
echo "RPC: https://mantle-sepolia.g.alchemy.com/v2/YOUR_API_KEY"
echo ""

# Check environment
if [ -z "$MANTLE_SEPOLIA_RPC" ]; then
    echo "❌ ERROR: MANTLE_SEPOLIA_RPC not set"
    echo "   Export: export MANTLE_SEPOLIA_RPC=https://mantle-sepolia.g.alchemy.com/v2/YOUR_KEY"
    exit 1
fi

if [ -z "$PRIVATE_KEY" ]; then
    echo "❌ ERROR: PRIVATE_KEY not set"
    echo "   Export: export PRIVATE_KEY=0x..."
    exit 1
fi

echo "✅ Environment variables set"
echo ""

# ════════════════════════════════════════════════════════════════════
# DEPLOYMENT STATUS
# ════════════════════════════════════════════════════════════════════

echo "📊 DEPLOYMENT STATUS"
echo "===================="
echo ""
echo "✅ ALREADY DEPLOYED (Do not redeploy):"
echo "   • UserVault: 0x65B43c257c885259360b7165C2773e0d53053b68"
echo "   • LendleAdapter: 0xEEE09B03d9260C77404bc51146F7C1d58B439150"
echo "   • FusionXAdapter: 0x2F65BE78959DA2D49f250Cc28E01589490cCd029"
echo ""
echo "🆕 NEED TO DEPLOY:"
echo "   1. StrategyNFT.sol"
echo "   2. AIStrategyValidator.sol"
echo "   3. StrategyExecutor.sol"
echo "   4. AdapterGovernance.sol"
echo "   5. PriceOracle.sol"
echo ""

# ════════════════════════════════════════════════════════════════════
# BUILD STATUS
# ════════════════════════════════════════════════════════════════════

echo "🔨 BUILD STATUS"
echo "==============="
echo ""

# Try to build
if forge build --skip test 2>&1 | grep -q "error"; then
    echo "❌ Build failed - OpenZeppelin dependencies issue"
    echo ""
    echo "📋 SOLUTION:"
    echo "============"
    echo ""
    echo "The contracts require OpenZeppelin but network is unstable."
    echo "Here's a manual deployment approach:"
    echo ""
    echo "STEP 1: Fix dependencies locally"
    echo "  $ git submodule update --init --recursive"
    echo "  $ forge install OpenZeppelin/openzeppelin-contracts"
    echo "  $ forge build"
    echo ""
    echo "STEP 2: Deploy StrategyNFT (once build succeeds)"
    echo "  $ forge script script/DeployStrategyNFT.s.sol \\"
    echo "      --broadcast --rpc-url \$MANTLE_SEPOLIA_RPC"
    echo ""
    echo "STEP 3: Deploy AIValidator"
    echo "  $ forge script script/DeployAIValidator.s.sol \\"
    echo "      --broadcast --rpc-url \$MANTLE_SEPOLIA_RPC"
    echo ""
    echo "STEP 4: Deploy StrategyExecutor"
    echo "  $ forge script script/DeployStrategyExecutor.s.sol \\"
    echo "      --broadcast --rpc-url \$MANTLE_SEPOLIA_RPC"
    echo ""
    echo "STEP 5: Deploy AdapterGovernance"
    echo "  $ forge script script/DeployAdapterGovernance.s.sol \\"
    echo "      --broadcast --rpc-url \$MANTLE_SEPOLIA_RPC"
    echo ""
    echo "STEP 6: Deploy PriceOracle (optional)"
    echo "  $ forge script script/DeployPriceOracle.s.sol \\"
    echo "      --broadcast --rpc-url \$MANTLE_SEPOLIA_RPC"
    echo ""
    exit 1
else
    echo "✅ Build successful!"
    echo ""
    echo "🎯 Ready to deploy. Execute commands:"
    echo ""
    echo "forge script script/DeployStrategyNFT.s.sol \\"
    echo "  --broadcast \\"
    echo "  --rpc-url \$MANTLE_SEPOLIA_RPC \\"
    echo "  --verify"
    echo ""
fi

echo ""
echo "════════════════════════════════════════════════════════════════"
echo "For detailed deployment info, see DEPLOYMENT_STATUS.md"
echo "════════════════════════════════════════════════════════════════"
