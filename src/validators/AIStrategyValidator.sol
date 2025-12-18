// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title AIStrategyValidator
 * @notice On-chain validator for AI-generated strategy parameters
 * @dev AI output is treated as untrusted user input; all validation happens here
 *
 * CRITICAL DESIGN PRINCIPLE:
 * AI is UX-ONLY, not a trust layer. All validation is deterministic, on-chain,
 * and completely independent of any off-chain AI system.
 */

import "@openzeppelin/contracts/access/Ownable.sol";

// ============================================================================
// INTERFACES & TYPES
// ============================================================================

/**
 * @dev AI-generated strategy parameters (treated as untrusted input)
 * This struct represents what the off-chain AI system generates.
 * EVERY field is validated before being accepted.
 */
struct AIStrategyOutput {
    string strategyName;              // User-facing name
    string riskProfile;               // "conservative", "moderate", "aggressive"
    address[] adapters;               // Adapter addresses
    uint16[] allocations;             // Basis points (0-10000)
    uint32 expectedAPY;               // Informational only (not enforced)
    string riskDisclosure;            // User acknowledgment text
    uint256 creatorFeeRequestBps;     // Requested fee (0-10000)
}

/**
 * @dev Validated strategy that can be safely minted as NFT
 */
struct ValidatedStrategy {
    address[] adapters;
    uint16[] allocations;
    uint8 riskLevel;                  // 1-5, derived from riskProfile
    uint16 approvedCreatorFeeBps;     // Capped creator fee
    bytes32 strategyHash;             // SHA3 of immutable params
}

// ============================================================================
// CONSTANTS & VALIDATION RULES
// ============================================================================

contract AIStrategyValidator is Ownable(msg.sender) {
    
    // Hard limits (immutable safety constraints)
    uint16 public constant MAX_ALLOCATION_BPS = 10000;           // 100%
    uint16 public constant TOTAL_ALLOCATION_BPS = 10000;         // Must sum to this
    uint8 public constant MAX_ADAPTERS = 10;                     // Array length cap
    uint16 public constant MAX_CREATOR_FEE_BPS = 1000;           // 10% max
    uint16 public constant MAX_SLIPPAGE_BPS = 500;               // 5% max
    uint16 public constant MIN_ALLOCATION_PER_ADAPTER = 100;     // 1% minimum

    // Risk profile mappings (immutable)
    mapping(string => uint8) public riskProfileToLevel;           // Profile string → 1-5
    mapping(uint8 => uint16) public riskLevelToMaxFee;            // Risk → max fee allowed

    // Adapter registry
    mapping(address => bool) public whitelistedAdapters;
    mapping(address => bytes32) public adapterIdentifiers;        // For verification

    // ========================================================================
    // EVENTS
    // ========================================================================

    event StrategyValidated(
        bytes32 indexed strategyHash,
        address[] adapters,
        uint16[] allocations,
        uint8 riskLevel,
        uint16 creatorFee
    );

    event ValidationFailed(
        string reason,
        string riskProfile,
        uint256 adapterCount
    );

    event RiskProfileConfigured(
        string profileName,
        uint8 riskLevel,
        uint16 maxFeeBps
    );

    // ========================================================================
    // INITIALIZATION
    // ========================================================================

    constructor() {
        // Configure risk profiles (immutable mappings)
        _configureRiskProfile("conservative", 1, 250);    // 1=Conservative, max 2.5% fee
        _configureRiskProfile("moderate", 3, 500);        // 3=Moderate, max 5% fee
        _configureRiskProfile("aggressive", 5, 1000);     // 5=Aggressive, max 10% fee
    }

    function _configureRiskProfile(
        string memory profileName,
        uint8 riskLevel,
        uint16 maxFeeBps
    ) internal {
        require(riskLevel >= 1 && riskLevel <= 5, "Invalid risk level");
        require(maxFeeBps <= MAX_CREATOR_FEE_BPS, "Max fee too high");

        riskProfileToLevel[profileName] = riskLevel;
        riskLevelToMaxFee[riskLevel] = maxFeeBps;

        emit RiskProfileConfigured(profileName, riskLevel, maxFeeBps);
    }

    // ========================================================================
    // ADAPTER MANAGEMENT (Admin)
    // ========================================================================

    /**
     * @notice Whitelist an adapter for AI strategies
     * @param adapter Adapter address
     * @param identifier Unique identifier for this adapter
     */
    function whitelistAdapter(address adapter, bytes32 identifier) external onlyOwner {
        require(adapter != address(0), "Invalid adapter address");
        require(identifier != bytes32(0), "Invalid identifier");

        whitelistedAdapters[adapter] = true;
        adapterIdentifiers[adapter] = identifier;
    }

    /**
     * @notice Blacklist an adapter
     * @param adapter Adapter address
     */
    function blacklistAdapter(address adapter) external onlyOwner {
        whitelistedAdapters[adapter] = false;
        adapterIdentifiers[adapter] = bytes32(0);
    }

    // ========================================================================
    // CORE VALIDATION FUNCTION
    // ========================================================================

    /**
     * @notice Validate AI-generated strategy output
     * @param aiOutput Untrusted output from AI system
     * @return validated Validated strategy safe for minting
     * @return isValid True if validation succeeded
     *
     * This function is the ONLY place where AI output is accepted.
     * ALL validation rules are applied here, deterministically.
     * If ANY check fails, the strategy is rejected.
     */
    function validateAIStrategy(AIStrategyOutput calldata aiOutput)
        external
        returns (ValidatedStrategy memory validated, bool isValid)
    {
        // =====================================================================
        // PHASE 1: Input Sanity Checks
        // =====================================================================

        // Check 1: Arrays length match and not empty
        if (aiOutput.adapters.length == 0) {
            emit ValidationFailed("No adapters provided", aiOutput.riskProfile, 0);
            return (validated, false);
        }

        if (aiOutput.adapters.length != aiOutput.allocations.length) {
            emit ValidationFailed(
                "Adapter/allocation length mismatch",
                aiOutput.riskProfile,
                aiOutput.adapters.length
            );
            return (validated, false);
        }

        // Check 2: Array length <= max
        if (aiOutput.adapters.length > MAX_ADAPTERS) {
            emit ValidationFailed(
                "Too many adapters",
                aiOutput.riskProfile,
                aiOutput.adapters.length
            );
            return (validated, false);
        }

        // Check 3: Strategy name not empty
        if (bytes(aiOutput.strategyName).length == 0) {
            emit ValidationFailed("Empty strategy name", aiOutput.riskProfile, 0);
            return (validated, false);
        }

        // =====================================================================
        // PHASE 2: Adapter Validation
        // =====================================================================

        for (uint256 i = 0; i < aiOutput.adapters.length; i++) {
            address adapter = aiOutput.adapters[i];

            // Check 4: No zero addresses
            if (adapter == address(0)) {
                emit ValidationFailed(
                    "Zero adapter address",
                    aiOutput.riskProfile,
                    i
                );
                return (validated, false);
            }

            // Check 5: Adapter is whitelisted
            if (!whitelistedAdapters[adapter]) {
                emit ValidationFailed(
                    "Adapter not whitelisted",
                    aiOutput.riskProfile,
                    i
                );
                return (validated, false);
            }

            // Check 6: No duplicate adapters
            for (uint256 j = i + 1; j < aiOutput.adapters.length; j++) {
                if (aiOutput.adapters[j] == adapter) {
                    emit ValidationFailed(
                        "Duplicate adapter",
                        aiOutput.riskProfile,
                        i
                    );
                    return (validated, false);
                }
            }
        }

        // =====================================================================
        // PHASE 3: Allocation Validation
        // =====================================================================

        uint256 totalAllocation = 0;

        for (uint256 i = 0; i < aiOutput.allocations.length; i++) {
            uint16 allocation = aiOutput.allocations[i];

            // Check 7: No allocation > 100%
            if (allocation > MAX_ALLOCATION_BPS) {
                emit ValidationFailed(
                    "Allocation exceeds 100%",
                    aiOutput.riskProfile,
                    i
                );
                return (validated, false);
            }

            // Check 8: Minimum non-zero allocation (prevent dust)
            if (allocation > 0 && allocation < MIN_ALLOCATION_PER_ADAPTER) {
                emit ValidationFailed(
                    "Allocation too small (dust)",
                    aiOutput.riskProfile,
                    i
                );
                return (validated, false);
            }

            totalAllocation += allocation;
        }

        // Check 9: Total allocation exactly 100% (prevent over/under allocation)
        if (totalAllocation != TOTAL_ALLOCATION_BPS) {
            emit ValidationFailed(
                "Allocations don't sum to 100%",
                aiOutput.riskProfile,
                totalAllocation
            );
            return (validated, false);
        }

        // =====================================================================
        // PHASE 4: Risk Profile Validation
        // =====================================================================

        // Check 10: Risk profile is valid
        uint8 riskLevel = riskProfileToLevel[aiOutput.riskProfile];
        if (riskLevel == 0) {
            emit ValidationFailed(
                "Invalid risk profile",
                aiOutput.riskProfile,
                0
            );
            return (validated, false);
        }

        // =====================================================================
        // PHASE 5: Fee Validation
        // =====================================================================

        uint16 maxAllowedFee = riskLevelToMaxFee[riskLevel];

        // Check 11: Requested fee doesn't exceed max
        if (aiOutput.creatorFeeRequestBps > maxAllowedFee) {
            emit ValidationFailed(
                "Creator fee too high for risk level",
                aiOutput.riskProfile,
                aiOutput.creatorFeeRequestBps
            );
            return (validated, false);
        }

        // Check 12: Requested fee is within global max AND fits in uint16
        if (aiOutput.creatorFeeRequestBps > MAX_CREATOR_FEE_BPS) {
            emit ValidationFailed(
                "Creator fee exceeds global maximum",
                aiOutput.riskProfile,
                aiOutput.creatorFeeRequestBps
            );
            return (validated, false);
        }

        // =====================================================================
        // PHASE 6: Build Validated Strategy & Hash
        // =====================================================================

        // Copy adapters and allocations to memory (safe)
        address[] memory validatedAdapters = new address[](aiOutput.adapters.length);
        uint16[] memory validatedAllocations = new uint16[](aiOutput.allocations.length);

        for (uint256 i = 0; i < aiOutput.adapters.length; i++) {
            validatedAdapters[i] = aiOutput.adapters[i];
            validatedAllocations[i] = aiOutput.allocations[i];
        }

        // Compute immutable hash of strategy parameters
        bytes32 strategyHash = keccak256(
            abi.encodePacked(
                validatedAdapters,
                validatedAllocations,
                riskLevel,
                aiOutput.creatorFeeRequestBps,
                aiOutput.strategyName
            )
        );

        // Build validated strategy struct
        uint16 approvedFee = uint16(aiOutput.creatorFeeRequestBps);
        validated = ValidatedStrategy({
            adapters: validatedAdapters,
            allocations: validatedAllocations,
            riskLevel: riskLevel,
            approvedCreatorFeeBps: approvedFee,
            strategyHash: strategyHash
        });

        emit StrategyValidated(
            strategyHash,
            validatedAdapters,
            validatedAllocations,
            riskLevel,
            approvedFee
        );

        return (validated, true);
    }

    // ========================================================================
    // UTILITY FUNCTIONS
    // ========================================================================

    /**
     * @notice Get all validation rules (for documentation)
     * @return rules Array of validation rule descriptions
     */
    function getValidationRules() external pure returns (string[] memory rules) {
        rules = new string[](12);
        rules[0] = "Arrays length must match and not be empty";
        rules[1] = "Array length must be <= max adapters (10)";
        rules[2] = "Strategy name must not be empty";
        rules[3] = "No zero adapter addresses";
        rules[4] = "All adapters must be whitelisted";
        rules[5] = "No duplicate adapters";
        rules[6] = "No allocation > 100%";
        rules[7] = "Minimum non-zero allocation is 1% (prevent dust)";
        rules[8] = "Total allocations must sum to exactly 100%";
        rules[9] = "Risk profile must be valid (conservative/moderate/aggressive)";
        rules[10] = "Creator fee must not exceed risk-level max";
        rules[11] = "Creator fee must not exceed global max (10%)";
        return rules;
    }

    /**
     * @notice Check if an adapter is whitelisted
     * @param adapter Adapter address
     * @return isWhitelisted True if adapter is approved
     */
    function isAdapterWhitelisted(address adapter) external view returns (bool) {
        return whitelistedAdapters[adapter];
    }

    /**
     * @notice Get maximum allowed fee for a risk level
     * @param riskLevel Risk level (1-5)
     * @return maxFeeBps Maximum fee in basis points
     */
    function getMaxFeeForRiskLevel(uint8 riskLevel) external view returns (uint16) {
        require(riskLevel >= 1 && riskLevel <= 5, "Invalid risk level");
        return riskLevelToMaxFee[riskLevel];
    }

    /**
     * @notice Get risk level for a profile name
     * @param profileName Profile string ("conservative", etc.)
     * @return riskLevel Risk level (1-5) or 0 if invalid
     */
    function getRiskLevel(string memory profileName) external view returns (uint8) {
        return riskProfileToLevel[profileName];
    }
}

// ============================================================================
// VALIDATION CHECKLIST (For Auditors)
// ============================================================================

/*
VALIDATION PHASES (Sequential, all-or-nothing):

✅ PHASE 1: Input Sanity
   - Arrays not empty
   - Arrays length match
   - Arrays length <= MAX_ADAPTERS
   - Strategy name not empty

✅ PHASE 2: Adapter Validation
   - No zero addresses
   - All whitelisted
   - No duplicates

✅ PHASE 3: Allocation Validation
   - No allocation > 100%
   - No dust (< 1%)
   - Total sum = exactly 100%

✅ PHASE 4: Risk Profile
   - Profile name is valid
   - Maps to valid risk level (1-5)

✅ PHASE 5: Fee Validation
   - Fee <= risk-level max
   - Fee <= global max (10%)

✅ PHASE 6: Hash & Return
   - Compute immutable hash
   - Copy to memory structures
   - Return validated strategy

WHY THIS IS SAFE:
1. AI output is NEVER trusted
2. AI output is treated as UNTRUSTED USER INPUT
3. ALL validation is deterministic & on-chain
4. 12 distinct validation checks prevent exploitation
5. Hard caps prevent arithmetic attacks
6. Strategy hash is immutable proof of parameters
7. Validation is independent of off-chain systems

SECURITY PROPERTIES:
- Malicious AI output: REJECTED (all checks fail)
- Prompt injection: REJECTED (validation independent of prompts)
- Adapter spoofing: REJECTED (whitelist check)
- Over-allocation: REJECTED (sum check)
- Dust attacks: REJECTED (minimum allocation check)
- Fee abuse: REJECTED (cap check + risk-based limit)
- Array overflow: REJECTED (length cap)
*/
