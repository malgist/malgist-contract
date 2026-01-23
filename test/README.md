# MALGIST Test Suite

This directory houses all Foundry-based tests for the protocol. Suites are grouped by intent so contributors can quickly discover the right coverage surface and target-only the scenarios they need during development.

## Directory Layout

```
test/
├── core/           Fundamental vault + accounting flows that must pass before any deploy
├── security/       Safeguards covering pause logic, adapter access, and slippage guards
├── strategy/       Strategy lifecycle, StrategyNFT metadata, and registry integration
├── experimental/   Research-heavy suites (4626 vault, auto rebalance, versioning, etc.)
├── fuzz/           Property-based harnesses (currently opt-in / legacy)
└── README.md       You are here
```

### Folder Details

| Folder | Focus | Key Files |
| --- | --- | --- |
| `core/` | Deterministic execution paths for user vaults, fee pipelines, composable vaults, faucets, and performance metrics. | `UniversalVault.t.sol`, `UserVault.t.sol`, `UserVaultV2Integration.t.sol`, `ShareAccounting.t.sol`, `FeeManager.t.sol`, `ComposableVault.t.sol`, `PerformanceTracking.t.sol`, `Faucet.t.sol` |
| `security/` | Emergency controls, adapter ACLs, MEV / slippage enforcement, and guardian overrides. | `EmergencyPause.t.sol`, `AdapterAccessControl.t.sol`, `SlippageProtection.t.sol` |
| `strategy/` | Strategy publishing lifecycle, NFT metadata, and registry-governed creation caps. | `StrategyNFT.t.sol`, `PermissionlessStrategy.t.sol` |
| `experimental/` | Optional suites for prototypes and research subsystems. They do not block CI but provide deep regression coverage when enabled. | `ERC4626StrategyVault.t.sol`, `AutoRebalance.t.sol`, `StrategyVersioning.t.sol` |
| `fuzz/` | Property-based or Echidna-driven invariants. These require manual enablement because they target legacy vault APIs. | `EchidnaFuzzTest.sol` |

## Running Tests

- Run the full deterministic suite:
  ```bash
  forge test
  ```
- Target a category:
  ```bash
  forge test --match-path test/core/*
  forge test --match-path test/security/*
  forge test --match-path test/experimental/*
  ```
- Run a single file:
  ```bash
  forge test --match-path test/strategy/StrategyNFT.t.sol
  ```

> **Note:** Experimental and fuzz folders are optional. Keep them up to date when touching related contracts, but they are safe to skip in default CI workflows.
