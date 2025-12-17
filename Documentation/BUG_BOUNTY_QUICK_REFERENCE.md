# MALGIST Bug Bounty - Quick Reference Guide

**For Security Researchers | Immunefi / HackenProof Programs**

---

## 🎯 Quick Start

**Contract**: `UserVault.sol` on Mantle Mainnet  
**Audit Status**: ✅ External Audit Complete  
**Bug Bounty**: 🚀 Active on Immunefi & HackenProof  
**Guardian**: Multisig (cannot move funds)  
**Emergency Response**: 24/7 on-call team

---

## 🔍 What's In Scope?

### ✅ Critical Functions (Highest Bounty)

| Function | Risk | Bounty |
|----------|------|--------|
| `deposit()` | Share inflation, fund loss | $25k+ |
| `withdraw()` | Accounting mismatch, fund loss | $25k+ |
| `_executeDeposit()` | Adapter callback attacks, fund routing errors | $20k+ |
| `reconcileAdapter()` | Incorrect balance tracking, loss | $15k+ |
| `setStrategyWithRisk()` | Invalid configuration, TVL cap bypass | $10k+ |
| `rebalanceByEngine()` | Slippage exploitation, accounting corruption | $15k+ |

### ✅ Attack Vectors We Want You to Find

1. **Share Inflation**
   - Minting more shares than proportional to deposit
   - Rounding exploits in share calculation
   - Precision loss in favor of attacker

2. **Fund Loss**
   - Withdrawal returns less than expected
   - Adapter callback reentrancy
   - Incomplete adapter deposits

3. **Accounting Bypass**
   - totalShares != sum(userShares)
   - totalAssets != sum(adapterCached)
   - Strategy copy fee bypass

4. **Adapter Routing Exploits**
   - Funds sent to wrong adapter
   - Adapter ratio manipulation
   - Incomplete adapter execution

5. **Fee Logic Exploits**
   - Double-charging fees
   - Overflow in fee calculation
   - Unauthorized fee claiming

6. **Slippage Protection Bypass**
   - Slippage checks evaded
   - MEV extraction through vault
   - Deadline validation bypass

### ❌ Out of Scope

- Lendle/Aave protocol exploits (external)
- FusionX DEX exploits (external)
- ERC20 non-standard tokens (external)
- Mantle network issues (external)
- Oracle manipulation (external)
- Transaction censorship (external)

---

## 🚨 How to Report

### Step 1: Find the Bug
- Write PoC in Solidity/TypeScript
- Test locally (forge test / hardhat)
- Document attack vector

### Step 2: Submit on Platform

**Immunefi**: https://immunefi.com/[PROGRAM_ID]  
**HackenProof**: https://hackenproof.com/[PROGRAM_ID]

**Include**:
- ✓ Detailed description
- ✓ Step-by-step reproduction
- ✓ PoC code (commit hash friendly)
- ✓ Impact assessment
- ✓ Suggested fix (optional but appreciated)

### Step 3: Verification
- Security team reviews (48-72h)
- Will request additional details if needed
- Confirms severity level
- Processes payout

---

## 💰 Bounty Tiers

| Severity | Example | Bounty | Timeline |
|----------|---------|--------|----------|
| CRITICAL | Share inflation, complete fund loss | $25k - $100k+ | 15 days |
| HIGH | TVL cap bypass, partial fund loss | $5k - $25k | 30 days |
| MEDIUM | Monitoring bypass, unauthorized fee charge | $1k - $5k | 45 days |
| LOW | Inefficient gas, non-critical precision loss | $100 - $1k | 60 days |

**Additional**:
- First reporter only
- PoC required for CRITICAL/HIGH
- Duplicates: partial bounty to second reporter

---

## 📊 Monitoring Setup

### Events to Watch

Every critical operation emits events for transparency:

```solidity
event LargeDeposit(
    address indexed user,
    uint256 indexed strategyId,
    uint256 amount,
    uint256 sharesReceived,
    uint256 timestamp
);

event SlippageWarning(
    address indexed adapter,
    uint256 expectedAmount,
    uint256 actualAmount,
    uint16 slippageBps
);

event AdapterOperation(
    address indexed adapter,
    uint8 indexed operation,
    uint256 amount,
    uint256 resultShares,
    uint8 status
);
```

### Real-Time Monitoring

- **Dashboard**: https://malgist.monitoring.live
- **Alert System**: Slack/Discord integration
- **TheGraph**: GraphQL API for event querying
- **API Docs**: https://docs.malgist.io/monitoring

---

## 🔐 Security Contacts

**Main Security Email**: security@malgist.com  
**Response Time**: <24 hours for submissions  
**Escalation**: security-lead@malgist.com (on-call)

**Do NOT**:
- ❌ Publicly disclose vulnerabilities
- ❌ Exploit beyond PoC
- ❌ Access other users' funds
- ❌ Test on mainnet without permission

---

## 🧪 Testing Environment

### Testnet Deployment

- **Network**: Mantle Sepolia
- **Contract**: [Address on Sepolia]
- **Faucet**: https://faucet.sepolia.mantle.io

### Local Testing

```bash
# Clone repo
git clone https://github.com/malgist/malgist-contracts.git
cd malgist-contracts

# Setup
forge install
forge build

# Run tests
forge test

# Deploy locally
anvil
forge script script/Deploy.s.sol --rpc-url http://localhost:8545 --broadcast
```

### Mock Adapters

- `MockAdapter.sol` — 1:1 deposit/share ratio
- `MockLendingPool.sol` — Simulates Lendle
- `MockUniswapV2Router.sol` — Simulates FusionX

---

## 📚 Key Documents

**For Researchers**:
- [BUG_BOUNTY_POLICY.md](./BUG_BOUNTY_POLICY.md) — Comprehensive scope definition
- [AUDIT_READINESS_CHECKLIST.md](./AUDIT_READINESS_CHECKLIST.md) — Pre-audit work
- [ISSUE_SEVERITY_POLICY.md](./ISSUE_SEVERITY_POLICY.md) — Severity classification
- [COMPATIBILITY_CHECK.md](./COMPATIBILITY_CHECK.md) — Technical architecture

**For Implementers**:
- [BUG_BOUNTY_CHECKLIST.md](./BUG_BOUNTY_CHECKLIST.md) — Integration guide
- [UserVault.sol](../src/UserVault.sol) — Main contract
- [IAdapter.sol](../src/interfaces/IAdapter.sol) — Adapter interface
- [BugBountyReadiness.sol](../src/BugBountyReadiness.sol) — Monitoring base

---

## ✅ Pre-Submission Checklist

Before reporting a vulnerability:

- [ ] Reproduced on testnet
- [ ] Created minimal PoC
- [ ] Verified it's in-scope
- [ ] Checked for similar reports
- [ ] Documented step-by-step reproduction
- [ ] Assessed impact (fund loss? accounting? monitoring?)
- [ ] Suggested fix (optional)
- [ ] Ready to disclose timeline

---

## 🎁 Hall of Fame

Recognized whitehats will be listed here:
- [Coming soon]

---

## 📞 Questions?

**FAQ**: https://docs.malgist.io/security/faq  
**Discord**: https://discord.gg/malgist  
**Twitter**: @MalgistOfficial  
**Email**: security@malgist.com

---

**Bug Bounty Status**: 🟢 ACTIVE  
**Last Updated**: December 17, 2025  
**Version**: 1.0

Good luck, researchers! 🚀
