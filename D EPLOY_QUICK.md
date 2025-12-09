# Quick Deployment Guide - UserVault (Copy-Trading)

## 🚀 Deploy to Mantle Sepolia

### Prerequisites
1. Get testnet MNT from faucet: https://faucet.sepolia.mantle.xyz/
2. Have your private key ready (without `0x` prefix)

### One-Command Deployment

```bash
cd ~/projects/Malgist

# Load environment
source .env

# Deploy everything
forge script script/DeployUserVault.s.sol \
  --rpc-url $MANTLE_SEPOLIA_RPC \
  --private-key $PRIVATE_KEY \
  --broadcast \
  --legacy \
  -vvvv
```

### What Gets Deployed

**Mock Ecosystem:**
- ✅ USDC (mock token)
- ✅ aUSDC (Lendle aToken)
- ✅ WMNT (Wrapped Mantle)
- ✅ Mock Lending Pool (Lendle-style)
- ✅ Mock DEX Router + LP Token (FusionX-style)

**Core Contracts:**
- ✅ UserVault (copy-trading engine)
- ✅ LendleAdapter (lending protocol)
- ✅ FusionXAdapter (DEX zap)

**Bonus:**
- 📦 10,000 test USDC minted to your wallet
- 📦 100 test WMNT minted to your wallet

---

## 📝 After Deployment

### Save Addresses

The script will print JSON at the end - save this for your frontend:

```json
{
  "network": "mantle-sepolia",
  "chainId": 5003,
  "contracts": {
    "usdc": "0x...",
    "userVault": "0x...",
    "lendleAdapter": "0x...",
    "fusionXAdapter": "0x..."
  }
}
```

---

## 🧪 Test Your Deployment

### 1. Create a Strategy

```bash
# Set addresses from deployment
VAULT=0x...  # Your UserVault address
LENDLE=0x... # LendleAdapter address
FUSION=0x... # FusionXAdapter address
USDC=0x...   # USDC address

# Create strategy
cast send $VAULT \
  "setStrategy(address[],uint16[],bool,string,uint16)" \
  "[$LENDLE,$FUSION]" \
  "[5000,5000]" \
  true \
  "My 50/50 Strategy" \
  10 \
  --private-key $PRIVATE_KEY \
  --rpc-url $MANTLE_SEPOLIA_RPC \
  --legacy
```

### 2. Deposit USDC

```bash
# Approve vault
cast send $USDC \
  "approve(address,uint256)" \
  $VAULT \
  1000000000 \
  --private-key $PRIVATE_KEY \
  --rpc-url $MANTLE_SEPOLIA_RPC \
  --legacy

# Deposit 100 USDC
cast send $VAULT \
  "deposit(uint256)" \
  100000000 \
  --private-key $PRIVATE_KEY \
  --rpc-url $MANTLE_SEPOLIA_RPC \
  --legacy
```

### 3. Copy Another Strategy

```bash
# Copy someone's strategy
cast send $VAULT \
  "copyStrategy(address)" \
  0xCREATOR_ADDRESS \
  --private-key $PRIVATE_KEY \
  --rpc-url $MANTLE_SEPOLIA_RPC \
  --legacy
```

### 4. Check Leaderboard

```bash
cast call $VAULT \
  "getLeaderboardByCopies(uint256)" \
  10 \
  --rpc-url $MANTLE_SEPOLIA_RPC
```

---

## 🔍 Verify Contracts

After deployment, verify on Mantle Sepolia explorer:

```bash
# Example for UserVault
forge verify-contract $VAULT \
  src/UserVault.sol:UserVault \
  --chain-id 5003 \
  --rpc-url $MANTLE_SEPOLIA_RPC \
  --constructor-args $(cast abi-encode "constructor(address)" $USDC)
```

---

## 🐛 Troubleshooting

### "Failed to decode private key"
- Remove `0x` prefix from private key in `.env`

### "Insufficient balance"
- Get testnet MNT from faucet first

### "Contract verification failed"
- Mantle Sepolia might not support Foundry verification
- Use manual verification on https://sepolia.mantlescan.xyz/

---

## 📊 Expected Gas Costs

| Operation | Gas | Cost (@ 0.01 Gwei) |
|-----------|-----|-------------------|
| Deploy All | ~5M | ~$0.05 |
| Create Strategy | ~150K | ~$0.0015 |
| Copy Strategy | ~80K | ~$0.0008 |
| Deposit | ~200K | ~$0.002 |

**Total deployment cost:** < $0.10 on Mantle! 🎉

---

## ✅ Success Checklist

After deployment and testing, you should have:

- [ ] All contracts deployed ✅
- [ ] Addresses saved for frontend
- [ ] Created at least one strategy
- [ ] Made a test deposit
- [ ] Tested copy functionality
- [ ] Verified on block explorer (optional)

---

## 🎯 Next Steps

1. **Frontend Integration**
   - Update contract addresses in frontend
   - Test wallet connection
   - Test create/copy flows

2. **Create Example Strategies**
   - Conservative (100% Lendle)
   - Balanced (50/50)
   - Aggressive (80% FusionX)

3. **Demo Preparation**
   - Record screen capture
   - Prepare talking points
   - Test end-to-end flow

---

## 🔗 Helpful Links

- **Faucet:** https://faucet.sepolia.mantle.xyz/
- **Explorer:** https://sepolia.mantlescan.xyz/
- **RPC:** https://rpc.sepolia.mantle.xyz
- **Chain ID:** 5003
- **Docs:** https://docs.mantle.xyz/

---

*Deployment script version: Copy-Trading (No NFT)*  
*Last updated: December 9, 2024*
