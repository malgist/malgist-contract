# MALGIST Code Compatibility Analysis

**Status**: 🔴 CRITICAL ISSUES IDENTIFIED  
**Date**: December 17, 2025  
**Test Results**: 130/152 tests passing (85.5% pass rate)  
**Failing Tests**: 22 failures across 6 test suites

---

## Executive Summary

The MALGIST codebase has **multiple compatibility and integration issues** that must be resolved before external audit:

| Category                       | Status     | Impact                                             | Severity |
| ------------------------------ | ---------- | -------------------------------------------------- | -------- |
| **Solidity Version**           | ✅ PASS    | All contracts use `^0.8.20` consistently           | GREEN    |
| **OpenZeppelin Compatibility** | ✅ PASS    | All imports properly aliased via remappings.txt    | GREEN    |
| **Interface Implementation**   | ❌ FAIL    | Some adapters don't fully implement IAdapter       | RED      |
| **ERC20 Approval Handling**    | ❌ FAIL    | SafeERC20 compatibility issues in adapter tests    | RED      |
| **Error Type Mismatches**      | ❌ FAIL    | Custom errors vs. built-in ERC20 errors            | RED      |
| **State Initialization**       | ❌ FAIL    | Mock contract and registry initialization problems | RED      |
| **Test Suite Integration**     | ⚠️ PARTIAL | Many tests fail due to setup/dependency issues     | YELLOW   |

---

## Part 1: Compiler & Dependency Compatibility ✅ PASS

### Solidity Version Consistency

```toml
[profile.default]
src = "src"
libs = ["lib"]
optimizer = true
optimizer_runs = 200
via_ir = true
```

**Finding**: All contracts uniformly use `pragma solidity ^0.8.20`

- ✅ UserVault.sol
- ✅ FusionXAdapter.sol
- ✅ LendleAdapter.sol
- ✅ UniversalVault.sol
- ✅ All supporting contracts

**Compatibility**: Full compatibility with Solidity ^0.8.20 semantics

### OpenZeppelin Library Integration

```
@openzeppelin/=lib/openzeppelin-contracts/
```

**Imports Verified**:

- ✅ `IERC20` from `@openzeppelin/contracts/token/ERC20/IERC20.sol`
- ✅ `SafeERC20` from `@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol`
- ✅ `ReentrancyGuard` from `@openzeppelin/contracts/utils/ReentrancyGuard.sol`
- ✅ Remapping configured correctly

**Status**: ✅ NO ISSUES

### Foundry Build Configuration

```toml
optimizer = true
optimizer_runs = 200
via_ir = true
```

**Status**: ✅ COMPATIBLE (via_ir improves code quality for complex contracts)

---

## Part 2: Interface & Contract Compatibility ❌ CRITICAL

### IAdapter Interface Implementation

**Expected Interface** (`src/interfaces/IAdapter.sol`):

```solidity
interface IAdapter {
    function deposit(uint256 amount) external returns (uint256 deposited);
    function withdraw(uint256 amount) external returns (uint256 withdrawn);
    function getBalance() external view returns (uint256 balance);
    function token() external view returns (address tokenAddress);
}
```

**Adapter Implementations**:

#### FusionXAdapter.sol ✅ IMPLEMENTS

```solidity
function deposit(uint256 amount) external onlyVault returns (uint256 shares) { ... }
function withdraw(uint256 amount) external onlyVault returns (uint256 withdrawn) { ... }
function getBalance() external view returns (uint256 balance) { ... }
function token() external view returns (address tokenAddress) { ... }
```

**Status**: ✅ FULLY COMPATIBLE

#### LendleAdapter.sol ✅ IMPLEMENTS

```solidity
function deposit(uint256 amount) external onlyVault returns (uint256 shares) { ... }
function withdraw(uint256 amount) external onlyVault returns (uint256 withdrawn) { ... }
function getBalance() external view returns (uint256 balance) { ... }
function token() external view returns (address tokenAddress) { ... }
```

**Status**: ✅ FULLY COMPATIBLE

#### MockAdapter.sol ✅ IMPLEMENTS

**Status**: ✅ Mock contract properly implements interface

---

## Part 3: Critical Test Failures ❌ RED

### Category 1: ERC20 Approval Handling (7 failures)

**File**: `test/AdapterAccessControl.t.sol`

**Issue**: SafeERC20 error type mismatch when approval is insufficient

```
[FAIL: ERC20InsufficientAllowance(..., 0, 5e20)] test_approval_front_running_prevention()
[FAIL: ERC20InsufficientAllowance(..., 0, 2e21)] test_approval_persistence_check()
[FAIL: SafeERC20FailedOperation(...)] test_no_lingering_approvals_after_withdrawal()
```

**Root Cause**:
OpenZeppelin's `SafeERC20` now uses typed errors for ERC20 failures (Solidity ^0.8.20):

- `error ERC20InsufficientAllowance(address spender, uint256 allowance, uint256 needed)`
- `error ERC20InsufficientBalance(address account, uint256 balance, uint256 needed)`

**Tests Expecting**: Custom error `0x2c19b8b8` (SlippageExceeded)  
**Tests Receiving**: `ERC20InsufficientAllowance` typed error

**Impact**: 🔴 CRITICAL - Adapter approval logic incompatible with new OZ error types

**Fix Required**:

1. Update test expectations to match new ERC20 typed errors
2. Review adapter SafeERC20 usage patterns
3. Add error handling for new error types

---

### Category 2: Mock Contract & Registry Issues (3 failures)

**File**: `test/StrategyVersioning.t.sol`

```
[FAIL: UnauthorizedRegistrar(0x5991A2dF15A8F6A256D3Ec51E99254Cd3fb576A9)]
testDeprecatedVersionRejectsDeposits()
testMigrateV1ToV2()
testPreventDowngrade()
```

**Root Cause**: `StrategyRegistry` constructor or access control initialization fails

**Mock Registry Issue**:

```solidity
// Registry not initialized properly for test environment
```

**Impact**: 🔴 CRITICAL - Version migration tests completely broken

**Fix Required**:

1. Initialize `StrategyRegistry` with proper admin in test setup
2. Grant `REGISTRAR_ROLE` to test contracts
3. Verify mock contract deployment parameters

---

### Category 3: UniversalVault Test Failures (3 failures)

**File**: `test/UniversalVault.t.sol`

```
[FAIL: UnauthorizedGovernance()] test_AllowHighRiskWithinCap()
[FAIL: UnauthorizedGovernance()] test_CreateMultiAdapterStrategy()
[FAIL: EvmError: Revert] test_SimpleDeposit()
```

**Root Cause**: Vault governance access control or adapter authorization mismatch

**Problem Pattern**:

```solidity
// Adapter not authorized before use
// Governance address not set properly
```

**Impact**: 🟡 HIGH - Core vault functionality tests failing

**Fix Required**:

1. Authorize adapters in test setup before use
2. Ensure governance address is properly set
3. Check modifier guards: `onlyGovernance()`, `whenNotPaused()`

---

### Category 4: Slippage Protection Logic (2 failures)

**File**: `test/SlippageProtection.t.sol`

```
[FAIL: Minimum should be 99.5% of expected: 995000000000000000000 != 99750000000000000000]
test_FullDepositFlow_WithAdapterQuote()

[FAIL: Time should have passed]
test_PreventExpiredDeadlineExecution()
```

**Root Cause 1**: Decimal precision mismatch in slippage calculation

**Issue**:

```
Expected: 995000000000000000000  (18 decimals, 99.5%)
Got:      99750000000000000000   (17 decimals, 9.975%)
```

**Root Cause 2**: Mock timestamp not advancing properly

**Impact**: 🔴 CRITICAL - Slippage protection logic has calculation bug

**Fix Required**:

1. Review SlippageProtection.calculateMinAmountOut() for decimal handling
2. Ensure 18-decimal token arithmetic is correct
3. Add time progression in tests before deadline checks

---

### Category 5: AutoRebalance Engine (1 failure)

**File**: `test/AutoRebalance.t.sol`

```
[FAIL: vault.rebalanceByEngine reverted]
testThresholdTriggeredRebalanceAuto()
```

**Root Cause**: AutoRebalanceEngine not properly integrated with vault

**Impact**: 🟡 MEDIUM - Optional feature breaking

**Fix Required**:

1. Verify AutoRebalanceEngine initialization
2. Check engine has proper vault access
3. Review threshold calculation logic

---

### Category 6: UserVaultV2 Integration (6 failures)

**File**: `test/UserVaultV2Integration.t.sol`

```
[FAIL: CopyFeeExceedsMax()] testFullDepositCopyWithdrawFlow()
[FAIL: panic: division or modulo by zero] testFusionXAdapterSlippageEstimation()
[FAIL: CopyFeeExceedsMax()] testLeaderboardWithCopierTVL()
[FAIL: Error != expected error] testPauseVault()
[FAIL: ERC20InsufficientBalance(..., 0, 5e9)] testSlippageExceeded()
[FAIL: ERC20InsufficientBalance(..., 0, 5e9)] testSlippageProtectionInDeposit()
```

**Root Cause Pattern 1**: Copy fee validation fails

```
CopyFeeExceedsMax() error thrown when copyFeeBps > 50
Tests may be passing invalid copy fee parameters
```

**Root Cause Pattern 2**: Division by zero in adapter slippage

```
testFusionXAdapterSlippageEstimation() panics
Likely: LiquidityPair reserves = 0 or price feed returns 0
```

**Root Cause Pattern 3**: Insufficient mock balance

```
Tests exceed mock USDC balance (5e9 insufficient)
Mock token deployment amount too small
```

**Impact**: 🔴 CRITICAL - Multiple V2 integration paths broken

**Fix Required**:

1. Validate copy fee parameters in test fixtures
2. Initialize FusionX reserves properly
3. Increase mock token initial balance
4. Fix pause state error type mismatch

---

## Part 4: Compatibility Matrix

| Component            | OZ Version | Solidity | Status  | Notes                          |
| -------------------- | ---------- | -------- | ------- | ------------------------------ |
| **IERC20**           | 5.x+       | ^0.8.20  | ✅ PASS | Typed errors in use            |
| **SafeERC20**        | 5.x+       | ^0.8.20  | ❌ FAIL | New error types breaking tests |
| **ReentrancyGuard**  | 5.x+       | ^0.8.20  | ✅ PASS | Standard usage                 |
| **Ownable**          | 5.x+       | ^0.8.20  | ✅ PASS | Via EmergencyPause             |
| **IUniswapV2Router** | N/A        | ^0.8.20  | ✅ PASS | Custom interface, no OZ dep    |
| **ILendingPool**     | N/A        | ^0.8.20  | ✅ PASS | Custom interface, no OZ dep    |

---

## Part 5: Remediation Priority

### 🔴 CRITICAL (Must Fix Before Audit)

1. **SafeERC20 Error Types** (7 test failures)

   - Update all test error expectations
   - Update adapter error handling
   - Estimated effort: 4-6 hours
   - Impact: Enables approval/balance tests

2. **Slippage Protection Decimal Bug** (2 test failures)

   - Fix SlippageProtection.calculateMinAmountOut()
   - Verify 18-decimal arithmetic
   - Estimated effort: 2-3 hours
   - Impact: Slippage protection correctness

3. **StrategyRegistry Initialization** (3 test failures)

   - Initialize registry in tests with proper roles
   - Grant REGISTRAR_ROLE to test contracts
   - Estimated effort: 1-2 hours
   - Impact: Version migration feature

4. **Mock Token Balance** (4 test failures)
   - Increase mock USDC initial balance from 5e9 to 50e18
   - Estimated effort: 0.5 hour
   - Impact: UserVaultV2 integration tests

### 🟡 HIGH (Should Fix Before Audit)

5. **UniversalVault Adapter Authorization** (3 test failures)

   - Pre-authorize adapters in test setup
   - Verify governance address initialization
   - Estimated effort: 2-3 hours
   - Impact: Core vault tests

6. **FusionX Liquidity Reserves** (1 test failure)

   - Initialize pool reserves before slippage test
   - Add mock pair setup
   - Estimated effort: 1-2 hours
   - Impact: Adapter slippage estimation

7. **Copy Fee Validation** (2 test failures)
   - Validate fee bounds in test fixtures
   - Estimated effort: 1 hour
   - Impact: Copy fee feature

### 🟢 MEDIUM (Optional Before Audit)

8. **AutoRebalance Integration** (1 test failure)
   - Lower priority unless feature is in scope
   - Estimated effort: 2-3 hours
   - Impact: Auto-rebalance feature only

---

## Part 6: Detailed Failure Analysis

### Failure #1: SafeERC20 Type Errors

**OpenZeppelin 5.x Changed Error Structure**:

Before (OZ 4.x):

```solidity
require(success, "SafeERC20: ERC20 operation failed");
```

After (OZ 5.x):

```solidity
error ERC20InsufficientAllowance(address spender, uint256 allowance, uint256 needed);
error ERC20InsufficientBalance(address account, uint256 balance, uint256 needed);
error SafeERC20FailedOperation(address token);
```

**Affected Tests**:

- `test_approval_front_running_prevention()` - Expects custom error, gets ERC20InsufficientAllowance
- `test_approval_persistence_check()` - Same issue
- `test_no_lingering_approvals_after_deposit()` - Same issue
- `test_multiple_deposits_dont_accumulate_approvals()` - Same issue
- `test_slippage_exceeded_reverts()` - Custom error mismatch
- `test_slippage_protection_with_min_amount_out()` - Custom error mismatch

**Solution**:

```solidity
// OLD (OZ 4.x):
vm.expectRevert("SafeERC20: insufficient allowance");

// NEW (OZ 5.x):
vm.expectRevert(
    abi.encodeWithSelector(
        IERC20Errors.ERC20InsufficientAllowance.selector,
        spender,
        allowance,
        needed
    )
);
```

---

### Failure #2: Decimal Precision in Slippage

**Current Logic** (src/SlippageProtection.sol):

```solidity
uint256 minAmountOut = (expectedOutput * (10000 - slippageBps)) / 10000;
```

**Issue**:

- expectedOutput = 100 \* 10^18 (100 tokens)
- slippageBps = 50 (0.5%)
- Calculation: (100 _ 10^18 _ 9950) / 10000
- Result: 99.5 \* 10^18 ✅ Correct

**But tests show**:

- Expected: 995000000000000000000 (995 tokens = wrong scaling)
- Got: 99750000000000000000 (9.975 tokens = wrong scaling)

**Root Cause**: Likely decimal conversion bug or mock value mismatch

**Fix**: Review calculateMinAmountOut() for all paths:

1. Single adapter: amount → minAmountOut
2. Multi-adapter: split amounts → aggregate minimum
3. Verify decimal preservation throughout

---

### Failure #3: Registry Authorization

**Test Setup Missing**:

```solidity
// Current test setup:
registry = new StrategyRegistry();
// ❌ MISSING: Grant REGISTRAR_ROLE

// Fixed test setup:
registry = new StrategyRegistry();
registry.grantRole(REGISTRAR_ROLE, address(this)); // Grant to test contract
```

**Issue**: Test cannot call registry.registerVersion() without role

---

### Failure #4: Mock Balance Insufficient

**Current Mock Setup**:

```solidity
mockUsdc = new MockERC20("USDC", "USDC", 6);
mockUsdc.mint(address(this), 5e9); // 5,000 USDC (6 decimals)
```

**Issue**: UserVaultV2 tests require multiple deposits × multiple users

- Per test: ~1-5 USDC transfers
- Multiple tests: ~20-50 USDC needed
- Current: 5 USDC → INSUFFICIENT

**Fix**:

```solidity
mockUsdc.mint(address(this), 50e18); // 50,000 USDC (increase 10x)
```

---

## Part 7: Compiler & Runtime Compatibility

### Solidity ^0.8.20 Features Used

✅ **Compatible**:

- Custom errors (error ZeroAddress())
- Unchecked arithmetic blocks
- Dynamic array operations
- Struct storage optimization
- Reentrancy guards (from OZ)

❌ **Incompatible**:

- None identified

### Runtime Compatibility Issues

**EVM Target**: All contracts compatible with EVM mainnet + Mantle (compatible EVM fork)

**External Call Patterns**:

- ✅ IERC20.transferFrom() → Uses SafeERC20
- ✅ IUniswapV2Router.swapExactTokensForTokens() → Deadline safety
- ✅ ILendingPool.supply() → Stateful but safe

---

## Part 8: Recommendations

### Before External Audit ✅ MUST DO

1. **Fix all 22 test failures** (estimated 2-3 weeks)

   - Prioritize CRITICAL category (14 failures)
   - Address HIGH category (5 failures)
   - MEDIUM can wait post-audit if feature scope allows

2. **Run full test suite with fixes**

   ```bash
   cd /home/manik/Documents/Malgist/malgist-contract-fresh
   forge test --gas-report
   ```

   Expected: 152/152 tests passing

3. **Update compatibility documentation**

   - Document OZ 5.x changes in this file
   - Add error type mappings

4. **Review error handling across codebase**
   - Audit all custom errors vs. built-in errors
   - Ensure error recovery is safe

### During Audit 📋 AUDITOR CHECKLIST

1. Verify all test failures have root-cause fixes
2. Check SafeERC20 error handling in production paths
3. Validate slippage protection math with formal verification
4. Review adapter approval safety patterns

### Post-Audit 🚀 DEPLOYMENT

1. Tag code as "pre-audit" on git
2. Create release notes documenting compatibility fixes
3. Set up CI/CD to ensure tests never regress

---

## Part 9: Compatibility Decision Matrix

| Issue                | Category | Blocker? | Fix Before Audit? | Auditor Should Review? |
| -------------------- | -------- | -------- | ----------------- | ---------------------- |
| SafeERC20 errors     | Code     | YES      | YES               | YES                    |
| Slippage decimal bug | Logic    | YES      | YES               | YES                    |
| Registry init        | Test     | NO       | YES               | MAYBE                  |
| Mock balance         | Test     | NO       | YES               | NO                     |
| Vault governance     | Test     | NO       | YES               | MAYBE                  |
| AutoRebalance        | Feature  | NO       | NO                | NO                     |
| FusionX reserves     | Test     | NO       | NO                | NO                     |
| Copy fee validation  | Test     | NO       | YES               | NO                     |

---

## Conclusion

**Current Status**: ⚠️ **NOT AUDIT-READY**

**Blocker Issues**: 2 critical code issues (SafeERC20 errors, slippage decimal bug)

**Timeline to Resolution**:

- CRITICAL fixes: 6-8 hours development + 4-6 hours testing
- HIGH fixes: 6-8 hours development + 2-3 hours testing
- Total: ~20 hours → ~3 working days

**Recommended Action**:

1. Fix all CRITICAL issues immediately (safety-critical)
2. Fix all HIGH issues within 1 week
3. Run full test suite until all 152 tests pass
4. Update this document with "AUDIT-READY" status
5. Proceed to external audit

**Next Step**: Create detailed fix implementation plan for each issue (provided in COMPATIBILITY_FIX_PLAN.md)
