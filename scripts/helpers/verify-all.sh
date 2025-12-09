#!/bin/bash
# Quick verification script for deployed Malgist contracts on Mantle Sepolia

# Load deployed addresses
source deployments/addresses.env
source .env

echo "========================================="
echo "Verifying Malgist Contracts"
echo "========================================="
echo ""

# Function to verify a contract
verify_contract() {
    local name=$1
    local address=$2
    local contract_path=$3
    local constructor_args=$4
    
    echo "[$name] Verifying..."
    
    if [ -z "$constructor_args" ]; then
        forge verify-contract $address \
            $contract_path \
            --chain-id 5003 \
            --rpc-url $MANTLE_SEPOLIA_RPC \
            --watch || echo "  ⚠ Verification failed (may need manual verification)"
    else
        forge verify-contract $address \
            $contract_path \
            --chain-id 5003 \
            --rpc-url $MANTLE_SEPOLIA_RPC \
            --constructor-args "$constructor_args" \
            --watch || echo "  ⚠ Verification failed (may need manual verification)"
    fi
    
    echo ""
}

# Verify MockERC20 tokens
verify_contract "USDC" $USDC \
    "src/mocks/MockERC20.sol:MockERC20" \
    "$(cast abi-encode 'constructor(string,string,uint8)' 'USD Coin' 'USDC' 6)"

verify_contract "WMNT" $WMNT \
    "src/mocks/MockERC20.sol:MockERC20" \
    "$(cast abi-encode 'constructor(string,string,uint8)' 'Wrapped Mantle' 'WMNT' 18)"

# Verify MockLendingPool
verify_contract "LendingPool" $LENDING_POOL \
    "src/mocks/MockLendingPool.sol:MockLendingPool" \
    ""

# Verify MockUniswapV2Router
verify_contract "DEX Router" $DEX_ROUTER \
    "src/mocks/MockUniswapV2Router.sol:MockUniswapV2Router" \
    ""

# Verify LP Token
verify_contract "LP Token" $LP_TOKEN \
    "src/mocks/MockUniswapV2Pair.sol:MockUniswapV2Pair" \
    "$(cast abi-encode 'constructor(address,address,string,string)' $USDC $WMNT 'FusionX USDC-WMNT LP' 'FUSION-LP')"

# Verify UserVault (MOST IMPORTANT!)
echo "⭐ Verifying UserVault (Main Contract)..."
verify_contract "UserVault" $USER_VAULT \
    "src/UserVault.sol:UserVault" \
    "$(cast abi-encode 'constructor(address)' $USDC)"

# Verify Adapters
verify_contract "LendleAdapter" $LENDLE_ADAPTER \
    "src/adapters/LendleAdapter.sol:LendleAdapter" \
    "$(cast abi-encode 'constructor(address,address,address)' $USDC $LENDING_POOL $USER_VAULT)"

verify_contract "FusionXAdapter" $FUSIONX_ADAPTER \
    "src/adapters/FusionXAdapter.sol:FusionXAdapter" \
    "$(cast abi-encode 'constructor(address,address,address,address,address)' $USDC $WMNT $LP_TOKEN $DEX_ROUTER $USER_VAULT)"

echo "========================================="
echo "Verification Complete!"
echo "========================================="
echo ""
echo "Check contracts on explorer:"
echo "https://sepolia.mantlescan.xyz/address/$USER_VAULT"
echo ""
