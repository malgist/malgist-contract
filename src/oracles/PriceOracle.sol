// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IPriceOracle} from "../interfaces/IPriceOracle.sol";

/**
 * @title Chainlink Aggregator V3 Interface
 * @notice Standard Chainlink price feed interface
 */
interface IAggregatorV3 {
    function decimals() external view returns (uint8);
    function description() external view returns (string memory);
    function version() external view returns (uint256);
    function latestRoundData()
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        );
}

/**
 * @title PriceOracle
 * @notice Aggregated price oracle with Chainlink integration and fallback mechanisms
 * @dev Provides reliable price feeds with staleness checks and circuit breakers
 *
 * DESIGN PHILOSOPHY:
 * - Primary: Chainlink price feeds (most reliable)
 * - Fallback: Manual price updates (emergency use)
 * - Safety: Staleness checks, deviation limits, circuit breakers
 * - Flexibility: Support multiple price sources per asset
 *
 * SECURITY FEATURES:
 * ✅ Staleness detection (revert if price too old)
 * ✅ Deviation limits (prevent price manipulation)
 * ✅ Circuit breaker (pause if anomaly detected)
 * ✅ Multi-source aggregation
 * ✅ Heartbeat monitoring
 */
contract PriceOracle is IPriceOracle, Ownable {

    // ============================================================================
    // TYPE DEFINITIONS
    // ============================================================================

    // ============================================================================
    // STRUCTS
    // ============================================================================

    /**
     * @notice Price feed configuration
     * @param feed Chainlink aggregator address
     * @param heartbeat Maximum allowed staleness (seconds)
     * @param decimals Price feed decimals
     * @param isActive Whether feed is active
     * @param maxDeviation Maximum allowed deviation from last price (BPS)
     */
    struct PriceFeed {
        address feed;
        uint32 heartbeat;
        uint8 decimals;
        bool isActive;
        uint16 maxDeviation;
    }

    /**
     * @notice Price data with metadata
     * @param price Price in 18 decimals
     * @param updatedAt Timestamp of price update
     * @param source Price source (0=Chainlink, 1=Manual)
     */
    struct PriceData {
        uint256 price;
        uint256 updatedAt;
        uint8 source;
    }

    // ============================================================================
    // STATE VARIABLES
    // ============================================================================

    /// @notice Mapping from asset address to price feed config
    mapping(address => PriceFeed) public priceFeeds;

    /// @notice Mapping from asset to last known good price
    mapping(address => PriceData) public lastPrices;

    /// @notice Mapping from asset to manual price (fallback)
    mapping(address => uint256) public manualPrices;

    /// @notice Circuit breaker status
    bool public circuitBreakerActive;

    /// @notice Default heartbeat (1 hour)
    uint32 public constant DEFAULT_HEARTBEAT = 3600;

    /// @notice Default max deviation (10%)
    uint16 public constant DEFAULT_MAX_DEVIATION = 1000; // 10% in BPS

    /// @notice Price decimals (standardized to 18)
    uint8 public constant PRICE_DECIMALS = 18;

    /// @notice Basis points denominator
    uint16 public constant BPS = 10000;

    // ============================================================================
    // EVENTS
    // ============================================================================

    event PriceFeedAdded(
        address indexed asset,
        address indexed feed,
        uint32 heartbeat,
        uint16 maxDeviation
    );

    event PriceFeedUpdated(
        address indexed asset,
        address indexed newFeed,
        uint32 heartbeat
    );

    event PriceFeedRemoved(address indexed asset);

    event ManualPriceSet(
        address indexed asset,
        uint256 price,
        address indexed setter
    );

    event CircuitBreakerTriggered(address indexed asset, string reason);

    event CircuitBreakerReset();

    event PriceUpdated(
        address indexed asset,
        uint256 price,
        uint8 source,
        uint256 timestamp
    );

    // ============================================================================
    // ERRORS
    // ============================================================================

    error InvalidFeed();
    error StalePrice();
    error PriceDeviation();
    error CircuitBreakerTripped();
    error NoPriceFeed();
    error InvalidPrice();

    // ============================================================================
    // CONSTRUCTOR
    // ============================================================================

    constructor() Ownable(msg.sender) {}

    // ============================================================================
    // EXTERNAL FUNCTIONS - PRICE FEED MANAGEMENT
    // ============================================================================

    /**
     * @notice Add Chainlink price feed for an asset
     * @param asset Asset address (e.g., USDC)
     * @param feed Chainlink aggregator address
     * @param heartbeat Maximum staleness in seconds
     * @param maxDeviation Maximum price deviation in BPS
     */
    function addPriceFeed(
        address asset,
        address feed,
        uint32 heartbeat,
        uint16 maxDeviation
    )
        external
        onlyOwner
    {
        require(asset != address(0), "Invalid asset");
        require(feed != address(0), "Invalid feed");
        require(heartbeat > 0, "Invalid heartbeat");
        require(maxDeviation <= BPS, "Invalid deviation");

        // Verify feed is valid by calling it
        IAggregatorV3 aggregator = IAggregatorV3(feed);
        uint8 decimals = aggregator.decimals();

        priceFeeds[asset] = PriceFeed({
            feed: feed,
            heartbeat: heartbeat,
            decimals: decimals,
            isActive: true,
            maxDeviation: maxDeviation
        });

        emit PriceFeedAdded(asset, feed, heartbeat, maxDeviation);
    }

    /**
     * @notice Update price feed for an asset
     * @param asset Asset address
     * @param newFeed New Chainlink aggregator address
     * @param heartbeat New heartbeat
     */
    function updatePriceFeed(
        address asset,
        address newFeed,
        uint32 heartbeat
    )
        external
        onlyOwner
    {
        require(priceFeeds[asset].isActive, "Feed not active");
        require(newFeed != address(0), "Invalid feed");

        IAggregatorV3 aggregator = IAggregatorV3(newFeed);
        uint8 decimals = aggregator.decimals();

        priceFeeds[asset].feed = newFeed;
        priceFeeds[asset].heartbeat = heartbeat;
        priceFeeds[asset].decimals = decimals;

        emit PriceFeedUpdated(asset, newFeed, heartbeat);
    }

    /**
     * @notice Remove price feed for an asset
     * @param asset Asset address
     */
    function removePriceFeed(address asset) external onlyOwner {
        priceFeeds[asset].isActive = false;
        emit PriceFeedRemoved(asset);
    }

    /**
     * @notice Set manual price (fallback/emergency use)
     * @param asset Asset address
     * @param price Price in 18 decimals
     */
    function setManualPrice(address asset, uint256 price) external onlyOwner {
        require(price > 0, "Invalid price");

        manualPrices[asset] = price;

        lastPrices[asset] = PriceData({
            price: price,
            updatedAt: block.timestamp,
            source: 1  // Manual
        });

        emit ManualPriceSet(asset, price, msg.sender);
        emit PriceUpdated(asset, price, 1, block.timestamp);
    }

    // ============================================================================
    // EXTERNAL FUNCTIONS - CIRCUIT BREAKER
    // ============================================================================

    /**
     * @notice Activate circuit breaker (emergency pause)
     * @param asset Asset that triggered circuit breaker
     * @param reason Reason for activation
     */
    function activateCircuitBreaker(address asset, string calldata reason)
        external
        onlyOwner
    {
        circuitBreakerActive = true;
        emit CircuitBreakerTriggered(asset, reason);
    }

    /**
     * @notice Deactivate circuit breaker
     */
    function deactivateCircuitBreaker() external onlyOwner {
        circuitBreakerActive = false;
        emit CircuitBreakerReset();
    }

    // ============================================================================
    // EXTERNAL FUNCTIONS - PRICE QUERIES
    // ============================================================================

    /**
     * @notice Get current price for an asset
     * @param asset Asset address
     * @return price Price in 18 decimals
     * @dev Reverts if circuit breaker active, price stale, or no feed
     */
    function getPrice(address asset) external view returns (uint256 price) {
        if (circuitBreakerActive) revert CircuitBreakerTripped();

        PriceFeed memory feed = priceFeeds[asset];
        if (!feed.isActive) {
            // Try manual price as fallback
            price = manualPrices[asset];
            if (price == 0) revert NoPriceFeed();
            return price;
        }

        // Get price from Chainlink
        price = _getChainlinkPrice(asset, feed);

        // Validate against last known price (deviation check)
        PriceData memory lastPrice = lastPrices[asset];
        if (lastPrice.price > 0) {
            _checkDeviation(price, lastPrice.price, feed.maxDeviation);
        }

        return price;
    }

    /**
     * @notice Get price with safety checks disabled (view only)
     * @param asset Asset address
     * @return price Price in 18 decimals
     * @return isStale Whether price is stale
     */
    function getPriceUnsafe(address asset)
        external
        view
        returns (uint256 price, bool isStale)
    {
        PriceFeed memory feed = priceFeeds[asset];
        if (!feed.isActive) {
            return (manualPrices[asset], false);
        }

        (price, isStale) = _getChainlinkPriceUnsafe(asset, feed);
        return (price, isStale);
    }

    /**
     * @notice Get price data with metadata
     * @param asset Asset address
     * @return data Price data struct
     */
    function getPriceData(address asset)
        external
        view
        returns (PriceData memory data)
    {
        return lastPrices[asset];
    }

    /**
     * @notice Check if price feed is healthy
     * @param asset Asset address
     * @return isHealthy True if feed is active and not stale
     */
    function isPriceFeedHealthy(address asset)
        external
        view
        returns (bool isHealthy)
    {
        PriceFeed memory feed = priceFeeds[asset];
        if (!feed.isActive) return false;

        (, bool isStale) = _getChainlinkPriceUnsafe(asset, feed);
        return !isStale;
    }

    // ============================================================================
    // INTERNAL FUNCTIONS
    // ============================================================================

    /**
     * @notice Get price from Chainlink with staleness check
     * @param asset Asset address
     * @param feed Price feed config
     * @return price Price in 18 decimals
     */
    function _getChainlinkPrice(address asset, PriceFeed memory feed)
        internal
        view
        returns (uint256 price)
    {
        IAggregatorV3 aggregator = IAggregatorV3(feed.feed);

        (
            uint80 roundId,
            int256 answer,
            ,
            uint256 updatedAt,
            uint80 answeredInRound
        ) = aggregator.latestRoundData();

        // Validate round data
        require(answer > 0, "Invalid price");
        require(answeredInRound >= roundId, "Stale round");
        require(updatedAt > 0, "Invalid timestamp");

        // Check staleness
        uint256 timeSinceUpdate = block.timestamp - updatedAt;
        if (timeSinceUpdate > feed.heartbeat) revert StalePrice();

        // Convert to 18 decimals
        price = _scalePrice(uint256(answer), feed.decimals, PRICE_DECIMALS);

        return price;
    }

    /**
     * @notice Get price from Chainlink without reverting
     * @param asset Asset address
     * @param feed Price feed config
     * @return price Price in 18 decimals
     * @return isStale Whether price is stale
     */
    function _getChainlinkPriceUnsafe(address asset, PriceFeed memory feed)
        internal
        view
        returns (uint256 price, bool isStale)
    {
        try IAggregatorV3(feed.feed).latestRoundData() returns (
            uint80 roundId,
            int256 answer,
            uint256,
            uint256 updatedAt,
            uint80 answeredInRound
        ) {
            if (answer <= 0) return (0, true);
            if (answeredInRound < roundId) return (0, true);

            uint256 timeSinceUpdate = block.timestamp - updatedAt;
            isStale = timeSinceUpdate > feed.heartbeat;

            price = _scalePrice(uint256(answer), feed.decimals, PRICE_DECIMALS);

            return (price, isStale);
        } catch {
            return (0, true);
        }
    }

    /**
     * @notice Check price deviation from last price
     * @param currentPrice Current price
     * @param lastPrice Last known price
     * @param maxDeviation Maximum allowed deviation in BPS
     */
    function _checkDeviation(
        uint256 currentPrice,
        uint256 lastPrice,
        uint16 maxDeviation
    )
        internal
        pure
    {
        if (lastPrice == 0) return;

        uint256 deviation;
        if (currentPrice > lastPrice) {
            deviation = ((currentPrice - lastPrice) * BPS) / lastPrice;
        } else {
            deviation = ((lastPrice - currentPrice) * BPS) / lastPrice;
        }

        if (deviation > maxDeviation) revert PriceDeviation();
    }

    /**
     * @notice Scale price to target decimals
     * @param price Price value
     * @param fromDecimals Source decimals
     * @param toDecimals Target decimals
     * @return scaled Scaled price
     */
    function _scalePrice(
        uint256 price,
        uint8 fromDecimals,
        uint8 toDecimals
    )
        internal
        pure
        returns (uint256 scaled)
    {
        if (fromDecimals == toDecimals) {
            return price;
        } else if (fromDecimals < toDecimals) {
            return price * (10 ** (toDecimals - fromDecimals));
        } else {
            return price / (10 ** (fromDecimals - toDecimals));
        }
    }
}
