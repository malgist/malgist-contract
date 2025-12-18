# MALGIST Faucet - Frontend Integration Guide

## Quick Start

### 1. Import ABIs

```typescript
// abis/Faucet.json
export const FAUCET_ABI = [
  {
    inputs: [],
    name: "claim",
    outputs: [],
    stateMutability: "nonpayable",
    type: "function",
  },
  {
    inputs: [{ internalType: "address", name: "user", type: "address" }],
    name: "canClaim",
    outputs: [{ internalType: "bool", name: "", type: "bool" }],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [{ internalType: "address", name: "user", type: "address" }],
    name: "getTimeUntilClaim",
    outputs: [{ internalType: "uint256", name: "", type: "uint256" }],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [],
    name: "getFaucetState",
    outputs: [
      { internalType: "uint256", name: "balance", type: "uint256" },
      { internalType: "uint256", name: "amount", type: "uint256" },
      { internalType: "uint256", name: "cooldown", type: "uint256" },
    ],
    stateMutability: "view",
    type: "function",
  },
  {
    anonymous: false,
    inputs: [
      { indexed: true, name: "user", type: "address" },
      { indexed: false, name: "amount", type: "uint256" },
      { indexed: false, name: "timestamp", type: "uint256" },
    ],
    name: "Claimed",
    type: "event",
  },
];

export const MOCK_USDC_ABI = [
  {
    inputs: [{ internalType: "address", name: "to", type: "address" }],
    name: "balanceOf",
    outputs: [{ internalType: "uint256", name: "", type: "uint256" }],
    stateMutability: "view",
    type: "function",
  },
];
```

### 2. Configuration

```typescript
// config/contracts.ts
export const TESTNET_CONFIG = {
  chainId: 5003,
  chainName: "Mantle Testnet",
  rpc: "https://rpc.sepolia.mantle.xyz",
  contracts: {
    mockUsdc: "0x...", // Deployed MockUSDC address
    faucet: "0x...", // Deployed Faucet address
  },
};

export const isTestnet = (chainId: number) =>
  chainId === TESTNET_CONFIG.chainId;
```

### 3. React Hooks

```typescript
// hooks/useFaucet.ts
import { useContractRead, useContractWrite, useAccount } from "wagmi";
import { FAUCET_ABI, MOCK_USDC_ABI } from "../abis";
import { TESTNET_CONFIG } from "../config/contracts";

export function useFaucetState() {
  const { data: state } = useContractRead({
    address: TESTNET_CONFIG.contracts.faucet,
    abi: FAUCET_ABI,
    functionName: "getFaucetState",
  });

  return state
    ? {
        balance: state[0],
        claimAmount: state[1],
        cooldown: state[2],
      }
    : null;
}

export function useFaucetClaim() {
  const { address } = useAccount();

  // Can user claim?
  const { data: canClaim } = useContractRead({
    address: TESTNET_CONFIG.contracts.faucet,
    abi: FAUCET_ABI,
    functionName: "canClaim",
    args: [address!],
    enabled: !!address,
  });

  // Time until next claim (seconds)
  const { data: timeUntilClaim } = useContractRead({
    address: TESTNET_CONFIG.contracts.faucet,
    abi: FAUCET_ABI,
    functionName: "getTimeUntilClaim",
    args: [address!],
    enabled: !!address,
  });

  // Claim function
  const {
    write: claim,
    isLoading,
    isSuccess,
    error,
  } = useContractWrite({
    address: TESTNET_CONFIG.contracts.faucet,
    abi: FAUCET_ABI,
    functionName: "claim",
  });

  // User's USDC balance
  const { data: balance, refetch: refetchBalance } = useContractRead({
    address: TESTNET_CONFIG.contracts.mockUsdc,
    abi: MOCK_USDC_ABI,
    functionName: "balanceOf",
    args: [address!],
    enabled: !!address,
  });

  return {
    canClaim: canClaim === true,
    timeUntilClaim: timeUntilClaim ? Number(timeUntilClaim) : 0,
    claim: () => claim(),
    isLoading,
    isSuccess,
    error,
    balance: balance ? BigInt(balance).toString() : "0",
    refetchBalance,
  };
}
```

### 4. UI Component

```typescript
// components/FaucetButton.tsx
import React, { useEffect, useState } from "react";
import { useFaucetClaim, useFaucetState } from "../hooks/useFaucet";
import { useAccount } from "wagmi";

export function FaucetButton() {
  const { address, isConnected } = useAccount();
  const {
    canClaim,
    timeUntilClaim,
    claim,
    isLoading,
    isSuccess,
    balance,
    refetchBalance,
  } = useFaucetClaim();
  const state = useFaucetState();
  const [displayTime, setDisplayTime] = useState("");

  // Countdown timer
  useEffect(() => {
    if (timeUntilClaim > 0) {
      const interval = setInterval(() => {
        setDisplayTime(formatTime(timeUntilClaim));
      }, 1000);
      return () => clearInterval(interval);
    }
  }, [timeUntilClaim]);

  useEffect(() => {
    if (isSuccess) {
      refetchBalance();
      // Show success toast
      setTimeout(() => alert("Tokens claimed successfully!"), 500);
    }
  }, [isSuccess, refetchBalance]);

  if (!isConnected) {
    return <button disabled>Connect Wallet</button>;
  }

  const claimAmount = state ? formatUnits(state.claimAmount, 6) : "1000";

  return (
    <div className="faucet-container">
      <h3>Testnet Faucet</h3>

      <div className="faucet-info">
        <p>Balance: {formatUnits(balance, 6)} USDC</p>
        <p>Faucet Balance: {formatUnits(state?.balance || 0n, 6)} USDC</p>
      </div>

      <button
        onClick={() => claim()}
        disabled={!canClaim || isLoading}
        className={canClaim ? "btn-success" : "btn-disabled"}
      >
        {isLoading && <span>Claiming...</span>}
        {!canClaim && <span>Claim Available in {displayTime}</span>}
        {canClaim && !isLoading && <span>Claim {claimAmount} USDC</span>}
      </button>

      <p className="faucet-disclaimer">
        ⚠️ Testnet only. Claims limited to 1 per 24 hours.
      </p>
    </div>
  );
}

// Utility functions
function formatUnits(value: bigint | number, decimals: number): string {
  const bigValue = typeof value === "number" ? BigInt(value) : value;
  const divisor = BigInt(10 ** decimals);
  const quotient = bigValue / divisor;
  return quotient.toString();
}

function formatTime(seconds: number): string {
  const hours = Math.floor(seconds / 3600);
  const minutes = Math.floor((seconds % 3600) / 60);
  const secs = seconds % 60;

  if (hours > 0) {
    return `${hours}h ${minutes}m`;
  }
  if (minutes > 0) {
    return `${minutes}m ${secs}s`;
  }
  return `${secs}s`;
}
```

### 5. Integration Example

```typescript
// pages/demo.tsx
import React from "react";
import { FaucetButton } from "../components/FaucetButton";
import { ConnectButton } from "@rainbow-me/rainbowkit";

export default function DemoPage() {
  return (
    <div className="demo-container">
      <h1>MALGIST Hackathon Demo</h1>

      <div className="toolbar">
        <ConnectButton />
      </div>

      <div className="demo-content">
        <section>
          <h2>Step 1: Get Test Tokens</h2>
          <FaucetButton />
        </section>

        <section>
          <h2>Step 2: Create a Strategy</h2>
          {/* Strategy creation UI */}
        </section>

        <section>
          <h2>Step 3: Copy a Strategy</h2>
          {/* Strategy copying UI */}
        </section>
      </div>

      <footer>
        <p>This is a testnet demo. Do not send real funds.</p>
      </footer>
    </div>
  );
}
```

### 6. Event Listening

```typescript
// hooks/useFaucetEvents.ts
import { useContractEvent } from "wagmi";
import { FAUCET_ABI } from "../abis";
import { TESTNET_CONFIG } from "../config/contracts";

export function useFaucetClaimedEvents() {
  useContractEvent({
    address: TESTNET_CONFIG.contracts.faucet,
    abi: FAUCET_ABI,
    eventName: "Claimed",
    listener: (logs) => {
      logs.forEach((log) => {
        const { user, amount, timestamp } = log.args;
        console.log(`User ${user} claimed ${amount} USDC at ${timestamp}`);
        // Update UI, analytics, etc.
      });
    },
  });
}
```

## Testing Checklist

- [ ] User can connect wallet
- [ ] Faucet state displays correctly
- [ ] User can claim tokens
- [ ] Balance updates after claim
- [ ] Cooldown timer starts after claim
- [ ] Cannot claim within cooldown period
- [ ] Can claim after cooldown expires
- [ ] Error displays gracefully
- [ ] Works on Mantle testnet (5003)
- [ ] Shows error on wrong network

## Common Issues & Solutions

### Issue: "NotTestnet" error

**Cause**: Connected to wrong network  
**Solution**: Switch to Mantle testnet (chainId 5003)

### Issue: "InsufficientFaucetBalance" error

**Cause**: Faucet contract doesn't have USDC tokens  
**Solution**: Admin needs to seed faucet with tokens via `mint()`

### Issue: "ClaimTooSoon" error

**Cause**: User claimed recently  
**Solution**: Wait for cooldown period (default: 24 hours)

### Issue: Claims not appearing in balance

**Cause**: UI not refreshing after transaction  
**Solution**: Call `refetchBalance()` on successful claim

## Environment Setup

```bash
# .env.local
VITE_TESTNET_CHAIN_ID=5003
VITE_FAUCET_ADDRESS=0x...
VITE_MOCK_USDC_ADDRESS=0x...
VITE_RPC_URL=https://rpc.sepolia.mantle.xyz
```

## Performance Notes

- **Faucet balance check**: ~2ms (view function)
- **Claim transaction**: ~50k gas, ~0.5s on testnet
- **Cooldown check**: ~2ms (view function)
- **Balance refresh**: ~500ms after confirmation

## Security Reminders

⚠️ **Never:**

- Share private keys in frontend code
- Store actual funds on testnet faucet
- Deploy faucet to mainnet
- Bypass chain ID checks

✅ **Always:**

- Use testnet-only chain ID (5003)
- Limit claim amounts (default: 1000 USDC)
- Enforce rate limiting (default: 24 hour cooldown)
- Show testnet disclaimer to users

## Support

For issues or questions:

- Check Faucet.sol documentation: `FAUCET_DESIGN.md`
- Review test suite: `test/Faucet.t.sol`
- Check deployment logs: `deployments/`
