// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/*
 * @status EXPERIMENTAL
 * @network Prototype only
 * @used-by ERC4626StrategyVault.sol
 * @notes ERC4626 helper mirrored locally for audits.
 */

/**
 * @title IERC4626
 * @notice ERC-4626 Tokenized Vault Standard
 * @dev Reference: https://eips.ethereum.org/EIPS/eip-4626
 */

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IERC4626 is IERC20 {
    
    // ========================================================================
    // EVENTS
    // ========================================================================

    event Deposit(
        address indexed caller,
        address indexed owner,
        uint256 assets,
        uint256 shares
    );

    event Withdraw(
        address indexed caller,
        address indexed receiver,
        address indexed owner,
        uint256 assets,
        uint256 shares
    );

    // ========================================================================
    // DEPOSIT/WITHDRAWAL METHODS
    // ========================================================================

    /**
     * @notice Deposit assets and receive shares
     * @param assets Amount of assets to deposit
     * @param receiver Address to receive shares
     * @return shares Amount of shares minted
     */
    function deposit(uint256 assets, address receiver)
        external
        returns (uint256 shares);

    /**
     * @notice Mint shares by depositing assets
     * @param shares Amount of shares to mint
     * @param receiver Address to receive shares
     * @return assets Amount of assets required
     */
    function mint(uint256 shares, address receiver)
        external
        returns (uint256 assets);

    /**
     * @notice Withdraw assets by burning shares
     * @param assets Amount of assets to withdraw
     * @param receiver Address to receive assets
     * @param owner Owner of shares to burn
     * @return shares Amount of shares burned
     */
    function withdraw(uint256 assets, address receiver, address owner)
        external
        returns (uint256 shares);

    /**
     * @notice Redeem shares for assets
     * @param shares Amount of shares to redeem
     * @param receiver Address to receive assets
     * @param owner Owner of shares to redeem
     * @return assets Amount of assets withdrawn
     */
    function redeem(uint256 shares, address receiver, address owner)
        external
        returns (uint256 assets);

    // ========================================================================
    // ACCOUNTING METHODS
    // ========================================================================

    /**
     * @notice Get total amount of assets in vault
     * @return Total assets value
     */
    function totalAssets() external view returns (uint256);

    /**
     * @notice Convert assets amount to equivalent shares
     * @param assets Amount of assets
     * @return shares Equivalent shares (rounded down)
     */
    function convertToShares(uint256 assets)
        external
        view
        returns (uint256 shares);

    /**
     * @notice Convert shares amount to equivalent assets
     * @param shares Amount of shares
     * @return assets Equivalent assets (rounded down)
     */
    function convertToAssets(uint256 shares)
        external
        view
        returns (uint256 assets);

    /**
     * @notice Get maximum deposit amount for given address
     * @param receiver Address to check
     * @return maxAssets Maximum deposit amount
     */
    function maxDeposit(address receiver)
        external
        view
        returns (uint256 maxAssets);

    /**
     * @notice Get maximum mint amount for given address
     * @param receiver Address to check
     * @return maxShares Maximum mint amount
     */
    function maxMint(address receiver)
        external
        view
        returns (uint256 maxShares);

    /**
     * @notice Get maximum withdrawal amount for given owner
     * @param owner Owner address
     * @return maxAssets Maximum withdrawal amount
     */
    function maxWithdraw(address owner)
        external
        view
        returns (uint256 maxAssets);

    /**
     * @notice Get maximum redemption amount for given owner
     * @param owner Owner address
     * @return maxShares Maximum redemption amount
     */
    function maxRedeem(address owner)
        external
        view
        returns (uint256 maxShares);

    /**
     * @notice Preview deposit effects (without state change)
     * @param assets Amount of assets
     * @return shares Shares that would be minted
     */
    function previewDeposit(uint256 assets)
        external
        view
        returns (uint256 shares);

    /**
     * @notice Preview mint effects (without state change)
     * @param shares Amount of shares
     * @return assets Assets required
     */
    function previewMint(uint256 shares)
        external
        view
        returns (uint256 assets);

    /**
     * @notice Preview withdrawal effects (without state change)
     * @param assets Amount of assets
     * @return shares Shares to burn
     */
    function previewWithdraw(uint256 assets)
        external
        view
        returns (uint256 shares);

    /**
     * @notice Preview redemption effects (without state change)
     * @param shares Amount of shares
     * @return assets Assets to receive
     */
    function previewRedeem(uint256 shares)
        external
        view
        returns (uint256 assets);

    // ========================================================================
    // VAULT METADATA
    // ========================================================================

    /**
     * @notice Get underlying asset address
     * @return asset Address of underlying asset
     */
    function asset() external view returns (address asset);

    /**
     * @notice Get name of vault share token
     * @return name Token name
     */
    function name() external view returns (string memory name);

    /**
     * @notice Get symbol of vault share token
     * @return symbol Token symbol
     */
    function symbol() external view returns (string memory symbol);

    /**
     * @notice Get decimals of vault share token
     * @return decimals Token decimals
     */
    function decimals() external view returns (uint8 decimals);
}
