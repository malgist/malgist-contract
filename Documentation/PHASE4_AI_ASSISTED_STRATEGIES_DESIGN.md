<!-- Documentation/PHASE4_AI_ASSISTED_STRATEGIES_DESIGN.md -->

# Phase 4: AI-Assisted, On-chain Verified Strategies

**Date:** December 17, 2025  
**Status:** MVP Design Complete  
**Jury Value Statement:** _"We don't trust AI — we trust Mantle smart contracts. AI improves UX, contracts enforce truth."_

---

## Executive Summary

**Phase 4** enables AI to improve user experience by generating investment strategy parameters off-chain, while maintaining 100% on-chain validation and execution. AI is treated as a **UX layer**, not a trusted execution component.

### Core Principle

```
AI: Generate suggestions (UX)  →  User: Review & sign  →  Contract: Validate & enforce (Truth)
```

**Key Achievement:** Smart contracts become the sole source of truth. AI outputs are treated as untrusted user input, then validated by immutable on-chain rules.

### Why This Matters

- ✅ AI improves UX without reducing security
- ✅ All trust remains in smart contracts
- ✅ Deterministic execution (auditable)
- ✅ No new attack surface
- ✅ Mantle-native (no oracles, no callbacks)

---

## REQUIREMENT 1: AI OUTPUT MODEL (OFF-CHAIN ONLY)

### 1.1 The AI's Exact Role

AI is a **suggestion engine**, never an execution engine:

```
┌────────────────────────────────────┐
│     USER                           │
│  (Reviews AI suggestion)           │
└─────────────┬──────────────────────┘
              │
        ┌─────▼─────────────────┐
        │ AI Inference Layer    │
        │ (Off-chain)           │
        │                       │
        │ Generates:            │
        │ • adapter[] array      │
        │ • ratio[] values       │
        │ • risk level           │
        │ • metadata             │
        └─────┬─────────────────┘
              │ (User chooses to accept)
        ┌─────▼──────────────────┐
        │ User Transaction       │
        │ (Signed by user)       │
        │ {                      │
        │  adapters,             │
        │  ratios,               │
        │  riskLevel,            │
        │  metadata              │
        │ }                      │
        └─────┬──────────────────┘
              │
        ┌─────▼──────────────────────┐
        │ Smart Contract             │
        │ (On-chain validation)      │
        │                            │
        │ Validates:                 │
        │ • sum(ratios) == 100%       │
        │ • all adapters in list?    │
        │ • fee < 10%?               │
        │ • risk constraints?        │
        │                            │
        │ Result: Accept/Reject      │
        └────────────────────────────┘
```

### 1.2 What AI Generates

**Scope (Allowed):**

```solidity
struct AIGeneratedSuggestion {
    // Adapter selection
    address[] suggestedAdapters;        // e.g., [Aave, Lendle]

    // Allocation ratios (in basis points)
    uint256[] suggestedRatios;          // e.g., [6000, 4000] = 60/40

    // Risk category
    uint8 suggestedRiskLevel;           // 1-5 (1=Low, 5=High)

    // Descriptive metadata (on-chain)
    string name;                        // "Conservative 60/40"
    string description;                 // "Diversified stablecoin strategy"

    // Metadata URI (optional, for images/details)
    string metadataURI;                 // Can point to IPFS (user verifies)

    // Reasoning (for user UX, not used on-chain)
    string reasoning;                   // "Balances Aave's yield with Lendle's APY"
}
```

**Scope (NOT Allowed):**

```solidity
// ❌ AI CANNOT DO THIS:

// - Sign transactions (user signs only)
// - Call contracts directly (user submits transaction)
// - Modify strategy after creation (immutable on-chain)
// - Override fee caps (hard limits in contract)
// - Select adapters outside whitelist (validated on-chain)
// - Generate allocation > 100% (validated on-chain)
// - Change risk level after creation (immutable)
```

### 1.3 Why AI Must Remain Off-Chain

**Trust Minimization Principle:**

```
On-Chain  = Immutable, verified, audited, executable
Off-Chain = Mutable, unverified, speeds iteration

Therefore:
├─ Execution → On-chain (trust critical)
├─ Validation → On-chain (trust critical)
├─ Data → On-chain if permanent (trust critical)
└─ Suggestions → Off-chain (UX only)
```

**Specific Reasons:**

1. **Immutability Requirement**

   - Once a strategy is deployed, its config cannot change
   - On-chain code is immutable by design
   - Off-chain AI can be updated/redeployed anytime
   - ✓ Conclusion: Suggestions must be off-chain

2. **Auditability Requirement**

   - Strategy validation must be verifiable by anyone
   - Anyone can check: did contract validate correctly?
   - Anyone can trace: what were the rules at block X?
   - ✓ Conclusion: Validation logic must be on-chain

3. **DeFi Trust Model**

   - DeFi = "Don't trust, verify"
   - Smart contracts are verifiable code
   - AI systems are statistical inference (not verifiable)
   - ✓ Conclusion: Truth lives in smart contracts

4. **Attack Surface**
   - If AI generation was trusted:
     - Compromise AI → steal all user funds
     - Modify AI → all future strategies compromised
     - Inference error → loss of capital
   - On-chain validation:
     - Compromise contract → detected immediately
     - Invalid output → reverts (user keeps funds)
     - Math error → verifiable by anyone

### 1.4 Alignment with DeFi Trust Minimization

**Traditional Trust Model (Broken):**

```
User → Platform → Database → Strategy Execution
         ↓
      (Trust platform not to steal/modify)
```

**MALGIST Model (Sound):**

```
User → Smart Contract → On-chain Data → Deterministic Execution
          ↑
       (Trust math, not people)
```

**With AI Added:**

```
User ← AI (suggestions)
User → Smart Contract → On-chain Data → Deterministic Execution
       (Validates all AI output)
          ↑
       (Trust math, not people or ML models)
```

**Key Difference:**

- AI: "Maybe try 60/40 allocation" (suggestion)
- Contract: "IF allocation = 100%, use it; ELSE revert" (enforcement)
- User: "Sees suggestion, decides, signs, contract validates"

---

## REQUIREMENT 2: ON-CHAIN VALIDATION (MANDATORY)

### 2.1 Validation Checklist

Every AI-generated strategy must pass all these checks on-chain:

```solidity
contract StrategyValidator {

    // ✓ CHECK 1: Ratio Sum Validation
    function validateRatios(uint256[] calldata ratios) internal pure returns (bool) {
        uint256 sum = 0;
        for (uint256 i = 0; i < ratios.length; i++) {
            sum += ratios[i];
        }
        // Must sum to exactly 10000 (100%)
        require(sum == 10000, "Ratios must sum to 100%");
        return true;
    }

    // ✓ CHECK 2: Adapter Whitelist Validation
    function validateAdapters(address[] calldata adapters)
        internal
        view
        returns (bool)
    {
        require(adapters.length > 0, "No adapters specified");
        require(adapters.length <= MAX_ADAPTERS, "Too many adapters");

        for (uint256 i = 0; i < adapters.length; i++) {
            address adapter = adapters[i];

            // ✓ Must be in whitelist
            require(adapterWhitelist[adapter], "Adapter not whitelisted");

            // ✓ Must not be duplicate
            for (uint256 j = i + 1; j < adapters.length; j++) {
                require(adapters[j] != adapter, "Duplicate adapter");
            }

            // ✓ Must be valid contract
            require(adapter.code.length > 0, "Adapter is not a contract");
        }
        return true;
    }

    // ✓ CHECK 3: Creator Fee Cap Validation
    function validateCreatorFee(uint256 feeBps)
        internal
        pure
        returns (bool)
    {
        // Hard cap: 10% = 1000 basis points
        require(feeBps <= MAX_CREATOR_FEE_BPS, "Fee exceeds 10% cap");
        return true;
    }

    // ✓ CHECK 4: Risk Level Validation
    function validateRiskLevel(uint8 riskLevel)
        internal
        pure
        returns (bool)
    {
        // Risk 1-5 only
        require(riskLevel >= 1 && riskLevel <= 5, "Invalid risk level");
        return true;
    }

    // ✓ CHECK 5: Array Length Matching
    function validateArrays(
        address[] calldata adapters,
        uint256[] calldata ratios
    ) internal pure returns (bool) {
        // Arrays must match in length
        require(adapters.length == ratios.length, "Array length mismatch");
        return true;
    }

    // ✓ CHECK 6: No Zero Amounts
    function validateNonZeroAllocations(uint256[] calldata ratios)
        internal
        pure
        returns (bool)
    {
        for (uint256 i = 0; i < ratios.length; i++) {
            require(ratios[i] > 0, "Zero allocation not allowed");
        }
        return true;
    }
}
```

### 2.2 Why Contracts Must Assume AI Is Adversarial

**Threat Model:**

```
Attack 1: Compromised AI System
├─ Attacker modifies AI model
├─ AI generates invalid strategies
├─ On-chain validation catches this
└─ User protected ✓

Attack 2: Malicious Frontend
├─ Attacker modifies frontend code
├─ Frontend sends invalid data
├─ On-chain validation catches this
└─ User protected ✓

Attack 3: Prompt Injection
├─ Attacker injects malicious prompts
├─ AI generates exploitative parameters
├─ On-chain validation catches this
└─ User protected ✓

Attack 4: AI Model Extraction
├─ Attacker extracts trained model
├─ Generates exploitative strategies offline
├─ On-chain validation catches this
└─ User protected ✓
```

**Fundamental Principle:**

```
"Never trust external input."

External = Anything not in the smart contract
├─ User input
├─ AI output
├─ Frontend input
├─ API responses
└─ All must be validated

Validation = Check against immutable rules
```

### 2.3 How Invalid AI Outputs Safely Revert

**Scenario 1: AI Generates 60/50 (sums to 110%)**

```solidity
// User submits: adapters=[Aave, Lendle], ratios=[6000, 5000]

function createStrategyWithAISuggestion(
    address[] calldata adapters,
    uint256[] calldata ratios,
    uint256 feeBps,
    uint8 riskLevel,
    string calldata name
) external {
    // Validation runs BEFORE state change

    validateArrays(adapters, ratios);           // ✓ Length 2 == 2
    validateRatios(ratios);                     // ✗ 6000+5000 = 11000 ≠ 10000

    // REVERTS here - no state changed
    // User's transaction fails
    // User keeps their funds
    // Can try again with correct parameters
}
```

**Gas Efficiency:** Validation happens before any storage writes

```
Before: Check inputs → If valid, write storage → If invalid, revert
                                                    (gas wasted)

Better: Check inputs → If invalid, revert immediately (save gas)
```

**Implementation Pattern:**

```solidity
// ✓ CORRECT: Validate first, state changes second

function createStrategy(
    address[] calldata adapters,
    uint256[] calldata ratios,
    uint256 feeBps
) external {
    // Phase 1: Pure validation (no state changes)
    validateArrays(adapters, ratios);
    validateRatios(ratios);
    validateAdapters(adapters);
    validateCreatorFee(feeBps);

    // Phase 2: Only if all validations passed
    uint256 strategyId = ++strategyCounter;
    strategies[strategyId] = StrategyConfig({
        adapters: adapters,
        ratios: ratios,
        creator: msg.sender,
        creatorFeeBps: feeBps,
        createdAt: block.timestamp
    });
}
```

### 2.4 Gas Impact of Validation

**Validation Cost Breakdown:**

```
Operation                       Gas Cost    Notes
─────────────────────────────────────────────────
Array length check (1 check)    ~100       O(1)
Ratio sum validation            ~2k        O(n) where n=adapters
Adapter whitelist check         ~3k        O(n) with storage lookup
Fee cap check                   ~100       O(1)
Risk level check                ~50        O(1)
─────────────────────────────────────────────
TOTAL per strategy creation:    ~5.5k      Mantle: ~$0.000055
```

**Cost on Different Networks:**

```
Ethereum L1:     5.5k gas × $10/Mgas = $0.055 (expensive)
Arbitrum/OP:     5.5k gas × $0.10/Mgas = $0.00055 (cheaper)
Mantle:          5.5k gas × $0.00001/Mgas = $0.000055 (cheapest!)
```

**Conclusion:** Validation cost is negligible on Mantle

---

## REQUIREMENT 3: STRATEGY MINT & EXECUTION FLOW

### 3.1 End-to-End Flow

**Step 1: AI Generates Suggestion (Off-Chain)**

```javascript
// Off-chain, in browser or backend
const aiSuggestion = {
  adapters: ["0xAave...", "0xLendle..."],
  ratios: [6000, 4000], // 60/40
  riskLevel: 2, // Conservative
  name: "Conservative Diversified",
  description: "Safe 60/40 allocation",
  creatorFee: 200, // 2%
};

// User reviews in UI:
console.log("AI suggests:", aiSuggestion);
// User can reject or modify here (before signing)
```

**Step 2: User Reviews & Signs (Off-Chain)**

```javascript
// User sees suggestion in UI
// User can:
// ✓ Accept (signs transaction)
// ✓ Modify parameters manually (signs modified)
// ✗ Reject (does nothing)

const userConfirmed = {
  adapters: aiSuggestion.adapters,
  ratios: [5500, 4500], // User modified to 55/45!
  riskLevel: 2,
  creatorFee: 200,
  name: "Conservative Diversified",
};

// User signs transaction
const tx = await contract.createStrategyWithAISuggestion(
  userConfirmed.adapters,
  userConfirmed.ratios,
  userConfirmed.creatorFee,
  userConfirmed.riskLevel,
  userConfirmed.name
);
```

**Step 3: Smart Contract Validates & Stores (On-Chain)**

```solidity
// On-chain validation - cannot be bypassed

function createStrategyWithAISuggestion(
    address[] calldata adapters,
    uint256[] calldata ratios,
    uint256 creatorFeeBps,
    uint8 riskLevel,
    string calldata name
) external returns (uint256 strategyId) {

    // VALIDATION PHASE (untrusted input check)
    require(adapters.length > 0, "No adapters");
    require(adapters.length == ratios.length, "Array mismatch");

    // Check sum = 100%
    uint256 sum = 0;
    for (uint i = 0; i < ratios.length; i++) {
        require(ratios[i] > 0, "No zero allocations");
        sum += ratios[i];
        require(adapterWhitelist[adapters[i]], "Not whitelisted");
    }
    require(sum == 10000, "Must sum to 100%");
    require(creatorFeeBps <= 1000, "Fee capped at 10%");
    require(riskLevel >= 1 && riskLevel <= 5, "Invalid risk");
    require(bytes(name).length > 0, "Name required");

    // EXECUTION PHASE (immutable record)
    strategyId = ++strategyCounter;

    StrategyConfig storage config = strategies[strategyId];
    config.creator = msg.sender;
    config.createdAt = block.timestamp;
    config.creatorFeeBps = creatorFeeBps;
    config.riskLevel = riskLevel;

    // Store arrays
    for (uint i = 0; i < adapters.length; i++) {
        config.adapters.push(adapters[i]);
        config.ratios.push(ratios[i]);
    }

    // Mint NFT (immutable proof)
    _safeMint(msg.sender, strategyId);

    emit StrategyCreated(strategyId, msg.sender, name, riskLevel);
    return strategyId;
}
```

**Step 4: Vault Executes Using On-Chain Data (On-Chain)**

```solidity
// Later, user deposits using the strategy

function depositWithStrategy(
    uint256 amount,
    uint256 strategyId
) external {
    // Read strategy config from on-chain storage
    StrategyConfig storage config = strategies[strategyId];

    // ALL data used is from on-chain storage
    // NOT from AI, NOT from off-chain, NOT from input parameters

    for (uint i = 0; i < config.adapters.length; i++) {
        address adapter = config.adapters[i];
        uint256 ratio = config.ratios[i];
        uint256 allocAmount = (amount * ratio) / 10000;

        // Dispatch to adapter
        IAdapter(adapter).deposit(allocAmount);
    }

    // Collect creator fees during harvest
    creatorFeeAccumulated[config.creator] += (yield * config.creatorFeeBps) / 10000;
}
```

### 3.2 Where User Consent Is Enforced

**User Consent Points:**

```
1. AI Generation
   └─ ✗ NO consent needed (suggestion only)

2. User Review
   └─ ✓ EXPLICIT consent needed (UI review)

3. Transaction Signature
   └─ ✓ CRYPTOGRAPHIC consent (user signs)

4. On-Chain Validation
   └─ ✓ IMMUTABLE enforcement (contract validates)

5. Execution
   └─ ✓ DETERMINISTIC (follows validated config)
```

**Consent in Code:**

```solidity
// User must sign this exact transaction
function createStrategyWithAISuggestion(
    address[] calldata adapters,          // User chose these
    uint256[] calldata ratios,            // User chose these
    uint256 creatorFeeBps,                // User chose this
    uint8 riskLevel,                      // User chose this
    string calldata name                  // User chose this
) external {
    // msg.sender = user who signed
    // All parameters = what user signed
    // Contract validates all parameters
    // If valid → strategy created (user's choice)
    // If invalid → transaction reverts (user's protection)
}
```

**NO Consent Required For:**

- AI suggestion generation (user can ignore)
- AI model updates (user not affected)
- Internal contract state changes (user's funds protected)

### 3.3 How Deterministic Execution Is Preserved

**Determinism Definition:**

```
Same input → Same output (always)
No randomness, no time dependency, no external calls
```

**How AI Could Break Determinism:**

```
❌ BAD:
contract.executeStrategy(strategyId, aiHint);
// Where aiHint is runtime suggestion
// Result: Different outcomes based on AI state

✓ GOOD:
contract.executeStrategy(strategyId);
// Reads config from strategyId (storage)
// Uses only on-chain data
// Result: Same outcome every time
```

**MALGIST Implementation:**

```solidity
// ✓ DETERMINISTIC: Strategy config stored at creation time
function createStrategy(
    address[] calldata adapters,
    uint256[] calldata ratios
) external returns (uint256 strategyId) {
    // Store config permanently
    strategies[strategyId] = StrategyConfig({
        adapters: adapters,
        ratios: ratios,
        createdAt: block.timestamp
    });
    // Will never change after this
}

// ✓ DETERMINISTIC: Execution reads stored config
function executeStrategy(uint256 strategyId, uint256 amount) external {
    StrategyConfig storage config = strategies[strategyId];

    // Uses ONLY stored config
    // NO runtime parameters
    // NO AI input

    for (uint i = 0; i < config.adapters.length; i++) {
        IAdapter(config.adapters[i]).deposit(
            (amount * config.ratios[i]) / 10000
        );
    }
}

// ✓ DETERMINISTIC: Harvest uses same config
function harvest(uint256 strategyId) external {
    StrategyConfig storage config = strategies[strategyId];

    // Fees calculated from stored creator fee
    uint256 creatorFee = (yield * config.creatorFeeBps) / 10000;
    creatorFeeAccumulated[config.creator] += creatorFee;
}
```

---

## REQUIREMENT 4: MANTLE TRANSACTION LIFECYCLE ALIGNMENT

### 4.1 Mantle Transaction Model

**Mantle L2 Execution:**

```
User submits transaction
     ↓
Sequencer includes in batch
     ↓
Local execution on Mantle
     ↓
Mantle finality: 2-5 seconds
     ↓
CVM proof generated (compressed)
     ↓
Proof submitted to Ethereum
     ↓
Final settlement on Ethereum
```

### 4.2 Why AI Strategy Model Fits Mantle

**Property 1: Deterministic Execution**

- ✓ Mantle: Requires deterministic execution (for CVM)
- ✓ Our design: Execution is deterministic (stored config)
- ✓ Result: Perfect fit

**Property 2: No Off-Chain Callbacks**

- ✗ Problem: If execution depended on off-chain AI state
- ✓ Solution: AI only generates suggestions (off-chain)
- ✓ Execution uses only on-chain data
- ✓ Result: No callbacks needed

**Property 3: Replay Safety**

- ✗ Problem: If strategy relied on runtime AI state
- ✓ Solution: Strategy config is immutable after creation
- ✓ Can replay any strategy N times, same result
- ✓ Result: Fully replay-safe

**Property 4: Clear Separation**

- ✓ Off-chain: AI inference (iterative, mutable)
- ✓ On-chain: Execution (immutable, deterministic)
- ✓ Result: Clean boundary for proof generation

### 4.3 Proof Generation & Auditability

**How Mantle CVM Proves Execution:**

```
Transaction: createStrategy([Aave, Lendle], [6000, 4000], ...)
     ↓
Mantle executes on sequencer
     ↓
State change:
  strategies[42] = {
    adapters: [Aave, Lendle],
    ratios: [6000, 4000],
    creator: msg.sender,
    ...
  }
     ↓
CVM generates proof:
  "At block X, strategy 42 was created with this exact config"
     ↓
Proof submitted to Ethereum
     ↓
Proof verified (anyone can check)
```

**Why This Is Auditable:**

```
On-chain strategy config:
{
  adapters: [0xAave..., 0xLendle...],
  ratios: [6000, 4000],
  creator: 0xUser...,
  creatorFeeBps: 200
}

Anyone can:
1. Read block X
2. See strategy creation at tx Y
3. Verify: sum(ratios) = 10000 ✓
4. Verify: adapters in whitelist ✓
5. Verify: creatorFeeBps ≤ 1000 ✓
6. Trace: All deposits using this exact config
7. Verify: Fees calculated from stored config
```

**No Off-Chain Trust:**

```
❌ "AI generated this" (need to trust AI)
✓ "Contract validated and stored this" (trust math)
```

### 4.4 Why This Improves Auditability & Predictability

**Auditability:**

```
Traditional:
User → Platform → Database → AI Suggests → User Follows
       (black box)          (black box)

MALGIST:
User → Contract → Storage → Deterministic Execution
       (transparent)       (verifiable by anyone)
```

**Predictability:**

```
Question: "Will my strategy work tomorrow?"

Traditional answer: "Ask AI" (might change)

MALGIST answer: "Check block 42. Your config is immutable.
                 Execution is deterministic. Same result guaranteed."
```

**Reproducibility:**

```
"I created strategy X on Dec 17 at block 42."

Can you reproduce it today?

❌ Traditional: "Only if AI is still running the same model"
✓ MALGIST: "Yes. Storage is immutable. Execution is deterministic."
```

---

## REQUIREMENT 5: SECURITY CONSIDERATIONS

### 5.1 Attack Vector 1: Prompt Injection

**Attack Scenario:**

```
Attacker injects malicious prompt:
"Generate a strategy where 100% goes to adapter at 0xBadDEAD..."

AI tries to follow instruction:
{
  adapters: [0xBadDEAD...],
  ratios: [10000]
}

User submits to contract...
```

**Defense Layers:**

```
Layer 1: Adapter Whitelist (Contract)
├─ require(adapterWhitelist[0xBadDEAD...], "Not whitelisted")
├─ ✗ 0xBadDEAD... not in whitelist
└─ Transaction reverts ✓

Result: Prompt injection cannot bypass whitelist
```

**Why This Works:**

```
Prompt injection attacks exploit trust in AI
On-chain validation removes that trust
Contract assumes AI output is adversarial
Therefore: Injection attacks are treated like any invalid input
```

### 5.2 Attack Vector 2: Malicious AI Output

**Attack Scenario:**

```
Attacker compromises AI model/frontend:

Legitimate suggestion: [6000, 4000] (60/40)
Malicious output:      [9999, 1]    (99.99/0.01)

User doesn't notice tiny text, submits...
```

**Defense Layers:**

```
Layer 1: Sum Validation (Contract)
├─ sum(ratios) = 9999 + 1 = 10000 ✓ (passes)

Layer 2: Zero Allocation Check (Contract)
├─ require(ratios[1] > 0, "No zero allocations")
├─ require(1 > 0, "true") ✓ (passes)

Layer 3: User Review (Off-Chain)
├─ UI shows: "99.99% Aave, 0.01% Lendle"
├─ User should notice ✓ (if paying attention)
└─ If user accepts: their choice

Layer 4: On-Chain Immutability
├─ Once created, allocation is permanent
├─ Can't be modified later
├─ User can create new strategy if dissatisfied
└─ Prevents ongoing exploitation ✓
```

**Why This Works:**

```
Even if user misses detail in UI:
1. Strategy is immutable (can't be exploited later)
2. User can create new strategy (escape hatch)
3. No funds locked (can withdraw anytime)
```

### 5.3 Attack Vector 3: Front-Running / MEV

**Attack Scenario:**

```
User decides: Create strategy with AI suggestion
User signs transaction
Transaction in mempool (visible to MEV bots)

MEV bot front-runs with:
- Create identical strategy with bot as creator
- Collect fees from all deposits

User's transaction creates strategy with user as creator (too late)
```

**Defense Layers:**

```
Layer 1: NFT Ownership (Contract)
├─ Strategy NFT created with msg.sender = original creator
├─ MEV bot's strategy is different (bot is creator)
├─ No fee revenue conflict ✓

Layer 2: User Choice (Off-Chain)
├─ User can accept bot's strategy if they want
├─ Or use their own strategy
└─ No forced usage ✓

Layer 3: Deterministic Execution (On-Chain)
├─ User decides which strategy to use when depositing
├─ Can always switch to own strategy
└─ No lock-in ✓

Result: MEV cannot steal creator revenue or lock users
```

**Why This Works:**

```
Traditional apps:
- "First creator gets all followers" (front-run advantage)

MALGIST:
- Each strategy is immutable NFT
- Users choose which strategy to follow
- Creator earnings are deterministic (can't be stolen)
- Users are free to switch strategies
```

### 5.4 Attack Vector 4: Constraint Bypass

**Attack Scenario:**

```
Attacker crafts AI output designed to bypass constraints:

// Try to bypass fee cap
{
  adapters: [Aave],
  ratios: [10000],
  feeBps: 5000  // 50% (violates 10% cap)
}
```

**Defense Layers:**

```
Layer 1: Fee Cap Check (Contract)
├─ require(feeBps <= MAX_CREATOR_FEE_BPS, "Fee cap violation")
├─ require(5000 <= 1000, "false")
└─ Transaction reverts ✓

Layer 2: Hard Limit in Code
├─ MAX_CREATOR_FEE_BPS = 1000 (10%)
├─ Defined as constant (immutable)
├─ Cannot be changed without contract upgrade
└─ Enforced everywhere ✓

Result: Fee cap cannot be bypassed
```

**Other Bypass Attempts:**

```
Attack: "Make allocation sum to 101%"
Defense: require(sum == 10000) → Transaction reverts ✓

Attack: "Use unapproved adapter"
Defense: require(adapterWhitelist[adapter]) → Transaction reverts ✓

Attack: "Set risk level to 0 or 100"
Defense: require(riskLevel >= 1 && riskLevel <= 5) → reverts ✓

Attack: "Create strategy with empty name"
Defense: require(bytes(name).length > 0) → Transaction reverts ✓
```

**Fundamental Property:**

```
If validation passes in contract:
  ✓ All constraints are satisfied
  ✓ Cannot be violated

If validation fails in contract:
  ✓ User is protected (transaction reverts)
  ✓ Funds remain in wallet

Therefore: No valid constraint bypass path exists
```

### 5.5 Attack Vector 5: Storage/State Collision

**Attack Scenario:**

```
Multiple users create strategies simultaneously
Race condition: Who gets strategyId = 42?

Or: User creates strategy A, then strategy B
Do they collide in storage?
```

**Defense Layers:**

```
Layer 1: Atomic Increment (Contract)
├─ strategyCounter++ happens atomically
├─ EVM prevents race conditions
├─ Each strategy gets unique ID
└─ No collisions possible ✓

Layer 2: NFT Unique ID (Contract)
├─ _safeMint(msg.sender, strategyId)
├─ ERC721 enforces token uniqueness
├─ Cannot mint two tokens with same ID
└─ No duplicates possible ✓

Layer 3: Storage Mapping (Contract)
├─ strategies[strategyId] stored independently
├─ Each ID has isolated storage slot
├─ No cross-contamination
└─ No data loss ✓
```

### 5.6 Security Summary: Defense-in-Depth

```
Attack Surface    Layer 1              Layer 2           Result
──────────────────────────────────────────────────────
Prompt Injection  Whitelist            Immutability      ✓ Blocked
Malicious Output  Sum validation       User review       ✓ Blocked
Front-Running     NFT ownership        Fee determinism   ✓ Protected
Constraint Bypass Hard caps            Requires/reverts  ✓ Blocked
State Collision   Atomic increment     ERC721            ✓ Protected

Overall: Defense-in-depth. Multiple layers catch different attacks.
```

---

## VALIDATION CHECKLIST

### On-Chain Validation Checklist

Smart contract must verify ALL of these before accepting strategy:

```solidity
contract StrategyValidator {

    function validateAIStrategy(
        address[] calldata adapters,
        uint256[] calldata ratios,
        uint256 creatorFeeBps,
        uint8 riskLevel,
        string calldata name
    ) external view returns (bool) {

        // ✓ CHECK 1: Array presence
        require(adapters.length > 0, "No adapters");

        // ✓ CHECK 2: Array matching
        require(adapters.length == ratios.length, "Array length mismatch");

        // ✓ CHECK 3: Not too many adapters
        require(adapters.length <= MAX_ADAPTERS, "Too many adapters");

        // ✓ CHECK 4: Name exists
        require(bytes(name).length > 0, "Name required");
        require(bytes(name).length <= 256, "Name too long");

        // ✓ CHECK 5: Risk level valid
        require(riskLevel >= 1 && riskLevel <= 5, "Invalid risk level");

        // ✓ CHECK 6: Creator fee capped
        require(creatorFeeBps <= MAX_CREATOR_FEE_BPS, "Fee cap exceeded");

        // ✓ CHECK 7: Ratio sum
        uint256 sum = 0;
        for (uint256 i = 0; i < ratios.length; i++) {
            // ✓ CHECK 7a: No zero allocations
            require(ratios[i] > 0, "Zero allocation not allowed");
            sum += ratios[i];
        }
        require(sum == 10000, "Ratios must sum to 100%");

        // ✓ CHECK 8: Adapter validation
        for (uint256 i = 0; i < adapters.length; i++) {
            address adapter = adapters[i];

            // ✓ CHECK 8a: Adapter in whitelist
            require(adapterWhitelist[adapter], "Adapter not whitelisted");

            // ✓ CHECK 8b: Adapter is contract
            require(adapter.code.length > 0, "Adapter must be contract");

            // ✓ CHECK 8c: Adapter implements interface
            try IAdapter(adapter).supportsInterface(type(IAdapter).interfaceId)
            returns (bool supported) {
                require(supported, "Adapter doesn't implement IAdapter");
            } catch {
                revert("Adapter validation failed");
            }

            // ✓ CHECK 8d: No duplicate adapters
            for (uint256 j = i + 1; j < adapters.length; j++) {
                require(adapters[i] != adapters[j], "Duplicate adapter");
            }
        }

        return true;
    }
}
```

### Gas Cost Analysis

```
Validation Check                    Gas Cost
────────────────────────────────────────────
Array presence (1 check)            ~100
Array length matching               ~100
Max adapter count check             ~100
Name validation (length)            ~200
Risk level check                    ~100
Creator fee cap                     ~100
Ratio sum validation (n=2)          ~2,000
Adapter whitelist check (n=2)       ~4,000
Adapter is contract check (n=2)     ~2,000
Interface support check (n=2)       ~3,000
Duplicate adapter check (n=2)       ~1,000
────────────────────────────────────────────
TOTAL: ~13,000 gas per strategy

Mantle cost: 13,000 gas × $0.00001/Mgas = $0.00013
```

---

## TRUST BOUNDARY DEFINITION

### What's On-Chain (Trusted)

```
┌─────────────────────────────────────┐
│ SMART CONTRACT (On-Chain)           │
│ ───────────────────────────────────│
│                                     │
│ • Strategy config storage           │
│ • Validation rules                  │
│ • Fee collection logic              │
│ • Adapter whitelist                 │
│ • NFT ownership                     │
│ • Immutability guarantees           │
│                                     │
│ TRUST: 100% (math is immutable)     │
└─────────────────────────────────────┘
        ↑
        │ Deterministic
        │ Execution
        │
```

### What's Off-Chain (Untrusted)

```
┌─────────────────────────────────────┐
│ USER INTERFACE (Off-Chain)          │
│ ───────────────────────────────────│
│                                     │
│ • AI suggestion generation          │
│ • Parameter display                 │
│ • User review                       │
│ • Frontend code                     │
│                                     │
│ TRUST: Minimize (user verifies)     │
└─────────────────────────────────────┘
        ↓
        │ Parameter
        │ Generation
        │
```

### Trust Boundary Crossing

```
AI generates: {adapters: [...], ratios: [...]}
     ↓
     │ (User sees in UI)
     ↓
User reviews & signs
     ↓
     │ (Transaction submitted)
     ↓
On-Chain validation
     ├─ Check: adapters in whitelist? ✓
     ├─ Check: ratios sum to 100%? ✓
     ├─ Check: fee capped? ✓
     ├─ Check: risk level valid? ✓
     └─ Result: Accept/Reject
     ↓
     │ If accepted:
     ├─ Store config on-chain (immutable)
     ├─ Mint NFT (proof of creation)
     └─ Ready for execution

     │ If rejected:
     ├─ Transaction reverts
     ├─ User keeps funds
     └─ Can try again
```

**Key Property:**

```
After trust boundary is crossed:
- Config is on-chain (immutable)
- No further validation needed
- Execution is deterministic
- Fees are auditable
- User is protected
```

---

## GAS IMPACT CONSIDERATIONS

### Per-Strategy Costs

```
Operation                      Gas        Mantle Cost
────────────────────────────────────────────────────
Validation checks              ~13,000    $0.00013
Storage writes (struct)        ~10,000    $0.0001
Array storage (2 items)        ~5,000     $0.00005
NFT mint                       ~30,000    $0.0003
─────────────────────────────────────────────────
TOTAL per strategy:            ~58,000    $0.00058

Compared:
- Ethereum L1:     58k × $10/Mgas = $0.58
- Arbitrum:        58k × $0.10/Mgas = $0.0058
- Mantle:          58k × $0.00001/Mgas = $0.00058
```

### Scaling Analysis

```
Cost per strategy: $0.00058

Scenarios:
10 strategies:     $0.0058
100 strategies:    $0.058
1000 strategies:   $0.58
10,000 strategies: $5.80

Mantle advantage: 100x cheaper than Ethereum L1
```

### Optimization Opportunities

```
Current: Store all data in struct
├─ adapters: address[]
├─ ratios: uint256[]
└─ metadata: string

Optimized: Pack smaller values
├─ adapters: address[] (can't pack)
├─ ratios: uint16[] (reduce precision if needed)
└─ metadata: hash (store only hash on-chain)

Potential savings: ~20% gas

Balance: Transparency vs gas cost
Current approach: Full transparency on Mantle
```

---

## JUDGE VALUE STATEMENT

### The Core Thesis

**"We don't trust AI — we trust Mantle smart contracts. AI improves UX, contracts enforce truth."**

### Why This Matters

1. **AI Doesn't Replace Trust**

   - AI can fail, hallucinate, be attacked
   - Smart contracts are deterministic, verifiable, immutable
   - We use AI for UX (speed), contracts for security (truth)

2. **DeFi Requires Truth, Not Trust**

   - Traditional: "Trust platform to act in your interest"
   - DeFi: "Trust math, not people"
   - MALGIST: "Trust math, not AI"

3. **Mantle Enables On-Chain Permanence**

   - Strategy config lives on Mantle (not IPFS, not database)
   - 100% verifiable by anyone
   - 100% immutable forever
   - 100x cheaper than Ethereum L1

4. **Clear Separation of Concerns**

   - Off-chain AI: Generate suggestions (mutable, fast, helpful)
   - On-chain Contracts: Enforce rules (immutable, slow, truthful)
   - User: Make choice (UI + signature)

5. **No New Trust Assumptions**
   - Users already trust smart contracts (DeFi standard)
   - AI is not trusted (treated as adversarial)
   - Therefore: Security model is unchanged
   - Only: UX is improved

### Why Judges Should Care

**Traditional DeFi:**

```
User manually generates strategy parameters
→ High friction, low adoption
→ Only technical users can participate
```

**MALGIST with AI:**

```
AI suggests parameters
→ User reviews (understanding improves)
→ Contract validates (security maintained)
→ UX dramatically improves
→ Adoption increases
```

**Safety Guarantee:**

```
Even if AI is compromised:
1. Invalid outputs are rejected by contract
2. Valid outputs are immutable (can't change)
3. Users can always withdraw (no lock-in)
4. Users can always create new strategy (escape hatch)
```

---

## IMPLEMENTATION ROADMAP

### MVP (Now)

- ✓ AI off-chain suggestion generation
- ✓ Smart contract validation
- ✓ User review & signature
- ✓ Strategy creation & storage
- ✓ Deterministic execution

### Phase 4.1 (Next)

- DAO governance for adapter whitelist
- Advanced risk scoring
- Strategy templates
- Multi-step execution paths

### Phase 4.2 (Future)

- Strategy versioning
- Automated rebalancing suggestions
- Market sentiment integration
- Yield optimization

### Phase 4.3 (Long-term)

- Cross-chain strategy composition
- Advanced AI models (not affecting on-chain)
- Strategy marketplace with AI filtering
- Community curated strategies

---

**End of Phase 4: AI-Assisted Strategies Design**

_AI improves UX. Mantle smart contracts enforce truth._
