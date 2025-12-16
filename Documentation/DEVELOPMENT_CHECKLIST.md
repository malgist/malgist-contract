# 📋 Malgist Smart Contract Development Checklist

**Status:** Branch `manik-dev` - Development Phase  
**Last Updated:** December 16, 2025

---

## ✅ COMPLETED FEATURES

### Core Smart Contracts

- [x] **UserVault.sol** - Main copy-trading vault

  - [x] Strategy creation & management
  - [x] Deposit/withdrawal with multi-adapter support
  - [x] Strategy copying mechanism
  - [x] Copy fee collection & claims
  - [x] Leaderboard generation
  - [x] Public strategy listing
  - [x] Reentrancy protection

- [x] **IAdapter.sol** - Standard protocol adapter interface

  - [x] Deposit/withdraw methods
  - [x] Balance tracking
  - [x] Token address getter

- [x] **LendleAdapter.sol** - Lendle (Aave V3) integration

  - [x] USDC deposit to lending pool
  - [x] aUSDC receipt token handling
  - [x] Withdrawal mechanism
  - [x] Balance retrieval
  - [x] Reserve token initialization

- [x] **FusionXAdapter.sol** - FusionX DEX integration
  - [x] Single-sided USDC deposit
  - [x] Automated WMNT swapping
  - [x] LP token provision
  - [x] Liquidity removal with USDC return
  - [x] Price calculation

### Mock Contracts (Testing)

- [x] **MockERC20.sol** - Test token
- [x] **MockLendingPool.sol** - Mock Aave protocol
- [x] **MockUniswapV2Router.sol** - Mock DEX
- [x] **MockUniswapV2Pair.sol** - Mock LP token

### Test Suite

- [x] **UserVault.t.sol** - Comprehensive test coverage
  - [x] Strategy creation tests
  - [x] Deposit/withdrawal tests
  - [x] Copy strategy tests
  - [x] Fee calculation tests
  - [x] Leaderboard tests
  - [x] Error handling tests

### Deployment Infrastructure

- [x] **DeployUserVault.s.sol** - Full deployment script
- [x] **.env** - Configuration with all addresses
- [x] **remappings.txt** - Import path configuration
- [x] **foundry.toml** - Foundry configuration

### Deployment Status

- [x] Deployed to Mantle Sepolia Testnet
  - UserVault: `0xa25660a6745B7c0Eb19B88d9bA8E494EBfc6b5ED`
  - LendleAdapter: `0x8C8369DA641Dc9c581875406D06bc40d88cca65e`
  - FusionXAdapter: `0xB43E52f8059F3cD684e887C2FC342503b2aaf471`

---

## 🚧 FEATURES THAT NEED TO BE ADDED/IMPROVED

### Priority 1: Core Improvements

#### 1. **Sorting for Leaderboard** ⚠️ TODO

**File:** `src/UserVault.sol` - `getLeaderboardByCopies()` function (line 333)

**Current Issue:** Simple return of first N strategies, no sorting by copies

**What to Add:**

```solidity
// Implement sorting algorithm for leaderboard
// Current: Just returns first N public strategies
// Needed: Sort by totalCopies in descending order before returning

// Suggested approach:
// 1. Use bubble sort or merge sort for the array
// 2. Or implement an off-chain indexing system
// 3. Consider gas optimization for large arrays
```

**Priority:** HIGH - Users need proper ranking

---

#### 2. **TVL Sorting in Leaderboard** ⚠️ TODO

**File:** `src/UserVault.sol`

**Current Issue:** Only sorting by copy count

**What to Add:**

```solidity
// Add new function: getLeaderboardByTVL()
// Return top strategies by Total Value Locked
// Implementation similar to getLeaderboardByCopies()
// But sorted by strategies[user].totalCopierTVL
```

**Priority:** HIGH - Metrics for success

---

#### 3. **Multi-Ratio Slippage Protection** ⚠️ TODO

**File:** `src/adapters/FusionXAdapter.sol`

**Current Issue:** Limited slippage handling in swap/LP operations

**What to Add:**

```solidity
// Add slippage parameters to deposit/withdraw
// Current: Fixed 50% swap ratio approximation
// Needed: Dynamic slippage tolerance

// Function enhancement:
function deposit(uint256 amount, uint256 minSwapAmount, uint256 minLpTokens)
    external returns (uint256 shares)

function withdraw(uint256 amount, uint256 minUsdcAmount)
    external returns (uint256 withdrawn)
```

**Priority:** HIGH - Security for users

---

#### 4. **Error Handling Improvements** ⚠️ TODO

**File:** `src/adapters/FusionXAdapter.sol` lines 250-270

**Current Issue:** Limited custom error coverage

**What to Add:**

```solidity
// Add custom errors for:
error ExcessiveSlippage();
error InvalidSwapPath();
error LiquidityRemovalFailed();
error InsufficientLiquidity();

// Add checks in:
- getExactSwapAmount()
- estimateWithdrawal()
- Swap operations
```

**Priority:** MEDIUM - Better error messages

---

### Priority 2: Feature Enhancements

#### 5. **Strategy Performance Tracking** ⚠️ TODO

**New File:** `src/StrategyTracker.sol`

**What to Add:**

```solidity
contract StrategyTracker {
    // Track performance metrics per strategy
    struct PerformanceMetrics {
        uint256 initialTVL;
        uint256 currentTVL;
        uint256 cumulativeYield;
        uint256 totalFees;
        uint256 lastUpdateTime;
    }

    mapping(address => PerformanceMetrics) public performance;

    // Functions:
    - calculateYield()
    - updateMetrics()
    - getROI()
    - getRiskScore()
}
```

**Priority:** MEDIUM - Transparency for users

---

#### 6. **Rebalancing Mechanism** ⚠️ TODO

**New File:** `src/Rebalancer.sol`

**What to Add:**

```solidity
contract Rebalancer {
    // Auto-rebalance strategies based on drift

    // Functions:
    function rebalanceIfNeeded(address user, uint256 maxDrift) external

    function targetAllocation(
        address user,
        address[] calldata adapters,
        uint16[] calldata newRatios
    ) external

    // Emit events for rebalancing
    event StrategyRebalanced(address indexed user, uint256 drift);
}
```

**Priority:** MEDIUM - Professional DeFi UX

---

#### 7. **Governance & Fee Management** ⚠️ TODO

**New File:** `src/FeeManager.sol`

**What to Add:**

```solidity
contract FeeManager is Ownable {
    // Centralized fee configuration

    uint16 platformFeeBps; // Platform take (0-50 bps)
    address feeCollector;  // Where fees go

    // Functions:
    function setPlatformFee(uint16 newFee) external onlyOwner
    function collectFees() external
    function withdrawFees(uint256 amount) external

    // Events:
    event FeeCollected(uint256 amount);
    event FeeWithdrawn(uint256 amount);
}
```

**Priority:** MEDIUM - Sustainability

---

### Priority 3: Advanced Features

#### 8. **Risk Management Module** ⚠️ TODO

**New File:** `src/RiskManager.sol`

**What to Add:**

```solidity
contract RiskManager {
    // Monitor & limit portfolio risk

    struct RiskLimits {
        uint256 maxPerAdapterTVL;
        uint256 maxUserTVL;
        uint256 maxProtocolExposure;
    }

    // Functions:
    function assessRisk(address user) external view returns (uint256 riskScore)
    function enforceRiskLimits(address user) external
    function updateRiskLimits(RiskLimits memory newLimits) external
}
```

**Priority:** LOW - Enterprise features

---

#### 9. **Emergency Pause Mechanism** ⚠️ TODO

**Enhancement to:** `src/UserVault.sol`

**What to Add:**

```solidity
// Add to UserVault:
bool public paused;
mapping(address => bool) public pausedAdapters;

modifier whenNotPaused() {
    require(!paused, "Vault is paused");
    _;
}

modifier adapterNotPaused(address adapter) {
    require(!pausedAdapters[adapter], "Adapter is paused");
    _;
}

function pauseVault() external onlyOwner
function unpauseVault() external onlyOwner
function pauseAdapter(address adapter) external onlyOwner
function unpauseAdapter(address adapter) external onlyOwner
```

**Priority:** HIGH (Security) - Production requirement

---

#### 10. **Comprehensive Events Logging** ⚠️ PARTIAL

**File:** `src/UserVault.sol`

**Current Issue:** Some events missing or incomplete

**What to Add:**

```solidity
// Missing events:
event AdapterApprovalChanged(address indexed adapter, uint256 amount);
event RatioValidationFailed(uint256[] ratios);
event MinSharesNotMet(address indexed user, uint256 expected, uint256 received);

// Enhance existing events with more indexed parameters
```

**Priority:** MEDIUM - Better monitoring

---

### Priority 4: Testing & Documentation

#### 11. **Integration Tests** ⚠️ TODO

**New File:** `test/Integration.t.sol`

**What to Add:**

```solidity
// Multi-contract integration tests
- testMultiAdapterDeposit() // 50/50 split across adapters
- testRebalancingFlow() // Deposit -> Rebalance -> Withdraw
- testCasecading copyFees() // Fee collection across multiple copies
- testAdapterFailover() // Behavior when one adapter fails
- testLargeScaleOperations() // Stress testing with large amounts
```

**Priority:** HIGH - Quality assurance

---

#### 12. **Adapter Integration Tests** ⚠️ TODO

**New File:** `test/FusionXAdapter.t.sol`

**What to Add:**

```solidity
// FusionX specific tests
- testSwapAmountCalculation()
- testSingleSidedDeposit()
- testSlippageHandling()
- testLPTokenMinting()
- testWithdrawalFlow()
```

**Priority:** HIGH - Reliability

---

#### 13. **Security Audit Checklist** ⚠️ TODO

**New File:** `SECURITY_AUDIT.md`

**What to Document:**

```
- Reentrancy attack vectors (covered by ReentrancyGuard)
- Integer overflow/underflow (covered by Solidity 0.8.20)
- Access control vulnerabilities
- Flash loan risks
- Front-running protection
- Precision loss in calculations
- Token approval patterns
```

**Priority:** HIGH - Pre-mainnet

---

### Priority 5: Optimization & Gas

#### 14. **Gas Optimization Pass** ⚠️ TODO

**Files:** All `.sol` files

**What to Improve:**

```solidity
// Use view/pure where possible
// Minimize storage writes
// Batch operations
// Use custom errors instead of require strings
// Pack struct variables efficiently
// Consider assembly for hot paths
```

**Priority:** MEDIUM - Mainnet readiness

---

#### 15. **Storage Layout Optimization** ⚠️ TODO

**File:** `src/UserVault.sol` - Structs section

**Current Issue:** Potential storage inefficiency

**What to Add:**

```solidity
// Analyze current layout:
struct Strategy {
    address[] adapters;      // Dynamic array
    uint16[] ratios;         // Dynamic array
    uint256 totalDeposited;  // 256-bit
    uint256 shares;          // 256-bit
    bool isPublic;           // 8-bit
    string name;             // Dynamic
    uint16 copyFeeBps;       // 16-bit
    address creator;         // 160-bit
    uint256 totalCopies;     // 256-bit
    uint256 totalCopierTVL;  // 256-bit
}

// Optimization: Pack bool, uint16, address in single slot
```

**Priority:** LOW - Optimization pass

---

## 🔧 MISSING IMPLEMENTATIONS

### Currently Unimplemented (Critical Path):

| #   | Feature             | File               | Status     | Impact   |
| --- | ------------------- | ------------------ | ---------- | -------- |
| 1   | Leaderboard Sorting | UserVault.sol      | ❌ TODO    | HIGH     |
| 2   | TVL Leaderboard     | UserVault.sol      | ❌ TODO    | HIGH     |
| 3   | Slippage Protection | FusionXAdapter.sol | ⚠️ PARTIAL | HIGH     |
| 4   | Emergency Pause     | UserVault.sol      | ❌ TODO    | CRITICAL |
| 5   | Performance Metrics | NEW FILE           | ❌ TODO    | MEDIUM   |
| 6   | Rebalancing         | NEW FILE           | ❌ TODO    | MEDIUM   |
| 7   | Fee Management      | NEW FILE           | ❌ TODO    | MEDIUM   |
| 8   | Integration Tests   | NEW FILE           | ❌ TODO    | HIGH     |
| 9   | FusionX Tests       | NEW FILE           | ❌ TODO    | HIGH     |
| 10  | Risk Management     | NEW FILE           | ❌ TODO    | LOW      |

---

## 📊 Code Coverage Status

### Current Test Coverage (Estimated):

- **UserVault.sol**: ~70% (basic flows covered)
- **LendleAdapter.sol**: ~60% (mock tests only)
- **FusionXAdapter.sol**: ~40% (limited mock testing)
- **Overall**: ~65%

### Target Coverage:

- **Pre-Production:** 90%+
- **Mainnet:** 100% (critical paths)

---

## 🎯 Recommended Implementation Order

### Phase 1: Critical (Do First)

1. ✅ Add emergency pause mechanism
2. ✅ Implement leaderboard sorting
3. ✅ Add slippage protection parameters
4. ✅ Write integration tests

### Phase 2: Important (Do Second)

5. ✅ Add TVL leaderboard
6. ✅ Create comprehensive event logging
7. ✅ Write FusionX adapter tests
8. ✅ Add custom error handling

### Phase 3: Enhancement (Do Later)

9. Performance tracking module
10. Rebalancing mechanism
11. Fee management contract
12. Risk management module

### Phase 4: Optimization (Do Last)

13. Gas optimization pass
14. Storage layout optimization
15. Security audit & fixes

---

## 🚀 Deployment Readiness Checklist

### Pre-Testnet Launch

- [x] All contracts compile without warnings
- [x] Mock contracts deployed and working
- [x] Basic functionality tests pass
- [x] Deployment script functional

### Pre-Mainnet Launch

- [ ] All critical features implemented
- [ ] 90%+ test coverage achieved
- [ ] Security audit completed
- [ ] Gas optimization done
- [ ] Emergency pause mechanism active
- [ ] Leaderboard sorting working
- [ ] Integration tests passing
- [ ] Documentation complete
- [ ] Monitoring/alerting configured

---

## 📝 Notes for Development

### Code Quality Standards:

- All functions must have NatSpec comments
- All custom errors must be documented
- Test cases should include happy path + error cases
- No magic numbers - use named constants

### Testing Standards:

- Unit tests for individual functions
- Integration tests for multi-function flows
- Edge case testing (0 amount, max amount, etc.)
- Error condition testing

### Security Considerations:

- Reentrancy guards on all state-changing functions
- SafeERC20 for all token transfers
- Access control on sensitive functions
- Overflow/underflow protection (Solidity 0.8.20)

---

## 🔗 Related Files

- **Main Contract:** `src/UserVault.sol`
- **Adapters:** `src/adapters/{LendleAdapter,FusionXAdapter}.sol`
- **Tests:** `test/UserVault.t.sol`
- **Deployment:** `script/DeployUserVault.s.sol`
- **Config:** `.env`, `remappings.txt`, `foundry.toml`

---

**Last Review:** December 16, 2025  
**Next Review:** When critical features are completed
