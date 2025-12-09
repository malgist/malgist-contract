#!/bin/bash

# Mantle Sepolia Contract Verification Script
# This script verifies all deployed contracts on Mantle Sepolia explorer

set -e  # Exit on error

source .env

echo "=== VERIFYING CONTRACTS ON MANTLE SEPOLIA ==="
echo ""

# You need to update these addresses from your deployment output
# Check: broadcast/Deploy.s.sol/5003/run-latest.json

# TODO: Replace these with your actual deployed addresses
USDC_ADDRESS="0x7d7685d22456984081c067a5504d3928172d0806"
AUSDC_ADDRESS="0x8b4d35388fbd6efd44bf1dbb6f8376faf68e4b8f"
MNT_ADDRESS="0x4e526bd39ac79fe5e6011bcc78f42f74984a4dd6"
LP_TOKEN_ADDRESS="0x86e03f1fd60083f0c20a3126d1e20f47ae1e371e"
LENDING_POOL_ADDRESS="0x..."
DEX_ROUTER_ADDRESS="0x..."
STRATEGY_NFT_ADDRESS="0x..."
VAULT_ADDRESS="0x..."
LENDLE_ADAPTER_ADDRESS="0x..."
FUSIONX_ADAPTER_ADDRESS="0x..."

# Mantle Sepolia doesn't have Etherscan, so we'll use a different approach
# You can verify manually on https://sepolia.mantlescan.xyz/

echo "Manual Verification Instructions:"
echo ""
echo "Visit: https://sepolia.mantlescan.xyz/"
echo ""
echo "For each contract:"
echo "1. Go to the contract address"
echo "2. Click 'Contract' tab"
echo "3. Click 'Verify and Publish'"
echo "4. Select:"
echo "   - Compiler: v0.8.30"
echo "   - Optimization: Yes (200 runs)"
echo "   - License: MIT"
echo ""

# Alternative: Use Foundry's verify command if Mantle supports it
echo "Attempting automated verification..."
echo ""

# 1. MockERC20 (USDC)
echo "1. Verifying MockERC20 (USDC)..."
forge verify-contract $USDC_ADDRESS \
  src/mocks/MockERC20.sol:MockERC20 \
  --chain 5003 \
  --constructor-args $(cast abi-encode "constructor(string,string,uint8)" "USD Coin" "USDC" 6) \
  --watch || echo "  → Verification failed or already verified"

# 2. MockERC20 (aUSDC)
echo "2. Verifying MockERC20 (aUSDC)..."
forge verify-contract $AUSDC_ADDRESS \
  src/mocks/MockERC20.sol:MockERC20 \
  --chain 5003 \
  --constructor-args $(cast abi-encode "constructor(string,string,uint8)" "Aave USDC" "aUSDC" 6) \
  --watch || echo "  → Verification failed or already verified"

# 3. MockERC20 (WMNT)
echo "3. Verifying MockERC20 (WMNT)..."
forge verify-contract $MNT_ADDRESS \
  src/mocks/MockERC20.sol:MockERC20 \
  --chain 5003 \
  --constructor-args $(cast abi-encode "constructor(string,string,uint8)" "Wrapped Mantle" "WMNT" 18) \
  --watch || echo "  → Verification failed or already verified"

# 4. MockLendingPool
echo "4. Verifying MockLendingPool..."
forge verify-contract $LENDING_POOL_ADDRESS \
  src/mocks/MockLendingPool.sol:MockLendingPool \
  --chain 5003 \
  --watch || echo "  → Verification failed or already verified"

# 5. MockUniswapV2Pair
echo "5. Verifying MockUniswapV2Pair..."
forge verify-contract $LP_TOKEN_ADDRESS \
  src/mocks/MockUniswapV2Pair.sol:MockUniswapV2Pair \
  --chain 5003 \
  --constructor-args $(cast abi-encode "constructor(address,address,string,string)" $USDC_ADDRESS $MNT_ADDRESS "FusionX USDC-WMNT LP" "FUSION-LP") \
  --watch || echo "  → Verification failed or already verified"

# 6. MockUniswapV2Router
echo "6. Verifying MockUniswapV2Router..."
forge verify-contract $DEX_ROUTER_ADDRESS \
  src/mocks/MockUniswapV2Router.sol:MockUniswapV2Router \
  --chain 5003 \
  --watch || echo "  → Verification failed or already verified"

# 7. StrategyNFT
echo "7. Verifying StrategyNFT..."
forge verify-contract $STRATEGY_NFT_ADDRESS \
  src/StrategyNFT.sol:StrategyNFT \
  --chain 5003 \
  --watch || echo "  → Verification failed or already verified"

# 8. UniversalVault
echo "8. Verifying UniversalVault..."
forge verify-contract $VAULT_ADDRESS \
  src/UniversalVault.sol:UniversalVault \
  --chain 5003 \
  --constructor-args $(cast abi-encode "constructor(address,address)" $USDC_ADDRESS $STRATEGY_NFT_ADDRESS) \
  --watch || echo "  → Verification failed or already verified"

# 9. LendleAdapter
echo "9. Verifying LendleAdapter..."
forge verify-contract $LENDLE_ADAPTER_ADDRESS \
  src/adapters/LendleAdapter.sol:LendleAdapter \
  --chain 5003 \
  --constructor-args $(cast abi-encode "constructor(address,address,address)" $USDC_ADDRESS $LENDING_POOL_ADDRESS $VAULT_ADDRESS) \
  --watch || echo "  → Verification failed or already verified"

# 10. FusionXAdapter
echo "10. Verifying FusionXAdapter..."
forge verify-contract $FUSIONX_ADAPTER_ADDRESS \
  src/adapters/FusionXAdapter.sol:FusionXAdapter \
  --chain 5003 \
  --constructor-args $(cast abi-encode "constructor(address,address,address,address,address)" $USDC_ADDRESS $MNT_ADDRESS $LP_TOKEN_ADDRESS $DEX_ROUTER_ADDRESS $VAULT_ADDRESS) \
  --watch || echo "  → Verification failed or already verified"

echo ""
echo "=== VERIFICATION COMPLETE ==="
echo ""
echo "Check status at: https://sepolia.mantlescan.xyz/"
