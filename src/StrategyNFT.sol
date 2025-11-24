// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title StrategyNFT
 * @notice NFT contract that stores DeFi strategy configurations on-chain
 * @dev Each NFT represents a unique investment strategy with adapters and allocation ratios
 */
contract StrategyNFT is ERC721, Ownable {
    /// @notice Strategy configuration stored for each NFT
    struct Strategy {
        string name; // Strategy name (e.g., "Conservative Yield")
        address[] adapters; // Array of whitelisted adapter addresses
        uint16[] ratios; // Allocation percentages in basis points (10000 = 100%)
        address creator; // Strategy creator (receives fees)
        uint16 creatorFeeBps; // Creator fee in basis points (e.g., 10 = 0.1%)
        bool isActive; // Whether the strategy can accept new deposits
    }

    /// @dev Counter for token IDs
    uint256 private _nextTokenId = 1;

    /// @dev Mapping from token ID to strategy data
    mapping(uint256 => Strategy) public strategies;

    /// @dev Mapping of whitelisted adapter addresses
    mapping(address => bool) public whitelistedAdapters;

    /// @notice Maximum number of adapters per strategy
    uint16 public constant MAX_ADAPTERS = 10;

    /// @notice Total basis points representing 100%
    uint16 public constant TOTAL_BPS = 10000;

    /// @notice Maximum creator fee (5%)
    uint16 public constant MAX_CREATOR_FEE_BPS = 500;

    /// @notice Emitted when a new strategy is minted
    event StrategyMinted(
        uint256 indexed tokenId, address indexed creator, string name, address[] adapters, uint16[] ratios
    );

    /// @notice Emitted when a strategy is deactivated
    event StrategyDeactivated(uint256 indexed tokenId);

    /// @notice Emitted when an adapter is whitelisted or delisted
    event AdapterWhitelisted(address indexed adapter, bool status);

    /// @dev Errors
    error InvalidAdapterCount();
    error ArrayLengthMismatch();
    error CreatorFeeTooHigh();
    error AdapterNotWhitelisted(address adapter);
    error RatiosMustBePositive();
    error RatiosMustSumTo100();
    error StrategyDoesNotExist();
    error NotAuthorized();

    constructor() ERC721("Mantle Strategy", "MSTR") Ownable(msg.sender) {}

    /**
     * @notice Mint a new strategy NFT
     * @param name Strategy name
     * @param adapters Array of adapter addresses
     * @param ratios Array of allocation percentages in basis points
     * @param creatorFeeBps Creator fee in basis points (max 500 = 5%)
     * @return tokenId The ID of the newly minted strategy NFT
     */
    function mintStrategy(string memory name, address[] memory adapters, uint16[] memory ratios, uint16 creatorFeeBps)
        external
        returns (uint256)
    {
        // Validate input lengths
        if (adapters.length == 0 || adapters.length > MAX_ADAPTERS) {
            revert InvalidAdapterCount();
        }
        if (adapters.length != ratios.length) {
            revert ArrayLengthMismatch();
        }
        if (creatorFeeBps > MAX_CREATOR_FEE_BPS) {
            revert CreatorFeeTooHigh();
        }

        // Validate all adapters are whitelisted
        for (uint256 i = 0; i < adapters.length; i++) {
            if (!whitelistedAdapters[adapters[i]]) {
                revert AdapterNotWhitelisted(adapters[i]);
            }
        }

        // Validate ratios sum to exactly 100%
        uint256 totalRatio = 0;
        for (uint256 i = 0; i < ratios.length; i++) {
            if (ratios[i] == 0) {
                revert RatiosMustBePositive();
            }
            totalRatio += ratios[i];
        }
        if (totalRatio != TOTAL_BPS) {
            revert RatiosMustSumTo100();
        }

        // Mint NFT
        uint256 tokenId = _nextTokenId++;
        _safeMint(msg.sender, tokenId);

        // Store strategy
        strategies[tokenId] = Strategy({
            name: name,
            adapters: adapters,
            ratios: ratios,
            creator: msg.sender,
            creatorFeeBps: creatorFeeBps,
            isActive: true
        });

        emit StrategyMinted(tokenId, msg.sender, name, adapters, ratios);
        return tokenId;
    }

    /**
     * @notice Deactivate a strategy to prevent new deposits
     * @param tokenId The strategy NFT ID to deactivate
     * @dev Can only be called by the strategy creator or contract owner
     */
    function deactivateStrategy(uint256 tokenId) external {
        if (_ownerOf(tokenId) == address(0)) {
            revert StrategyDoesNotExist();
        }

        Strategy storage strategy = strategies[tokenId];
        if (msg.sender != strategy.creator && msg.sender != owner()) {
            revert NotAuthorized();
        }

        strategy.isActive = false;
        emit StrategyDeactivated(tokenId);
    }

    /**
     * @notice Add or remove an adapter from the whitelist
     * @param adapter Address of the adapter contract
     * @param status True to whitelist, false to delist
     * @dev Only callable by contract owner
     */
    function setAdapterWhitelist(address adapter, bool status) external onlyOwner {
        whitelistedAdapters[adapter] = status;
        emit AdapterWhitelisted(adapter, status);
    }

    /**
     * @notice Get complete strategy details for a token ID
     * @param tokenId The strategy NFT ID
     * @return strategy The complete strategy struct
     */
    function getStrategy(uint256 tokenId) external view returns (Strategy memory strategy) {
        if (_ownerOf(tokenId) == address(0)) {
            revert StrategyDoesNotExist();
        }
        return strategies[tokenId];
    }

    /**
     * @notice Get only the adapters and ratios for a strategy
     * @param tokenId The strategy NFT ID
     * @return adapters Array of adapter addresses
     * @return ratios Array of allocation ratios
     */
    function getStrategyConfig(uint256 tokenId)
        external
        view
        returns (address[] memory adapters, uint16[] memory ratios)
    {
        if (_ownerOf(tokenId) == address(0)) {
            revert StrategyDoesNotExist();
        }
        Strategy storage strategy = strategies[tokenId];
        return (strategy.adapters, strategy.ratios);
    }
}
