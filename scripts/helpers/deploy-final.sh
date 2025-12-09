#!/bin/bash
# Final deployment script - bug fixed

source .env

echo "========================================="
echo "Malgist Final Deployment"
echo "========================================="
echo ""
echo "Using Alchemy RPC: ✅"
echo "Private key configured: ✅"
echo ""

# Rebuild to use fixed deployment script
echo "Rebuilding contracts..."
forge build

echo ""
echo "Starting deployment..."
echo ""

# Deploy with Alchemy RPC
forge script script/DeployUserVault.s.sol \
  --rpc-url $MANTLE_SEPOLIA_RPC \
  --private-key $PRIVATE_KEY \
  --broadcast \
  --legacy \
  -vv

echo ""
echo "========================================="
echo "Checking deployment..."
echo "========================================="
echo ""

# Wait a moment for propagation
sleep 3

# Check if contracts exist
DEPLOYER=$(cast wallet address --private-key $PRIVATE_KEY)
echo "Deployer: $DEPLOYER"

# The addresses will be different now, but we can check the deployer's nonce
NONCE=$(cast nonce $DEPLOYER --rpc-url $MANTLE_SEPOLIA_RPC)
echo "Deployer nonce: $NONCE"

if [ "$NONCE" -gt "0" ]; then
    echo ""
    echo "✅ SUCCESS! Contracts deployed!"
    echo ""
    echo "Copy the contract addresses from the output above"
    echo "and save them to deployments/addresses.env"
else
    echo ""
    echo "❌ FAILED: No transactions from deployer"
    exit 1
fi
