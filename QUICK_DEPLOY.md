# Quick Deploy to Mantle Sepolia

## 🚀 Quick Start (Mantle Sepolia)

### 1. Get Testnet MNT
Visit: https://faucet.sepolia.mantle.xyz/
- Connect your wallet
- Request testnet MNT tokens

### 2. Setup Environment

```bash
cd ~/projects/Malgist
nano .env
```

Add:
```bash
PRIVATE_KEY=your_private_key_here
MANTLE_SEPOLIA_RPC=https://rpc.sepolia.mantle.xyz
```

### 3. Deploy Everything

```bash
source .env

forge script script/Deploy.s.sol \
  --rpc-url $MANTLE_SEPOLIA_RPC \
  --private-key $PRIVATE_KEY \
  --broadcast \
  -vvvv
```

That's it! The script will deploy:
- ✅ Mock USDC, aUSDC, WMNT tokens
- ✅ Mock Lending Pool (Lendle-style)
- ✅ Mock DEX Router (FusionX-style)
- ✅ StrategyNFT + UniversalVault
- ✅ LendleAdapter + FusionXAdapter
- ✅ 10,000 test USDC to your wallet

## 📝 After Deployment

Save all the contract addresses printed at the end!

## 🧪 Test Your Deployment

### Mint a Strategy
```bash
# Replace with your actual addresses
STRATEGY_NFT=0x...
LENDLE_ADAPTER=0x...
FUSIONX_ADAPTER=0x...

cast send $STRATEGY_NFT \
  "mintStrategy(string,address[],uint16[],uint16)" \
  "50/50 Lendle+FusionX" \
  "[$LENDLE_ADAPTER,$FUSIONX_ADAPTER]" \
  "[5000,5000]" \
  100 \
  --private-key $PRIVATE_KEY \
  --rpc-url $MANTLE_SEPOLIA_RPC
```

### Make a Deposit
```bash
VAULT=0x...
USDC=0x...
STRATEGY_ID=0  # First strategy minted

# Approve vault
cast send $USDC \
  "approve(address,uint256)" \
  $VAULT \
  1000000000 \
  --private-key $PRIVATE_KEY \
  --rpc-url $MANTLE_SEPOLIA_RPC

# Deposit 100 USDC
cast send $VAULT \
  "deposit(uint256,uint256)" \
  $STRATEGY_ID \
  100000000 \
  --private-key $PRIVATE_KEY \
  --rpc-url $MANTLE_SEPOLIA_RPC
```

## 🔗 Mantle Sepolia Links

- **Faucet:** https://faucet.sepolia.mantle.xyz/
- **Explorer:** https://sepolia.mantlescan.xyz/
- **RPC:** https://rpc.sepolia.mantle.xyz
- **Chain ID:** 5003

## 💡 Why Deploy Mocks?

We're deploying **mock protocols** (not real Lendle/FusionX) because:
1. ✅ Full control - you own all contracts
2. ✅ No dependencies - works even if real protocols aren't on testnet
3. ✅ Perfect for demos and testing
4. ✅ Can mint unlimited test tokens

For production mainnet, you would integrate with real protocols!
