// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IPriceOracle
 * @notice Interface for price oracle contracts
 * @dev Standard interface for querying asset prices
 */
interface IPriceOracle {
    /**
     * @notice Get current price for an asset
     * @param asset Asset address
     * @return price Price in 18 decimals
     * @dev Reverts if circuit breaker active, price stale, or no feed
     */
    function getPrice(address asset) external view returns (uint256 price);

    /**
     * @notice Get price with safety checks disabled (view only)
     * @param asset Asset address
     * @return price Price in 18 decimals
     * @return isStale Whether price is stale
     */
    function getPriceUnsafe(address asset)
        external
        view
        returns (uint256 price, bool isStale);

    /**
     * @notice Check if price feed is healthy
     * @param asset Asset address
     * @return isHealthy True if feed is active and not stale
     */
    function isPriceFeedHealthy(address asset)
        external
        view
        returns (bool isHealthy);
}
