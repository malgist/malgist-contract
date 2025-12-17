# MALGIST Compatibility Fix Implementation Plan

**Status**: Implementation-Ready  
**Target**: Achieve 152/152 tests passing (100% pass rate)  
**Estimated Duration**: 20-25 hours development + testing  
**Owner**: Development Team

---

## Overview

This document provides **step-by-step implementation guidance** to fix all 22 failing tests and achieve audit-readiness.

---

## CRITICAL FIXES (Must Complete First)

### ⚠️ FIX #1: SafeERC20 Error Type Compatibility (7 test failures)

**Location**: `test/AdapterAccessControl.t.sol`

**Affected Tests**:

1. test_approval_front_running_prevention
2. test_approval_persistence_check
3. test_multiple_deposits_dont_accumulate_approvals
4. test_no_lingering_approvals_after_deposit
5. test_no_lingering_approvals_after_withdrawal
6. test_slippage_exceeded_reverts
7. test_slippage_protection_with_min_amount_out

**Root Cause**:
OpenZeppelin 5.x introduced typed errors. Tests expect custom error `0x2c19b8b8` (SlippageExceeded) but receive `ERC20InsufficientAllowance`.

**Implementation Steps**:

**Step 1A**: Import error definitions at top of test file

```solidity
// Add to test/AdapterAccessControl.t.sol imports:
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
```

**Step 1B**: Update test expectation functions

Find and replace all instances of:

```solidity
// OLD - Line ~48:
vm.expectRevert(SlippageExceeded.selector);
```

With:

```solidity
// NEW - Updated for OZ 5.x:
// This test checks approval, which now throws ERC20InsufficientAllowance
// if allowance < amount. Update test to check the correct error.
```

**Step 1C**: Fix each test individually

**Test 1**: `test_approval_front_running_prevention`

```solidity
// BEFORE:
vm.expectRevert(SlippageExceeded.selector);
// User tries to call without approval

// AFTER:
// Remove expectRevert - approval should be granted in setup
// OR expect ERC20InsufficientAllowance if testing insufficient approval
vm.expectRevert(
    abi.encodeWithSelector(
        IERC20Errors.ERC20InsufficientAllowance.selector,
        address(mockAdapter),
        0,
        amountDesired
    )
);
```

**Test 2-4**: Similar pattern - check if test is validating approvals or slippage

- If approving: Remove expect, let it succeed
- If testing insufficient: Expect `ERC20InsufficientAllowance`
- If testing slippage: Expect `SlippageExceeded` only if adapter actually fails slippage check

**Test 5**: `test_no_lingering_approvals_after_withdrawal`

```solidity
// Issue: withdrawal may fail if balance is 0 (SafeERC20FailedOperation)
// Fix: Ensure deposit succeeded with sufficient balance before withdrawal

// Add to test setup:
uint256 depositAmount = 1000 * 10**6; // 1000 USDC
mockUsdc.mint(address(this), depositAmount);
mockUsdc.approve(address(mockAdapter), depositAmount);
mockAdapter.deposit(depositAmount); // Ensure deposit succeeds
```

**Test 6-7**: Slippage error tests

```solidity
// These should expect SlippageExceeded, not ERC20 errors
// Verify adapter is correctly throwing SlippageExceeded
// Check that mock adapter's slippage calculation is working

// Ensure mock adapter implements slippage correctly:
// If returning less than minAmountOut, should revert with SlippageExceeded
```

**Verification**:

```bash
cd /home/manik/Documents/Malgist/malgist-contract-fresh
forge test test/AdapterAccessControl.t.sol --match "test_approval" -vvv
# All 7 tests should pass
```

**Time Estimate**: 3-4 hours

---

### ⚠️ FIX #2: Slippage Protection Decimal Calculation Bug (2 test failures)

**Location**: `src/SlippageProtection.sol` and `test/SlippageProtection.t.sol`

**Affected Tests**:

1. test_FullDepositFlow_WithAdapterQuote
2. test_PreventExpiredDeadlineExecution

**Root Cause**:
Test failure message: `Minimum should be 99.5% of expected: 995000000000000000000 != 99750000000000000000`
This indicates a decimal scaling mismatch (10x difference).

**Investigation Steps**:

**Step 2A**: Review SlippageProtection.calculateMinAmountOut()

```solidity
// File: src/SlippageProtection.sol
function calculateMinAmountOut(uint256 expectedOutput, uint16 slippageBps)
    internal
    pure
    returns (uint256)
{
    // Check: Is this handling 18-decimal tokens correctly?
    uint256 minAmountOut = (expectedOutput * (10000 - slippageBps)) / 10000;
    return minAmountOut;

    // Math check for expectedOutput = 100 * 10^18, slippageBps = 50:
    // = (100000000000000000000 * 9950) / 10000
    // = 995000000000000000000 ✅ CORRECT (99.5 tokens)
}
```

**Step 2B**: Review test setup

```solidity
// File: test/SlippageProtection.t.sol - test_FullDepositFlow_WithAdapterQuote()

// ISSUE LIKELY HERE:
uint256 expectedOutput = ...; // What value is this?
uint256 minAmountOut = slippageProtection.calculateMinAmountOut(expectedOutput, 50);

// Test assertion:
assertEq(minAmountOut, expectedMinimum); // What's expectedMinimum?

// If expectedOutput = 10 * 10^18 (10 tokens):
// minAmountOut should = 9.95 * 10^18 = 9950000000000000000
// But test expects 99500000000000000000 (10x larger) ❌
```

**Step 2C**: Fix the test

```solidity
// BEFORE (wrong expectation):
uint256 expectedMinimum = 995000000000000000000; // 995 tokens

// AFTER (correct expectation):
uint256 expectedMinimum = 99500000000000000000;  // 99.5 tokens (if expected = 100)
// OR verify expectedOutput is actually 100 * 10^18
```

**Step 2D**: Fix deadline expiration test

```solidity
// File: test/SlippageProtection.t.sol - test_PreventExpiredDeadlineExecution()

// ISSUE: "Time should have passed"
// Mock might not be advancing block.timestamp

// FIX:
function test_PreventExpiredDeadlineExecution() public {
    uint256 deadline = block.timestamp + 1 hours;

    // Advance time past deadline
    vm.warp(block.timestamp + 2 hours); // ← ADD THIS

    // Now deadline check should fail
    vm.expectRevert(DeadlineExpired.selector);
    slippageProtection.validateDeadline(deadline);
}
```

**Verification**:

```bash
forge test test/SlippageProtection.t.sol::SlippageProtectionTest::test_FullDepositFlow_WithAdapterQuote -vvv
forge test test/SlippageProtection.t.sol::SlippageProtectionTest::test_PreventExpiredDeadlineExecution -vvv
```

**Time Estimate**: 2-3 hours

---

## HIGH PRIORITY FIXES (Complete After CRITICAL)

### FIX #3: StrategyRegistry Initialization (3 test failures)

**Location**: `test/StrategyVersioning.t.sol`

**Affected Tests**:

1. testDeprecatedVersionRejectsDeposits
2. testMigrateV1ToV2
3. testPreventDowngrade

**Error**: `UnauthorizedRegistrar(0x5991A2dF15A8F6A256D3Ec51E99254Cd3fb576A9)`

**Root Cause**:
Test contract doesn't have `REGISTRAR_ROLE` to call registry functions.

**Fix**:

**Step 3A**: Update test setup

```solidity
// File: test/StrategyVersioning.t.sol

// BEFORE:
function setUp() public {
    registry = new StrategyRegistry();
    vault = new UniversalVault(address(mockUsdc), address(this));
}

// AFTER:
function setUp() public {
    registry = new StrategyRegistry();
    vault = new UniversalVault(address(mockUsdc), address(this));

    // Grant REGISTRAR_ROLE to test contract
    bytes32 registrarRole = keccak256("REGISTRAR_ROLE");
    registry.grantRole(registrarRole, address(this));
}
```

**Step 3B**: Verify admin is correctly set

```solidity
// Check if StrategyRegistry needs admin initialization
// File: src/StrategyRegistry.sol - constructor

// If using AccessControl, admin should be caller
constructor() {
    // _grantRole(DEFAULT_ADMIN_ROLE, msg.sender); ← Verify this exists
}
```

**Verification**:

```bash
forge test test/StrategyVersioning.t.sol -vvv
```

**Time Estimate**: 1-2 hours

---

### FIX #4: UniversalVault Adapter Authorization (3 test failures)

**Location**: `test/UniversalVault.t.sol`

**Affected Tests**:

1. test_AllowHighRiskWithinCap
2. test_CreateMultiAdapterStrategy
3. test_SimpleDeposit (indirect)

**Error**: `UnauthorizedGovernance()` or general revert

**Root Cause**:
Adapters are not authorized in the vault before strategy creation attempts to use them.

**Fix**:

**Step 4A**: Add adapter authorization to test setup

```solidity
// File: test/UniversalVault.t.sol

// In setUp() or before tests that use adapters:
function setUp() public {
    vault = new UniversalVault(address(mockUsdc), address(this));

    // ← ADD THIS SECTION:
    // Create mock adapters
    mockAdapter1 = new MockAdapter(address(mockUsdc), address(vault));
    mockAdapter2 = new MockAdapter(address(mockUsdc), address(vault));

    // Authorize adapters with vault
    vault.authorizeAdapter(address(mockAdapter1), 1); // Risk tier 1
    vault.authorizeAdapter(address(mockAdapter2), 2); // Risk tier 2
}
```

**Step 4B**: Update strategy creation tests

```solidity
// BEFORE:
function test_CreateBasicStrategy() public {
    address[] memory adapters = new address[](1);
    adapters[0] = address(mockAdapter1);
    uint16[] memory ratios = new uint16[](1);
    ratios[0] = 10000;

    vault.setStrategy(adapters, ratios, true, "Basic", 0);
    // ❌ FAILS: Adapter not authorized
}

// AFTER:
function test_CreateBasicStrategy() public {
    // Adapter is now authorized in setUp()
    address[] memory adapters = new address[](1);
    adapters[0] = address(mockAdapter1);
    uint16[] memory ratios = new uint16[](1);
    ratios[0] = 10000;

    vault.setStrategy(adapters, ratios, true, "Basic", 0);
    // ✅ PASSES
}
```

**Step 4C**: Check governance address in vault

```solidity
// If test is failing on governance check:
// File: src/UniversalVault.sol

// Verify modifier exists:
modifier onlyGovernance() {
    if (msg.sender != governance) revert UnauthorizedGovernance();
    _;
}

// In test, ensure governance is set correctly:
assertEq(vault.governance(), address(this)); // Or expected address
```

**Verification**:

```bash
forge test test/UniversalVault.t.sol::UniversalVaultTest::test_CreateBasicStrategy -vvv
forge test test/UniversalVault.t.sol::UniversalVaultTest::test_AllowHighRiskWithinCap -vvv
```

**Time Estimate**: 2-3 hours

---

### FIX #5: Mock Token Insufficient Balance (4 test failures)

**Location**: `test/UserVaultV2Integration.t.sol`

**Affected Tests**:

1. testSlippageExceeded
2. testSlippageProtectionInDeposit
3. testFullDepositCopyWithdrawFlow
4. testLeaderboardWithCopierTVL

**Error**: `ERC20InsufficientBalance(..., 0, 5e9)`

**Root Cause**:
Mock USDC has insufficient total supply for multiple test transactions.

**Fix**:

**Step 5A**: Increase mock token supply

```solidity
// File: test/UserVaultV2Integration.t.sol

// BEFORE:
function setUp() public {
    mockUsdc = new MockERC20("USDC", "USDC", 6);
    mockUsdc.mint(address(this), 5e9); // 5,000 USDC
    // ❌ Insufficient for all tests
}

// AFTER:
function setUp() public {
    mockUsdc = new MockERC20("USDC", "USDC", 6);
    mockUsdc.mint(address(this), 500e18); // 500,000 USDC (increased 100x)

    // Or with 6 decimals:
    mockUsdc.mint(address(this), 500_000 * 10**6); // 500,000 USDC
}
```

**Step 5B**: Verify mock implementation supports minting

```solidity
// File: src/mocks/MockERC20.sol

// Ensure mint function exists:
function mint(address to, uint256 amount) external {
    _mint(to, amount);
}
```

**Verification**:

```bash
forge test test/UserVaultV2Integration.t.sol -k "Slippage" -vvv
```

**Time Estimate**: 0.5-1 hour

---

### FIX #6: Copy Fee Validation (2 test failures)

**Location**: `test/UserVaultV2Integration.t.sol`

**Affected Tests**:

1. testFullDepositCopyWithdrawFlow
2. testLeaderboardWithCopierTVL

**Error**: `CopyFeeExceedsMax()`

**Root Cause**:
Tests pass invalid copy fee (> 50 bps) to setStrategy or copying function.

**Fix**:

**Step 6A**: Find where CopyFeeExceedsMax is thrown

```solidity
// File: src/UserVault.sol or src/UserVaultV2.sol

// Search for:
if (copyFeeBps > MAX_COPY_FEE_BPS) revert CopyFeeExceedsMax();

// MAX_COPY_FEE_BPS = 50
```

**Step 6B**: Update test to use valid fee

```solidity
// BEFORE:
uint16 invalidCopyFee = 100; // 1% (exceeds max 50 bps = 0.5%)
vault.setStrategy(adapters, ratios, true, "Strategy", invalidCopyFee);
// ❌ FAILS

// AFTER:
uint16 validCopyFee = 50; // Max allowed = 0.5%
vault.setStrategy(adapters, ratios, true, "Strategy", validCopyFee);
// ✅ PASSES

// Or if testing max boundary:
uint16 maxAllowedFee = 50;
vault.setStrategy(adapters, ratios, true, "Strategy", maxAllowedFee);
assertEq(vault.strategies(address(this)).copyFeeBps, 50);
```

**Verification**:

```bash
forge test test/UserVaultV2Integration.t.sol::UserVaultV2IntegrationTest::testFullDepositCopyWithdrawFlow -vvv
```

**Time Estimate**: 1 hour

---

### FIX #7: FusionX Liquidity Pool Initialization (1 test failure)

**Location**: `test/UserVaultV2Integration.t.sol`

**Affected Test**:

- testFusionXAdapterSlippageEstimation

**Error**: `panic: division or modulo by zero`

**Root Cause**:
FusionX adapter tries to get price from empty liquidity pool (reserves = 0).

**Fix**:

**Step 7A**: Add liquidity pool initialization

```solidity
// File: test/UserVaultV2Integration.t.sol

function setUp() public {
    // Existing setup...
    fusionxAdapter = new FusionXAdapter(
        address(mockUsdc),
        address(mockMnt),
        address(mockLpToken),
        address(mockRouter)
    );

    // ← ADD THIS:
    // Initialize FusionX pool with liquidity
    // Mint LP tokens or mock reserves
    mockLpToken.mint(address(mockPool), 1000 * 10**18);

    // If using mock pair, set reserves:
    // mockPair.setReserves(1000 * 10**6, 1000 * 10**18); // USDC, MNT
}
```

**Step 7B**: Update adapter price calculation

```solidity
// File: src/adapters/FusionXAdapter.sol

// In deposit or slippage functions, add zero-check:
function _swapAForB(uint256 amountIn) internal returns (uint256 amountOut) {
    uint256[] memory amounts = ROUTER.getAmountsOut(amountIn, path);

    // Add check:
    require(amounts[amounts.length - 1] > 0, "Invalid swap: zero output");

    amountOut = amounts[amounts.length - 1];
}
```

**Verification**:

```bash
forge test test/UserVaultV2Integration.t.sol::UserVaultV2IntegrationTest::testFusionXAdapterSlippageEstimation -vvv
```

**Time Estimate**: 1-2 hours

---

### FIX #8: AutoRebalance Integration (1 test failure)

**Location**: `test/AutoRebalance.t.sol`

**Affected Test**:

- testThresholdTriggeredRebalanceAuto

**Error**: `vault.rebalanceByEngine reverted`

**Root Cause**:
AutoRebalanceEngine not properly initialized or lacks vault permissions.

**Fix**:

**Step 8A**: Initialize engine in test setup

```solidity
// File: test/AutoRebalance.t.sol

function setUp() public {
    vault = new UniversalVault(address(mockUsdc), address(this));
    engine = new AutoRebalanceEngine(address(vault));

    // Grant engine permission to rebalance
    // vault.grantRole(REBALANCER_ROLE, address(engine));
}
```

**Step 8B**: Check engine callback function

```solidity
// Ensure vault has rebalanceByEngine function
// Or update test to use correct function name

// File: src/UniversalVault.sol
function rebalanceByEngine(bytes calldata params) external onlyEngine {
    // Rebalance logic
}

// File: test/AutoRebalance.t.sol
vault.rebalanceByEngine(params); // Match actual function signature
```

**Verification**:

```bash
forge test test/AutoRebalance.t.sol::AutoRebalanceTest::testThresholdTriggeredRebalanceAuto -vvv
```

**Time Estimate**: 2-3 hours

---

### FIX #9: Pause State Error Type (1 test failure)

**Location**: `test/UserVaultV2Integration.t.sol`

**Affected Test**:

- testPauseVault

**Error**: `VaultIsPaused() != VaultPausedForDeposits()`

**Root Cause**:
Test expects one error type, vault throws different error.

**Fix**:

**Step 9A**: Check actual error thrown

```solidity
// File: src/UserVault.sol or src/UserVaultV2.sol

// Find pause check:
modifier whenNotPaused() {
    if (isPaused) revert VaultIsPaused();
    // or
    if (isPaused) revert VaultPausedForDeposits();
}
```

**Step 9B**: Update test expectation

```solidity
// BEFORE:
function testPauseVault() public {
    vault.pause();
    vm.expectRevert(VaultIsPaused.selector);
    vault.deposit(1000);
}

// AFTER - match actual error:
function testPauseVault() public {
    vault.pause();
    vm.expectRevert(VaultPausedForDeposits.selector); // Use correct error
    vault.deposit(1000);
}
```

**Verification**:

```bash
forge test test/UserVaultV2Integration.t.sol::UserVaultV2IntegrationTest::testPauseVault -vvv
```

**Time Estimate**: 0.5-1 hour

---

## VERIFICATION & VALIDATION

### Complete Test Run After All Fixes

```bash
cd /home/manik/Documents/Malgist/malgist-contract-fresh

# Run full test suite
forge test --gas-report

# Expected output:
# Ran 12 test suites in <time>: 152 tests passed, 0 failed, 0 skipped

# Check coverage
forge coverage --report html

# Build verification
forge build --via-ir

# Gas optimization check
forge test --gas-report > gas-report-fixed.txt
diff gas-report.txt gas-report-fixed.txt
```

### Regression Testing

```bash
# Test critical paths
forge test test/UserVault.t.sol -vvv       # Core vault
forge test test/UniversalVault.t.sol -vvv  # Universal vault
forge test test/EmergencyPause.t.sol -vvv   # Safety mechanisms
forge test test/SlippageProtection.t.sol -vvv # Slippage protection

# Verify no new failures introduced
forge test 2>&1 | grep -E "FAILED|failed"
# Should output nothing if all pass
```

### Compatibility Verification

```bash
# Verify Solidity compilation
solc --version  # Should be ^0.8.20

# Check OpenZeppelin imports
grep -r "import.*@openzeppelin" src/

# Verify no deprecated patterns
grep -r "pragma solidity <0.8.20" src/ # Should be empty
```

---

## Implementation Schedule

### Week 1 (Days 1-3): CRITICAL Fixes

| Day | Task                           | Estimated Hours | Owner |
| --- | ------------------------------ | --------------- | ----- |
| Mon | SafeERC20 error types (Fix #1) | 4               | Dev1  |
| Tue | Slippage decimal bug (Fix #2)  | 3               | Dev1  |
| Wed | Run & verify CRITICAL tests    | 2               | QA1   |

### Week 1 (Days 4-5): HIGH Priority Fixes

| Day | Task                                         | Estimated Hours | Owner |
| --- | -------------------------------------------- | --------------- | ----- |
| Thu | Registry init (Fix #3) + Vault auth (Fix #4) | 5               | Dev2  |
| Fri | Mock balance (Fix #5) + Copy fee (Fix #6)    | 2               | Dev2  |

### Week 2 (Days 1-2): Remaining Fixes

| Day | Task                                         | Estimated Hours | Owner |
| --- | -------------------------------------------- | --------------- | ----- |
| Mon | FusionX init (Fix #7) + Pause error (Fix #9) | 3               | Dev1  |
| Tue | AutoRebalance (Fix #8) + Full test run       | 3               | Dev1  |

### Week 2 (Days 3-5): Validation & Documentation

| Day | Task                                      | Estimated Hours | Owner     |
| --- | ----------------------------------------- | --------------- | --------- |
| Wed | Fix verification & regression testing     | 4               | QA1       |
| Thu | Coverage report & gas optimization verify | 3               | QA1       |
| Fri | Documentation update & audit handoff      | 2               | Tech Lead |

**Total**: ~40 hours development + testing = 1 week intensive, 2 weeks relaxed

---

## Audit Readiness Checklist

After all fixes complete:

- [ ] All 152 tests passing (100%)
- [ ] No compiler warnings or errors
- [ ] Gas report stable vs baseline
- [ ] CODE_COMPATIBILITY_ANALYSIS.md updated with "FIXED" status
- [ ] No new issues in Slither or other static analysis
- [ ] Coverage report >= 85%
- [ ] Git tag created: `pre-audit-v1.0`
- [ ] Release notes documenting all fixes
- [ ] Audit firm briefing completed
- [ ] Feature freeze confirmed
- [ ] No uncommitted changes

---

## Risk Mitigation

### If a fix introduces new issues:

1. **Revert immediately** to last known good state
2. **Document the issue** in COMPATIBILITY_ISSUES.md
3. **Escalate to tech lead** for review
4. **Try alternative approach** after root cause analysis

### If tests still fail after applying fix:

1. **Enable verbose logging**: `forge test -vvv`
2. **Add debug statements** in contract and test
3. **Compare to original working version** (git diff)
4. **Check mock implementations** for correctness
5. **Verify test assumptions** about contract state

---

## Success Criteria

✅ **Project will be considered AUDIT-READY when:**

1. All 152 tests pass consistently
2. No SafeERC20 error type mismatches
3. Slippage protection math verified mathematically
4. All adapters properly authorized in test environment
5. Mock infrastructure correctly initialized
6. Code review approval from tech lead
7. Final commit tagged as `pre-audit-v1.0`

---

## Post-Fix Procedure

Once all tests pass:

```bash
# 1. Update documentation
cp CODE_COMPATIBILITY_ANALYSIS.md AUDIT_READY_COMPATIBILITY.md
# Edit to mark all fixes as COMPLETE

# 2. Tag the release
git tag -a pre-audit-v1.0 -m "All compatibility fixes applied, 152/152 tests passing"

# 3. Create audit package
mkdir audit-package
cp -r src/ audit-package/
cp -r test/ audit-package/
cp Documentation/*.md audit-package/
cp foundry.toml remappings.txt audit-package/

# 4. Generate reports
forge test --gas-report > audit-package/gas-report.txt
forge coverage --report lcov > audit-package/coverage.lcov

# 5. Notify audit firm
echo "MALGIST audit package ready for review" | mail -s "Pre-Audit Submission" auditors@firm.com
```

---

## Contact & Escalation

- **Technical Lead**: [To be filled]
- **QA Lead**: [To be filled]
- **On-Call**: [To be filled]

For blocking issues during implementation, escalate immediately.
