#!/bin/bash
# Status: ACTIVE
# Usage: ./scripts/helpers/deploy-retry-rpc.sh
# Env: .env (PRIVATE_KEY)
# Notes: Retries DeployUserVault across fallback Mantle RPC endpoints.
# Retry deployment with different RPC endpoints

source .env

echo "========================================="
echo "RPC Retry Script"
echo "========================================="
echo ""

# Array of RPC endpoints to try
RPC_ENDPOINTS=(
    "https://rpc.sepolia.mantle.xyz"
    "https://mantle-sepolia.public.blastapi.io"
    "https://rpc.ankr.com/mantle_sepolia"
)

DEPLOYER=$(cast wallet address --private-key $PRIVATE_KEY)

for RPC in "${RPC_ENDPOINTS[@]}"; do
    echo "Trying RPC: $RPC"
    echo ""
    
    # Test RPC connectivity
    echo "Testing connectivity..."
    BALANCE=$(cast balance $DEPLOYER --rpc-url $RPC 2>&1)
    
    if [ $? -eq 0 ]; then
        echo "✅ RPC working! Balance: $(cast to-unit $BALANCE ether) MNT"
        echo ""
        echo "Deploying with this RPC..."
        
        forge script script/DeployUserVault.s.sol \
            --rpc-url $RPC \
            --private-key $PRIVATE_KEY \
            --broadcast \
            --legacy \
            --slow \
            -vv
        
        if [ $? -eq 0 ]; then
            echo ""
            echo "✅ DEPLOYMENT SUCCESSFUL!"
            echo "RPC used: $RPC"
            echo ""
            echo "Update your .env with:"
            echo "MANTLE_SEPOLIA_RPC=$RPC"
            exit 0
        else
            echo "❌ Deployment failed with this RPC, trying next..."
            echo ""
        fi
    else
        echo "❌ RPC not responding, trying next..."
        echo ""
    fi
done

echo "========================================="
echo "All RPCs failed"
echo "========================================="
echo ""
echo "Possible solutions:"
echo "1. Wait a few minutes and try again"
echo "2. Check https://status.mantle.xyz/ for network status"
echo "3. Try deploying during off-peak hours"
exit 1
