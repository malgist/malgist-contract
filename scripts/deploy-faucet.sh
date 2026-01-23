#!/bin/bash
# Status: ACTIVE
# Usage: ./scripts/deploy-faucet.sh
# Env: PRIVATE_KEY, RPC_URL
# Notes: Deploys MockUSDC + Faucet to Mantle testnet and records addresses.

##############################################################################
# MALGIST Faucet Deployment Script
# 
# Deploys MockUSDC and Faucet contracts to Mantle testnet (chain ID 5003)
# 
# Requirements:
# - forge installed
# - RPC_URL set to Mantle testnet
# - PRIVATE_KEY set to deployment account
# 
# Usage:
#   ./scripts/deploy-faucet.sh
##############################################################################

set -e

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== MALGIST Faucet Deployment ===${NC}"
echo ""

# Verify environment
if [ -z "$PRIVATE_KEY" ]; then
    echo -e "${YELLOW}⚠️  PRIVATE_KEY not set. Using default test key.${NC}"
    PRIVATE_KEY="0xac0974bec39a17e36ba4a6b4d238ff944bacb476c6b8d6c1f02960247590993f"
fi

if [ -z "$RPC_URL" ]; then
    echo -e "${YELLOW}⚠️  RPC_URL not set. Using Mantle testnet.${NC}"
    RPC_URL="https://rpc.sepolia.mantle.xyz"
fi

echo -e "${BLUE}Configuration:${NC}"
echo "  RPC URL: $RPC_URL"
echo "  Private Key: ${PRIVATE_KEY:0:10}..."
echo ""

# ============================================================================
# Step 1: Deploy MockUSDC
# ============================================================================

echo -e "${BLUE}Step 1: Deploying MockUSDC...${NC}"

USDC_OUTPUT=$(forge create src/mocks/MockUSDC.sol:MockUSDC \
  --rpc-url "$RPC_URL" \
  --private-key "$PRIVATE_KEY" \
  --verify \
  2>&1)

USDC_ADDRESS=$(echo "$USDC_OUTPUT" | grep "Deployed to:" | awk '{print $NF}')

if [ -z "$USDC_ADDRESS" ]; then
    echo -e "${YELLOW}Failed to extract USDC address. Full output:${NC}"
    echo "$USDC_OUTPUT"
    exit 1
fi

echo -e "${GREEN}✓ MockUSDC deployed to: $USDC_ADDRESS${NC}"
echo ""

# ============================================================================
# Step 2: Deploy Faucet
# ============================================================================

echo -e "${BLUE}Step 2: Deploying Faucet...${NC}"

FAUCET_OUTPUT=$(forge create src/Faucet.sol:Faucet \
  --constructor-args "$USDC_ADDRESS" \
  --rpc-url "$RPC_URL" \
  --private-key "$PRIVATE_KEY" \
  --verify \
  2>&1)

FAUCET_ADDRESS=$(echo "$FAUCET_OUTPUT" | grep "Deployed to:" | awk '{print $NF}')

if [ -z "$FAUCET_ADDRESS" ]; then
    echo -e "${YELLOW}Failed to extract Faucet address. Full output:${NC}"
    echo "$FAUCET_OUTPUT"
    exit 1
fi

echo -e "${GREEN}✓ Faucet deployed to: $FAUCET_ADDRESS${NC}"
echo ""

# ============================================================================
# Step 3: Add Faucet as minter (requires second transaction)
# ============================================================================

echo -e "${BLUE}Step 3: Adding Faucet as minter...${NC}"

# Note: In real deployment, would use cast to call addMinter
# For now, document the transaction
cat > /tmp/add_minter.txt <<EOF
# To add faucet as minter, run:
cast send "$USDC_ADDRESS" "addMinter(address)" "$FAUCET_ADDRESS" \
  --rpc-url "$RPC_URL" \
  --private-key "$PRIVATE_KEY"
EOF

echo "  Save and run: $(cat /tmp/add_minter.txt | tail -1)"
echo ""

# ============================================================================
# Step 4: Seed Faucet with tokens (requires second transaction)
# ============================================================================

echo -e "${BLUE}Step 4: Seeding faucet with 1M USDC...${NC}"

cat > /tmp/seed_faucet.txt <<EOF
# To seed faucet with tokens, run:
cast send "$USDC_ADDRESS" "mint(address,uint256)" "$FAUCET_ADDRESS" "1000000000000" \
  --rpc-url "$RPC_URL" \
  --private-key "$PRIVATE_KEY"

# Note: 1000000000000 = 1M USDC (with 6 decimals: 1000000 * 1e6)
EOF

echo "  $(cat /tmp/seed_faucet.txt | tail -3 | head -1)"
echo ""

# ============================================================================
# Step 5: Save deployment info
# ============================================================================

echo -e "${BLUE}Step 5: Saving deployment info...${NC}"

DEPLOYMENT_FILE="deployments/faucet-$(date +%s).txt"

mkdir -p deployments

cat > "$DEPLOYMENT_FILE" <<EOF
# MALGIST Faucet Deployment
# Generated: $(date)

## Network
Chain ID: 5003 (Mantle Testnet)
RPC URL: $RPC_URL

## Deployed Contracts
MockUSDC Address: $USDC_ADDRESS
Faucet Address: $FAUCET_ADDRESS

## Configuration
Default Claim Amount: 1000e6 (1000 USDC)
Default Cooldown: 24 hours (86400 seconds)
Max Claim Amount: 10000e6 (10000 USDC)
Testnet Chain ID: 5003

## Next Steps
1. Add Faucet as minter:
   cast send "$USDC_ADDRESS" "addMinter(address)" "$FAUCET_ADDRESS" \
     --rpc-url "$RPC_URL" \
     --private-key $PRIVATE_KEY

2. Seed Faucet with initial USDC:
   cast send "$USDC_ADDRESS" "mint(address,uint256)" "$FAUCET_ADDRESS" "1000000000000" \
     --rpc-url "$RPC_URL" \
     --private-key $PRIVATE_KEY

3. Verify Faucet state:
   cast call "$FAUCET_ADDRESS" "getFaucetState()(uint256,uint256,uint256)" \
     --rpc-url "$RPC_URL"

4. Test claim (replace USER_ADDRESS):
   cast send "$FAUCET_ADDRESS" "claim()" \
     --rpc-url "$RPC_URL" \
     --private-key $PRIVATE_KEY

## Verification
View on Explorer: 
  MockUSDC: https://explorer.sepolia.mantle.xyz/address/$USDC_ADDRESS
  Faucet: https://explorer.sepolia.mantle.xyz/address/$FAUCET_ADDRESS
EOF

echo "  Saved to: $DEPLOYMENT_FILE"
echo ""

# ============================================================================
# Summary
# ============================================================================

echo -e "${GREEN}=== Deployment Summary ===${NC}"
echo ""
echo "MockUSDC:  $USDC_ADDRESS"
echo "Faucet:    $FAUCET_ADDRESS"
echo ""
echo -e "${YELLOW}⚠️  IMPORTANT: Complete these manual steps:${NC}"
echo ""
echo "1. Add Faucet as minter:"
echo "   cast send $USDC_ADDRESS \"addMinter(address)\" $FAUCET_ADDRESS \\"
echo "     --rpc-url \"$RPC_URL\" \\"
echo "     --private-key \$PRIVATE_KEY"
echo ""
echo "2. Seed Faucet with tokens:"
echo "   cast send $USDC_ADDRESS \"mint(address,uint256)\" $FAUCET_ADDRESS \"1000000000000\" \\"
echo "     --rpc-url \"$RPC_URL\" \\"
echo "     --private-key \$PRIVATE_KEY"
echo ""
echo "3. Verify setup:"
echo "   cast call $FAUCET_ADDRESS \"getFaucetState()(uint256,uint256,uint256)\" \\"
echo "     --rpc-url \"$RPC_URL\""
echo ""
echo -e "${GREEN}✓ Deployment script completed${NC}"
