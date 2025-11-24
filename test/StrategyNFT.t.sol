// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/StrategyNFT.sol";

contract StrategyNFTTest is Test {
    StrategyNFT public strategyNFT;

    address public owner = address(this);
    address public alice = address(0x1);
    address public bob = address(0x2);

    // Mock adapter addresses
    address public adapter1 = address(0x100);
    address public adapter2 = address(0x200);
    address public adapter3 = address(0x300);

    function setUp() public {
        // Deploy StrategyNFT contract
        strategyNFT = new StrategyNFT();

        // Whitelist mock adapters
        strategyNFT.setAdapterWhitelist(adapter1, true);
        strategyNFT.setAdapterWhitelist(adapter2, true);
        strategyNFT.setAdapterWhitelist(adapter3, true);
    }

    /**
     * @notice Test successful minting of a valid strategy
     */
    function testMintStrategy() public {
        // Prepare strategy data
        address[] memory adapters = new address[](3);
        adapters[0] = adapter1;
        adapters[1] = adapter2;
        adapters[2] = adapter3;

        uint16[] memory ratios = new uint16[](3);
        ratios[0] = 5000; // 50%
        ratios[1] = 3000; // 30%
        ratios[2] = 2000; // 20%

        uint16 creatorFee = 10; // 0.1%

        // Mint as Alice
        vm.prank(alice);
        uint256 tokenId = strategyNFT.mintStrategy("Balanced Growth", adapters, ratios, creatorFee);

        // Assertions
        assertEq(tokenId, 1, "First token ID should be 1");
        assertEq(strategyNFT.ownerOf(tokenId), alice, "Alice should own the NFT");

        // Verify stored strategy data
        StrategyNFT.Strategy memory strategy = strategyNFT.getStrategy(tokenId);
        assertEq(strategy.name, "Balanced Growth", "Strategy name mismatch");
        assertEq(strategy.creator, alice, "Creator should be Alice");
        assertEq(strategy.creatorFeeBps, creatorFee, "Creator fee mismatch");
        assertTrue(strategy.isActive, "Strategy should be active");
        assertEq(strategy.adapters.length, 3, "Should have 3 adapters");
        assertEq(strategy.ratios.length, 3, "Should have 3 ratios");

        // Verify adapters and ratios
        assertEq(strategy.adapters[0], adapter1);
        assertEq(strategy.adapters[1], adapter2);
        assertEq(strategy.adapters[2], adapter3);
        assertEq(strategy.ratios[0], 5000);
        assertEq(strategy.ratios[1], 3000);
        assertEq(strategy.ratios[2], 2000);
    }

    /**
     * @notice Test that ratios must sum to exactly 10000 (100%)
     */
    function testRevertInvalidRatiosSum() public {
        address[] memory adapters = new address[](2);
        adapters[0] = adapter1;
        adapters[1] = adapter2;

        uint16[] memory ratios = new uint16[](2);
        ratios[0] = 6000; // 60%
        ratios[1] = 3000; // 30% - Total = 90%

        vm.prank(alice);
        vm.expectRevert(StrategyNFT.RatiosMustSumTo100.selector);
        strategyNFT.mintStrategy("Invalid Strategy", adapters, ratios, 10);
    }

    /**
     * @notice Test array length mismatch validation
     */
    function testRevertArrayLengthMismatch() public {
        address[] memory adapters = new address[](3);
        adapters[0] = adapter1;
        adapters[1] = adapter2;
        adapters[2] = adapter3;

        uint16[] memory ratios = new uint16[](2); // Mismatch!
        ratios[0] = 5000;
        ratios[1] = 5000;

        vm.prank(alice);
        vm.expectRevert(StrategyNFT.ArrayLengthMismatch.selector);
        strategyNFT.mintStrategy("Mismatched Strategy", adapters, ratios, 10);
    }

    /**
     * @notice Test non-whitelisted adapter rejection
     */
    function testRevertNonWhitelistedAdapter() public {
        address nonWhitelisted = address(0x999);

        address[] memory adapters = new address[](1);
        adapters[0] = nonWhitelisted;

        uint16[] memory ratios = new uint16[](1);
        ratios[0] = 10000; // 100%

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(StrategyNFT.AdapterNotWhitelisted.selector, nonWhitelisted));
        strategyNFT.mintStrategy("Bad Adapter", adapters, ratios, 10);
    }

    /**
     * @notice Test creator fee cap (max 5%)
     */
    function testRevertCreatorFeeTooHigh() public {
        address[] memory adapters = new address[](1);
        adapters[0] = adapter1;

        uint16[] memory ratios = new uint16[](1);
        ratios[0] = 10000;

        vm.prank(alice);
        vm.expectRevert(StrategyNFT.CreatorFeeTooHigh.selector);
        strategyNFT.mintStrategy("High Fee", adapters, ratios, 600); // 6% - too high!
    }

    /**
     * @notice Test zero ratios are rejected
     */
    function testRevertZeroRatio() public {
        address[] memory adapters = new address[](2);
        adapters[0] = adapter1;
        adapters[1] = adapter2;

        uint16[] memory ratios = new uint16[](2);
        ratios[0] = 10000;
        ratios[1] = 0; // Invalid!

        vm.prank(alice);
        vm.expectRevert(StrategyNFT.RatiosMustBePositive.selector);
        strategyNFT.mintStrategy("Zero Ratio", adapters, ratios, 10);
    }

    /**
     * @notice Test strategy deactivation by creator
     */
    function testDeactivateStrategyByCreator() public {
        // Alice mints a strategy
        address[] memory adapters = new address[](1);
        adapters[0] = adapter1;
        uint16[] memory ratios = new uint16[](1);
        ratios[0] = 10000;

        vm.prank(alice);
        uint256 tokenId = strategyNFT.mintStrategy("Test Strategy", adapters, ratios, 10);

        // Alice deactivates it
        vm.prank(alice);
        strategyNFT.deactivateStrategy(tokenId);

        // Verify it's deactivated
        StrategyNFT.Strategy memory strategy = strategyNFT.getStrategy(tokenId);
        assertFalse(strategy.isActive, "Strategy should be deactivated");
    }

    /**
     * @notice Test strategy deactivation by owner (admin)
     */
    function testDeactivateStrategyByOwner() public {
        // Alice mints a strategy
        address[] memory adapters = new address[](1);
        adapters[0] = adapter1;
        uint16[] memory ratios = new uint16[](1);
        ratios[0] = 10000;

        vm.prank(alice);
        uint256 tokenId = strategyNFT.mintStrategy("Test Strategy", adapters, ratios, 10);

        // Contract owner deactivates it
        strategyNFT.deactivateStrategy(tokenId);

        // Verify it's deactivated
        StrategyNFT.Strategy memory strategy = strategyNFT.getStrategy(tokenId);
        assertFalse(strategy.isActive, "Strategy should be deactivated");
    }

    /**
     * @notice Test unauthorized deactivation fails
     */
    function testRevertUnauthorizedDeactivation() public {
        // Alice mints a strategy
        address[] memory adapters = new address[](1);
        adapters[0] = adapter1;
        uint16[] memory ratios = new uint16[](1);
        ratios[0] = 10000;

        vm.prank(alice);
        uint256 tokenId = strategyNFT.mintStrategy("Test Strategy", adapters, ratios, 10);

        // Bob tries to deactivate (should fail)
        vm.prank(bob);
        vm.expectRevert(StrategyNFT.NotAuthorized.selector);
        strategyNFT.deactivateStrategy(tokenId);
    }

    /**
     * @notice Test getStrategyConfig helper function
     */
    function testGetStrategyConfig() public {
        address[] memory adapters = new address[](2);
        adapters[0] = adapter1;
        adapters[1] = adapter2;

        uint16[] memory ratios = new uint16[](2);
        ratios[0] = 7000;
        ratios[1] = 3000;

        vm.prank(alice);
        uint256 tokenId = strategyNFT.mintStrategy("Config Test", adapters, ratios, 10);

        (address[] memory returnedAdapters, uint16[] memory returnedRatios) = strategyNFT.getStrategyConfig(tokenId);

        assertEq(returnedAdapters.length, 2);
        assertEq(returnedRatios.length, 2);
        assertEq(returnedAdapters[0], adapter1);
        assertEq(returnedAdapters[1], adapter2);
        assertEq(returnedRatios[0], 7000);
        assertEq(returnedRatios[1], 3000);
    }

    /**
     * @notice Test multiple strategies can be minted
     */
    function testMultipleMints() public {
        address[] memory adapters = new address[](1);
        adapters[0] = adapter1;
        uint16[] memory ratios = new uint16[](1);
        ratios[0] = 10000;

        vm.prank(alice);
        uint256 tokenId1 = strategyNFT.mintStrategy("Strategy 1", adapters, ratios, 10);

        vm.prank(bob);
        uint256 tokenId2 = strategyNFT.mintStrategy("Strategy 2", adapters, ratios, 20);

        assertEq(tokenId1, 1);
        assertEq(tokenId2, 2);
        assertEq(strategyNFT.ownerOf(tokenId1), alice);
        assertEq(strategyNFT.ownerOf(tokenId2), bob);
    }
}
