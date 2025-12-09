# Quick Manual Verification Commands
# Copy these one-by-one if automated script fails

# IMPORTANT: Load addresses first
source deployments/addresses.env
source .env

# 1. Verify USDC
forge verify-contract $USDC \
  src/mocks/MockERC20.sol:MockERC20 \
  --chain-id 5003 \
  --rpc-url $MANTLE_SEPOLIA_RPC \
  --constructor-args $(cast abi-encode "constructor(string,string,uint8)" "USD Coin" "USDC" 6) \
  --watch

# 2. Verify WMNT  
forge verify-contract $WMNT \
  src/mocks/MockERC20.sol:MockERC20 \
  --chain-id 5003 \
  --rpc-url $MANTLE_SEPOLIA_RPC \
  --constructor-args $(cast abi-encode "constructor(string,string,uint8)" "Wrapped Mantle" "WMNT" 18) \
  --watch

# 3. Verify MockLendingPool
forge verify-contract $LENDING_POOL \
  src/mocks/MockLendingPool.sol:MockLendingPool \
  --chain-id 5003 \
  --rpc-url $MANTLE_SEPOLIA_RPC \
  --watch

# 4. Verify DEX Router
forge verify-contract $DEX_ROUTER \
  src/mocks/MockUniswapV2Router.sol:MockUniswapV2Router \
  --chain-id 5003 \
  --rpc-url $MANTLE_SEPOLIA_RPC \
  --watch

# 5. Verify LP Token
forge verify-contract $LP_TOKEN \
  src/mocks/MockUniswapV2Pair.sol:MockUniswapV2Pair \
  --chain-id 5003 \
  --rpc-url $MANTLE_SEPOLIA_RPC \
  --constructor-args $(cast abi-encode "constructor(address,address,string,string)" $USDC $WMNT "FusionX USDC-WMNT LP" "FUSION-LP") \
  --watch

# 6. ⭐ Verify UserVault (MOST IMPORTANT!)
forge verify-contract $USER_VAULT \
  src/UserVault.sol:UserVault \
  --chain-id 5003 \
  --rpc-url $MANTLE_SEPOLIA_RPC \
  --constructor-args $(cast abi-encode "constructor(address)" $USDC) \
  --watch

# 7. Verify LendleAdapter
forge verify-contract $LENDLE_ADAPTER \
  src/adapters/LendleAdapter.sol:LendleAdapter \
  --chain-id 5003 \
  --rpc-url $MANTLE_SEPOLIA_RPC \
  --constructor-args $(cast abi-encode "constructor(address,address,address)" $USDC $LENDING_POOL $USER_VAULT) \
  --watch

# 8. Verify FusionXAdapter
forge verify-contract $FUSIONX_ADAPTER \
  src/adapters/FusionXAdapter.sol:FusionXAdapter \
  --chain-id 5003 \
  --rpc-url $MANTLE_SEPOLIA_RPC \
  --constructor-args $(cast abi-encode "constructor(address,address,address,address,address)" $USDC $WMNT $LP_TOKEN $DEX_ROUTER $USER_VAULT) \
  --watch

echo "Done! Check explorer: https://sepolia.mantlescan.xyz/address/$USER_VAULT"
