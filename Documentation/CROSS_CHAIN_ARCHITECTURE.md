# MALGIST Cross-Chain Adapter Architecture

**Status**: Production-Ready Design
**Date**: December 2025
**Scope**: Secure cross-chain strategy support for MALGIST DeFi Protocol

---

## 1. Overview

### Design Principle: Cross-Chain is Optional, Never Blocking

The MALGIST protocol enables strategies to optionally use cross-chain adapters for multi-chain exposure. The critical design principle is:

> **Cross-chain operations MUST NEVER block user withdrawals or local vault operations.**

This is achieved through:

- **Conservative accounting**: Only settled (confirmed) balances count toward TVL
- **Pending state isolation**: In-flight funds are tracked separately, never assumed settled
- **All-or-nothing validation**: Operations either fully succeed or fully revert
- **Emergency exit patterns**: Users can force-withdraw even during bridge halts

---

## 2. Architecture Overview

### 2.1 Component Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                    MALGIST VAULT (Mantle)                       │
│  - Accepts deposits                                              │
│  - Routes to adapters based on strategy                          │
│  - Never blocks on cross-chain state                             │
└──────────────────────────────┬──────────────────────────────────┘
                               │
                ┌──────────────┼──────────────┐
                │              │              │
        ┌───────▼────────┐  ┌──▼──────────┐  ┌──▼──────────┐
        │ Local Adapter  │  │ Cross-Chain │  │ Cross-Chain │
        │ (Aave)         │  │ Adapter 1   │  │ Adapter 2   │
        │                │  │ (LayerZero) │  │ (Canonical) │
        │ Status: LIVE   │  │ Status:     │  │ Status:     │
        │ Risk: LOW      │  │ PENDING/    │  │ PENDING/    │
        │                │  │ CONFIRMED   │  │ CONFIRMED   │
        └────────────────┘  └──────┬──────┘  └──────┬──────┘
                                   │                │
                            ┌──────▼────────────────▼────────┐
                            │  Bridge Layer (LayerZero, LZ)   │
                            │  - Message relay               │
                            │  - Retry/timeout logic         │
                            │  - Replay protection           │
                            └──────┬─────────────────────────┘
                                   │
                        ┌──────────┴──────────┐
                        │                     │
                  ┌─────▼──────┐      ┌──────▼──────┐
                  │ Ethereum   │      │ Arbitrum    │
                  │ Aave (v3)  │      │ Compound    │
                  │            │      │             │
                  └────────────┘      └─────────────┘
```

### 2.2 Lifecycle: Cross-Chain Operation

```
PHASE 1: INITIATION (Source Chain - Mantle)
┌─────────────────────────────────┐
│ User calls vault.deposit()      │
│ Routes to CrossChainAdapter     │
│ User specifies destination      │
└────────────┬────────────────────┘
             │
             ▼
┌─────────────────────────────────┐
│ Adapter locks funds in ESCROW   │
│ Generates operationId           │
│ settledBalance += amount        │
└────────────┬────────────────────┘
             │
             ▼
┌─────────────────────────────────┐
│ Initiate bridge message:        │
│ - LayerZero / Canonical / etc   │
│ - Message state = PENDING       │
│ - operationId registered        │
└────────────┬────────────────────┘
             │
             ▼
             Event: CrossChainInitiated
             Status: ✅ COMMITTED LOCALLY
             User can force-withdraw


PHASE 2: IN-FLIGHT (Bridge Network)
┌─────────────────────────────────┐
│ Bridge relayer picks up msg     │
│ Transfers tokens to dest        │
│ Typical latency: 10-60 min      │
└────────────┬────────────────────┘
             │
             ▼
             Status: ⏳ IN FLIGHT
             Pending operations tracked
             No assumptions about arrival


PHASE 3: DESTINATION (Destination Chain - e.g., Arbitrum)
┌─────────────────────────────────┐
│ Destination adapter receives    │
│ Tokens arrive on dest chain     │
│ Deploy to protocol (Compound)   │
└────────────┬────────────────────┘
             │
             ▼
┌─────────────────────────────────┐
│ Destination settledBalance++    │
│ Send confirmation back to src   │
│ Via same bridge layer           │
└────────────┬────────────────────┘
             │
             ▼
             Status: ✅ CONFIRMED DESTINATION


PHASE 4: SETTLEMENT (Source Chain - Mantle)
┌─────────────────────────────────┐
│ Confirmation message received   │
│ relayer calls confirmOperation()│
│ Mark operation as CONFIRMED     │
│ Remove from pending             │
└────────────┬────────────────────┘
             │
             ▼
             Event: CrossChainConfirmed
             Status: ✅ FULLY SETTLED
             Funds now generating yield
```

---

## 3. Interface Design: ICrossChainAdapter

### 3.1 Core Methods

#### `depositAndBridge(amount, destinationChain, destinationAdapter)`

**Purpose**: Deposit funds locally and initiate cross-chain bridge

**Returns**:

- `operationId`: Unique ID to track operation
- `deposited`: Amount locked locally (amount == deposited in success case)

**Guarantees**:

- Funds are held in escrow until confirmed
- Vault can force-withdraw at any time
- Never blocks vault operations
- Emits `CrossChainInitiated` event

**Reverts on**:

- Bridge is blocked
- Destination chain not supported
- Amount exceeds max bridge limit
- Total pending exceeds capacity

#### `receiveBridged(sourceChain, sourceAdapter, amount)`

**Purpose**: Receive tokens from another chain (called by bridge relayer)

**Access**: Only RELAYER_ROLE can call

**Guarantees**:

- Verifies source adapter authenticity
- Never reverts (bridge finality is guaranteed by design)
- Updates settledBalance immediately

#### `getBalanceSplit() → (settled, pending)`

**Purpose**: Get balance breakdown

**Critical for vault**:

- Vault uses only `settled` for withdrawal calculations
- `pending` is informational only
- Never over-counts assets

#### `forceWithdrawCrossChain(operationId) → recovered`

**Purpose**: Emergency recover funds from escrow during bridge failure

**Access**: Only EMERGENCY_ADMIN_ROLE

**Guarantees**:

- Can always recover funds
- Marks operation as FAILED
- Returns funds to source chain
- Clears pending accounting

#### `getPendingOperation(operationId) → PendingCrossChainOp`

**Purpose**: Query operation status

**Returns**:

```solidity
struct PendingCrossChainOp {
    uint256 operationId;           // Unique ID
    bytes32 bridgeId;              // Bridge tx hash
    uint256 amount;                // Amount in transit
    uint64 destinationChain;       // Target chain
    address destinationAdapter;    // Target adapter
    CrossChainState state;         // PENDING/CONFIRMED/FAILED/STUCK
    uint40 initiatedAt;            // Timestamp
    uint40 confirmedAt;            // Confirmation time (0 if pending)
}
```

---

## 4. State Machine: Cross-Chain Lifecycle

```
                    ┌─────────────────┐
                    │    PENDING      │
                    │ (in-flight)     │
                    └────────┬────────┘
                             │
                ┌────────────┼────────────┐
                │            │            │
         CONFIRMED      FAILED        STUCK
      (settled on    (bridge          (bridge
       dest)         failed)           halted)
                │            │
                ▼            ▼
           COMPLETE    FORCE-WITHDRAW
           (success)   (emergency)
```

**Transitions**:

1. **PENDING → CONFIRMED**: Bridge successfully delivers and settles

   - Called by: `confirmCrossChainOperation(operationId)`
   - Action: Remove from pending accounting
   - Funds now generating yield

2. **PENDING → FAILED**: Bridge fails or times out

   - Called by: `forceWithdrawCrossChain(operationId)` or timeout handler
   - Action: Recover funds to escrow, mark FAILED
   - User can re-deposit locally

3. **PENDING → STUCK**: Bridge halted by emergency
   - Called by: `markOperationStuck(operationId, reason)`
   - Action: Prevent new operations, allow force-withdraw
   - Temporary state, recoverable

**Immutability**: Once an operation leaves PENDING state, it cannot return.

---

## 5. Risk Isolation: Critical Safety Mechanisms

### 5.1 Per-Strategy Opt-In

Cross-chain is never mandatory. Each strategy specifies:

```solidity
struct StrategyConfig {
    address[] adapters;              // Local + cross-chain adapters
    uint16[] ratios;                 // Allocation % per adapter
    bool allowsCrossChain;           // True if strategy includes cross-chain
    uint64[] supportedDestinationChains;  // Which chains allowed
    // ...
}
```

**Vault-level validation**:

```solidity
if (strategy.allowsCrossChain) {
    // Only use cross-chain adapters if strategy allows
    // Vault can refuse strategies with cross-chain adapters
}
```

### 5.2 Max Allocation Cap

**Global cap**: Cross-chain adapters limited to **50% of strategy allocation**

```solidity
uint16 public constant MAX_ALLOCATION_CROSS_CHAIN_BPS = 5000;  // 50%
```

**Per-adapter cap**: Each adapter has max pending amount

```solidity
uint256 public maxPendingAmount = 50_000_000e18;  // 50M tokens
```

**Ensures**: Even if all cross-chain bridges fail, vault still has 50% in liquid local assets

### 5.3 Independent State: No Shared Escrow

Each cross-chain adapter has its own escrow:

```
Adapter A (LayerZero) → Escrow A (separate contract)
Adapter B (Canonical) → Escrow B (separate contract)
Local Adapter (Aave)  → Direct on Aave (no escrow)
```

**Failure of Adapter A escrow does NOT affect Adapter B**

### 5.4 Emergency Exit Patterns

#### Pattern 1: Force-Withdraw Pending Operations

```solidity
// During bridge halt
vault.forceWithdrawCrossChain(operationId);
// Recovers funds to vault
// User can withdraw from vault immediately
```

**Guarantee**: Even with 100% cross-chain allocation, user can exit in ~1 tx + 1 force-withdraw

#### Pattern 2: Pause & Block Bridge

```solidity
adapter.blockBridge("LayerZero endpoint down");
// Prevents new cross-chain operations
// Allows force-withdraw of existing operations
```

#### Pattern 3: Vault Pause

```solidity
vault.pause();
// Stops all new deposits/withdrawals
// Emergency measure for cascading failures
```

---

## 6. Vault Interaction Rules

### 6.1 Deposit Flow with Cross-Chain Adapters

```
vault.deposit(strategyId, amount)
│
├─ Validate strategy allows cross-chain (if applicable)
│
├─ For each adapter in strategy.adapters:
│  │
│  ├─ IF local (non-cross-chain):
│  │  └─ deposit() → settled balance updated immediately
│  │
│  └─ IF cross-chain:
│     ├─ depositAndBridge() → operationId returned
│     ├─ settledBalance updated (escrowed)
│     └─ pendingByChain[destChain] += amount
│
└─ Vault issues shares based on SETTLED balance only
```

**Key principle**: Shares are issued immediately, but only against settled funds

### 6.2 Withdrawal Flow

```
vault.withdraw(shareAmount)
│
├─ Calculate tokensOwed = shareAmount / sharesPerToken
│
├─ While tokensOwed > 0:
│  │
│  ├─ Use settled local balance first
│  │
│  ├─ IF insufficient local, check adapters in order:
│  │  ├─ Local adapters: withdraw() immediately
│  │  └─ Cross-chain adapters: SKIP (don't wait for bridge)
│  │
│  └─ IF still insufficient:
│     └─ Revert("Insufficient liquidity")
│
└─ Transfer tokens to user
```

**Key principle**: Never wait for cross-chain confirmations. Use local liquidity first.

### 6.3 TVL Reporting

```solidity
function getTVL() external view returns (uint256) {
    uint256 tvl = 0;

    for (adapter in adapters) {
        if (adapter.isCrossChain()) {
            (uint256 settled, uint256 pending) = adapter.getBalanceSplit();
            tvl += settled;  // Only count settled
            // pending not counted (conservative)
        } else {
            tvl += adapter.getBalance();
        }
    }

    return tvl;
}
```

**Reporting**: Always conservative. Never optimistically include pending.

---

## 7. Bridge Interaction Layer

### 7.1 Message Delivery Guarantees

#### LayerZero

```
Guarantee: At-most-once delivery
Latency: 10-60 minutes (typically)
Cost: Per-message fee + destination gas

Flow:
1. Source calls lzEndpoint.send()
2. LayerZero validators sign message
3. Relayer picks up and delivers to destination
4. Destination calls lzReceive()

Retry: Automatic, with exponential backoff
Timeout: 1 hour (configurable)
```

#### Canonical Bridges (e.g., Stargate)

```
Guarantee: At-least-once delivery
Latency: 5-30 minutes
Cost: Typically cheaper than LayerZero

Flow:
1. Source locks tokens in bridge contract
2. Validators confirm lock
3. Tokens minted on destination
4. Destination unlocks/mints tokens

Retry: Manual or automatic (bridge-dependent)
Timeout: Bridge-dependent
```

### 7.2 Replay Protection

**Method 1: Operation IDs**

```solidity
struct PendingCrossChainOp {
    uint256 operationId;  // Unique counter, never reused
    // ...
}
```

**Method 2: Message Hashing**

```solidity
bytes32 messageHash = keccak256(abi.encodePacked(
    operationId,
    sourceChain,
    destinationChain,
    amount,
    timestamp
));
// Hash ensures message uniqueness across space/time
```

**Method 3: Destination State**

```solidity
mapping(bytes32 => bool) public processedMessages;

function lzReceive(...) external {
    bytes32 msgHash = keccak256(_payload);
    require(!processedMessages[msgHash], "Already processed");
    // ...
    processedMessages[msgHash] = true;
}
```

### 7.3 Chain Re-org Handling

**Scenario**: Chain re-orgs and message delivery order changes

**Protection 1: Idempotent Messages**

```
Messages must be safe to process multiple times
Example: "Deposit 1000 USDC" (idempotent)
Bad: "Increase balance by 1000" (not idempotent)
```

**Protection 2: Finality Checking**

```solidity
// Only confirm operations after N blocks
function confirmCrossChainOperation(uint256 operationId) external {
    require(block.number >= confirmedBlockNumber + 256, "Too early");
    // ...
}
```

**Protection 3: State Versioning**

```solidity
mapping(uint256 => mapping(bytes32 => bool)) public stateByBlock;
// Prevents re-org attacks by anchoring to specific blocks
```

---

## 8. Security Threat Model & Mitigations

### Threat 1: Bridge Exploit (e.g., LayerZero hack)

**Attack**: Attacker controls bridge and mints tokens on destination

**Mitigation**:

- Adapter maintains separate accounting per chain
- Exploit limited to that adapter only
- Vault can force-withdraw pending operations
- User's local holdings remain secure

**Impact**: Limited to funds in cross-chain adapter, ≤ 50% of strategy

### Threat 2: Message Spoofing

**Attack**: Attacker forges confirmation message

**Mitigation**:

- Only RELAYER_ROLE can call `confirmCrossChainOperation()`
- Relayer is trusted (either vault admin or whitelisted service)
- Message signature verification (bridge-native)
- Operation ID ensures uniqueness

**Impact**: Prevented by role-based access control

### Threat 3: Stuck Funds (Bridge Halted)

**Attack**: Bridge service goes down, funds stuck in escrow

**Mitigation**:

- `forceWithdrawCrossChain()` recovers funds at any time
- Emergency admin can call during halts
- Escrow contract separate from vault
- Timeouts trigger automatic recovery

**Impact**: User can exit with ~2 tx (force-withdraw + vault withdraw)

### Threat 4: Cross-Chain Reentrancy

**Attack**: Destination adapter calls back source adapter before state settled

**Mitigation**:

- Each adapter's operations are independent
- State updates are atomic (confirm/fail only)
- No recursive external calls
- ReentrancyGuard on all state changes

**Impact**: Prevented by reentrancy guard

### Threat 5: Governance Abuse (Malicious Bridge Added)

**Attack**: Admin adds bridge that steals funds

**Mitigation**:

- All bridge additions use ADMIN_ROLE
- Can be managed by DAO/multisig
- Per-strategy opt-in (users choose strategies)
- TVL reporting is conservative (pending not counted)

**Impact**: Limited to future deposits to that strategy (existing fund exit is always possible)

### Threat 6: Total Bridge Failure Scenario

**Scenario**: All bridges halt simultaneously

**Impact Assessment**:

- Local adapters continue working (50%+ of TVL)
- Cross-chain adapters marked STUCK
- Users withdraw from local adapters first
- Cross-chain funds can be force-withdrawn
- Worst case: 24-48 hour delay for full exit

**Recovery**:

1. Admin calls `blockBridge()`
2. Admin calls `forceWithdrawCrossChain()` for all operations
3. Funds returned to source chain
4. Vault pause lifted
5. Users withdraw normally

---

## 9. Latency & Accounting

### 9.1 Delayed Execution Model

**Assumption**: Bridge latency = 10-60 minutes (typical LayerZero)

**Accounting Timeline**:

```
T+0s    : User deposits 1000 USDC
         vault.settledBalance = 1000
         vault shares issued

T+5s    : Bridge initiated
         pendingByChain[Arbitrum] = 1000
         settledBalance = 1000 (still committed locally)

T+30m   : Bridge confirms arrival
         Destination adapter: settledBalance += 1000
         Confirmation sent back

T+30m+10s: Source receives confirmation
          confirmCrossChainOperation(opId) called
          pendingByChain[Arbitrum] -= 1000
          Both chains now settled

T+30m+1h: User requests withdrawal
          Vault checks: settledBalance = 1000 (if no other ops)
          User can withdraw immediately
```

### 9.2 Partial Fills

**Scenario**: Bridge delivers 900 USDC instead of 1000 (slippage)

**Handling**:

```solidity
function receiveBridged(..., uint256 expectedAmount) external returns (uint256 actual) {
    // Bridge delivers what it can
    uint256 actualAmount = bridgeTransfer(expectedAmount);

    if (actualAmount < expectedAmount) {
        // Record shortfall
        recordSlippage(expectedAmount - actualAmount);
        emit PartialFill(expectedAmount, actualAmount);
    }

    settledBalance += actualAmount;
    return actualAmount;
}
```

**Vault handling**:

```
Expected: 1000 USDC on destination
Actual: 900 USDC received
Shortfall: 100 USDC

Accounting:
- Source: settledBalance = 1000 (escrowed locally)
- Destination: settledBalance = 900 (received)
- Total TVL = 1900 USDC (conservative, counts both)
- User's 1000 USDC still backed
```

### 9.3 Pending vs Settled Balances

**Vault-level accounting**:

```solidity
uint256 totalSettled = 0;
uint256 totalPending = 0;

for (adapter in strategy.adapters) {
    if (adapter.isCrossChain()) {
        (uint256 settled, uint256 pending) = adapter.getBalanceSplit();
        totalSettled += settled;
        totalPending += pending;
    } else {
        totalSettled += adapter.getBalance();
    }
}

// For withdrawals and shares:
uint256 tvl = totalSettled;  // NEVER use totalPending

// For reporting:
reportedTVL = totalSettled;
reportedPending = totalPending; // Informational only
```

---

## 10. Implementation: Concrete Example

### 10.1 LayerZero-Based Implementation

**Architecture**:

```
┌─ Mantle (Source) ───────────────────────────────────────────┐
│                                                              │
│  User → Vault → LayerZeroAdapter                            │
│         ├─ depositAndBridge(1000, Arbitrum, ...)            │
│         └─ Creates operation: opId=1                        │
│                                                              │
│  Escrow Contract                                            │
│  └─ Holds 1000 USDC in escrow                              │
│                                                              │
│  CrossChainAdapterBase                                      │
│  ├─ settledBalance = 1000                                   │
│  ├─ pendingByChain[Arbitrum] = 1000                         │
│  └─ pendingOperations[1] = { state: PENDING, ... }          │
│                                                              │
│  LayerZero Endpoint                                         │
│  └─ send() to Arbitrum...                                   │
│                                                              │
└──────────────────────────────────────────────────────────────┘

LayerZero Network (Relayer)
  └─ Pick up message and relay to Arbitrum

┌─ Arbitrum (Destination) ──────────────────────────────────┐
│                                                            │
│  LayerZeroAdapter (Remote)                               │
│  └─ lzReceive() called by LayerZero                       │
│     ├─ Decode payload                                    │
│     ├─ settledBalance += 1000                            │
│     └─ Deploy to Compound                                │
│                                                            │
│  Compound Protocol                                        │
│  └─ cUSDC balance += 1000 USDC (earning yield)           │
│                                                            │
└────────────────────────────────────────────────────────────┘

Back to Mantle

┌─ Confirmation Message ────────────────────────────────────┐
│                                                            │
│  Destination sends confirmation back via LayerZero       │
│  "Operation 1 confirmed on Arbitrum"                     │
│                                                            │
│  LayerZeroAdapter.lzReceive() receives confirmation      │
│  └─ confirmCrossChainOperation(1) called                 │
│     ├─ pendingByChain[Arbitrum] -= 1000                 │
│     ├─ pendingOperations[1].state = CONFIRMED            │
│     └─ Funds now settled on both chains                  │
│                                                            │
└────────────────────────────────────────────────────────────┘
```

### 10.2 Code Flow: Complete Example

```solidity
// User deposits with cross-chain strategy
vault.deposit(strategyId=1, amount=1000e18);  // 1000 USDC

// Strategy 1 allocation:
// - 50% to Aave (local) = 500 USDC
// - 50% to Compound (Arbitrum, cross-chain) = 500 USDC

// Vault execution:
vault.route(strategyId, 1000e18) {
    // Route to Local Adapter
    uint256 localDeposited = aaveAdapter.deposit(500e18);
    vault.settledBalance += 500;

    // Route to Cross-Chain Adapter
    (uint256 opId, uint256 bridgeDeposited) =
        layerZeroAdapter.depositAndBridge(
            500e18,
            chainId=Arbitrum,
            destinationAdapter=...
        );

    // LocalAdapter: settledBalance = 500 ✅
    // CrossChainAdapter:
    //   - settledBalance = 500 (escrowed) ✅
    //   - pendingByChain[Arbitrum] = 500 ✅
    //   - pendingOperations[opId] = PENDING ✅

    // Issue shares
    vault.issueShares(user, 1000e18);
}

// After ~30 minutes: Bridge confirms on destination
arbitrumLayerZeroAdapter.lzReceive(...) {
    settledBalance += 500;  // Destination confirms
    sendConfirmationBack();  // Send confirmation to source
}

// After ~30 minutes: Source receives confirmation
mantle_layerZeroAdapter.lzReceive(confirmation) {
    confirmCrossChainOperation(opId=1);
    // pendingOperations[1].state = CONFIRMED
    // pendingByChain[Arbitrum] = 0
}

// Now both chains settled:
// Mantle Adapter: settledBalance = 500 (local in Aave)
// Arbitrum Adapter: settledBalance = 500 (in Compound)
// Total: 1000 USDC earning yield

// User withdraws after earning yield
vault.withdraw(shares=1000e18);

// Vault checks liquidity:
// needToPay = 1100 USDC (1000 + 100 yield)
// available = 550 USDC (500 local + 50 from Aave fees)
// Insufficient! Revert.
//
// OR if Aave has enough yield:
// available = 1100 USDC (from local adapters)
// Transfer 1100 to user ✅
```

---

## 11. Configuration Best Practices

### 11.1 Recommended Settings

```solidity
// Hard Limits (Immutable)
MAX_ALLOCATION_CROSS_CHAIN_BPS = 5000;    // 50% max
MAX_ADAPTERS = 10;                         // Per strategy
BRIDGE_CONFIRMATION_TIMEOUT = 3600;        // 1 hour

// Risk-Based Per-Adapter Caps
- Canonical Bridges: maxPending = 50M tokens
- LayerZero: maxPending = 30M tokens
- Experimental: maxPending = 5M tokens

// Gas/Fee Budgets
- LayerZero gas limit = 200k
- Estimated fee per tx = 5-50 USD
- Allow 2x fee variance

// Monitoring Thresholds
- Alert if pending > 24 hours
- Alert if pending amount > 10M tokens
- Force-withdraw if > 48 hours pending
```

### 11.2 Multi-Sig Governance

```solidity
// Recommended roles:
- DEFAULT_ADMIN: 3-of-5 multisig (protocol changes)
- RELAYER_ROLE: Trusted relay service (messages)
- EMERGENCY_ADMIN: 2-of-3 multisig (force-withdraw)

// Time locks:
- New chain registration: 2 day timelock
- Bridge parameter changes: 1 day timelock
- Emergency actions: Immediate
```

---

## 12. Deployment Checklist

- [ ] Deploy CrossChainAdapterBase
- [ ] Deploy LayerZeroAdapter with correct endpoint
- [ ] Register supported destination chains
- [ ] Register destination adapters on each chain
- [ ] Set maxPendingAmount based on TVL
- [ ] Configure emergency admin roles
- [ ] Set up relayer service (whitelisted)
- [ ] Configure LayerZero gas limits
- [ ] Test full deposit/withdrawal flow on testnet
- [ ] Test force-withdraw scenarios
- [ ] Test bridge halt scenarios
- [ ] Audit contract (especially escrow)
- [ ] Deploy to mainnet with time locks
- [ ] Monitor pending operations
- [ ] Set up alerts for bridge health

---

## 13. FAQ & Troubleshooting

**Q: What if bridge is down?**
A: Call `forceWithdrawCrossChain()` to recover funds. Operations marked STUCK. User exits normally.

**Q: What if destination chain re-orgs?**
A: Message tracking and state versioning prevent duplicate processing. No fund loss.

**Q: Can adapters steal funds?**
A: No. Escrow is separate from vault. Only escrow contract can unlock. Adapter can't transfer from escrow.

**Q: What if relayer is compromised?**
A: Relayer can only call RELAYER_ROLE functions. Can't confirm operations falsely without valid bridge messages. Worst case: denial of service (no new confirmations). Recovery via timeout/force-withdraw.

**Q: What's the maximum loss scenario?**
A: All cross-chain bridges fail + destination protocols exploit. Max loss = 50% of strategy TVL (cross-chain cap). Local 50% remains intact. User can exit with recovered funds.

---

## 14. Conclusion

The MALGIST cross-chain architecture achieves:

✅ **Safety**: Conservative accounting, never optimistic
✅ **Resilience**: Multiple exit paths, no hard dependencies
✅ **Scalability**: Supports multiple chains and bridges
✅ **Auditability**: Every operation tracked, immutable state
✅ **User Control**: Opt-in per strategy, force-withdraw always available

Cross-chain is optional and never blocks vault operations.
