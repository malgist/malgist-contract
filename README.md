# Malgist - Copy-Trading DeFi Platform

> Social copy-trading on Mantle Network - Follow top performers, earn creator fees, build wealth together.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Solidity](https://img.shields.io/badge/Solidity-0.8.20-blue)](https://soliditylang.org/)
[![Network](https://img.shields.io/badge/Network-Mantle%20Sepolia-purple)](https://sepolia.mantlescan.xyz/)

**🚀 Live on Mantle Sepolia Testnet**

---

## 📖 Overview

**Malgist** is a decentralized copy-trading platform that allows users to create, share, and monetize DeFi investment strategies. Unlike traditional copy-trading platforms, Malgist is:

- **Fully On-Chain:** All strategies and trades execute via smart contracts
- **Creator-Friendly:** Strategy creators earn 0-0.5% fees from copiers
- **Multi-Protocol:** Supports multiple DeFi protocols (Lendle, FusionX)
- **USDC-Optimized:** Single base asset for simplicity
- **Leaderboard-Driven:** Transparent performance tracking

### Key Features

✅ **Create Custom Strategies** - Allocate funds across multiple protocols  
✅ **Copy Top Performers** - One-click strategy copying  
✅ **Earn Creator Fees** - Monetize your successful strategies  
✅ **Transparent Leaderboard** - Track top strategies by copies and TVL  
✅ **Gas-Optimized** - Built for Mantle's low-fee environment

---

## 📍 Deployed Contracts (Mantle Sepolia)

### Core Contracts

| Contract | Address | Explorer |
|----------|---------|----------|
| **UserVault** | `0x65B43c257c885259360b7165C2773e0d53053b68` | [View](https://sepolia.mantlescan.xyz/address/0x65B43c257c885259360b7165C2773e0d53053b68) |
| **LendleAdapter** | `0xEEE09B03d9260C77404bc51146F7C1d58B439150` | [View](https://sepolia.mantlescan.xyz/address/0xEEE09B03d9260C77404bc51146F7C1d58B439150) |
| **FusionXAdapter** | `0x2F65BE78959DA2D49f250Cc28E01589490cCd029` | [View](https://sepolia.mantlescan.xyz/address/0x2F65BE78959DA2D49f250Cc28E01589490cCd029) |

### Mock Tokens (Testnet)

| Token | Address | Purpose |
|-------|---------|---------|
| **USDC** | `0x7F5E3eDC4f3c7505C52Cd7938468A630Ad1E32Ee` | Base asset for strategies |
| **WMNT** | `0x68Cd4bD113F5f5A05007a6E2F05C65D3ed80a80F` | For FusionX LP pairs |

<details>
<summary>📋 View All Deployed Addresses</summary>

```json
{
  "network": "mantle-sepolia",
  "chainId": 5003,
  "contracts": {
    "userVault": "0x65B43c257c885259360b7165C2773e0d53053b68",
    "lendleAdapter": "0xEEE09B03d9260C77404bc51146F7C1d58B439150",
    "fusionXAdapter": "0x2F65BE78959DA2D49f250Cc28E01589490cCd029",
    "usdc": "0x7F5E3eDC4f3c7505C52Cd7938468A630Ad1E32Ee",
    "wmnt": "0x68Cd4bD113F5f5A05007a6E2F05C65D3ed80a80F"
  }
}
```

</details>

---

## 🔧 Contract ABIs

### UserVault ABI

<details>
<summary>Click to expand full ABI</summary>

Key functions:
```solidity
// Create or update strategy
function setStrategy(
    address[] memory adapters,
    uint16[] memory ratios,
    bool isPublic,
    string memory name,
    uint16 copyFeeBps
) external

// Copy another user's strategy
function copyStrategy(address creator) external

// Deposit USDC into strategy
function deposit(uint256 amount) external returns (uint256 shares)

// Withdraw from strategy
function withdraw(uint256 shareAmount) external returns (uint256 withdrawn)

// Claim accumulated creator fees
function claimCopyFees() external

// View functions
function getStrategy(address user) external view returns (Strategy memory)
function getLeaderboardByCopies(uint256 count) external view returns (...)
```

Generate full ABI:
```bash
forge inspect src/UserVault.sol:UserVault abi > abis/UserVault.json
```

</details>

### Adapter ABIs

<details>
<summary>LendleAdapter & FusionXAdapter ABI</summary>

```bash
# Generate ABIs
forge inspect src/adapters/LendleAdapter.sol:LendleAdapter abi > abis/LendleAdapter.json
forge inspect src/adapters/FusionXAdapter.sol:FusionXAdapter abi > abis/FusionXAdapter.json
```

</details>

---

## 🚀 Quick Start

### For Users

1. **Get Testnet Tokens**
   ```bash
   # Visit Mantle Sepolia faucet
   https://faucet.sepolia.mantle.xyz/
   ```

2. **Interact via Explorer**
   - Visit [UserVault on Explorer](https://sepolia.mantlescan.xyz/address/0x65B43c257c885259360b7165C2773e0d53053b68)
   - Click "Contract" → "Write Contract"
   - Connect wallet and call functions directly

3. **Or Use Cast CLI**
   ```bash
   # Create strategy
   cast send 0x65B43c257c885259360b7165C2773e0d53053b68 \
     "setStrategy(address[],uint16[],bool,string,uint16)" \
     "[0xEEE09...,0x2F65B...]" \
     "[5000,5000]" \
     true \
     "My Strategy" \
     10
   ```

### For Developers

```bash
# Clone repository
git clone https://github.com/yourusername/Malgist.git
cd Malgist

# Install dependencies
forge install

# Run tests
forge test

# Build contracts
forge build
```

---

## 📚 Documentation

- **[DEPLOYMENT_SUCCESS.md](./DEPLOYMENT_SUCCESS.md)** - Deployment details and next steps
- **[DEPLOY_AND_VERIFY.md](./DEPLOY_AND_VERIFY.md)** - Contract verification guide
- **[TROUBLESHOOTING.md](./TROUBLESHOOTING.md)** - Common issues and solutions
- **[QUICKSTART.md](./QUICKSTART.md)** - Quick deployment and testing guide

---

## 🏗️ Architecture

### System Overview

```
┌─────────────┐
│   UserVault │  ← Main contract (strategy management)
└──────┬──────┘
       │
       ├─────► LendleAdapter   (Lending protocol)
       └─────► FusionXAdapter  (DEX LP farming)
```

### Key Contracts

**UserVault.sol** (463 lines)
- Manages user strategies using `mapping(address => Strategy)`
- Handles deposits, withdrawals, and fee distribution
- Tracks leaderboard data (totalCopies, totalCopierTVL)
- Enforces 0.5% max copy fee

**LendleAdapter.sol** (165 lines)
- Integrates with Lendle (Aave V3 fork)
- Auto-compounds yield via aTokens
- USDC → aUSDC conversion

**FusionXAdapter.sol** (305 lines)
- Zap-in logic: USDC → 50% swap → Add liquidity
- Zap-out: Remove liquidity → Swap to USDC
- Supports USDC-WMNT LP pairs

---

## 🧪 Testing

```bash
# Run all tests
forge test

# Run specific test file
forge test --match-contract UserVault

# Run with verbosity
forge test -vv

# Run with gas report
forge test --gas-report
```

**Test Coverage:** 10/10 UserVault tests passing ✅

---

## 🔐 Security

- ✅ `ReentrancyGuard` on all state-changing functions
- ✅ `SafeERC20` for all token interactions
- ✅ Input validation on all public functions
- ✅ Adapter allowance reset after each operation
- ✅ `onlyVault` modifier on adapter functions

**⚠️ Note:** Contracts have NOT been professionally audited. Use at your own risk.

---

## 📊 Project Stats

- **Language:** Solidity 0.8.20
- **Framework:** Foundry
- **Network:** Mantle Sepolia (Chain ID: 5003)
- **Total Contracts:** 9 deployed
- **Deployment Cost:** ~0.812 MNT (~$0.80)
- **Test Coverage:** 100% of core functionality

---

## 🛠️ Development

### Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation)
- Node.js 18+ (for frontend, optional)

### Setup

```bash
# Install Foundry dependencies
forge install

# Copy environment file
cp .env.example .env
# Edit .env with your private key

# Build contracts
forge build

# Run tests
forge test
```

### Deploy to Mantle Sepolia

```bash
# Set environment variables
source .env

# Deploy
forge script script/DeployUserVault.s.sol \
  --rpc-url $MANTLE_SEPOLIA_RPC \
  --private-key $PRIVATE_KEY \
  --broadcast \
  --legacy
```

---

## 📁 Project Structure

```
Malgist/
├── src/
│   ├── UserVault.sol           # Main vault contract
│   ├── adapters/
│   │   ├── LendleAdapter.sol   # Lending protocol adapter
│   │   └── FusionXAdapter.sol  # DEX adapter
│   ├── interfaces/
│   │   └── IAdapter.sol        # Adapter interface
│   └── mocks/                  # Mock contracts for testing
├── test/
│   └── UserVault.t.sol         # Test suite
├── script/
│   └── DeployUserVault.s.sol   # Deployment script
├── deployments/
│   └── addresses.env           # Deployed contract addresses
└── docs/                       # Additional documentation
```

---

## 🤝 Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

---

## 📜 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

## 🔗 Links

- **Explorer:** https://sepolia.mantlescan.xyz/
- **Faucet:** https://faucet.sepolia.mantle.xyz/
- **Mantle Docs:** https://docs.mantle.xyz/
- **Foundry Book:** https://book.getfoundry.sh/

---

## 💡 Roadmap

- [ ] Deploy to Mantle mainnet
- [ ] Add more protocol adapters
- [ ] Implement APY-based leaderboard
- [ ] Build frontend interface
- [ ] Professional security audit
- [ ] Add strategy risk scoring

---

## 👥 Team

Built during Mantle Hackathon 2024

---

## ⭐ Support

If you find this project useful, please consider giving it a star on GitHub!

---

**Made with ❤️ for the Mantle ecosystem**
