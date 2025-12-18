// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title StrategyValidator
 * @notice Custom validation contract for strategy configurations
 * @dev Implements custom business logic for strategy approval
 */

interface IStrategyConfig {
    struct StrategyConfig {
        address[] adapters;
        uint16[] ratios;
        address creator;
        uint16 creatorFeeBps;
        uint8 riskLevel;
        bool isActive;
        uint40 createdAt;
        uint16 version;
        uint8 rebalanceFrequency;
        bytes32 strategistName;
        uint8 slippageToleranceBps;
    }
}

contract StrategyValidator is IStrategyConfig {
    
    // ============================================================================
    // VALIDATION RULES
    // ============================================================================

    /**
     * @notice Validates strategy configuration
     * @param config Strategy configuration to validate
     * @return isValid True if strategy passes all validation rules
     */
    function validateStrategy(StrategyConfig memory config) external pure returns (bool) {
        // Rule 1: Creator cannot be zero address
        if (config.creator == address(0)) {
            return false;
        }

        // Rule 2: At least 1 adapter required
        if (config.adapters.length < 1) {
            return false;
        }

        // Rule 3: At most 10 adapters
        if (config.adapters.length > 10) {
            return false;
        }

        // Rule 4: Ratios must sum to 10000 basis points
        uint256 ratioSum = 0;
        for (uint256 i = 0; i < config.ratios.length; i++) {
            ratioSum += config.ratios[i];
        }
        if (ratioSum != 10000) {
            return false;
        }

        // Rule 5: Creator fee cannot exceed 10% (1000 BPS)
        if (config.creatorFeeBps > 1000) {
            return false;
        }

        // Rule 6: Risk level must be 1-5
        if (config.riskLevel < 1 || config.riskLevel > 5) {
            return false;
        }

        // Rule 7: Rebalance frequency must be reasonable (1-90 days)
        if (config.rebalanceFrequency < 1 || config.rebalanceFrequency > 90) {
            return false;
        }

        // Rule 8: Slippage tolerance must not exceed 5% (500 BPS)
        if (config.slippageToleranceBps > 500) {
            return false;
        }

        // Rule 9: At least one adapter must have non-zero allocation
        bool hasAllocation = false;
        for (uint256 i = 0; i < config.ratios.length; i++) {
            if (config.ratios[i] > 0) {
                hasAllocation = true;
                break;
            }
        }
        if (!hasAllocation) {
            return false;
        }

        // Rule 10: No duplicate adapters (if needed, check against adapter registry)
        for (uint256 i = 0; i < config.adapters.length; i++) {
            for (uint256 j = i + 1; j < config.adapters.length; j++) {
                if (config.adapters[i] == config.adapters[j]) {
                    return false;
                }
            }
        }

        // All validations passed
        return true;
    }

    /**
     * @notice Get validation requirements as human-readable rules
     * @return rules Array of validation rule descriptions
     */
    function getValidationRules() external pure returns (string[] memory rules) {
        rules = new string[](10);
        rules[0] = "Creator cannot be zero address";
        rules[1] = "At least 1 adapter required";
        rules[2] = "At most 10 adapters allowed";
        rules[3] = "Ratios must sum to 10000 basis points";
        rules[4] = "Creator fee cannot exceed 10% (1000 BPS)";
        rules[5] = "Risk level must be 1-5";
        rules[6] = "Rebalance frequency must be 1-90 days";
        rules[7] = "Slippage tolerance cannot exceed 5% (500 BPS)";
        rules[8] = "At least one adapter must have non-zero allocation";
        rules[9] = "No duplicate adapters in configuration";
        return rules;
    }
}

// ============================================================================
// STRATEGY VALIDATOR EXTENDED (Future Enhancement)
// ============================================================================

/**
 * @title StrategyValidatorExtended
 * @notice Advanced validation with risk scoring and performance history
 */

interface IAdapterRegistry {
    function getAdapterScore(address adapter) external view returns (uint8);
    function isAdapterTrusted(address adapter) external view returns (bool);
}

interface IPerformanceHistory {
    function getCreatorWinRate(address creator) external view returns (uint256);
    function getAverageCreatorPerformance(address creator) external view returns (int256);
}

contract StrategyValidatorExtended is IStrategyConfig {
    
    IAdapterRegistry public adapterRegistry;
    IPerformanceHistory public performanceHistory;

    constructor(address _adapterRegistry, address _performanceHistory) {
        adapterRegistry = IAdapterRegistry(_adapterRegistry);
        performanceHistory = IPerformanceHistory(_performanceHistory);
    }

    /**
     * @notice Advanced validation with risk and history scoring
     * @param config Strategy configuration
     * @return isValid True if passes advanced validation
     * @return riskScore Risk score (0-100, higher = riskier)
     * @return approvalScore Approval confidence score (0-100)
     */
    function validateStrategyExtended(StrategyConfig memory config) 
        external 
        view 
        returns (bool isValid, uint8 riskScore, uint8 approvalScore)
    {
        // Basic validation first
        isValid = _basicValidation(config);
        if (!isValid) {
            return (false, 0, 0);
        }

        // Calculate risk score based on strategy parameters
        riskScore = _calculateRiskScore(config);

        // Calculate approval score based on creator history
        approvalScore = _calculateApprovalScore(config);

        return (true, riskScore, approvalScore);
    }

    function _basicValidation(StrategyConfig memory config) internal pure returns (bool) {
        if (config.creator == address(0)) return false;
        if (config.adapters.length < 1 || config.adapters.length > 10) return false;
        if (config.riskLevel < 1 || config.riskLevel > 5) return false;
        if (config.creatorFeeBps > 1000) return false;
        return true;
    }

    function _calculateRiskScore(StrategyConfig memory config)
        internal
        pure
        returns (uint8)
    {
        uint8 score = 0;

        // Risk level contribution (0-40 points)
        score += uint8((config.riskLevel - 1) * 10);  // 0, 10, 20, 30, 40

        // Slippage tolerance contribution (0-30 points)
        score += uint8(config.slippageToleranceBps / 20);  // 0-25 for 500 max

        // Number of adapters contribution (0-20 points)
        // More adapters = higher complexity = higher risk
        if (config.adapters.length <= 2) {
            score += 5;
        } else if (config.adapters.length <= 5) {
            score += 10;
        } else {
            score += 15;
        }

        // Creator fee contribution (0-10 points)
        // Higher fees = incentive alignment but also higher cost
        score += uint8(config.creatorFeeBps / 100);

        return score;
    }

    function _calculateApprovalScore(StrategyConfig memory config)
        internal
        view
        returns (uint8)
    {
        uint8 score = 50;  // Start at 50

        // Creator history (0-30 points)
        uint256 winRate = performanceHistory.getCreatorWinRate(config.creator);
        if (winRate > 75) {
            score += 30;
        } else if (winRate > 60) {
            score += 20;
        } else if (winRate > 50) {
            score += 10;
        }

        // Creator performance (0-20 points)
        int256 avgPerf = performanceHistory.getAverageCreatorPerformance(config.creator);
        if (avgPerf > 0) {
            score += 10;  // Positive performance
        }

        // Adapter quality (0-20 points)
        uint256 trustScore = 0;
        for (uint256 i = 0; i < config.adapters.length; i++) {
            if (adapterRegistry.isAdapterTrusted(config.adapters[i])) {
                trustScore += 10 / config.adapters.length;
            }
        }
        score += uint8(trustScore);

        return score;
    }

    /**
     * @notice Get risk score categories
     */
    function getRiskCategories() external pure returns (string[] memory categories) {
        categories = new string[](5);
        categories[0] = "Conservative (0-20)";
        categories[1] = "Low Risk (21-40)";
        categories[2] = "Medium Risk (41-60)";
        categories[3] = "High Risk (61-80)";
        categories[4] = "Aggressive (81-100)";
        return categories;
    }
}
