# MALGIST Faucet - Testnet USDC Distribution

## Overview

The **Faucet** contract is a testnet-only utility for distributing MockUSDC tokens to users in the MALGIST hackathon environment. It is **NOT part of the core protocol** and is excluded from audit scope.

### Design Philosophy

- **Testnet-only**: Chain ID check prevents accidental mainnet deployment
- **Self-contained**: Does not interact with UserVault or core protocol
- **User-friendly**: Rate limiting prevents abuse without blocking legitimate users
- **Auditor-safe**: Clear separation between faucet and core contracts

---

## Architecture

### Contract Stack

```
Faucet.sol          - Main faucet logic (testnet-only)
MockUSDC.sol        - Mintable USDC token (testnet mock)
IFaucet.sol         - Faucet interface (optional, for integrations)
```

### Security Constraints

1. **Chain ID Enforcement**

   - Only callable on Mantle testnet (Chain ID 5003)
   - `NotTestnet` error on mainnet/other chains
   - Prevents accidental mainnet deployment

2. **Rate Limiting**

   - Default: 1 claim per 24 hours per address
   - Configurable by admin (1 sec - 30 days)
   - Tracks `lastClaimTime` and `totalClaimed` per address

3. **Claim Amount Limits**

   - Default: 1000 USDC per claim
   - Maximum: 10,000 USDC per claim
   - Prevents griefing and single-request vault abuse

4. **Reentrancy Protection**

   - `ReentrancyGuard` prevents callback attacks
   - Checks-effects-interactions pattern followed
   - State updated before external transfers

5. **Minter Authorization** (MockUSDC)
   - Only authorized addresses can mint
   - Faucet added as minter during deployment
   - Prevents unauthorized token creation

---

## Contract Interfaces

### Faucet.sol

#### Public Functions

```solidity
/// @notice User claims USDC tokens
function claim() external onlyTestnet nonReentrant
```

**Access**: Public  
**Rate Limit**: 1 per 24 hours (default)  
**Requirements**:

- Chain ID must be 5003 (testnet)
- User must wait `cooldownPeriod` since last claim
- Faucet must have sufficient balance

**Effects**:

- Updates `lastClaimTime[user]`
- Increments `totalClaimed[user]`
- Transfers `claimAmount` to user
- Emits `Claimed` event

---

#### Admin Functions

```solidity
/// @notice Update claim amount
function setClaimAmount(uint256 newAmount) external onlyOwner
```

- Max: 10,000 USDC (prevents DoS)
- Emits `ClaimAmountUpdated` event

```solidity
/// @notice Update cooldown between claims
function setCooldownPeriod(uint256 newCooldown) external onlyOwner
```

- Range: 1 sec - 30 days
- Emits `CooldownUpdated` event

```solidity
/// @notice Withdraw tokens from faucet
function withdraw(address recipient, uint256 amount) external onlyOwner onlyTestnet
```

- Only on testnet
- Transfers to recipient
- Emits `Withdrawn` event

---

#### View Functions

```solidity
/// @notice Get time (in seconds) until user can claim again
function getTimeUntilClaim(address user) external view returns (uint256)
```

Returns 0 if user can claim immediately.

```solidity
/// @notice Check if user can claim now
function canClaim(address user) external view returns (bool)
```

Returns `true` if `cooldownPeriod` has elapsed since last claim.

```solidity
/// @notice Get faucet state (balance, claim amount, cooldown)
function getFaucetState() external view returns (uint256, uint256, uint256)
```

Useful for frontend UI state initialization.

---

### MockUSDC.sol

#### Public Functions

```solidity
/// @notice Grant minting rights to address
function addMinter(address minter) external onlyOwner
```

```solidity
/// @notice Revoke minting rights
function removeMinter(address minter) external onlyOwner
```

```solidity
/// @notice Mint tokens (only authorized minters)
function mint(address to, uint256 amount) external
```

---

## Deployment

### Step 1: Deploy MockUSDC

```solidity
MockUSDC usdc = new MockUSDC();
```

### Step 2: Add Faucet as Minter

```solidity
address faucetAddress = 0x...; // Deploy faucet first, then add as minter
usdc.addMinter(faucetAddress);
```

### Step 3: Deploy Faucet

```solidity
Faucet faucet = new Faucet(address(usdc));
```

### Step 4: Seed Faucet with Tokens

```solidity
// Mint initial supply to faucet
usdc.mint(address(faucet), 1000000e6); // 1M USDC
```

### Step 5: Verify Testnet Chain ID

```bash
# Run on Mantle testnet (5003)
forge create src/Faucet.sol:Faucet \
  --rpc-url https://rpc.sepolia.mantle.xyz \
  --constructor-args <USDC_ADDRESS> \
  --private-key $PRIVATE_KEY
```

---

## Frontend Integration

### Example: React Hook

```typescript
import { useContractRead, useContractWrite } from "wagmi";
import { FAUCET_ABI, FAUCET_ADDRESS } from "./config";

export function useFaucet() {
  // Get faucet state
  const { data: state } = useContractRead({
    address: FAUCET_ADDRESS,
    abi: FAUCET_ABI,
    functionName: "getFaucetState",
  });

  // Check if can claim
  const { data: canClaim } = useContractRead({
    address: FAUCET_ADDRESS,
    abi: FAUCET_ABI,
    functionName: "canClaim",
    args: [userAddress],
  });

  // Get time until next claim
  const { data: timeUntilClaim } = useContractRead({
    address: FAUCET_ADDRESS,
    abi: FAUCET_ABI,
    functionName: "getTimeUntilClaim",
    args: [userAddress],
  });

  // Claim tokens
  const { write: claim, isLoading } = useContractWrite({
    address: FAUCET_ADDRESS,
    abi: FAUCET_ABI,
    functionName: "claim",
  });

  return { state, canClaim, timeUntilClaim, claim, isLoading };
}
```

### UI Components

```typescript
export function FaucetButton() {
  const { canClaim, timeUntilClaim, claim, isLoading } = useFaucet();

  if (!canClaim) {
    return (
      <button disabled>Claim Available in {formatTime(timeUntilClaim)}</button>
    );
  }

  return (
    <button onClick={() => claim()} disabled={isLoading}>
      {isLoading ? "Claiming..." : "Claim 1000 USDC"}
    </button>
  );
}
```

---

## Security Assumptions

### What This Contract Protects Against

✅ **Mainnet Deployment**: Chain ID check prevents production mistakes  
✅ **Spam/DoS**: Rate limiting and max claim amount prevent abuse  
✅ **Reentrancy**: Guard protects against callback attacks  
✅ **Unauthorized Minting**: Only faucet can mint USDC  
✅ **Vault Griefing**: Faucet never mints to vault contracts

### What This Contract Does NOT Protect Against

❌ **Admin Key Compromise**: Owner can drain faucet or modify parameters  
❌ **Token Mint Inflation**: Faucet admin can mint arbitrary USDC amounts  
❌ **Testnet Fork Attacks**: Chain ID check can be bypassed on forked testnets

⚠️ **These are acceptable risks for a testnet-only faucet**

---

## Testing

### Run All Tests

```bash
forge test test/Faucet.t.sol -v
```

### Run Specific Test Suite

```bash
# Test basic claiming
forge test test/Faucet.t.sol::FaucetTest::test_ClaimSuccessful -v

# Test rate limiting
forge test test/Faucet.t.sol::FaucetTest::test_CannotClaimTwiceWithinCooldown -v

# Test testnet enforcement
forge test test/Faucet.t.sol::FaucetTest::test_CannotClaimOnMainnet -v
```

### Test Coverage

- ✅ Basic claim flow
- ✅ Rate limiting enforcement
- ✅ Cooldown tracking
- ✅ Admin configuration
- ✅ Withdrawal functionality
- ✅ Testnet-only enforcement
- ✅ Reentrancy protection
- ✅ State consistency

---

## Gas Optimization Notes

- `claim()`: ~50,000 gas (single claim, no storage conflicts)
- `setClaimAmount()`: ~25,000 gas (admin only)
- `getTimeUntilClaim()`: ~2,000 gas (view, no storage)

All operations are optimized for hackathon environment where gas costs are subsidized.

---

## Audit & Disclosure

### Scope Exclusion

This faucet is **explicitly excluded** from the MALGIST core protocol audit. Reasons:

1. **Testnet-only**: Not deployed to production
2. **Separate concern**: Does not touch core vault logic
3. **Admin-controlled**: Designed for demo/hackathon use
4. **Low security risk**: No real funds involved

### Recommendations for Auditors

- Do **not** audit this contract as part of core protocol review
- Verify chain ID checks in deployment documentation
- Confirm faucet is removed before mainnet launch
- Validate MockUSDC is testnet-only

---

## Deployment Checklist for Hackathon

- [ ] Deploy MockUSDC
- [ ] Set faucet as minter
- [ ] Deploy Faucet pointing to MockUSDC
- [ ] Seed faucet with 1M USDC tokens
- [ ] Test claim on testnet (chain ID 5003)
- [ ] Verify fails on mainnet/other chains
- [ ] Update frontend with faucet address
- [ ] Test complete user flow (claim → approve → deposit to vault)
- [ ] Document faucet address in frontend config
- [ ] Add faucet disclaimer to UI ("Testnet Only")

---

## Summary

The Faucet contract provides a **simple, secure, testnet-only mechanism** for distributing test USDC to hackathon participants. It maintains clear separation from the core MALGIST protocol while providing smooth UX for demo purposes.

**Key Features**:

- ✅ Testnet-enforced (chain ID 5003)
- ✅ Rate-limited (1 claim per 24 hours)
- ✅ Admin-configurable (claim amount, cooldown)
- ✅ Reentrancy-safe
- ✅ Zero interaction with UserVault
- ✅ Audit-excluded (testnet-only)
