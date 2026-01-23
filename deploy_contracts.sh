#!/bin/bash

# Load from .env
set -a
[ -f .env ] && source .env
set +a

export MANTLE_SEPOLIA_RPC="${MANTLE_SEPOLIA_RPC:-https://mantle-sepolia.g.alchemy.com/v2/hWStvrZu_Sw31tO2Hpjzv}"

echo "🚀 DEPLOYMENT SUMMARY FOR 5 NEW CONTRACTS"
echo "=========================================="
echo ""
echo "Network: Mantle Sepolia (5003)"
echo "RPC: $MANTLE_SEPOLIA_RPC"
echo "Wallet: ${OWNER:0:10}...${OWNER: -8}"
echo ""

echo "📋 CONTRACTS TO DEPLOY"
echo "====================="
echo ""
echo "1️⃣  StrategyNFT.sol"
echo "   - ERC721 for strategy ownership"
echo "   - Immutable strategy data on-chain"
echo "   - Creator fee collection"
echo ""
echo "2️⃣  AIStrategyValidator.sol"
echo "   - 12-point zero-trust validation"
echo "   - AI output verification"
echo "   - Adapter whitelist enforcement"
echo ""
echo "3️⃣  StrategyExecutor.sol"
echo "   - Dynamic adapter routing"
echo "   - Multi-protocol transaction execution"
echo "   - Calldata encoding/decoding"
echo ""
echo "4️⃣  AdapterGovernance.sol"
echo "   - Timelock-protected adapter whitelist"
echo "   - 2-day approval window"
echo "   - Staged rollout system"
echo ""
echo "5️⃣  PriceOracle.sol"
echo "   - Chainlink/Pyth integration"
echo "   - Slippage protection"
echo "   - Price feed aggregation"
echo ""

echo "📊 DEPLOYMENT STATUS"
echo "===================="
echo ""

# Check if contracts can build
if forge build --skip test 2>&1 | grep -q "error\|Error"; then
    BUILD_STATUS="❌ FAILED - Dependencies missing"
else
    BUILD_STATUS="✅ PASSED"
fi

echo "Build Status: $BUILD_STATUS"
echo ""

if [[ "$BUILD_STATUS" == *"FAILED"* ]]; then
    echo "⚠️  CURRENT ISSUE: OpenZeppelin submodule not fully downloaded"
    echo ""
    echo "🔧 QUICK FIX:"
    echo "1. Manually init submodules:"
    echo "   $ git submodule update --init --recursive --force"
    echo ""
    echo "2. Once fixed, run deployment:"
    echo "   $ export PRIVATE_KEY=$(cat .env | grep PRIVATE_KEY | cut -d'=' -f2)"
    echo "   $ forge script script/DeployStrategyNFT.s.sol \\"
    echo "       --broadcast --rpc-url \$MANTLE_SEPOLIA_RPC --verify"
    echo ""
    exit 1
fi

echo "✅ All checks passed!"
echo ""
echo "🚀 NEXT STEP: Deploy to Mantle Sepolia"
echo "======================================"
echo ""
echo "Execute these commands in order:"
echo ""
echo "# Deploy 1: StrategyNFT (core dependency)"
echo "forge script script/DeployStrategyNFT.s.sol \\"
echo "  --broadcast --rpc-url \$MANTLE_SEPOLIA_RPC"
echo ""
echo "# Deploy 2: AIValidator (used by StrategyNFT)"
echo "forge script script/DeployAIValidator.s.sol \\"
echo "  --broadcast --rpc-url \$MANTLE_SEPOLIA_RPC"
echo ""
echo "# Deploy 3: StrategyExecutor"
echo "forge script script/DeployStrategyExecutor.s.sol \\"
echo "  --broadcast --rpc-url \$MANTLE_SEPOLIA_RPC"
echo ""
echo "# Deploy 4: AdapterGovernance"
echo "forge script script/DeployAdapterGovernance.s.sol \\"
echo "  --broadcast --rpc-url \$MANTLE_SEPOLIA_RPC"
echo ""
echo "# Deploy 5: PriceOracle (optional)"
echo "forge script script/DeployPriceOracle.s.sol \\"
echo "  --broadcast --rpc-url \$MANTLE_SEPOLIA_RPC"
echo ""
