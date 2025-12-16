# 🎓 Panduan Lengkap: Design Patterns & Alasan Teknis (Bahasa Indonesia)

**Target Audience:** Developer Solidity yang ingin memahami design decisions  
**Level:** Intermediate - Advanced

---

## 📚 Table of Contents

1. [Design Patterns Digunakan](#design-patterns-digunakan)
2. [Why This Architecture?](#why-this-architecture)
3. [Common Scenarios & Solutions](#common-scenarios--solutions)
4. [Gas Optimization Explained](#gas-optimization-explained)
5. [Potential Improvements](#potential-improvements)

---

## Design Patterns Digunakan

### 1️⃣ Adapter Pattern

**File:** `src/adapters/FusionXAdapterV2.sol` + `IAdapter.sol`

**Konsep:**

```solidity
// Interface (abstraksi)
interface IAdapter {
    function deposit(uint256 amount) external returns (uint256 shares);
    function withdraw(uint256 lpAmount) external returns (uint256 withdrawn);
    function getBalance() external view returns (uint256);
    function token() external view returns (address);
}

// Multiple implementations:
contract FusionXAdapterV2 is IAdapter { ... }
contract LendleAdapter is IAdapter { ... }
contract AaveAdapter is IAdapter { ... }  // Future
```

**Mengapa?**

- **Flexibility:** Mudah tambah protocol baru tanpa ubah UserVaultV2
- **Abstraction:** UserVaultV2 tidak perlu tahu detail FusionX
- **Testability:** Mock adapter mudah untuk testing
- **Extensibility:** Maintenance mode untuk adapter tertentu

**Analogi Real-World:**

```
Seperti socket listrik universal:
- TV, Laptop, Charger → berbeda device
- Semua gunakan adapter yang sama
- Interface standar (plug shape)
```

### 2️⃣ Library for Utility Functions

**File:** `src/libraries/LeaderboardLib.sol`

**Konsep:**

```solidity
library LeaderboardLib {
    struct LeaderboardEntry { ... }

    function sortDescending(...) internal pure { ... }
    function getTopN(...) internal pure { ... }
    function getPercentile(...) internal pure { ... }
}

// Usage:
contract UserVaultV2 {
    using LeaderboardLib for LeaderboardLib.LeaderboardEntry[];

    // Now can use library functions like methods:
    entries.sortDescending(maxLength);
}
```

**Mengapa?**

- **Code Reusability:** Sorting logic bisa digunakan multiple contracts
- **Delegation:** Pure functions tidak state change
- **Gas Efficiency:** Library deployment terpisah
- **Testing:** Fungsi library bisa tested independently

### 3️⃣ Composite Pattern (Multiple Adapters)

**File:** `src/UserVaultV2.sol`

**Konsep:**

```solidity
struct Strategy {
    address[] adapters;  // Multiple adapters
    uint16[] ratios;     // Weights untuk setiap adapter
}

// User bisa:
// Option 1: 100% FusionX
//   adapters: [FusionX]
//   ratios: [10000]

// Option 2: 60% FusionX, 40% Lendle
//   adapters: [FusionX, Lendle]
//   ratios: [6000, 4000]

// Option 3: 40% FusionX, 40% Lendle, 20% Aave
//   adapters: [FusionX, Lendle, Aave]
//   ratios: [4000, 4000, 2000]
```

**Mengapa?**

- **Diversification:** User bisa hedge risk
- **Risk Management:** Tidak all-in satu protocol
- **Flexibility:** Change allocation without withdraw
- **Simplicity:** User set once, execute many times

### 4️⃣ State Management with Enums (Future)

**Konsep untuk PRIORITY 2:**

```solidity
enum StrategyState {
    ACTIVE,      // Normal operation
    PAUSED,      // Owner paused
    LIQUIDATED,  // Risk threshold breached
    ARCHIVED     // Creator deprecated
}

// Implementation:
mapping(address => StrategyState) public strategyState;

modifier whenActive(address strategy) {
    require(strategyState[strategy] == StrategyState.ACTIVE);
    _;
}
```

**Mengapa?**

- Better state tracking
- More explicit than boolean flags
- Future-proof untuk status tambahan

### 5️⃣ Inheritance Hierarchy

**File:** `src/UserVaultV2.sol` + `src/Pausable.sol`

**Konsep:**

```
        ReentrancyGuard      Pausable
              |                |
              └────────┬───────┘
                       |
                 UserVaultV2
```

**Mengapa Separate Pausable?**

```solidity
// ❌ Bad: Pause logic tercampur
contract UserVaultV2 {
    bool paused;
    bool[] adapterPaused;
    function pauseVault() { ... }
    function pauseAdapter() { ... }
    // ... 450 lines
}

// ✅ Good: Separation of concerns
contract Pausable {
    // 110 lines only
    bool paused;
    mapping pausedAdapters;
    function pauseVault() { ... }
}

contract UserVaultV2 is Pausable {
    // Fokus pada vault logic
}
```

**Benefits:**

- **Modularity:** Bisa reuse Pausable untuk contract lain
- **Simplicity:** Setiap contract punya single responsibility
- **Testability:** Pause logic tested independently

---

## Why This Architecture?

### 1. TVL Tracking dengan Dual Components

**Problem:**

```
Scenario 1: Ranking hanya by creator deposits
  Alice: 10k USDC → Rank 1
  Bob (creator yang biasa): 8k → Rank 2

Scenario 2: Bob-nya strategy bagus, banyak yang copy
  Bob copies get: 50k from copiers
  But ranking unchanged (only 8k creator)

❌ UNFAIR: Baik strategy tidak ter-reward
```

**Solution: Dual-Component TVL**

```solidity
struct Strategy {
    uint256 totalDeposited;   // Creator deposits: 8k
    uint256 totalCopierTVL;   // Copier deposits: 50k
}

// Total TVL = 8k + 50k = 58k
// Ranking: Bob #1 (58k), Alice #2 (10k)

✅ FAIR: Good creators ranked high
```

**Design Decision:**

- Incentivize quality strategy creation
- Copier TVL boost creator ranking
- Encourage experimentation (can copy other strategies)

### 2. Per-Adapter Pause vs Global Pause

**Scenario:**

```
Vault operations:
- FusionX (DEX)
- Lendle (Lending)
- Aave (Lending)

Senario: FusionX bug ditemukan
```

**Option 1: Global Pause**

```solidity
paused = true;
// Semua operation blocked:
// - FusionX: STOP ❌
// - Lendle: STOP ❌
// - Aave: STOP ❌

❌ Overkill: Lendle/Aave aman tapi di-pause
```

**Option 2: Per-Adapter Pause** ✅

```solidity
pausedAdapters[FusionX] = true;

// Hasil:
// - FusionX: STOP (bug isolated)
// - Lendle: CONTINUE ✅
// - Aave: CONTINUE ✅

// User jalan terus dengan Lendle/Aave
// Minimal disruption
```

**Design Decision:**

- Granular control lebih baik
- Keep good protocols running
- Faster recovery time

### 3. Slippage Enforcement On-Chain

**Scenario:**

```
User ingin deposit 10k USDC → FusionX LP
Target exchange rate: 1 USDC = 100 WMNT

Frontend estimate: 10k USDC → ~1m WMNT
User set slippage: 0.5% (acceptable)
```

**Option 1: Frontend-Only Validation**

```javascript
// ❌ Frontend (dapat disapu attacker)
let estimatedOutput = estimate(10k);  // 1m WMNT
let userSlippage = 0.5;
let minOutput = estimatedOutput * (1 - userSlippage);

// ❓ But blockchain bisa execute dengan harga berbeda!
// Attacker bisa kirim transaksi dengan berbeda harga
```

**Option 2: On-Chain Enforcement** ✅

```solidity
// ✅ Blockchain (cannot bypass)
function depositWithSlippage(uint256 amount, uint16 slippageBps) {
    uint256 expectedOutput = getAmountsOut(amount);
    uint256 minOutput = (expectedOutput * (TOTAL_BPS - slippageBps)) / TOTAL_BPS;

    // Swap dengan minimum enforcement
    router.swapExactTokensForTokens(
        amount,
        minOutput,  // 🔴 Blockchain validasi ini
        path,
        address(this),
        deadline
    );
}

// Jika actual output < minOutput → REVERT
// Attacker tidak bisa bypass
```

**Design Decision:**

- Security > Convenience
- On-chain > Off-chain validation
- User bisa retry dengan different slippage

### 4. Copy Strategy dengan Relationship Tracking

**Problem:**

```
User A copy User B strategy
- Perlu track: User A copied from User B
- Perlu track: B dapat berapa copy
- Perlu calculate: Fee distribution

Without tracking:
Copy → dapat apa fee? dari siapa?
```

**Solution:**

```solidity
mapping(address => address) public copiedFrom;
// copiedFrom[0x222...] = 0x111... (Bob copied from Alice)

mapping(address => uint256) public copyFeeEarnings;
// copyFeeEarnings[0x111...] = 500 (Alice earn 500 USDC)

function deposit() {
    address creator = copiedFrom[msg.sender];
    if (creator != address(0)) {
        uint256 fee = (amount * creatorStrategy.copyFeeBps) / TOTAL_BPS;
        copyFeeEarnings[creator] += fee;
    }
}
```

**Design Decision:**

- Simple one-parent relationship (not multi-level)
- Fee akumulasi, claim dengan batch
- Track untuk ranking

### 5. Withdrawal Always Works (Safety First)

**Problem:**

```
Normal pause scenario:
paused = true  // Emergency pause

User ingin withdraw dana:
require(!paused);  // REVERT ❌

❌ UNFAIR: User terjebak dengan dana di kontrak
```

**Solution:**

```solidity
// Withdraw tidak ada whenNotPaused modifier
function withdraw(uint256 shareAmount)
    external nonReentrant  // Only reentrancy guard
    returns (uint256 withdrawn)
{
    // No: require(!paused) ✅
    // User selalu bisa withdraw
}
```

**Design Decision:**

- Emergency pause = stop deposits, not withdrawals
- User asset safety > operational flexibility
- Governance principle: never trap user funds

---

## Common Scenarios & Solutions

### Scenario 1: User Melihat Strategy Bagus, Ingin Copy

**Flow:**

```
1. User lihat leaderboard
   Alice: 150 copies, 150k TVL, top rank

2. User panggil: vault.copyStrategy(alice)
   → strategies[user] = copy dari Alice
   → copiedFrom[user] = alice
   → strategies[alice].totalCopies++

3. User panggil: vault.deposit(10k, 50)
   → Transfer 10k USDC dari user
   → Calculate fee: 10k × 0.5% = 50 USDC
   → copyFeeEarnings[alice] += 50
   → strategies[alice].totalCopierTVL += 9950
   → Execute deposit: 9950 USDC ke adapters

4. Leaderboard update:
   alice.TVL = 150k creator + 9950 copier = 150k + X

✅ Alice dapat fee, ranking naik (lebih banyak TVL)
```

### Scenario 2: Emergency Pause - FusionX Bug

**Flow:**

```
1. Owner detect bug di FusionX

2. Owner call: vault.pauseAdapter(fusionX)

3. Efek:
   - ✅ New strategies can't use FusionX
   - ✅ New deposits blocked untuk FusionX strat
   - ✅ Existing dengan FusionX can withdraw
   - ✅ Lendle/Aave users unaffected

4. Meanwhile:
   - Lendle/Aave users continue depositing
   - Existing FusionX users withdraw gradually
   - Team fix bug

5. Owner call: vault.unpauseAdapter(fusionX)
   - FusionX available again
```

### Scenario 3: MEV Attack Prevention

**Without Slippage Protection:**

```
User: deposit 10k USDC
Frontend estimate: 1m WMNT

Block timeline:
1. User send tx: swap 10k → 1m WMNT (min: not set)
2. Attacker sandwich:
   - Front-run: buy lots of WMNT (pump price)
   - User transaction execute (swap at bad rate)
   - Back-run: sell WMNT (take profit)
3. User receive: 900k WMNT (10% slipped!)
```

**With Slippage Protection:**

```
User: deposit 10k USDC, slippage 0.5%
Frontend estimate: 1m WMNT
minAmount = 1m × 0.995 = 995k WMNT

Block timeline:
1. User send tx: swap 10k → 995k min WMNT
2. Attacker try sandwich:
   - Front-run: buy WMNT
   - User transaction: "actual 900k < 995k" → REVERT ❌
   - Back-run cancelled

✅ User safe, tx reverted, can retry with tighter slippage
```

### Scenario 4: TVL Leaderboard Dynamic Update

**Before Deposits:**

```
Leaderboard:
1. Alice: 100k TVL (200 copies)
2. Bob: 80k TVL (150 copies)
3. Charlie: 60k TVL (100 copies)
```

**Alice Create New Strategy + Deposit 50k:**

```
// Note: Alice already exist in leaderboard

2. vault.setStrategy([FusionX], [10000], true, "Growth", 50)
   → New strategy entry

3. vault.deposit(50k, 50)
   → Untuk strategy existing yang di-rank
   → strategies[alice].totalDeposited += 50k

New Leaderboard:
1. Alice: 150k TVL (200 copies) ← Updated!
2. Bob: 80k TVL (150 copies)
3. Charlie: 60k TVL (100 copies)

✅ Ranking auto-update next view call
```

---

## Gas Optimization Explained

### 1. Using Libraries for Sorting

**Why not embed di contract?**

```solidity
// ❌ Expensive way
contract UserVaultV2 {
    // 450 lines + 80 lines = 530 lines code
    // Larger bytecode = expensive deployment
    // Larger ABI

    function sortDescending() { ... }  // Embedded
    function getTopN() { ... }
    function getPercentile() { ... }
}

// Deployment cost: ~2.5m gas
```

**Using Library (✅ Actual):**

```solidity
// library: 80 lines
// contract: 450 lines
// Total: 530 lines tapi split

library LeaderboardLib { ... }
contract UserVaultV2 is ... {
    using LeaderboardLib for ...
}

// Deployment cost:
// - Library: 0.5m gas
// - Contract: 2m gas
// - Total: 2.5m gas (but more efficient linkage)
```

**Benefit:**

- Multiple contracts dapat link same library
- Library code reuse
- Cleaner separation

### 2. View Functions Cost Nothing

```solidity
// ✅ Free to call (view)
function getLeaderboardByCopies(uint256 count) external view {
    // Read-only operations
    // No gas cost (untuk viewer)
    // Miners/validators execute untuk free
}

// ❌ Expensive (state-changing)
function updateLeaderboard() external {
    // Would cost gas
    // Must persist state
}
```

**Design Decision:**

- Leaderboard calculated on-the-fly (not cached)
- Eliminate cache invalidation problems
- Always accurate, never stale

### 3. Efficient Ratio Calculation

```solidity
// Split 10k across 3 adapters dengan ratios [5000, 3000, 2000]

❌ Naive approach:
amount[0] = (10k * 5000) / 10000 = 5000
amount[1] = (10k * 3000) / 10000 = 3000
amount[2] = (10k * 2000) / 10000 = 2000
// Total: 10000 ✅ Tapi rounding bisa ada

✅ Smart approach:
remaining = 10k
for i in 0..1:
    amount[i] = (10k * ratio[i]) / 10000
    remaining -= amount[i]
amount[2] = remaining  // Last adapter dapat sisa

// Total: exactly 10000 (no rounding loss)
```

### 4. Storage Packing

```solidity
// Current Strategy struct:
struct Strategy {
    address[] adapters;        // 32 bytes (pointer)
    uint16[] ratios;           // 32 bytes (pointer)
    uint256 totalDeposited;    // 32 bytes
    uint256 shares;            // 32 bytes
    bool isPublic;             // 1 byte
    string name;               // 32 bytes (pointer)
    uint16 copyFeeBps;         // 2 bytes
    address creator;           // 20 bytes
    uint256 totalCopies;       // 32 bytes
    uint256 totalCopierTVL;    // 32 bytes
    uint256 lastUpdated;       // 32 bytes
}

// Could optimize (PRIORITY 2):
// Pack bool + uint16 + address = 1 slot (instead of 3)
// But tradeoff: code complexity
```

---

## Potential Improvements

### PRIORITY 2: Performance Tracking Module

**Current Limitation:**

```
No yield/ROI tracking
No historical performance
No risk metrics
```

**Solution:**

```solidity
struct PerformanceSnapshot {
    uint256 timestamp;
    uint256 tvl;
    uint256 copieCount;
    int256 roi;
    uint256 volatility;
}

mapping(address => PerformanceSnapshot[]) public history;

function recordSnapshot() external {
    // Called weekly/monthly
    // Track historical performance
}
```

### PRIORITY 3: Risk Management

**Current Limitation:**

```
No limits on allocation
No drawdown protection
No concentration risk checks
```

**Solution:**

```solidity
struct RiskParams {
    uint256 maxAllocationPerAdapter;  // Max 40% per protocol
    uint256 maxDrawdown;              // Max 20% from peak
    uint256 vixThreshold;             // Pause if market volatility high
}

function validateAllocation(uint256[] memory amounts) internal view {
    for (uint256 i = 0; i < amounts.length; i++) {
        require(amounts[i] <= maxAllocation, "Concentration risk");
    }
}
```

### PRIORITY 4: Advanced Fee Structure

**Current:**

```
Fixed copyFeeBps (0-50 bps)
```

**Future:**

```
- Performance-based fee (higher if better ROI)
- Tiered fee (discount for loyal copiers)
- Exit fee (for strategy changes)
- Management fee (% of TVL annually)
```

---

## 🎓 Learning Takeaways

1. **Architecture First:** Good design > clever code
2. **Safety First:** Emergency pause yang fair
3. **Incentives Matter:** TVL tracking incentivize good creators
4. **On-Chain Logic:** Never trust frontend-only validation
5. **Modularity:** Separate contracts > monolithic
6. **Testing:** 16 tests cover critical paths
7. **Gas Efficiency:** Libraries for reusable code
8. **State Management:** Single responsibility

---

**Next Reading:** CODE_EXPLANATIONS.md untuk deep-dive setiap function
