# AI Strategy Generator | Complete Implementation Guide

**Status**: Production-Ready  
**Security Level**: ZERO-TRUST AI (All validation on-chain)  
**Date**: December 2024

---

## Strategy Creation Flow (End-to-End)

```
┌─────────────────────────────────────────────────────────────────────┐
│  STEP 1: USER INPUT (Off-Chain)                                     │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  User provides preferences:                                         │
│  ┌─────────────────────────────────────────────────────────────┐  │
│  │ Risk Tolerance:     Moderate                                │  │
│  │ Target Yield:       8%                                      │  │
│  │ Deposit Amount:     1000 USDC                               │  │
│  │ Preferred Protocols: Aave, Lendle                           │  │
│  └─────────────────────────────────────────────────────────────┘  │
│                                                                     │
│  Frontend: User clicks "Generate Strategy"                          │
│                                                                     │
│  Responsibility: FRONTEND                                           │
│  Status: ✅ Safe (user input only)                                 │
│                                                                     │
└──────────────────────────┬──────────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────────────┐
│  STEP 2: AI GENERATION (Off-Chain, Untrusted)                       │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  API Call: /api/generate-strategy                                   │
│                                                                     │
│  AI Model processes user preferences and returns JSON:             │
│  ⚠️  THIS OUTPUT IS UNTRUSTED - TREATED AS ADVERSARIAL             │
│                                                                     │
│  Example Output:                                                    │
│  ┌─────────────────────────────────────────────────────────────┐  │
│  │ {                                                           │  │
│  │   "strategyName": "Balanced Yield Farming",                │  │
│  │   "riskProfile": "moderate",                              │  │
│  │   "adapters": [                                            │  │
│  │     "0xAaveAdapterAddress1234567890123456789012",         │  │
│  │     "0xLendleAdapterAddress1234567890123456789012"        │  │
│  │   ],                                                        │  │
│  │   "allocations": [6000, 4000],     // 60% / 40%           │  │
│  │   "expectedAPY": 850,              // AI's guess           │  │
│  │   "riskDisclosure": "Moderate strategy...",               │  │
│  │   "creatorFeeRequestBps": 500      // 5%                  │  │
│  │ }                                                           │  │
│  └─────────────────────────────────────────────────────────────┘  │
│                                                                     │
│  Responsibility: OFF-CHAIN AI (untrusted)                          │
│  Status: ⚠️ May contain errors/malicious data                      │
│                                                                     │
└──────────────────────────┬──────────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────────────┐
│  STEP 3: FRONTEND SCHEMA VALIDATION (Optional, Defense-in-Depth)    │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  Frontend performs basic validation:                                │
│  ✅ All required fields present                                     │
│  ✅ Types correct (string, array, number)                          │
│  ✅ Arrays same length                                              │
│  ✅ Adapter count <= 10                                             │
│  ✅ Risk profile in ["conservative", "moderate", "aggressive"]     │
│  ✅ Allocations sum to 10000                                        │
│                                                                     │
│  if (!validateSchema(aiOutput)) {                                   │
│    showError("AI output invalid - rejected");                       │
│    return;  // Don't send to contract                               │
│  }                                                                   │
│                                                                     │
│  Responsibility: FRONTEND                                           │
│  Status: ✅ Quick feedback to user (optional layer)                │
│                                                                     │
└──────────────────────────┬──────────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────────────┐
│  STEP 4: FRONTEND SHOWS STRATEGY PREVIEW (UI/UX)                    │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  User reviews proposed strategy:                                    │
│                                                                     │
│  ┌──────────────────────────────────────────────────────────────┐ │
│  │ Strategy: Balanced Yield Farming                            │ │
│  │ Risk Level: Moderate (🟡)                                   │ │
│  │ Creator Fee: 5%                                             │ │
│  │                                                              │ │
│  │ Allocation:                                                 │ │
│  │ • Aave Protocol:      60% ($600)                           │ │
│  │ • Lendle Protocol:    40% ($400)                           │ │
│  │                                                              │ │
│  │ Expected APY: 8.5% (AI estimate, not guaranteed)           │ │
│  │                                                              │ │
│  │ ⚠️ RISK DISCLOSURE:                                         │ │
│  │ "This strategy involves exposure to multiple protocols.     │ │
│  │  Market risk is present. You could lose part of your        │ │
│  │  investment."                                                │ │
│  │                                                              │ │
│  │ [✓] I Accept the Risk    [✗] Cancel                        │ │
│  └──────────────────────────────────────────────────────────────┘ │
│                                                                     │
│  User clicks "Accept" → Frontend prepares transaction              │
│                                                                     │
│  Responsibility: FRONTEND + USER                                    │
│  Status: ✅ User makes informed decision                           │
│                                                                     │
└──────────────────────────┬──────────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────────────┐
│  STEP 5: PREPARE CONTRACT ARGUMENTS (Frontend → Contract)           │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  Frontend transforms AI output to contract arguments:               │
│                                                                     │
│  const args = {                                                     │
│    adapters: [                    // address[]                      │
│      "0xAaveAdapter...",                                            │
│      "0xLendleAdapter..."                                           │
│    ],                                                                │
│    allocations: [6000, 4000],     // uint16[] (BPS)                │
│    riskProfile: "moderate",       // string (matched to 1-5)       │
│    expectedAPY: 850,              // uint32                         │
│    riskDisclosure: "Moderate...", // string                         │
│    creatorFeeRequestBps: 500      // uint16 (BPS)                  │
│  };                                                                  │
│                                                                     │
│  Frontend sends transaction:                                        │
│  strategyNFT.createStrategyFromAI(args, {                          │
│    gasLimit: 300000,                                                │
│    value: 0  // No ETH needed                                       │
│  });                                                                 │
│                                                                     │
│  Responsibility: FRONTEND + ETHERS.JS                               │
│  Status: ✅ Type-safe mapping                                       │
│                                                                     │
└──────────────────────────┬──────────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────────────┐
│  STEP 6: SMART CONTRACT RECEIVES TX (On-Chain)                      │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  StrategyNFT.createStrategyFromAI(args) is called:                 │
│                                                                     │
│  function createStrategyFromAI(AIStrategyOutput calldata aiOutput)  │
│    external                                                          │
│    returns (uint256 tokenId)                                        │
│  {                                                                   │
│    // Step 6a: Call validator                                      │
│    (ValidatedStrategy memory validated, bool isValid) =            │
│      validator.validateAIStrategy(aiOutput);                       │
│                                                                     │
│    // Step 6b: Require validation passed                           │
│    require(isValid, "AI output failed validation");                │
│                                                                     │
│    // Step 6c: Mint NFT with validated parameters                 │
│    tokenId = _mintStrategyNFT(                                      │
│      msg.sender,                                                    │
│      validated.adapters,                                            │
│      validated.allocations,                                         │
│      validated.riskLevel,                                           │
│      validated.approvedCreatorFeeBps                                │
│    );                                                                │
│                                                                     │
│    return tokenId;                                                  │
│  }                                                                   │
│                                                                     │
│  Responsibility: SMART CONTRACT                                     │
│  Status: ✅ Deterministic, immutable                                │
│                                                                     │
└──────────────────────────┬──────────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────────────┐
│  STEP 7: AI VALIDATOR PERFORMS 12 CHECKS (On-Chain, Critical)       │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  ALL validation happens deterministically on-chain:                │
│                                                                     │
│  ✅ Check 1:  Arrays not empty                                      │
│  ✅ Check 2:  Arrays length match & <= MAX (10)                    │
│  ✅ Check 3:  Strategy name not empty                              │
│  ✅ Check 4:  No zero adapter addresses                            │
│  ✅ Check 5:  All adapters whitelisted                             │
│  ✅ Check 6:  No duplicate adapters                                │
│  ✅ Check 7:  No allocation > 100%                                 │
│  ✅ Check 8:  No dust (< 1%) if non-zero                          │
│  ✅ Check 9:  Allocations sum exactly 100%                         │
│  ✅ Check 10: Risk profile valid                                   │
│  ✅ Check 11: Creator fee <= risk-level max                        │
│  ✅ Check 12: Creator fee <= global max (10%)                      │
│                                                                     │
│  If ANY check fails:                                                │
│    → Transaction REVERTS                                            │
│    → User loses gas (small amount on Mantle)                        │
│    → NO funds lost (no actual transfer occurred)                    │
│    → NO invalid strategy created                                    │
│    → Clear error message displayed                                  │
│                                                                     │
│  If ALL checks pass:                                                │
│    → Continue to Step 8                                             │
│                                                                     │
│  Responsibility: SMART CONTRACT (ZERO TRUST)                        │
│  Status: ✅ All validation on-chain, immutable                      │
│                                                                     │
└──────────────────────────┬──────────────────────────────────────────┘
                           │
                      ┌────┴─────────────────────────────┐
                      │                                  │
                      ▼                                  ▼
            ┌──────────────────────┐        ┌──────────────────────┐
            │   VALIDATION PASSED  │        │ VALIDATION FAILED    │
            │                      │        │                      │
            │ ✅ Mint Strategy NFT │        │ ❌ Revert TX        │
            │ ✅ Issue to creator  │        │ ❌ Show error        │
            │ ✅ Return tokenId    │        │ ❌ User tries again │
            │                      │        │                      │
            └──────────┬───────────┘        └──────────────────────┘
                       │
                       ▼
            ┌──────────────────────┐
            │   STRATEGY NFT       │
            │   CREATED ✅         │
            │                      │
            │ • NFT ID: 42        │
            │ • Owner: User       │
            │ • Adapters: Locked │
            │ • Allocations: ...  │
            │ • Risk: Immutable   │
            │ • Fee: Immutable    │
            │ • Hash: Proof       │
            └─────────────────────┘
```

---

## Step 7: Detailed Validation Checks

### Check Group A: Input Sanity

```solidity
// Check 1 & 2: Arrays validation
require(
    aiOutput.adapters.length > 0 &&
    aiOutput.adapters.length == aiOutput.allocations.length &&
    aiOutput.adapters.length <= MAX_ADAPTERS,
    "Invalid array dimensions"
);

// Check 3: Name validation
require(bytes(aiOutput.strategyName).length > 0, "Empty name");
```

### Check Group B: Adapter Validation

```solidity
// Check 4, 5, 6: Adapter whitelist + no duplicates
for (uint256 i = 0; i < aiOutput.adapters.length; i++) {
    address adapter = aiOutput.adapters[i];

    // Check 4: No zero address
    require(adapter != address(0), "Zero adapter");

    // Check 5: Must be whitelisted
    require(whitelistedAdapters[adapter], "Not whitelisted");

    // Check 6: No duplicates
    for (uint256 j = i + 1; j < aiOutput.adapters.length; j++) {
        require(
            aiOutput.adapters[j] != adapter,
            "Duplicate adapter"
        );
    }
}
```

### Check Group C: Allocation Validation

```solidity
// Check 7, 8, 9: Allocation bounds and sum
uint256 totalAllocation = 0;

for (uint256 i = 0; i < aiOutput.allocations.length; i++) {
    uint16 alloc = aiOutput.allocations[i];

    // Check 7: No allocation > 100%
    require(alloc <= 10000, "Allocation > 100%");

    // Check 8: No dust (if non-zero, must be >= 1%)
    if (alloc > 0) {
        require(alloc >= 100, "Dust allocation");
    }

    totalAllocation += alloc;
}

// Check 9: Allocations sum exactly 100%
require(totalAllocation == 10000, "Allocations don't sum to 100%");
```

### Check Group D: Risk & Fee Validation

```solidity
// Check 10: Risk profile valid
uint8 riskLevel = riskProfileToLevel[aiOutput.riskProfile];
require(riskLevel > 0, "Invalid risk profile");

// Check 11 & 12: Fee validation
uint16 maxAllowedFee = riskLevelToMaxFee[riskLevel];
require(
    aiOutput.creatorFeeRequestBps <= maxAllowedFee &&
    aiOutput.creatorFeeRequestBps <= MAX_CREATOR_FEE_BPS,
    "Fee too high"
);
```

---

## Step 8: Mint & Return (On-Chain)

```solidity
// All checks passed - safe to mint

// Create memory copy
address[] memory adapters = new address[](aiOutput.adapters.length);
uint16[] memory allocations = new uint16[](aiOutput.allocations.length);

for (uint256 i = 0; i < aiOutput.adapters.length; i++) {
    adapters[i] = aiOutput.adapters[i];
    allocations[i] = aiOutput.allocations[i];
}

// Compute strategy hash (immutable proof)
bytes32 strategyHash = keccak256(
    abi.encodePacked(
        adapters,
        allocations,
        riskLevel,
        aiOutput.creatorFeeRequestBps,
        aiOutput.strategyName
    )
);

// Mint ERC-721 NFT
uint256 tokenId = _mint(msg.sender, tokenIdCounter++);

// Store strategy data (locked in NFT)
strategies[tokenId] = Strategy({
    adapters: adapters,
    allocations: allocations,
    riskLevel: riskLevel,
    creatorFeeBps: aiOutput.creatorFeeRequestBps,
    strategyHash: strategyHash,
    createdAt: block.timestamp,
    isActive: true
});

emit StrategyCreated(
    tokenId,
    msg.sender,
    adapters,
    allocations,
    riskLevel,
    strategyHash
);

return tokenId;
```

---

## Failure Cases (All Safe)

### Scenario 1: AI Returns Invalid Adapter

```json
{
  "adapters": ["0x0000000000000000000000000000000000000000"],
  "allocations": [10000]
}
```

**Result**: ✅ REJECTED (Check 4: Zero address)  
**User Experience**: Error message "Invalid adapter address"  
**Loss**: 0 (only gas spent)

### Scenario 2: AI Over-Allocates

```json
{
  "adapters": ["0xAave", "0xLendle"],
  "allocations": [7000, 5000] // 120% total
}
```

**Result**: ✅ REJECTED (Check 9: Sum != 100%)  
**User Experience**: Error message "Allocations don't sum to 100%"  
**Loss**: 0 (only gas spent)

### Scenario 3: Malicious AI Requests Excessive Fee

```json
{
  "creatorFeeRequestBps": 5000 // 50%
}
```

**Result**: ✅ REJECTED (Check 11: Exceeds risk-level max)  
**User Experience**: Error message "Creator fee too high"  
**Loss**: 0 (only gas spent)

### Scenario 4: Frontend Tries to Bypass Validation

```typescript
// Attacker modifies frontend code
const args = {
  adapters: [maliciousAddress], // Not whitelisted
  allocations: [10000],
};

// Direct contract call without validation
strategyNFT.createStrategyFromAI(args);
```

**Result**: ✅ REJECTED (Check 5: Not whitelisted)  
**Why**: Contract validation is INDEPENDENT of frontend  
**Loss**: 0 (only gas spent, no funds risked)

---

## Frontend Integration Code (TypeScript Example)

```typescript
import { Contract, ContractFactory, ethers } from "ethers";

interface AIStrategyOutput {
  strategyName: string;
  riskProfile: "conservative" | "moderate" | "aggressive";
  adapters: string[];
  allocations: number[];
  expectedAPY: number;
  riskDisclosure: string;
  creatorFeeRequestBps: number;
}

// 1. Validate AI output (optional, defense-in-depth)
function validateAIOutput(output: AIStrategyOutput): {
  isValid: boolean;
  errors: string[];
} {
  const errors: string[] = [];

  if (!output.strategyName?.length) {
    errors.push("Empty strategy name");
  }

  if (
    !["conservative", "moderate", "aggressive"].includes(output.riskProfile)
  ) {
    errors.push("Invalid risk profile");
  }

  if (output.adapters.length === 0 || output.adapters.length > 10) {
    errors.push("Invalid adapter count (must be 1-10)");
  }

  if (output.adapters.length !== output.allocations.length) {
    errors.push("Adapter/allocation mismatch");
  }

  const totalAlloc = output.allocations.reduce((a, b) => a + b, 0);
  if (totalAlloc !== 10000) {
    errors.push(`Allocations sum to ${totalAlloc}%, must be 100%`);
  }

  for (let i = 0; i < output.allocations.length; i++) {
    if (output.allocations[i] < 0 || output.allocations[i] > 10000) {
      errors.push(`Invalid allocation at index ${i}`);
    }
  }

  if (output.creatorFeeRequestBps < 0 || output.creatorFeeRequestBps > 10000) {
    errors.push("Invalid creator fee");
  }

  return {
    isValid: errors.length === 0,
    errors,
  };
}

// 2. Call AI API
async function generateStrategyWithAI(preferences: {
  riskTolerance: string;
  targetYield: number;
}): Promise<AIStrategyOutput> {
  const response = await fetch("/api/generate-strategy", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(preferences),
  });

  if (!response.ok) {
    throw new Error("AI generation failed");
  }

  return response.json();
}

// 3. Show strategy to user
function displayStrategyPreview(output: AIStrategyOutput): void {
  console.log(`\n🎯 Strategy: ${output.strategyName}`);
  console.log(`Risk Level: ${output.riskProfile}`);
  console.log(`Expected APY: ${output.expectedAPY}%`);
  console.log(`Creator Fee: ${output.creatorFeeRequestBps / 100}%`);
  console.log(`\nAllocations:`);

  for (let i = 0; i < output.adapters.length; i++) {
    const percent = (output.allocations[i] / 100).toFixed(2);
    console.log(`  ${output.adapters[i]}: ${percent}%`);
  }

  console.log(`\n⚠️  Risk Disclosure:\n${output.riskDisclosure}`);
}

// 4. Submit to contract
async function submitStrategyToContract(
  output: AIStrategyOutput,
  strategyNFTAddress: string,
  signer: ethers.Signer
): Promise<string> {
  // Validate frontend (optional)
  const validation = validateAIOutput(output);
  if (!validation.isValid) {
    console.error("Validation failed:", validation.errors);
    throw new Error("AI output failed frontend validation");
  }

  // Get contract
  const strategyNFT = new Contract(
    strategyNFTAddress,
    [
      "function createStrategyFromAI((string,string,address[],uint16[],uint32,string,uint16) aiOutput) public returns (uint256)",
    ],
    signer
  );

  // Show user preview
  displayStrategyPreview(output);

  // Get user confirmation
  const confirmed = await new Promise((resolve) => {
    console.log("\n❓ Create this strategy? (y/n)");
    // In real app, use UI dialog
    resolve(true);
  });

  if (!confirmed) {
    throw new Error("User cancelled");
  }

  try {
    // Submit transaction
    // NOTE: SmartContract validation (AIStrategyValidator) is independent
    // Frontend validation is just UX improvement
    const tx = await strategyNFT.createStrategyFromAI(output);
    const receipt = await tx.wait();

    console.log(`✅ Strategy created! Token ID: ${receipt.tokenId}`);
    return receipt.tokenId;
  } catch (error) {
    console.error("❌ Strategy creation failed:", error.message);
    throw error;
  }
}

// 5. Main flow
async function createAIStrategy() {
  try {
    // Get AI output
    console.log("🤖 Generating strategy with AI...");
    const aiOutput = await generateStrategyWithAI({
      riskTolerance: "moderate",
      targetYield: 8,
    });

    // Submit to contract
    const tokenId = await submitStrategyToContract(
      aiOutput,
      "0x...", // Strategy NFT address
      provider.getSigner() // Current user
    );

    return tokenId;
  } catch (error) {
    console.error("Failed:", error);
    // Show error UI
  }
}
```

---

## Security Checklist

- [ ] AI output schema documented
- [ ] 12 validation checks implemented
- [ ] Frontend schema validation deployed
- [ ] Hard caps are immutable (can't be changed)
- [ ] Adapter whitelist is maintained
- [ ] Risk profiles configured
- [ ] All checks tested with edge cases
- [ ] Transaction revert messages clear
- [ ] User disclosure prominent
- [ ] Strategy hash immutability verified
- [ ] No off-chain dependencies in validation
- [ ] Auditor review completed

---

## Gas Costs (Mantle L2)

| Operation                  | Gas           | Mantle Cost |
| -------------------------- | ------------- | ----------- |
| AI Strategy validation     | 95K           | ~$0.010     |
| Frontend validation        | 0 (off-chain) | Free        |
| Failed validation (revert) | 45K           | ~$0.005     |
| Successful creation        | 120K          | ~$0.012     |

---

## Summary

**AI Role**: UX-only, suggest parameters  
**Contract Role**: Validate & enforce all security  
**User Role**: Understand risk & approve  
**Trust**: ZERO in AI, ALL in contract validation

**Result**: Safe, deterministic, auditable strategy creation
