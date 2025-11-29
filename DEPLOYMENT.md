# Deployment Guide - Mantle Testnet

This guide will walk you through deploying the Mantle Strategy Studio contracts to Mantle Testnet.

## Prerequisites

1. **Foundry installed** (you already have this)
2. **Testnet MNT tokens** for gas
3. **Private key** for deployment
4. **RPC URL** for Mantle Testnet

---

## Step 1: Get Testnet MNT

### Option A: Mantle Testnet Faucet
1. Visit: https://faucet.testnet.mantle.xyz/
2. Connect your wallet
3. Request testnet MNT tokens
4. Wait for confirmation

### Option B: Mantle Bridge (if available)
- Use the official Mantle bridge for testnet tokens

---

## Step 2: Setup Environment Variables

Create a `.env` file in the project root:

```bash
cd ~/projects/Malgist
nano .env
```

Add the following:

```bash
# Your deployer private key (WITHOUT 0x prefix)
PRIVATE_KEY=your_private_key_here

# Mantle Testnet RPC URL
MANTLE_TESTNET_RPC=https://rpc.testnet.mantle.xyz

# Mantle Testnet Chain ID
MANTLE_TESTNET_CHAIN_ID=5003

# Etherscan API Key for verification (optional)
ETHERSCAN_API_KEY=your_api_key_here

# Block explorer URL
MANTLE_EXPLORER=https://explorer.testnet.mantle.xyz
```

**⚠️ Security Warning:**
- Never commit `.env` to git
- Add `.env` to `.gitignore`

```bash
echo ".env" >> .gitignore
```

---

## Step 3: Update Protocol Addresses

Before deploying, update `script/Deploy.s.sol` with actual protocol addresses:

```solidity
// Update these addresses:
address constant USDC_TESTNET = 0x...; // Get from Mantle testnet docs
address constant LENDLE_POOL = 0x...; // Lendle lending pool
address constant FUSIONX_ROUTER = 0x...; // FusionX router
address constant FUSIONX_USDC_MNT_PAIR = 0x...; // USDC/MNT pair
```

**Where to find addresses:**
- **Mantle Testnet Docs:** https://docs.mantle.xyz/
- **Lendle Docs:** https://docs.lendle.xyz/ (if available on testnet)
- **FusionX Docs:** Check FusionX documentation for testnet deployments

---

## Step 4: Load Environment Variables

```bash
source .env
```

Or export them manually:

```bash
export PRIVATE_KEY=your_private_key
export MANTLE_TESTNET_RPC=https://rpc.testnet.mantle.xyz
```

---

## Step 5: Dry Run (Simulation)

Test the deployment without broadcasting:

```bash
forge script script/Deploy.s.sol \
  --rpc-url $MANTLE_TESTNET_RPC \
  --private-key $PRIVATE_KEY
```

This will simulate the deployment and show you what will be deployed.

---

## Step 6: Deploy Contracts

### Deploy with Verification

```bash
forge script script/Deploy.s.sol \
  --rpc-url $MANTLE_TESTNET_RPC \
  --private-key $PRIVATE_KEY \
  --broadcast \
  --verify \
  -vvvv
```

### Deploy without Verification (faster)

```bash
forge script script/Deploy.s.sol \
  --rpc-url $MANTLE_TESTNET_RPC \
  --private-key $PRIVATE_KEY \
  --broadcast \
  -vvvv
```

**Flags explained:**
- `--broadcast`: Actually send the transactions
- `--verify`: Verify contracts on block explorer
- `-vvvv`: Maximum verbosity for debugging

---

## Step 7: Save Deployment Addresses

After deployment, you'll see output like:

```
=== DEPLOYMENT COMPLETE ===
StrategyNFT: 0x1234...
UniversalVault: 0x5678...
LendleAdapter: 0x9abc...
FusionXAdapter: 0xdef0...
```

**Save these addresses!** You'll need them for:
1. Frontend integration
2. Verification
3. Interacting with contracts

Create a file to track deployments:

```bash
cat > deployments/mantle-testnet.json << EOF
{
  "chainId": 5003,
  "network": "mantle-testnet",
  "contracts": {
    "StrategyNFT": "0x...",
    "UniversalVault": "0x...",
    "LendleAdapter": "0x...",
    "FusionXAdapter": "0x..."
  },
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
```

---

## Step 8: Verify Contracts (Manual)

If auto-verification failed, verify manually:

```bash
forge verify-contract \
  --chain-id 5003 \
  --compiler-version v0.8.30 \
  <CONTRACT_ADDRESS> \
  src/StrategyNFT.sol:StrategyNFT \
  --etherscan-api-key $ETHERSCAN_API_KEY
```

Repeat for each contract.

---

## Step 9: Test Deployment

### Using Cast (Foundry CLI)

```bash
# Check StrategyNFT owner
cast call <STRATEGY_NFT_ADDRESS> "owner()" --rpc-url $MANTLE_TESTNET_RPC

# Check Vault asset
cast call <VAULT_ADDRESS> "ASSET()" --rpc-url $MANTLE_TESTNET_RPC

# Mint a test strategy (requires adapters deployed)
cast send <STRATEGY_NFT_ADDRESS> \
  "mintStrategy(string,address[],uint16[],uint16)" \
  "Test Strategy" \
  "[<ADAPTER1>,<ADAPTER2>]" \
  "[5000,5000]" \
  100 \
  --private-key $PRIVATE_KEY \
  --rpc-url $MANTLE_TESTNET_RPC
```

---

## Troubleshooting

### Error: "Insufficient funds"
- Make sure you have enough testnet MNT
- Check your balance: `cast balance <YOUR_ADDRESS> --rpc-url $MANTLE_TESTNET_RPC`

### Error: "Nonce too low"
- Reset your nonce or wait for pending transactions

### Error: "Contract verification failed"
- Verify manually using the command in Step 8
- Check that compiler version matches (0.8.30)

### Error: "RPC request failed"
- Try alternative RPC: `https://rpc.testnet.mantle.xyz`
- Check if testnet is operational

---

## Alternative: Deploy with Hardhat (Optional)

If you prefer Hardhat:

1. Install Hardhat:
```bash
npm install --save-dev hardhat @nomicfoundation/hardhat-foundry
```

2. Create `hardhat.config.js`:
```javascript
require("@nomicfoundation/hardhat-foundry");

module.exports = {
  solidity: "0.8.30",
  networks: {
    mantleTestnet: {
      url: process.env.MANTLE_TESTNET_RPC,
      accounts: [process.env.PRIVATE_KEY],
      chainId: 5003,
    }
  }
};
```

3. Deploy:
```bash
npx hardhat run script/deploy.js --network mantleTestnet
```

---

## Next Steps After Deployment

1. **Update Frontend**: Add contract addresses to `lib/contracts/index.ts`
2. **Create Initial Strategies**: Mint a few example strategies
3. **Test with Small Amounts**: Do a test deposit/withdrawal
4. **Monitor Gas Usage**: Track transaction costs
5. **Setup Monitoring**: Use tools like Tenderly for contract monitoring

---

## Useful Links

- **Mantle Testnet Faucet:** https://faucet.testnet.mantle.xyz/
- **Mantle Explorer:** https://explorer.testnet.mantle.xyz/
- **Mantle Docs:** https://docs.mantle.xyz/
- **Foundry Book:** https://book.getfoundry.sh/

---

## Security Note

🔒 **Before Mainnet:**
- Get professional audit
- Run extensive testnet testing
- Test with real users on testnet
- Verify all contract addresses
- Setup multi-sig for admin functions
- Implement emergency pause mechanisms
