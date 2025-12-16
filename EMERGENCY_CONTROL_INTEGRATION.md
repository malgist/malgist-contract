# Emergency Control System - Integration into Existing UserVault

**Guide Version:** 1.0  
**Target Contract:** `src/UserVault.sol`  
**Integration Effort:** ~2 hours

---

## Overview

This guide shows the **minimal changes** needed to add emergency pause functionality to your existing `UserVault.sol`.

### Changes Summary

```
Files Modified:
1. UserVault.sol                  ← Add EmergencyPause inheritance + modifiers
2. src/adapters/FusionXAdapter.sol  ← Add return value validation (optional)
3. src/adapters/LendleAdapter.sol   ← Add return value validation (optional)

Files Added:
1. src/EmergencyPause.sol          ← Paste provided contract
2. test/EmergencyPause.t.sol       ← Paste provided tests
3. Documentation (already provided)

Total Changes: ~20 lines in UserVault, ~5 lines per adapter
```

---

## Step 1: Import EmergencyPause

**Location:** Top of `UserVault.sol`

```solidity
// EXISTING IMPORTS
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IAdapter} from "./interfaces/IAdapter.sol";

// ADD THIS:
import {EmergencyPause} from "./EmergencyPause.sol";
```

---

## Step 2: Update Contract Declaration

**Current:**

```solidity
contract UserVault is ReentrancyGuard {
```

**New:**

```solidity
contract UserVault is ReentrancyGuard, EmergencyPause {
```

---

## Step 3: Update Constructor

**Current:**

```solidity
constructor(address _asset) {
    ASSET = IERC20(_asset);
}
```

**New:**

```solidity
/**
 * @notice Initialize vault with base asset and pause owner
 * @param _asset Address of base asset (USDC)
 * @param _pauseOwner Address authorized to control emergency pause (multisig)
 */
constructor(address _asset, address _pauseOwner)
    EmergencyPause(_pauseOwner)
{
    ASSET = IERC20(_asset);
}
```

---

## Step 4: Add Pause Modifier to deposit()

**Current:**

```solidity
function deposit(uint256 amount)
    external
    nonReentrant
    returns (uint256 shares)
{
```

**New:**

```solidity
function deposit(uint256 amount)
    external
    nonReentrant
    whenDepositsNotPaused        // ← ADD THIS
    returns (uint256 shares)
{
```

---

## Step 5: Add Adapter Operational Check in deposit()

**Location:** In `deposit()` function, after strategy retrieval

**Current:**

```solidity
function deposit(uint256 amount)
    external
    nonReentrant
    whenDepositsNotPaused
    returns (uint256 shares)
{
    if (amount == 0) revert InvalidAmount();

    Strategy storage s = strategies[msg.sender];
    if (s.adapters.length == 0) revert NoStrategySet();

    // Transfer assets from user
    ASSET.safeTransferFrom(msg.sender, address(this), amount);

    // ... rest of deposit logic
}
```

**New:**

```solidity
function deposit(uint256 amount)
    external
    nonReentrant
    whenDepositsNotPaused
    returns (uint256 shares)
{
    if (amount == 0) revert InvalidAmount();

    Strategy storage s = strategies[msg.sender];
    if (s.adapters.length == 0) revert NoStrategySet();

    // ADD THIS: Validate all adapters are operational
    for (uint256 i = 0; i < s.adapters.length; i++) {
        _checkAdapterOperational(s.adapters[i]);
    }

    // Transfer assets from user
    ASSET.safeTransferFrom(msg.sender, address(this), amount);

    // ... rest of deposit logic
}
```

---

## Step 6: Add Pause Check to setStrategy()

**Current:**

```solidity
function setStrategy(
    address[] memory adapters,
    uint16[] memory ratios,
    bool isPublic,
    string memory name,
    uint16 copyFeeBps
) external {
```

**New:**

```solidity
function setStrategy(
    address[] memory adapters,
    uint16[] memory ratios,
    bool isPublic,
    string memory name,
    uint16 copyFeeBps
) external whenStrategyExecutionNotPaused {  // ← ADD THIS
```

**Also add adapter validation after existing checks:**

```solidity
function setStrategy(
    address[] memory adapters,
    uint16[] memory ratios,
    bool isPublic,
    string memory name,
    uint16 copyFeeBps
) external whenStrategyExecutionNotPaused {
    // Existing validations
    if (adapters.length == 0 || adapters.length != ratios.length) {
        revert ArrayLengthMismatch();
    }
    if (copyFeeBps > MAX_COPY_FEE_BPS) {
        revert CopyFeeExceedsMax();
    }

    // ADD THIS: Validate all adapters are operational
    for (uint256 i = 0; i < adapters.length; i++) {
        _checkAdapterOperational(adapters[i]);
    }

    // ... rest of existing logic
}
```

---

## Step 7: Add Pause Check to copyStrategy()

**Current:**

```solidity
function copyStrategy(address creator) external {
```

**New:**

```solidity
function copyStrategy(address creator) external whenStrategyExecutionNotPaused {  // ← ADD THIS
```

---

## Step 8: Update withdraw() (CRITICAL - NO PAUSE CHECK)

**Current:**

```solidity
function withdraw(uint256 shareAmount)
    external
    nonReentrant
    returns (uint256 withdrawn)
{
```

**New:**

```solidity
/**
 * @notice Withdraw assets from user's strategy
 * @param shareAmount Amount of shares to burn
 * @return withdrawn Amount of assets withdrawn
 *
 * CRITICAL: This function is NEVER paused, even during emergency
 * User funds are always accessible
 */
function withdraw(uint256 shareAmount)
    external
    nonReentrant
    withdrawalAlwaysPermitted    // ← ADD THIS (documents: no pause checks)
    returns (uint256 withdrawn)
{
```

---

## Step 9: Add emergencyWithdraw() (Optional but Recommended)

**Add after withdraw() function:**

```solidity
/**
 * @notice Emergency withdrawal (alias for withdraw)
 * @param shareAmount Amount of shares to burn
 * @return withdrawn Amount of assets withdrawn
 *
 * This function is identical to withdraw() but serves as explicit
 * documentation that withdrawals are allowed during emergency pause
 */
function emergencyWithdraw(uint256 shareAmount)
    external
    nonReentrant
    withdrawalAlwaysPermitted
    returns (uint256 withdrawn)
{
    return withdraw(shareAmount);
}
```

---

## Step 10: Update claimCopyFees() (NO PAUSE CHECK)

**Current:**

```solidity
function claimCopyFees() external nonReentrant {
```

**New:**

```solidity
/**
 * @notice Claim accumulated copy fees
 * @dev Copy fees are NOT affected by pause - they represent user earnings
 */
function claimCopyFees() external nonReentrant {  // No pause modifier
```

**Explanation:** No changes needed - already doesn't have pause. Just document intent.

---

## Step 11: Update \_executeDeposit() (OPTIONAL - Return Value Validation)

**Current:**

```solidity
function _executeDeposit(
    address[] memory adapters,
    uint16[] memory ratios,
    uint256 amount
) internal {
    uint256 remaining = amount;

    for (uint256 i = 0; i < adapters.length; i++) {
        uint256 adapterAmount = (amount * ratios[i]) / TOTAL_BPS;
        if (i == adapters.length - 1) {
            adapterAmount = remaining;
        }

        ASSET.forceApprove(adapters[i], adapterAmount);
        IAdapter(adapters[i]).deposit(adapterAmount);

        remaining -= adapterAmount;
    }
}
```

**Enhanced (RECOMMENDED for safety):**

```solidity
function _executeDeposit(
    address[] memory adapters,
    uint16[] memory ratios,
    uint256 amount
) internal {
    uint256 remaining = amount;

    for (uint256 i = 0; i < adapters.length; i++) {
        uint256 adapterAmount = (amount * ratios[i]) / TOTAL_BPS;
        if (i == adapters.length - 1) {
            adapterAmount = remaining;
        }

        ASSET.forceApprove(adapters[i], adapterAmount);

        // ADD THIS: Validate deposit return value
        uint256 shares = IAdapter(adapters[i]).deposit(adapterAmount);
        if (shares == 0) revert AdapterDepositFailed();  // ← Add error

        remaining -= adapterAmount;
    }
}
```

**Add error to contract:**

```solidity
error AdapterDepositFailed();
```

---

## Step 12: Update \_executeWithdraw() (OPTIONAL - Return Value Validation)

**Current:**

```solidity
function _executeWithdraw(
    address[] memory adapters,
    uint16[] memory ratios,
    uint256 shareAmount
) internal returns (uint256 totalWithdrawn) {
    totalWithdrawn = 0;

    for (uint256 i = 0; i < adapters.length; i++) {
        uint256 withdrawAmount = (shareAmount * ratios[i]) / TOTAL_BPS;
        uint256 withdrawn = IAdapter(adapters[i]).withdraw(withdrawAmount);
        totalWithdrawn += withdrawn;
    }
}
```

**Enhanced (RECOMMENDED for safety):**

```solidity
function _executeWithdraw(
    address[] memory adapters,
    uint16[] memory ratios,
    uint256 shareAmount
) internal returns (uint256 totalWithdrawn) {
    totalWithdrawn = 0;

    for (uint256 i = 0; i < adapters.length; i++) {
        uint256 withdrawAmount = (shareAmount * ratios[i]) / TOTAL_BPS;
        uint256 withdrawn = IAdapter(adapters[i]).withdraw(withdrawAmount);

        // ADD THIS: Validate withdraw return value
        if (withdrawn == 0) revert AdapterWithdrawFailed();  // ← Add error

        totalWithdrawn += withdrawn;
    }
}
```

**Add error to contract:**

```solidity
error AdapterWithdrawFailed();
```

---

## Complete Modified Constructor (Reference)

```solidity
/**
 * @notice Initialize vault with base asset and pause owner
 * @param _asset Address of base asset (USDC)
 * @param _pauseOwner Address authorized to control emergency pause (multisig)
 */
constructor(address _asset, address _pauseOwner)
    EmergencyPause(_pauseOwner)
{
    ASSET = IERC20(_asset);
}
```

---

## Testing Your Integration

### Quick Test: Can Deploy

```bash
# Compile
forge build

# Should show: ✓ Build succeeded

# If errors, check:
# 1. EmergencyPause.sol imported correctly
# 2. Constructor signature updated
# 3. Modifiers applied to right functions
```

### Quick Test: Pause Works

```solidity
// In test file:
function test_pause_blocks_deposit() public {
    // Setup user strategy (in normal state)
    // Enable pause
    vault.enableGlobalPause("Test pause");

    // Deposit should fail
    vm.expectRevert(EmergencyPause.DepositsPaused.selector);
    vault.deposit(1000e6);
}

function test_withdrawal_works_during_pause() public {
    // Deposit in normal state
    vault.deposit(1000e6);

    // Enable pause
    vault.enableGlobalPause("Test pause");

    // Withdrawal should succeed
    uint256 withdrawn = vault.withdraw(500e6);
    assert(withdrawn > 0);
}
```

---

## Deployment Configuration

### Before Deployment

```solidity
// Get multisig address (3-of-5 Gnosis Safe)
address MULTISIG = 0x...;  // Your multisig address
address USDC = 0x...;      // USDC address

// Deploy with new constructor
UserVault vault = new UserVault(USDC, MULTISIG);

// Verify
assert(vault.pauseOwner() == MULTISIG);
assert(vault.isGlobalPauseActive() == false);
```

### After Deployment

```solidity
// Test pause functionality
vault.pauseAdapter(adapter1, "Testing pause system");
assert(vault.isAdapterPaused(adapter1));

vault.unpauseAdapter(adapter1);
assert(!vault.isAdapterPaused(adapter1));

// Withdraw during pause
vault.enableGlobalPause("Test");
uint256 withdrawn = vault.withdraw(shares);
assert(withdrawn > 0);
```

---

## Summary of Changes

| Component       | Change                  | Lines         | Impact   |
| --------------- | ----------------------- | ------------- | -------- |
| Import          | Add EmergencyPause      | 1             | Critical |
| Declaration     | Add inheritance         | 1             | Critical |
| Constructor     | Add parameter + call    | 5             | Critical |
| deposit()       | Add modifier + checks   | 2             | High     |
| withdraw()      | Add modifier            | 1             | High     |
| setStrategy()   | Add modifier + checks   | 2             | High     |
| copyStrategy()  | Add modifier            | 1             | High     |
| claimCopyFees() | Document (no change)    | 1             | Low      |
| Adapters        | Return value validation | 5             | Medium   |
| **TOTAL**       |                         | **~20 lines** | **SAFE** |

---

## Validation Checklist

```
Code Changes:
□ EmergencyPause imported
□ Contract inherits from EmergencyPause
□ Constructor updated with pauseOwner
□ deposit() has @whenDepositsNotPaused
□ withdraw() has @withdrawalAlwaysPermitted
□ setStrategy() has @whenStrategyExecutionNotPaused
□ copyStrategy() has @whenStrategyExecutionNotPaused
□ Adapter checks before deposit calls
□ Return value validation added (optional)

Testing:
□ Compiles without errors
□ Unit tests pass
□ deposit() blocked during pause
□ withdraw() works during pause
□ claimCopyFees() works during pause
□ Only pauseOwner can pause
□ Events emitted correctly

Deployment:
□ pauseOwner set to multisig
□ isGlobalPauseActive() == false
□ All adapters operational
□ Pause functionality verified
```

---

## Rollback Plan (If Needed)

If you need to remove emergency pause system:

```bash
# 1. Remove EmergencyPause import
# 2. Remove EmergencyPause from inheritance
# 3. Remove pauseOwner parameter from constructor
# 4. Remove pause modifiers from functions
# 5. Remove pause checks

# Effort: ~1 hour
# Risk: Low (simple removal)
```

---

## Questions?

**Q: Do I have to add pause checks to every function?**  
A: No. Only add to:

- deposit() ← YES
- withdraw() ← NO (critical: never pause)
- setStrategy() ← YES
- copyStrategy() ← YES
- claimCopyFees() ← NO

**Q: Do adapters need to change?**  
A: No. Adapters don't know about pause. Vault handles everything.

**Q: Can I add timelock to pause?**  
A: Yes, after MVP. Current design prioritizes speed (sub-minute response).

**Q: What if I get pause owner address wrong?**  
A: You can't change it (it's immutable). Redeploy vault with correct address.

---

**Integration Effort:** ~2 hours (mostly copy-paste)  
**Testing Effort:** ~1 hour  
**Total:** ~3 hours  
**Risk Level:** LOW (modular, easy to verify)

**Ready to integrate? Start with Step 1! 🚀**
