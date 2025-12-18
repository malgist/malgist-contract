# MALGIST Cross-Chain: Risk Isolation & Vault Integration

**Document Purpose**: Detailed technical guide for cross-chain risk isolation and vault integration patterns

---

## 1. Risk Isolation Architecture

### 1.1 Multiple Layers of Isolation

```
┌─────────────────────────────────────────────────────────────────┐
│                         VAULT LAYER                              │
│  - Accepts deposits                                              │
│  - Validates strategy config                                    │
│  - Routes to adapters                                           │
│  - Manages withdrawals                                          │
│                                                                  │
│  ISOLATION: Vault never directly interacts with cross-chain    │
│             Vault uses only settled balances for accounting    │
└───────────────────────────────┬─────────────────────────────────┘
                                │
                 ┌──────────────┴──────────────┐
                 │                             │
        ┌────────▼────────────┐      ┌────────▼────────────┐
        │  LOCAL ADAPTER      │      │ CROSS-CHAIN         │
        │                     │      │ ADAPTER             │
        │  - Aave             │      │                     │
        │  - Compound         │      │ ISOLATION:          │
        │  - Direct protocol  │      │ - Separate escrow   │
        │                     │      │ - Independent state │
        │  State: Settled     │      │ - Failure contained │
        │  Risk: Inherited    │      │                     │
        │  (protocol risk)    │      │ State: Split        │
        │                     │      │ (settled+pending)   │
        │                     │      │ Risk: Elevated      │
        │                     │      │ (+ bridge risk)     │
        └─────────────────────┘      └────────┬────────────┘
                                              │
                    ┌─────────────────────────┼─────────────┐
                    │                         │             │
          ┌─────────▼─────┐       ┌───────────▼────┐  ┌────▼─────────┐
          │   ESCROW A    │       │   ESCROW B     │  │ ESCROW C     │
          │ (LayerZero)   │       │ (Canonical)    │  │ (Future)     │
          │               │       │                │  │              │
          │ - Holds funds │       │ - Holds funds  │  │ - Holds funds│
          │ - Per-tx auth │       │ - Per-tx auth  │  │ - Per-tx auth│
          │ - Recoverable │       │ - Recoverable  │  │ - Recoverable│
          └───────────────┘       └────────────────┘  └──────────────┘
                    │                     │                   │
          ┌─────────▼─────────────────────┼──────────────────▼────┐
          │         BRIDGE LAYER (External)                        │
          │  - LayerZero / Canonical / Etc                        │
          │  - Operates independently                             │
          │  - Failures isolated to each bridge                   │
          └──────────────────────────────────────────────────────┘
```

### 1.2 Isolation Properties

#### Property 1: Independent Accounting

```solidity
// Each adapter tracks its own state
contract CrossChainAdapter {
    uint256 settledBalance;              // Only this adapter
    mapping(uint64 => uint256) pendingByChain;  // This adapter only
    mapping(uint256 => PendingOp) pendingOperations;  // This adapter only
}

// Vault combines but never mixes state
uint256 vaultSettledTotal = localAdapter.getBalance()
                          + ccAdapter1.settledBalance
                          + ccAdapter2.settledBalance;
```

#### Property 2: Independent Failures

```
Scenario: LayerZero bridge exploited

┌─ Mantle ──────────────────────────┐
│ ✅ Local Adapter (Aave) WORKING  │
│ ❌ LZ Adapter (LayerZero) BROKEN │
│ ✅ Canonical Adapter WORKING     │
│                                  │
│ User can:                        │
│ 1. Withdraw from local + canon   │
│ 2. Force-withdraw from LZ        │
│ 3. Exit fully                   │
└──────────────────────────────────┘
```

#### Property 3: Separate Escrow Contracts

```solidity
// Each bridge has its own escrow
layerZeroEscrow = new CrossChainEscrow(token);
canonicalEscrow = new CrossChainEscrow(token);

// Escrow contracts have minimal logic
contract CrossChainEscrow {
    // Only owner (adapter) can unlock
    function unlock(recipient, amount) onlyOwner external {
        token.transfer(recipient, amount);
    }
}

// If one escrow is hacked, other untouched
```

### 1.3 Per-Strategy Opt-In

```solidity
// Strategy creator declares cross-chain usage
struct StrategyConfig {
    // ... existing fields
    bool allowsCrossChain;                   // Opt-in flag
    uint64[] supportedDestinationChains;     // Whitelist chains
    address[] crossChainAdapters;            // Which adapters can be cross-chain
    uint16[] crossChainAllocationsCap;       // Max allocation per cross-chain adapter
}

// Vault validates before using strategy
function deposit(uint256 strategyId, uint256 amount) external {
    StrategyConfig storage strategy = strategies[strategyId];

    // Check: If strategy uses cross-chain, mark position as high-risk
    if (strategy.allowsCrossChain) {
        positions[posId].isHighRisk = true;
    }

    // Check: Can still withdraw without cross-chain operations
    require(_canExitWithoutCrossChain(strategy), "Strategy too risky");
}
```

**User UI Warning**:

```
⚠️  This strategy uses cross-chain bridges (Arbitrum, Mainnet)

    Risk: Higher risk than local-only strategies
    Benefit: Access to other protocols (Aave Mainnet, Compound)

    You can always exit, even if bridges are down.
    Force-withdraw available in emergency.

    [Accept] [Cancel]
```

### 1.4 Allocation Caps

#### Hard Limit: 50% Cross-Chain Maximum

```solidity
// Per strategy validation
uint256 totalCrossChainAllocation = 0;
for (adapter in strategy.adapters) {
    if (adapter.isCrossChain()) {
        totalCrossChainAllocation += strategy.allocations[i];
    }
}
require(totalCrossChainAllocation <= 5000, "Max 50% cross-chain");
```

**Example: Valid Strategy**

```
Allocations:
- Aave (local, Mantle): 50%
- Compound (Arbitrum, cross-chain): 30%
- Stargate (Mainnet, cross-chain): 20%
-------
Total cross-chain: 50% ✅ VALID

If bridge fails:
- Local: 50% always available
- Arbitrum: Can force-withdraw 30%
- Mainnet: Can force-withdraw 20%
```

**Example: Invalid Strategy**

```
Allocations:
- Compound (Arbitrum, cross-chain): 60%
- Stargate (Mainnet, cross-chain): 40%
-------
Total cross-chain: 100% ❌ REJECTED

Reason: Exceeds 50% cross-chain limit
Solution: Add local adapter or reduce cross-chain allocation
```

#### Per-Bridge Capacity Limits

```solidity
struct AdapterConfig {
    uint256 maxPendingAmount;    // E.g., 50M USDC
    uint40 bridgeLatencySeconds; // E.g., 600 (10 min)
    uint16 maxAllocationBps;     // E.g., 5000 (50%)
}

// During deposit
if (adapter.isCrossChain()) {
    uint256 newPending = adapter.getPendingAmount() + depositAmount;
    require(newPending <= adapter.maxPendingAmount,
            "Adapter capacity exceeded");
}
```

---

## 2. No Shared State Between Adapters

### 2.1 State Isolation Pattern

```solidity
// ❌ BAD: Shared escrow
contract SharedEscrow {
    mapping(address => uint256) balances;  // Multiple adapters share

    // Problem: If one adapter is hacked, can drain all balances
    function steal() external {
        // Access another adapter's funds
    }
}

// ✅ GOOD: Separate escrow per adapter
contract CrossChainAdapter {
    CrossChainEscrow private myEscrow;  // Only for this adapter

    function _recoverFromEscrow(amount) internal {
        myEscrow.unlock(address(this), amount);
    }
}
```

### 2.2 State Transition Rules

```solidity
// Each adapter manages its own state machine
enum State { LOCAL, IN_TRANSIT, REMOTE, FAILED, STUCK }

// Transitions are atomic and isolated
function deposit() external {
    // State: LOCAL → IN_TRANSIT
    (opId, ) = depositAndBridge(amount, dest);
    // Now: pendingOperations[opId].state = IN_TRANSIT
}

function confirmCrossChainOperation(opId) external {
    // State: IN_TRANSIT → REMOTE
    op.state = CONFIRMED;
    // Now: can be withdrawn from destination
}

function forceWithdrawCrossChain(opId) external {
    // State: IN_TRANSIT → FAILED
    // OR: STATE: STUCK → FAILED
    _recoverFromEscrow(op.amount);
    op.state = FAILED;
    // Now: funds back to source chain
}
```

### 2.3 No Cross-Adapter Communication

```solidity
// ❌ BAD: Adapters call each other
contract AdapterA {
    function deposit() external {
        adapterB.stealBalances();  // Cross-adapter call
    }
}

// ✅ GOOD: Vault mediates all interactions
contract StrategyVault {
    function executeStrategy(id) external {
        for (adapter in adapters) {
            if (adapter.settled >= withdrawAmount) {
                adapter.withdraw(withdrawAmount);
                return;
            }
        }
    }
}
```

---

## 3. Emergency Exit & Force-Withdraw Patterns

### 3.1 Force-Withdraw Mechanism

```solidity
contract CrossChainAdapterBase {
    /**
     * @notice Emergency force-withdraw from pending operations
     * Callable by EMERGENCY_ADMIN during bridge failures
     */
    function forceWithdrawCrossChain(uint256 operationId)
        external
        onlyRole(EMERGENCY_ADMIN_ROLE)
        returns (uint256 recovered)
    {
        PendingCrossChainOp storage op = pendingOperations[operationId];

        require(op.state == PENDING || op.state == STUCK,
                "Cannot force-withdraw non-pending operations");

        // Recover funds from escrow
        recovered = op.amount;
        _recoverFromEscrow(recovered);

        // Mark operation as failed
        op.state = FAILED;

        // Emit event for audit trail
        emit ForceWithdrawCrossChain(operationId, recovered, "Emergency");

        return recovered;
    }
}
```

### 3.2 Vault Integration: Force-Withdraw Flow

```solidity
contract StrategyVault {
    /**
     * @notice Emergency exit: Recover all pending cross-chain operations
     */
    function emergencyRecoverCrossChain(address adapterAddress)
        external
        onlyRole(EMERGENCY_ADMIN_ROLE)
    {
        ICrossChainAdapter adapter = ICrossChainAdapter(adapterAddress);
        PendingCrossChainOp[] memory pending = adapter.getAllPendingOperations();

        uint256 totalRecovered = 0;
        for (uint i = 0; i < pending.length; i++) {
            if (pending[i].state == CrossChainState.PENDING ||
                pending[i].state == CrossChainState.STUCK) {
                uint256 recovered = adapter.forceWithdrawCrossChain(pending[i].operationId);
                totalRecovered += recovered;
            }
        }

        emit EmergencyRecoveryCrossChain(adapterAddress, totalRecovered);
    }

    /**
     * @notice Allow users to withdraw even if cross-chain operations are stuck
     */
    function emergencyWithdraw(uint256 shareAmount)
        external
        nonReentrant
    {
        // Calculate withdrawal amount from shares
        uint256 tokensOwed = (shareAmount * vault.totalAssets()) / vault.totalShares();

        // Iterate through adapters: try local first, skip cross-chain stuck ones
        uint256 available = 0;

        for (adapter in adapters) {
            if (!adapter.isCrossChain()) {
                // Local adapters: always available
                (uint256 settled, ) = adapter.getBalanceSplit();
                available += settled;
            } else {
                // Cross-chain adapters: only use settled balance
                (uint256 settled, ) = adapter.getBalanceSplit();
                available += settled;
            }

            if (available >= tokensOwed) {
                // Enough available, proceed with withdrawal
                _withdrawFromAdapters(adapters, tokensOwed);
                return;
            }
        }

        // If not enough even with settled, revert
        revert("Insufficient settled liquidity for emergency withdrawal");
    }
}
```

### 3.3 Timeout-Based Automatic Force-Withdraw

```solidity
contract CrossChainAdapterBase {
    uint40 public constant BRIDGE_CONFIRMATION_TIMEOUT = 3600;  // 1 hour

    /**
     * @notice Check if operation should be auto-recovered
     */
    function shouldAutoRecover(uint256 operationId)
        external
        view
        returns (bool shouldRecover, string memory reason)
    {
        PendingCrossChainOp storage op = pendingOperations[operationId];

        if (op.state != PENDING) {
            return (false, "Not pending");
        }

        // If pending > 1 hour, auto-recover
        if (block.timestamp > op.initiatedAt + BRIDGE_CONFIRMATION_TIMEOUT) {
            return (true, "Confirmation timeout (>1 hour)");
        }

        // If bridge is blocked, auto-recover
        if (bridgeBlocked) {
            return (true, "Bridge is blocked");
        }

        return (false, "");
    }

    /**
     * @notice Keeper calls this to auto-recover stuck operations
     */
    function autoRecoverIfTimeout(uint256 operationId)
        external
        nonReentrant
    {
        (bool shouldRecover, ) = shouldAutoRecover(operationId);
        require(shouldRecover, "Auto-recovery not triggered");

        forceWithdrawCrossChain(operationId);
    }
}
```

### 3.4 Multi-Step Exit Scenario

```
Scenario: LayerZero bridge is halted, user wants to exit

Step 1: Admin marks bridge as blocked
────────────────────────────────────
vault.adapter.blockBridge("LayerZero endpoint halted");
// Prevents new cross-chain deposits
// Allows force-withdraw of pending operations

Step 2: Admin auto-recovers all pending operations
──────────────────────────────────────────────────
for (opId in pendingOperations) {
    if (shouldAutoRecover(opId)) {
        vault.adapter.autoRecoverIfTimeout(opId);
        // Recovers funds to source chain
    }
}

Step 3: User withdraws normally
───────────────────────────────
vault.withdraw(shareAmount);
// Vault uses settled balances (including recovered funds)
// User receives tokens

Total exit time: ~30 min (bridge latency) + ~5 min (recovery) = ~35 min
No fund loss, only cross-chain yield lost (if any)
```

---

## 4. Vault Interaction Rules (Detailed)

### 4.1 Strategy Validation Before Acceptance

```solidity
contract StrategyVault {

    function validateStrategyWithCrossChain(StrategyConfig memory strategy)
        internal
        view
        returns (bool isValid, string memory reason)
    {
        // Rule 1: Total allocations sum to 100%
        uint256 totalAllocation = 0;
        for (uint i = 0; i < strategy.allocations.length; i++) {
            totalAllocation += strategy.allocations[i];
        }
        require(totalAllocation == 10000, "Allocations don't sum to 100%");

        // Rule 2: Cross-chain allocation <= 50%
        uint256 crossChainAllocation = 0;
        for (uint i = 0; i < strategy.adapters.length; i++) {
            if (isCrossChainAdapter(strategy.adapters[i])) {
                crossChainAllocation += strategy.allocations[i];
            }
        }
        if (crossChainAllocation > 5000) {
            return (false, "Cross-chain exceeds 50%");
        }

        // Rule 3: Each cross-chain adapter has capacity
        for (uint i = 0; i < strategy.adapters.length; i++) {
            if (isCrossChainAdapter(strategy.adapters[i])) {
                ICrossChainAdapter adapter = ICrossChainAdapter(strategy.adapters[i]);
                require(adapter.supportedChains(strategy.destChains[i]),
                        "Destination chain not supported");
            }
        }

        // Rule 4: At least 50% can be exited without cross-chain
        uint256 localAllocation = 0;
        for (uint i = 0; i < strategy.adapters.length; i++) {
            if (!isCrossChainAdapter(strategy.adapters[i])) {
                localAllocation += strategy.allocations[i];
            }
        }
        if (localAllocation < 5000) {
            return (false, "Must have >= 50% local allocation");
        }

        return (true, "");
    }
}
```

### 4.2 Deposit Routing

```solidity
contract StrategyVault {

    function executeDeposit(uint256 strategyId, uint256 amount)
        internal
    {
        StrategyConfig storage strategy = strategies[strategyId];
        uint256 remainingAmount = amount;

        // Route to adapters in priority order:
        // 1. Local adapters first
        // 2. Cross-chain adapters second

        for (uint i = 0; i < strategy.adapters.length; i++) {
            address adapter = strategy.adapters[i];
            uint16 allocation = strategy.allocations[i];
            uint256 routeAmount = (amount * allocation) / 10000;

            if (isCrossChainAdapter(adapter)) {
                // Cross-chain adapter
                (uint256 opId, uint256 deposited) = ICrossChainAdapter(adapter)
                    .depositAndBridge(
                        routeAmount,
                        strategy.destinationChains[i],
                        strategy.destinationAdapters[i]
                    );

                // Track pending operation
                emit RouteToAdapter(adapter, routeAmount, true, opId);

            } else {
                // Local adapter
                uint256 deposited = IAdapter(adapter).deposit(routeAmount);
                emit RouteToAdapter(adapter, deposited, false, 0);
            }
        }
    }
}
```

### 4.3 Withdrawal Logic: Conservative Approach

```solidity
contract StrategyVault {

    function executeWithdraw(uint256 strategyId, uint256 tokenAmount)
        internal
        returns (uint256 withdrawn)
    {
        StrategyConfig storage strategy = strategies[strategyId];
        uint256 needed = tokenAmount;

        // PHASE 1: Try local adapters only
        for (uint i = 0; i < strategy.adapters.length; i++) {
            if (needed == 0) break;

            address adapter = strategy.adapters[i];
            if (isCrossChainAdapter(adapter)) continue;  // Skip cross-chain

            uint256 available = IAdapter(adapter).getBalance();
            uint256 toWithdraw = min(available, needed);

            if (toWithdraw > 0) {
                uint256 withdrawn = IAdapter(adapter).withdraw(toWithdraw);
                needed -= withdrawn;
            }
        }

        // PHASE 2: Try cross-chain adapters (settled balance only)
        for (uint i = 0; i < strategy.adapters.length; i++) {
            if (needed == 0) break;

            address adapter = strategy.adapters[i];
            if (!isCrossChainAdapter(adapter)) continue;  // Only cross-chain

            (uint256 settled, ) = ICrossChainAdapter(adapter).getBalanceSplit();
            uint256 toWithdraw = min(settled, needed);

            if (toWithdraw > 0) {
                uint256 withdrawn = IAdapter(adapter).withdraw(toWithdraw);
                needed -= withdrawn;
            }
        }

        // If still needed, revert
        if (needed > 0) {
            revert("Insufficient settled liquidity");
        }

        return tokenAmount;
    }
}
```

### 4.4 TVL Reporting (Conservative)

```solidity
contract StrategyVault {

    function getTVL() external view returns (uint256 tvl) {
        for (uint i = 0; i < adapters.length; i++) {
            address adapter = adapters[i];

            if (isCrossChainAdapter(adapter)) {
                // Cross-chain: only count settled
                (uint256 settled, uint256 pending) =
                    ICrossChainAdapter(adapter).getBalanceSplit();
                tvl += settled;

                // Report pending separately for dashboard
                emit PendingCrossChain(pending);

            } else {
                // Local: count everything
                tvl += IAdapter(adapter).getBalance();
            }
        }
    }

    function getTVLDetailed() external view returns (
        uint256 settled,
        uint256 pending,
        mapping addressToSettled
    ) {
        // Detailed breakdown for UI
    }
}
```

---

## 5. Scenario Analysis

### Scenario 1: Normal Operation

```
Time 0: User deposits 1000 USDC
├─ 50% to Aave (Mantle): 500 USDC
└─ 50% to Compound (Arbitrum): 500 USDC (cross-chain)

Time 5: Bridge initiates
├─ Aave: settled = 500 ✅
├─ Compound: settled = 500 (escrowed), pending = 500
└─ Total: settled = 1000, pending = 500

Time 30: Bridge confirms
├─ Aave: settled = 500 (earning)
├─ Compound: settled = 500 (earning)
└─ Total: settled = 1000, earning

User can withdraw at any time ✅
```

### Scenario 2: Partial Bridge Failure (Slippage)

```
Expected: 500 USDC to arrive on Arbitrum
Actual: 480 USDC arrived (slippage/fees)

Source chain:
├─ Aave: settled = 500
├─ Compound adapter: settled = 500 (escrowed)
└─ Pending: 500

Destination chain:
├─ Compound: settled = 480 (only partial arrived)

Total asset accounting:
├─ Fully settled: 980 USDC
├─ Unaccounted (stuck in bridge): 20 USDC
└─ User position: backed by 980 USDC

Vault reports:
├─ TVL: 980 USDC (conservative)
├─ User's 1000 USDC shares backed by 980 USDC (97.6% backed)

User can withdraw 980 USDC ✅
Remaining 20 USDC: can be recovered via manual bridge intervention
```

### Scenario 3: Complete Bridge Halt

```
LayerZero network halted for 2 hours

Pending operations:
├─ opId=1: 500 USDC, state=PENDING (1 hour 50 min pending)
├─ opId=2: 300 USDC, state=PENDING (1 hour 20 min pending)
└─ opId=3: 200 USDC, state=PENDING (30 min pending)

Admin actions:
1. blockBridge("LayerZero halted")
   └─ Prevents new cross-chain operations

2. emergencyRecoverCrossChain(ccAdapter)
   └─ Force-withdraws all pending:
      └─ totalRecovered = 1000 USDC

3. Operations marked FAILED and escrowed funds unlocked

Vault state after recovery:
├─ Aave: settled = 500
├─ CC Adapter: settled = 500 (recovered from escrow)
└─ Total: settled = 1000

User can withdraw immediately ✅
```

### Scenario 4: Destination Chain Exploited

```
Compound protocol on Arbitrum exploited
All funds in Compound adapter lost

Vault state:
├─ Aave (Mantle): settled = 500, healthy ✅
├─ Compound (Arbitrum): settled = 500, but underlying lost ❌
└─ Total TVL: 1000 USDC reported (but only 500 actually backed)

Cross-chain allocation: 50%
Local allocation: 50%

User's position:
├─ Backing: 500 USDC (from Aave)
├─ Loss: 500 USDC (from Compound exploit)
└─ Net: 50% loss

But:
- User can still withdraw 500 USDC immediately ✅
- Remaining 500 frozen (not recoverable without bridge)
- Total loss contained to cross-chain portion only
- Local adapter 100% safe ✅
```

---

## 6. Monitoring & Alerts

### 6.1 Metrics to Track

```solidity
struct CrossChainMetrics {
    uint256 totalPendingAmount;           // All pending across adapters
    uint40 maxPendingAge;                  // Oldest pending operation
    uint256 pendingOperationCount;         // Number of pending ops
    uint16 bridgeHealthScore;              // 0-10000, 10000 = healthy
    uint256 totalForcedWithdrawals;        // All-time emergency exits
    uint256 bridgeHaltCount;               // All-time halts
}
```

### 6.2 Alert Thresholds

```
🟢 HEALTHY:
  - totalPendingAmount < 5M tokens
  - maxPendingAge < 30 min
  - 0 pending timeouts

🟡 WARNING:
  - totalPendingAmount 5M - 20M tokens
  - maxPendingAge 30 min - 1 hour
  - 1-5 pending timeouts

🔴 CRITICAL:
  - totalPendingAmount > 20M tokens
  - maxPendingAge > 1 hour
  - > 5 pending timeouts
  - Bridge halted
```

---

## Conclusion

The MALGIST cross-chain architecture achieves complete isolation through:

1. **Per-Adapter Independence**: Each adapter has separate state, escrow, and failure domain
2. **Opt-In Strategy**: Users choose cross-chain via strategy selection
3. **Allocation Caps**: 50% max cross-chain prevents catastrophic scenarios
4. **Conservative Accounting**: Only settled balances count
5. **Force-Exit Paths**: Multiple ways to recover funds during emergencies

No cross-chain operation can ever block vault withdrawals or jeopardize local assets.
