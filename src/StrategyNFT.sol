// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title StrategyNFT
 * @notice ERC-721 NFT contract representing investment strategies for MALGIST protocol
 * @dev Each NFT is immutable after minting but supports versioning for future strategy changes
 */

interface IStrategyValidator {
    function validateStrategy(StrategyConfig memory config) external view returns (bool);
}

/**
 * @dev Strategy configuration stored immutably on-chain
 * Total storage: ~5-6 slots (optimized for efficient access)
 */
struct StrategyConfig {
    // Slot 0-1: Arrays (dynamic)
    address[] adapters;              // Whitelisted protocol adapters
    uint16[] ratios;                 // Allocation ratios (sum = 10000)
    
    // Slot 2: Core metadata
    address creator;                 // Strategy creator (receives fees)
    uint16 creatorFeeBps;            // Creator fee in basis points (0-1000 = 0-10%)
    uint8 riskLevel;                 // Risk classification: 1=Conservative, 5=Aggressive
    bool isActive;                   // Can be deactivated by creator
    
    // Slot 3: Timestamps & versioning
    uint40 createdAt;                // Creation timestamp
    uint16 version;                  // Version number (for tracking strategy evolution)
    uint8 rebalanceFrequency;        // Recommended rebalance period in days
    
    // Slot 4: Metadata (for future extensions)
    bytes32 strategistName;          // Hashed strategist name/identifier
    uint8 slippageToleranceBps;      // Max allowed slippage during execution
}

/**
 * @dev Strategy update request for versioning
 */
struct StrategyUpdateRequest {
    uint256 tokenId;
    StrategyConfig newConfig;
    uint40 effectiveAt;              // When this version takes effect
    bool isApproved;
    uint40 proposedAt;
}

contract StrategyNFT is ERC721Enumerable, Ownable, ReentrancyGuard {
    // ============================================================================
    // EVENTS
    // ============================================================================

    event StrategyCreated(
        uint256 indexed tokenId,
        address indexed creator,
        address[] adapters,
        uint16[] ratios,
        uint8 riskLevel
    );

    event StrategyDeactivated(uint256 indexed tokenId, address indexed creator);
    
    event StrategyReactivated(uint256 indexed tokenId, address indexed creator);

    event StrategyVersioned(
        uint256 indexed tokenId,
        uint16 oldVersion,
        uint16 newVersion,
        address indexed updatedBy
    );

    event AdapterWhitelisted(address indexed adapter);
    
    event AdapterBlacklisted(address indexed adapter);

    event StrategyValidatorSet(address indexed validator);

    // ============================================================================
    // STATE VARIABLES
    // ============================================================================

    uint256 private _tokenIdCounter;

    // Mapping: tokenId => StrategyConfig (immutable data)
    mapping(uint256 => StrategyConfig) public strategies;

    // Mapping: creator => array of created strategy IDs
    mapping(address => uint256[]) public creatorStrategies;

    // Mapping: adapter => whitelisted status
    mapping(address => bool) public whitelistedAdapters;

    // Mapping: tokenId => pending updates (for versioning)
    mapping(uint256 => StrategyUpdateRequest) public pendingUpdates;

    // Strategy validator for custom validation logic
    IStrategyValidator public strategyValidator;

    // Configuration constraints
    uint16 public constant MAX_CREATOR_FEE_BPS = 1000;  // 10% max
    uint8 public constant MAX_ADAPTERS = 10;             // Max 10 adapters per strategy
    uint8 public constant MIN_ADAPTERS = 1;              // Min 1 adapter
    uint16 public constant MAX_SLIPPAGE_BPS = 500;       // 5% max slippage

    // ============================================================================
    // INITIALIZATION
    // ============================================================================

    constructor() ERC721("MALGIST Strategy", "MAL-STRAT") Ownable(msg.sender) {}

    // ============================================================================
    // STRATEGY CREATION
    // ============================================================================

    /**
     * @notice Creates a new strategy NFT
     * @param adapters Array of whitelisted adapter addresses
     * @param ratios Allocation ratios (must sum to 10000 basis points)
     * @param creatorFeeBps Creator fee in basis points (0-1000)
     * @param riskLevel Risk level (1-5)
     * @param strategistName Hashed strategist identifier
     * @param rebalanceFrequency Recommended rebalance period
     * @param slippageToleranceBps Maximum slippage tolerance
     * @return tokenId New strategy NFT ID
     */
    function createStrategy(
        address[] calldata adapters,
        uint16[] calldata ratios,
        uint16 creatorFeeBps,
        uint8 riskLevel,
        bytes32 strategistName,
        uint8 rebalanceFrequency,
        uint8 slippageToleranceBps
    ) external nonReentrant returns (uint256) {
        // Input validation
        require(adapters.length >= MIN_ADAPTERS, "Too few adapters");
        require(adapters.length <= MAX_ADAPTERS, "Too many adapters");
        require(adapters.length == ratios.length, "Length mismatch");
        require(creatorFeeBps <= MAX_CREATOR_FEE_BPS, "Fee too high");
        require(riskLevel >= 1 && riskLevel <= 5, "Invalid risk level");
        require(slippageToleranceBps <= MAX_SLIPPAGE_BPS, "Slippage too high");

        // Validate ratios sum to 10000 and no adapter is duplicated
        uint256 ratioSum = 0;
        for (uint256 i = 0; i < adapters.length; i++) {
            require(whitelistedAdapters[adapters[i]], "Adapter not whitelisted");
            require(adapters[i] != address(0), "Zero adapter address");
            require(ratios[i] > 0, "Zero ratio");
            
            // Check for duplicates
            for (uint256 j = i + 1; j < adapters.length; j++) {
                require(adapters[i] != adapters[j], "Duplicate adapter");
            }
            
            ratioSum += ratios[i];
        }
        require(ratioSum == 10000, "Ratios must sum to 10000");

        // Custom validation if validator is set
        if (address(strategyValidator) != address(0)) {
            StrategyConfig memory config = StrategyConfig({
                adapters: adapters,
                ratios: ratios,
                creator: msg.sender,
                creatorFeeBps: creatorFeeBps,
                riskLevel: riskLevel,
                isActive: true,
                createdAt: uint40(block.timestamp),
                version: 1,
                rebalanceFrequency: rebalanceFrequency,
                strategistName: strategistName,
                slippageToleranceBps: slippageToleranceBps
            });
            require(strategyValidator.validateStrategy(config), "Validation failed");
        }

        // Mint NFT
        uint256 tokenId = _tokenIdCounter;
        _tokenIdCounter++;
        
        _safeMint(msg.sender, tokenId);

        // Store strategy config
        strategies[tokenId] = StrategyConfig({
            adapters: adapters,
            ratios: ratios,
            creator: msg.sender,
            creatorFeeBps: creatorFeeBps,
            riskLevel: riskLevel,
            isActive: true,
            createdAt: uint40(block.timestamp),
            version: 1,
            rebalanceFrequency: rebalanceFrequency,
            strategistName: strategistName,
            slippageToleranceBps: slippageToleranceBps
        });

        // Track creator ownership
        creatorStrategies[msg.sender].push(tokenId);

        emit StrategyCreated(tokenId, msg.sender, adapters, ratios, riskLevel);

        return tokenId;
    }

    // ============================================================================
    // STRATEGY MANAGEMENT (Creator)
    // ============================================================================

    /**
     * @notice Deactivate a strategy (only creator can do this)
     * @param tokenId Strategy NFT ID
     */
    function deactivateStrategy(uint256 tokenId) external {
        StrategyConfig storage strategy = strategies[tokenId];
        require(strategy.creator == msg.sender, "Only creator can deactivate");
        require(strategy.isActive, "Already deactivated");
        
        strategy.isActive = false;
        emit StrategyDeactivated(tokenId, msg.sender);
    }

    /**
     * @notice Reactivate a deactivated strategy
     * @param tokenId Strategy NFT ID
     */
    function reactivateStrategy(uint256 tokenId) external {
        StrategyConfig storage strategy = strategies[tokenId];
        require(strategy.creator == msg.sender, "Only creator can reactivate");
        require(!strategy.isActive, "Already active");
        
        strategy.isActive = true;
        emit StrategyReactivated(tokenId, msg.sender);
    }

    // ============================================================================
    // STRATEGY VERSIONING & UPDATES
    // ============================================================================

    /**
     * @notice Propose a strategy update (creates new version)
     * @param tokenId Strategy NFT ID
     * @param newAdapters Updated adapter list
     * @param newRatios Updated ratios
     * @param newCreatorFeeBps Updated creator fee
     * @param effectiveAt When this version becomes effective
     */
    function proposeStrategyUpdate(
        uint256 tokenId,
        address[] calldata newAdapters,
        uint16[] calldata newRatios,
        uint16 newCreatorFeeBps,
        uint40 effectiveAt
    ) external {
        StrategyConfig storage strategy = strategies[tokenId];
        require(strategy.creator == msg.sender, "Only creator can update");
        require(effectiveAt > block.timestamp, "Invalid effective time");
        require(newAdapters.length >= MIN_ADAPTERS && newAdapters.length <= MAX_ADAPTERS, "Invalid adapter count");
        require(newCreatorFeeBps <= MAX_CREATOR_FEE_BPS, "Fee too high");

        // Validate new configuration
        uint256 ratioSum = 0;
        for (uint256 i = 0; i < newAdapters.length; i++) {
            require(whitelistedAdapters[newAdapters[i]], "Adapter not whitelisted");
            require(newAdapters[i] != address(0), "Zero address");
            ratioSum += newRatios[i];
        }
        require(ratioSum == 10000, "Ratios must sum to 10000");

        // Store pending update
        StrategyConfig memory newConfig = StrategyConfig({
            adapters: newAdapters,
            ratios: newRatios,
            creator: strategy.creator,
            creatorFeeBps: newCreatorFeeBps,
            riskLevel: strategy.riskLevel,
            isActive: strategy.isActive,
            createdAt: strategy.createdAt,
            version: strategy.version + 1,
            rebalanceFrequency: strategy.rebalanceFrequency,
            strategistName: strategy.strategistName,
            slippageToleranceBps: strategy.slippageToleranceBps
        });

        pendingUpdates[tokenId] = StrategyUpdateRequest({
            tokenId: tokenId,
            newConfig: newConfig,
            effectiveAt: effectiveAt,
            isApproved: false,
            proposedAt: uint40(block.timestamp)
        });
    }

    /**
     * @notice Approve and activate a pending strategy update
     * @param tokenId Strategy NFT ID
     */
    function approveStrategyUpdate(uint256 tokenId) external {
        StrategyUpdateRequest storage request = pendingUpdates[tokenId];
        StrategyConfig storage strategy = strategies[tokenId];
        
        require(request.tokenId == tokenId, "No pending update");
        require(strategy.creator == msg.sender, "Only creator can approve");
        require(!request.isApproved, "Already approved");
        require(block.timestamp >= request.effectiveAt, "Not yet effective");

        // Update strategy to new version
        strategies[tokenId] = request.newConfig;
        request.isApproved = true;

        emit StrategyVersioned(tokenId, strategy.version - 1, strategy.version, msg.sender);
    }

    // ============================================================================
    // READ FUNCTIONS (For Vault Integration)
    // ============================================================================

    /**
     * @notice Get complete strategy configuration (read-only)
     * @param tokenId Strategy NFT ID
     * @return config Immutable strategy configuration
     */
    function getStrategy(uint256 tokenId) external view returns (StrategyConfig memory) {
        require(_ownerOf(tokenId) != address(0), "Strategy does not exist");
        return strategies[tokenId];
    }

    /**
     * @notice Get adapters for a strategy
     * @param tokenId Strategy NFT ID
     * @return adapters Array of adapter addresses
     */
    function getStrategyAdapters(uint256 tokenId) external view returns (address[] memory) {
        require(_ownerOf(tokenId) != address(0), "Strategy does not exist");
        return strategies[tokenId].adapters;
    }

    /**
     * @notice Get allocation ratios for a strategy
     * @param tokenId Strategy NFT ID
     * @return ratios Array of allocation ratios
     */
    function getStrategyRatios(uint256 tokenId) external view returns (uint16[] memory) {
        require(_ownerOf(tokenId) != address(0), "Strategy does not exist");
        return strategies[tokenId].ratios;
    }

    /**
     * @notice Check if strategy is valid and active
     * @param tokenId Strategy NFT ID
     * @return isValid True if strategy is active and all adapters are whitelisted
     */
    function isStrategyValid(uint256 tokenId) external view returns (bool) {
        require(_ownerOf(tokenId) != address(0), "Strategy does not exist");
        
        StrategyConfig memory strategy = strategies[tokenId];
        
        // Check if active
        if (!strategy.isActive) return false;

        // Verify all adapters are still whitelisted
        for (uint256 i = 0; i < strategy.adapters.length; i++) {
            if (!whitelistedAdapters[strategy.adapters[i]]) return false;
        }

        return true;
    }

    /**
     * @notice Get creator of a strategy
     * @param tokenId Strategy NFT ID
     * @return creator Strategy creator address
     */
    function getStrategyCreator(uint256 tokenId) external view returns (address) {
        require(_ownerOf(tokenId) != address(0), "Strategy does not exist");
        return strategies[tokenId].creator;
    }

    /**
     * @notice Get creator fee for a strategy
     * @param tokenId Strategy NFT ID
     * @return feeBps Creator fee in basis points
     */
    function getCreatorFee(uint256 tokenId) external view returns (uint16) {
        require(_ownerOf(tokenId) != address(0), "Strategy does not exist");
        return strategies[tokenId].creatorFeeBps;
    }

    // ============================================================================
    // ADAPTER MANAGEMENT (Admin)
    // ============================================================================

    /**
     * @notice Whitelist a new adapter
     * @param adapter Adapter contract address
     */
    function whitelistAdapter(address adapter) external onlyOwner {
        require(adapter != address(0), "Invalid adapter");
        require(!whitelistedAdapters[adapter], "Already whitelisted");
        
        whitelistedAdapters[adapter] = true;
        emit AdapterWhitelisted(adapter);
    }

    /**
     * @notice Blacklist an adapter (prevents new strategies, but existing ones unaffected)
     * @param adapter Adapter contract address
     */
    function blacklistAdapter(address adapter) external onlyOwner {
        require(whitelistedAdapters[adapter], "Not whitelisted");
        
        whitelistedAdapters[adapter] = false;
        emit AdapterBlacklisted(adapter);
    }

    /**
     * @notice Check if an adapter is whitelisted
     * @param adapter Adapter contract address
     * @return isWhitelisted True if adapter is whitelisted
     */
    function isAdapterWhitelisted(address adapter) external view returns (bool) {
        return whitelistedAdapters[adapter];
    }

    // ============================================================================
    // VALIDATOR SETUP (Admin)
    // ============================================================================

    /**
     * @notice Set custom strategy validator
     * @param validator Strategy validator contract
     */
    function setStrategyValidator(address validator) external onlyOwner {
        strategyValidator = IStrategyValidator(validator);
        emit StrategyValidatorSet(validator);
    }

    // ============================================================================
    // UTILITY FUNCTIONS
    // ============================================================================

    /**
     * @notice Get strategies created by a specific creator
     * @param creator Creator address
     * @return tokenIds Array of strategy NFT IDs
     */
    function getCreatorStrategies(address creator) external view returns (uint256[] memory) {
        return creatorStrategies[creator];
    }

    /**
     * @notice Get total number of strategies created
     * @return count Total strategy count
     */
    function getTotalStrategies() external view returns (uint256) {
        return _tokenIdCounter;
    }

    /**
     * @notice Get current version of a strategy
     * @param tokenId Strategy NFT ID
     * @return version Current version number
     */
    function getStrategyVersion(uint256 tokenId) external view returns (uint16) {
        require(_ownerOf(tokenId) != address(0), "Strategy does not exist");
        return strategies[tokenId].version;
    }

    // ============================================================================
    // REQUIRED OVERRIDES
    // ============================================================================

    /**
     * @notice Override supportsInterface for ERC721Enumerable
     */
    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721Enumerable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}
