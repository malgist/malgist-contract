#!/bin/bash
# Status: ACTIVE
# Usage: ./scripts/helpers/deploy-with-check.sh
# Env: .env (PRIVATE_KEY, MANTLE_SEPOLIA_RPC)
# Notes: Preflight balance checks plus DeployUserVault broadcast.
# Check balance and deploy properly

source .env

echo "========================================="
echo "Pre-Deployment Check"
echo "========================================="
echo ""

DEPLOYER=$(cast wallet address --private-key $PRIVATE_KEY)
echo "Deployer address: $DEPLOYER"
echo ""

echo "Checking balance..."
BALANCE=$(cast balance $DEPLOYER --rpc-url $MANTLE_SEPOLIA_RPC)
echo "Balance: $BALANCE wei"

# Convert to ETH for readability
BALANCE_ETH=$(cast to-unit $BALANCE ether)
echo "Balance: $BALANCE_ETH MNT"
echo ""

# Check if balance is sufficient (need at least 0.01 MNT for deployment)
MIN_BALANCE="10000000000000000"  # 0.01 ETH in wei
if [ "$BALANCE" -lt "$MIN_BALANCE" ]; then
    echo "❌ ERROR: Insufficient balance!"
    echo "You need at least 0.01 testnet MNT"
    echo ""
    echo "Get testnet MNT from: https://faucet.sepolia.mantle.xyz/"
    echo "Your address: $DEPLOYER"
    exit 1
fi

echo "✅ Balance sufficient for deployment"
echo ""

echo "========================================="
echo "Starting Deployment..."
echo "========================================="
echo ""

# Deploy with explicit error handling
forge script script/DeployUserVault.s.sol \
  --rpc-url $MANTLE_SEPOLIA_RPC \
  --private-key $PRIVATE_KEY \
  --broadcast \
  --legacy \
  -vvvv

echo ""
echo "========================================="
echo "Deployment Complete!"
echo "========================================="
echo ""

# Check if deployment succeeded
echo "Verifying deployment..."
USER_VAULT="0x65B43c257c885259360b7165C2773e0d53053b68"
CODE_LENGTH=$(cast code $USER_VAULT --rpc-url $MANTLE_SEPOLIA_RPC | wc -c)

if [ "$CODE_LENGTH" -gt "3" ]; then
    echo "✅ SUCCESS! Contracts are deployed on-chain"
    echo ""
    echo "UserVault: $USER_VAULT"
    echo "Explorer: https://sepolia.mantlescan.xyz/address/$USER_VAULT"
else
    echo "❌ FAILED: Contracts not found on-chain"
    echo "Check the error messages above"
    exit 1
fi
