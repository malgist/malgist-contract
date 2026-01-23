#!/bin/bash
# Status: ACTIVE
# Usage: ./scripts/helpers/setup-env.sh
# Env: .env (PRIVATE_KEY, MANTLE_SEPOLIA_RPC)
# Notes: Loads env vars, validates key format, and preps DeployUserVault runs.
# Quick environment setup script for Malgist deployment

echo "========================================="
echo "Malgist Environment Setup"
echo "========================================="
echo ""

# Fix line endings if needed
if command -v dos2unix &> /dev/null; then
    echo "[1/4] Fixing line endings..."
    dos2unix .env 2>/dev/null || true
    dos2unix .env.example 2>/dev/null || true
    echo "  ✓ Line endings fixed"
else
    echo "[1/4] Skipping line ending fix (dos2unix not installed)"
fi

echo ""
echo "[2/4] Loading environment variables..."
set -a
source .env
set +a

echo "  ✓ Environment loaded"
echo ""

echo "[3/4] Verifying configuration..."

# Check required variables
REQUIRED_VARS=("PRIVATE_KEY" "MANTLE_SEPOLIA_RPC")
MISSING=()

for var in "${REQUIRED_VARS[@]}"; do
    if [ -z "${!var}" ]; then
        MISSING+=("$var")
    fi
done

if [ ${#MISSING[@]} -gt 0 ]; then
    echo "  ✗ Missing required variables:"
    for var in "${MISSING[@]}"; do
        echo "    - $var"
    done
    echo ""
    echo "Please edit .env and add the missing variables"
    exit 1
fi

echo "  ✓ All required variables present"
echo ""

echo "[4/4] Checking private key format..."

# Check if private key has 0x prefix (it shouldn't)
if [[ $PRIVATE_KEY == 0x* ]]; then
    echo "  ✗ ERROR: Private key has '0x' prefix"
    echo ""
    echo "Please remove '0x' from your PRIVATE_KEY in .env"
    echo "Example: PRIVATE_KEY=abc123... (not 0xabc123...)"
    exit 1
fi

# Check private key length (should be 64 hex characters)
if [ ${#PRIVATE_KEY} -ne 64 ]; then
    echo "  ⚠ WARNING: Private key length is ${#PRIVATE_KEY} (expected 64)"
    echo "  This might cause deployment issues"
fi

echo "  ✓ Private key format looks good"
echo ""

echo "========================================="
echo "Setup Complete!"
echo "========================================="
echo ""
echo "Configuration:"
echo "  RPC: $MANTLE_SEPOLIA_RPC"
echo "  Private Key: ${PRIVATE_KEY:0:10}...${PRIVATE_KEY: -4}"
echo ""
echo "Ready to deploy!"
echo ""
echo "Run: forge script script/DeployUserVault.s.sol \\"
echo "       --rpc-url \$MANTLE_SEPOLIA_RPC \\"
echo "       --private-key \$PRIVATE_KEY \\"
echo "       --broadcast --legacy -vvvv"
echo ""
