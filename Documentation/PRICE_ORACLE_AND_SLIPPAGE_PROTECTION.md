# Price Oracle & Dynamic Slippage Protection

## Overview

This document describes **Aspect #5** of the Malgist system enhancements: **Slippage & Price Oracle Protection**. This enhancement replaces hardcoded slippage values with dynamic, trade-size-based slippage calculation using Chainlink price oracles.

---

## 🎯 Problem Statement

**Before (Hardcoded Slippage)**:
```solidity
// ❌ All trades use same 0.5% slippage regardless of size
uint16 public constant SLIPPAGE_BPS = 50;  // 0.5%
uint256 minAmountOut = (amountsOut[1] * (TOTAL_BPS - SLIPPAGE_BPS)) / TOTAL_BPS;
```

**Issues**:
- Small trades ($100) overpay with 0.5% slippage
- Large trades ($1M) get sandwiched/MEV attacked with only 0.5% protection
- No oracle validation of DEX quotes
- No protection against stale prices

---

## ✅ Solution (Dynamic Slippage + Oracle)

**After (Dynamic Slippage with Oracle Validation)**:
```solidity
// ✅ Slippage scales with trade size
SlippageProtection.SwapParams memory params = SlippageProtection.SwapParams({
    tokenIn: address(TOKEN_A),
    tokenOut: address(TOKEN_B),
    amountIn: amountIn,
    priceOracle: address(priceOracle),
    config: slippageConfig  // Conservative/Moderate/Aggressive
});

SlippageProtection.SlippageResult memory result = SlippageProtection.calculateSlippage(params);
// result.minOutput = oracle-based minimum with dynamic slippage
// result.slippageBps = 0.3% for $1k, 1% for $100k, 5% for $1M+
// result.tradeSizeTier = SMALL/MEDIUM/LARGE/WHALE
```

---

## 📐 Architecture

### Components

1. **PriceOracle.sol** - Chainlink price feed aggregator with safety checks
2. **SlippageProtection.sol** - Library for dynamic slippage calculation
3. **IPriceOracle.sol** - Standard interface for price oracles
4. **FusionXAdapter.sol** (Enhanced) - Example adapter using dynamic slippage

### File Locations

```
src/
├── oracles/
│   └── PriceOracle.sol                      # Chainlink integration
├── libraries/
│   └── SlippageProtection.sol               # Dynamic slippage logic
├── interfaces/
│   └── IPriceOracle.sol                     # Oracle interface
└── adapters/
    └── FusionXAdapter.sol                   # Enhanced with oracle
```

---

## 🔧 PriceOracle.sol Features

### Core Functionality

1. **Chainlink Integration** - AggregatorV3Interface for price feeds
2. **Staleness Detection** - Revert if price older than heartbeat (e.g., 1 hour)
3. **Deviation Limits** - Prevent manipulation (max 10% deviation from last price)
4. **Circuit Breaker** - Emergency pause if anomaly detected
5. **Manual Fallback** - Owner can set manual prices for emergencies
6. **18 Decimal Normalization** - All prices standardized to 18 decimals

### Price Feed Configuration

```solidity
struct PriceFeed {
    address feed;           // Chainlink aggregator address
    uint32 heartbeat;       // Max staleness (e.g., 3600 = 1 hour)
    uint8 decimals;         // Price feed decimals
    bool isActive;          // Feed status
    uint16 maxDeviation;    // Max price change (BPS, e.g., 1000 = 10%)
}
```

### Safety Checks

```solidity
// Staleness check
uint256 timeSinceUpdate = block.timestamp - updatedAt;
if (timeSinceUpdate > feed.heartbeat) revert StalePrice();

// Deviation check
if (deviation > maxDeviation) revert PriceDeviation();

// Circuit breaker
if (circuitBreakerActive) revert CircuitBreakerTripped();
```

---

## 📊 SlippageProtection.sol Features

### Dynamic Slippage Tiers

| Trade Size Tier | USD Value Range | Conservative | Moderate | Aggressive |
|----------------|-----------------|--------------|----------|------------|
| **SMALL**      | < $10k          | 0.3%         | 0.5%     | 1%         |
| **MEDIUM**     | $10k - $100k    | 0.5%         | 1%       | 2%         |
| **LARGE**      | $100k - $1M     | 1%           | 2%       | 3%         |
| **WHALE**      | $1M+            | 2%           | 3%       | 5%         |

### Slippage Calculation Flow

```
1. Get tokenIn price from oracle (18 decimals)
2. Get tokenOut price from oracle (18 decimals)
3. Calculate expected output: (amountIn * priceIn) / priceOut
4. Calculate trade value in USD: (amountIn * priceIn) / 1e18
5. Determine tier based on USD value (SMALL/MEDIUM/LARGE/WHALE)
6. Apply tier slippage: minOutput = expectedOutput * (BPS - slippageBps) / BPS
7. Return SlippageResult{expectedOutput, minOutput, slippageBps, tradeSizeTier}
```

### Configuration Presets

```solidity
// Conservative (low slippage tolerance)
SlippageProtection.getConservativeConfig()
// - smallTradeBps: 30 (0.3%)
// - mediumTradeBps: 50 (0.5%)
// - largeTradeBps: 100 (1%)
// - whaleTradeBps: 200 (2%)

// Moderate (balanced)
SlippageProtection.getModerateConfig()
// - smallTradeBps: 50 (0.5%)
// - mediumTradeBps: 100 (1%)
// - largeTradeBps: 200 (2%)
// - whaleTradeBps: 300 (3%)

// Aggressive (high slippage tolerance)
SlippageProtection.getAggressiveConfig()
// - smallTradeBps: 100 (1%)
// - mediumTradeBps: 200 (2%)
// - largeTradeBps: 300 (3%)
// - whaleTradeBps: 500 (5%)
```

---

## 🚀 Deployment Guide

### Step 1: Deploy PriceOracle

```solidity
// Deploy PriceOracle
PriceOracle oracle = new PriceOracle();

// Add Chainlink price feeds
oracle.addPriceFeed(
    USDC,                           // asset
    CHAINLINK_USDC_USD_FEED,        // Chainlink aggregator
    3600,                           // heartbeat (1 hour)
    1000                            // maxDeviation (10%)
);

oracle.addPriceFeed(
    MNT,                            // asset
    CHAINLINK_MNT_USD_FEED,         // Chainlink aggregator
    3600,                           // heartbeat (1 hour)
    1000                            // maxDeviation (10%)
);

oracle.addPriceFeed(
    WETH,                           // asset
    CHAINLINK_ETH_USD_FEED,         // Chainlink aggregator
    3600,                           // heartbeat (1 hour)
    500                             // maxDeviation (5% - more stable)
);
```

### Step 2: Deploy Adapter with Oracle

```solidity
// Deploy FusionXAdapter with oracle integration
FusionXAdapter adapter = new FusionXAdapter(
    USDC,                           // tokenA
    MNT,                            // tokenB
    FUSION_LP_TOKEN,                // lpToken
    FUSION_ROUTER,                  // router
    VAULT,                          // vault
    address(oracle),                // priceOracle
    owner                           // owner (for admin functions)
);

// Adapter initializes with moderate slippage by default
// adapter.slippageConfig = SlippageProtection.getModerateConfig();
```

### Step 3: Configure Slippage Profile (Optional)

```solidity
// Option 1: Use preset
adapter.setConservativeSlippage();  // 0.3% - 2%
adapter.setModerateSlippage();      // 0.5% - 3% (default)
adapter.setAggressiveSlippage();    // 1% - 5%

// Option 2: Custom configuration
SlippageProtection.SlippageConfig memory customConfig = SlippageProtection.SlippageConfig({
    smallTradeBps: 40,              // 0.4%
    mediumTradeBps: 80,             // 0.8%
    largeTradeBps: 150,             // 1.5%
    whaleTradeBps: 250,             // 2.5%
    tier1Threshold: 5_000e18,       // $5k
    tier2Threshold: 50_000e18,      // $50k
    tier3Threshold: 500_000e18      // $500k
});

adapter.setSlippageConfig(customConfig);
```

---

## 📝 Example: FusionXAdapter Integration

### Before (Hardcoded Slippage)

```solidity
function _swapAForB(uint256 amountIn) internal returns (uint256 amountOut) {
    // ❌ Hardcoded 0.5% slippage for all trades
    uint256 minAmountOut = (amountsOut[1] * (TOTAL_BPS - SLIPPAGE_BPS)) / TOTAL_BPS;

    uint256[] memory amounts = ROUTER.swapExactTokensForTokens(
        amountIn,
        minAmountOut,  // ❌ Same for $100 and $1M trades
        path,
        address(this),
        block.timestamp
    );
}
```

### After (Dynamic Slippage with Oracle)

```solidity
function _swapAForB(uint256 amountIn) internal returns (uint256 amountOut) {
    // ✅ Calculate dynamic slippage based on trade size
    SlippageProtection.SwapParams memory params = SlippageProtection.SwapParams({
        tokenIn: address(TOKEN_A),
        tokenOut: address(TOKEN_B),
        amountIn: amountIn,
        priceOracle: address(priceOracle),
        config: slippageConfig
    });

    SlippageProtection.SlippageResult memory result =
        SlippageProtection.calculateSlippage(params);

    // result.minOutput is oracle-based with dynamic slippage
    // result.slippageBps scales with trade size (0.3% - 5%)
    // result.tradeSizeTier indicates SMALL/MEDIUM/LARGE/WHALE

    uint256[] memory amounts = ROUTER.swapExactTokensForTokens(
        amountIn,
        result.minOutput,  // ✅ Dynamic minimum based on oracle + tier
        path,
        address(this),
        block.timestamp
    );

    amountOut = amounts[1];

    // ✅ Validate output against oracle expectation
    SlippageProtection.validateOutput(amountOut, result.minOutput);
}
```

---

## 🔍 Monitoring & Testing

### View Functions for Monitoring

```solidity
// Check if price feed is healthy
bool isHealthy = oracle.isPriceFeedHealthy(USDC);

// Get price without revert (for monitoring)
(uint256 price, bool isStale) = oracle.getPriceUnsafe(USDC);

// Get price data with metadata
PriceData memory data = oracle.getPriceData(USDC);
// data.price = 1000000000000000000 (18 decimals)
// data.updatedAt = 1705932000
// data.source = 0 (0=Chainlink, 1=Manual)

// Preview slippage for a trade (front-end integration)
SlippageProtection.SlippageResult memory preview = adapter.previewSlippage(
    USDC,       // tokenIn
    MNT,        // tokenOut
    1000e6      // $1,000 USDC
);
// preview.expectedOutput = oracle-based expected MNT
// preview.minOutput = minimum acceptable output
// preview.slippageBps = 50 (0.5% for moderate config, small trade)
// preview.tradeSizeTier = 0 (SMALL)
```

### Testing Scenarios

```solidity
// Scenario 1: Small trade ($500)
// Expected: 0.3% slippage (conservative), 0.5% (moderate), 1% (aggressive)
adapter.deposit(500e6);

// Scenario 2: Medium trade ($50k)
// Expected: 0.5% slippage (conservative), 1% (moderate), 2% (aggressive)
adapter.deposit(50_000e6);

// Scenario 3: Whale trade ($2M)
// Expected: 2% slippage (conservative), 3% (moderate), 5% (aggressive)
adapter.deposit(2_000_000e6);

// Scenario 4: Stale price
// Expected: Revert with StalePrice() error
// (Simulate by not updating oracle for > heartbeat)

// Scenario 5: Price deviation attack
// Expected: Revert with PriceDeviation() error
// (Price jumps >10% from last known price)

// Scenario 6: Circuit breaker active
// Expected: Revert with CircuitBreakerTripped() error
oracle.activateCircuitBreaker(USDC, "Suspected oracle manipulation");
```

---

## 🛡️ Security Features

### PriceOracle Protections

| Protection | Description | Configuration |
|-----------|-------------|---------------|
| **Staleness Detection** | Revert if price older than heartbeat | `heartbeat: 3600` (1 hour) |
| **Deviation Limits** | Revert if price deviates >X% from last | `maxDeviation: 1000` (10%) |
| **Circuit Breaker** | Emergency pause all price queries | `activateCircuitBreaker()` |
| **Manual Fallback** | Owner sets emergency price | `setManualPrice()` |
| **Round Validation** | Check answeredInRound >= roundId | `answeredInRound >= roundId` |

### SlippageProtection Safeguards

| Safeguard | Description | Effect |
|-----------|-------------|--------|
| **Config Validation** | Checks tier ordering and BPS limits | Revert on invalid config |
| **Max Slippage Cap** | Global 10% maximum slippage | `MAX_SLIPPAGE_BPS = 1000` |
| **Threshold Ordering** | tier1 < tier2 < tier3 | Prevents tier overlap |
| **Slippage Progression** | small ≤ medium ≤ large ≤ whale | Ensures larger trades = higher slippage |
| **Output Validation** | Revert if actualOutput < minOutput | `validateOutput()` function |

---

## 🌐 Chainlink Price Feed Addresses (Mantle Mainnet)

```solidity
// Mantle Mainnet Chainlink Feeds
// Source: https://docs.chain.link/data-feeds/price-feeds/addresses?network=mantle

// USDC/USD
address CHAINLINK_USDC_USD = 0x...; // TODO: Replace with actual address

// MNT/USD
address CHAINLINK_MNT_USD = 0x...; // TODO: Replace with actual address

// WETH/USD
address CHAINLINK_ETH_USD = 0x...; // TODO: Replace with actual address

// USDT/USD
address CHAINLINK_USDT_USD = 0x...; // TODO: Replace with actual address
```

**Note**: Always verify Chainlink feed addresses from official documentation:
- https://docs.chain.link/data-feeds/price-feeds/addresses?network=mantle

---

## 📋 Configuration Checklist

### Deployment Checklist

- [ ] Deploy PriceOracle contract
- [ ] Add Chainlink price feeds for all supported tokens
- [ ] Set appropriate heartbeat values (e.g., 1 hour for stablecoins, 30 min for volatile assets)
- [ ] Set maxDeviation based on token volatility (5% for stable, 10% for volatile)
- [ ] Test price queries for all tokens
- [ ] Verify staleness detection works (advance time > heartbeat)
- [ ] Test circuit breaker activation/deactivation
- [ ] Set manual fallback prices for critical tokens
- [ ] Deploy adapters with oracle address
- [ ] Configure slippage profile (conservative/moderate/aggressive)
- [ ] Test slippage calculation for different trade sizes
- [ ] Monitor oracle health via `isPriceFeedHealthy()`
- [ ] Set up off-chain monitoring for price anomalies

### Security Checklist

- [ ] Verify all Chainlink feed addresses from official docs
- [ ] Set conservative heartbeat values initially
- [ ] Configure emergency guardian multi-sig for circuit breaker
- [ ] Test manual price fallback mechanism
- [ ] Verify deviation limits prevent manipulation
- [ ] Test slippage validation rejects bad swaps
- [ ] Monitor for repeated StalePrice errors
- [ ] Set up alerts for circuit breaker activations
- [ ] Review slippage config matches strategy risk profile

---

## 🔄 Upgrade Path from Hardcoded Slippage

### For Existing Adapters

1. **Add imports**:
   ```solidity
   import {SlippageProtection} from "../libraries/SlippageProtection.sol";
   import {IPriceOracle} from "../interfaces/IPriceOracle.sol";
   ```

2. **Add state variables**:
   ```solidity
   IPriceOracle public priceOracle;
   SlippageProtection.SlippageConfig public slippageConfig;
   ```

3. **Update constructor**:
   ```solidity
   constructor(..., address _priceOracle, address owner) Ownable(owner) {
       ...
       priceOracle = IPriceOracle(_priceOracle);
       slippageConfig = SlippageProtection.getModerateConfig();
   }
   ```

4. **Replace hardcoded slippage in swap functions**:
   ```solidity
   // Before:
   uint256 minAmountOut = (amountsOut[1] * (TOTAL_BPS - SLIPPAGE_BPS)) / TOTAL_BPS;

   // After:
   SlippageProtection.SwapParams memory params = SlippageProtection.SwapParams({
       tokenIn: tokenIn,
       tokenOut: tokenOut,
       amountIn: amountIn,
       priceOracle: address(priceOracle),
       config: slippageConfig
   });
   SlippageProtection.SlippageResult memory result = SlippageProtection.calculateSlippage(params);
   uint256 minAmountOut = result.minOutput;
   ```

5. **Add validation after swaps**:
   ```solidity
   SlippageProtection.validateOutput(actualOutput, minAmountOut);
   ```

6. **Add admin functions**:
   ```solidity
   function setPriceOracle(address newOracle) external onlyOwner { ... }
   function setSlippageConfig(SlippageProtection.SlippageConfig calldata newConfig) external onlyOwner { ... }
   function setConservativeSlippage() external onlyOwner { ... }
   function setModerateSlippage() external onlyOwner { ... }
   function setAggressiveSlippage() external onlyOwner { ... }
   ```

---

## 🎓 Best Practices

### Oracle Configuration

1. **Heartbeat Selection**:
   - Stablecoins (USDC, USDT): 1-2 hours
   - Volatile assets (ETH, BTC): 15-30 minutes
   - Exotic tokens: 5-15 minutes

2. **Deviation Limits**:
   - Stablecoins: 5% (should never move this much)
   - Blue-chip (ETH, BTC): 10%
   - Volatile tokens: 15-20%

3. **Manual Fallback**:
   - Always set manual prices for critical tokens
   - Update during circuit breaker events
   - Use TWAP from DEX as fallback reference

### Slippage Configuration

1. **Risk Profile Matching**:
   - Conservative strategies → Conservative slippage config
   - Moderate strategies → Moderate slippage config
   - Aggressive strategies → Aggressive slippage config

2. **Tier Threshold Tuning**:
   - Set tier1Threshold based on average user deposit size
   - Set tier3Threshold based on whale deposit threshold
   - Adjust based on historical trade volume distribution

3. **Monitoring**:
   - Log all slippage results with trade size tier
   - Alert on repeated WHALE tier trades (possible manipulation)
   - Track slippage revert rate (too high = config too tight)

---

## 📚 References

- **Chainlink Price Feeds**: https://docs.chain.link/data-feeds/price-feeds
- **Mantle Network Chainlink Feeds**: https://docs.chain.link/data-feeds/price-feeds/addresses?network=mantle
- **MEV Protection Best Practices**: https://www.paradigm.xyz/2020/08/ethereum-is-a-dark-forest
- **Dynamic Slippage Research**: https://ethresear.ch/t/dynamic-slippage-protection/

---

## ✅ Completion Summary

### What Was Implemented

✅ **PriceOracle.sol** - Chainlink integration with safety checks
✅ **SlippageProtection.sol** - Dynamic slippage library with trade size tiers
✅ **IPriceOracle.sol** - Standard oracle interface
✅ **FusionXAdapter.sol Enhancement** - Example adapter using dynamic slippage
✅ **Configuration Presets** - Conservative/Moderate/Aggressive configs
✅ **Admin Functions** - Oracle and slippage config management
✅ **Validation Functions** - Output validation against oracle expectations
✅ **Preview Functions** - Front-end integration for slippage previews

### Security Improvements

✅ Eliminates hardcoded slippage vulnerability
✅ Prevents MEV attacks on large trades (5% slippage for $1M+)
✅ Protects against stale oracle prices
✅ Validates swap outputs against oracle expectations
✅ Circuit breaker for emergency oracle failures
✅ Manual price fallback for critical situations
✅ Configurable slippage matching strategy risk profiles

---

**END OF DOCUMENTATION**
