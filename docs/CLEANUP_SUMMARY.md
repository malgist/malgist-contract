# CLEANUP_SUMMARY

## KEEP (production-critical)
- src/UserVault.sol — primary Mantle Sepolia vault powering adapter deposits.
- src/StrategyExecutor.sol — permissioned execution router invoked by UserVault + scripts.
- src/AdapterRegistry.sol — authoritative adapter whitelist shared by executors and governance.
- src/FeeManager.sol — routes protocol + strategist fees; required for live deposits.
- src/validators/AIStrategyValidator.sol — AI strategy gatekeeper referenced by registry + vault.
- script/DeployProtocolCore.s.sol — current path to AdapterRegistry/FeeManager/Faucet on Mantle.
- scripts/helpers/verify-all.sh — only maintained batch verification flow against Mantle explorers.

## REVIEW (experimental / staging)
- src/AutoRebalanceEngine.sol — keeper research queue; keep until vNext decision.
- src/UniversalVaultV2.sol — MEV-aware prototype; decide whether to fold into UserVault backlog.
- src/UniversalVaultV3.sol — governance-heavy research vault; requires dedicated audit or archival.
- src/adapters/FusionXAdapterV2.sol — upgrade candidate pending protocol greenlight.
- src/libraries/SlippageProtection.sol — oracle-aware math prototype; evaluate reuse vs removal.
- script/DeployUserVault.s.sol — spins up mocks + adapters; confirm whether still needed post mainnet.

## REMOVE LATER (legacy / redundancy)
- src/UserVaultV2.sol — deprecated copy-trading implementation kept only for regression history.
- src/StrategyVault.sol — NFT-centric vault replaced by StrategyRegistry + UserVault combo.
- src/BugBountyReadiness.sol — documentation helper with no on-chain consumers.
- scripts/helpers/deploy-final.sh — emergency redeploy script superseded by deploy-with-check.
- scripts/helpers/verify-manual.sh — manual checklist duplicated by verify-all automation.
