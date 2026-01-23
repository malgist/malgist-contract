// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @test-type CORE-DATA
/// @covers StrategyNFT
/// @notes Protects ERC721 metadata + versioning behavior.


import "forge-std/Test.sol";
import "../../src/StrategyNFT.sol";
import "../../src/StrategyVault.sol";
import "../../src/validators/StrategyValidator.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title MockERC20Test
 * @notice Mock ERC20 for testing
 */
contract MockERC20Test is ERC20 {
    constructor() ERC20("Test Token", "TEST") {
        _mint(msg.sender, 1_000_000_000 * 10 ** 18);
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

/**
 * @title StrategyNFTTest
 * @notice Comprehensive tests for StrategyNFT contract
 */
contract StrategyNFTTest is Test {
    StrategyNFT strategyNFT;
    MockERC20Test token;
    StrategyValidator validator;

    address creator = address(0x1);
    address adapter1 = address(0x2);
    address adapter2 = address(0x3);
    address owner = address(this);

    function setUp() public {
        token = new MockERC20Test();
        strategyNFT = new StrategyNFT(address(this));
        validator = new StrategyValidator();

        // Whitelist adapters
        strategyNFT.whitelistAdapter(adapter1);
        strategyNFT.whitelistAdapter(adapter2);
    }

    // ========================================================================
    // TESTS: Strategy Creation
    // ========================================================================

    function test_createStrategy_success() public {
        vm.prank(creator);
        
        address[] memory adapters = new address[](1);
        adapters[0] = adapter1;
        
        uint16[] memory ratios = new uint16[](1);
        ratios[0] = 10000;

        uint256 tokenId = strategyNFT.createStrategy(
            adapters,
            ratios,
            100,  // 1% fee
            3,    // medium risk
            keccak256("TestStrategy"),
            7,    // weekly rebalance
            50    // 0.5% slippage
        );

        assertEq(tokenId, 0, "First strategy should have ID 0");
        assertEq(strategyNFT.ownerOf(tokenId), creator, "Creator should own NFT");
    }

    function test_createStrategy_multipleAdapters() public {
        vm.prank(creator);
        
        address[] memory adapters = new address[](2);
        adapters[0] = adapter1;
        adapters[1] = adapter2;
        
        uint16[] memory ratios = new uint16[](2);
        ratios[0] = 6000;  // 60%
        ratios[1] = 4000;  // 40%

        uint256 tokenId = strategyNFT.createStrategy(
            adapters,
            ratios,
            250,  // 2.5% fee
            2,    // low risk
            keccak256("DiverseStrategy"),
            14,   // bi-weekly rebalance
            100   // 1% slippage
        );

        StrategyConfig memory config = strategyNFT.getStrategy(tokenId);
        assertEq(config.adapters.length, 2, "Should have 2 adapters");
        assertEq(config.ratios[0], 6000, "First ratio should be 6000");
        assertEq(config.ratios[1], 4000, "Second ratio should be 4000");
    }

    function test_createStrategy_revertOnInvalidRatios() public {
        vm.prank(creator);
        
        address[] memory adapters = new address[](1);
        adapters[0] = adapter1;
        
        uint16[] memory ratios = new uint16[](1);
        ratios[0] = 9000;  // Sum != 10000

        vm.expectRevert("Ratios must sum to 10000");
        strategyNFT.createStrategy(
            adapters,
            ratios,
            100,
            3,
            keccak256("InvalidStrategy"),
            7,
            50
        );
    }

    function test_createStrategy_revertOnHighFee() public {
        vm.prank(creator);
        
        address[] memory adapters = new address[](1);
        adapters[0] = adapter1;
        
        uint16[] memory ratios = new uint16[](1);
        ratios[0] = 10000;

        vm.expectRevert("Fee too high");
        strategyNFT.createStrategy(
            adapters,
            ratios,
            2000,  // 20% > 10% max
            3,
            keccak256("ExpensiveStrategy"),
            7,
            50
        );
    }

    function test_createStrategy_revertOnZeroAdapters() public {
        vm.prank(creator);
        
        address[] memory adapters = new address[](0);
        uint16[] memory ratios = new uint16[](0);

        vm.expectRevert("Too few adapters");
        strategyNFT.createStrategy(
            adapters,
            ratios,
            100,
            3,
            keccak256("EmptyStrategy"),
            7,
            50
        );
    }

    function test_createStrategy_revertOnUnwhitelistedAdapter() public {
        vm.prank(creator);
        
        address[] memory adapters = new address[](1);
        adapters[0] = address(0x99);  // Not whitelisted
        
        uint16[] memory ratios = new uint16[](1);
        ratios[0] = 10000;

        vm.expectRevert("Adapter not whitelisted");
        strategyNFT.createStrategy(
            adapters,
            ratios,
            100,
            3,
            keccak256("BadAdapterStrategy"),
            7,
            50
        );
    }

    // ========================================================================
    // TESTS: Strategy Management
    // ========================================================================

    function test_deactivateStrategy() public {
        vm.prank(creator);
        
        address[] memory adapters = new address[](1);
        adapters[0] = adapter1;
        
        uint16[] memory ratios = new uint16[](1);
        ratios[0] = 10000;

        uint256 tokenId = strategyNFT.createStrategy(
            adapters,
            ratios,
            100,
            3,
            keccak256("StrategyToDeactivate"),
            7,
            50
        );

        // Deactivate
        vm.prank(creator);
        strategyNFT.deactivateStrategy(tokenId);

        StrategyConfig memory config = strategyNFT.getStrategy(tokenId);
        assertFalse(config.isActive, "Strategy should be deactivated");
        assertFalse(strategyNFT.isStrategyValid(tokenId), "Invalid strategy should return false");
    }

    function test_reactivateStrategy() public {
        vm.prank(creator);
        
        address[] memory adapters = new address[](1);
        adapters[0] = adapter1;
        
        uint16[] memory ratios = new uint16[](1);
        ratios[0] = 10000;

        uint256 tokenId = strategyNFT.createStrategy(
            adapters,
            ratios,
            100,
            3,
            keccak256("StrategyToReactivate"),
            7,
            50
        );

        vm.prank(creator);
        strategyNFT.deactivateStrategy(tokenId);

        vm.prank(creator);
        strategyNFT.reactivateStrategy(tokenId);

        StrategyConfig memory config = strategyNFT.getStrategy(tokenId);
        assertTrue(config.isActive, "Strategy should be reactivated");
        assertTrue(strategyNFT.isStrategyValid(tokenId), "Valid strategy should return true");
    }

    // ========================================================================
    // TESTS: Adapter Management
    // ========================================================================

    function test_whitelistAdapter() public {
        address newAdapter = address(0x100);
        
        strategyNFT.whitelistAdapter(newAdapter);
        
        assertTrue(strategyNFT.isAdapterWhitelisted(newAdapter), "Adapter should be whitelisted");
    }

    function test_blacklistAdapter() public {
        strategyNFT.blacklistAdapter(adapter1);
        
        assertFalse(strategyNFT.isAdapterWhitelisted(adapter1), "Adapter should be blacklisted");
    }

    function test_blacklistAdapter_affectsValidation() public {
        vm.prank(creator);
        
        address[] memory adapters = new address[](1);
        adapters[0] = adapter1;
        
        uint16[] memory ratios = new uint16[](1);
        ratios[0] = 10000;

        uint256 tokenId = strategyNFT.createStrategy(
            adapters,
            ratios,
            100,
            3,
            keccak256("StrategyBeforeBlacklist"),
            7,
            50
        );

        assertTrue(strategyNFT.isStrategyValid(tokenId), "Should be valid before blacklist");

        // Blacklist adapter
        strategyNFT.blacklistAdapter(adapter1);

        assertFalse(strategyNFT.isStrategyValid(tokenId), "Should be invalid after blacklist");
    }

    // ========================================================================
    // TESTS: Utility Functions
    // ========================================================================

    function test_getCreatorStrategies() public {
        vm.prank(creator);
        
        address[] memory adapters = new address[](1);
        adapters[0] = adapter1;
        
        uint16[] memory ratios = new uint16[](1);
        ratios[0] = 10000;

        strategyNFT.createStrategy(adapters, ratios, 100, 3, keccak256("Strategy1"), 7, 50);
        strategyNFT.createStrategy(adapters, ratios, 100, 3, keccak256("Strategy2"), 7, 50);

        uint256[] memory strategies = strategyNFT.getCreatorStrategies(creator);
        assertEq(strategies.length, 2, "Creator should have 2 strategies");
    }

    function test_getTotalStrategies() public {
        vm.prank(creator);
        
        address[] memory adapters = new address[](1);
        adapters[0] = adapter1;
        
        uint16[] memory ratios = new uint16[](1);
        ratios[0] = 10000;

        strategyNFT.createStrategy(adapters, ratios, 100, 3, keccak256("Strategy1"), 7, 50);
        strategyNFT.createStrategy(adapters, ratios, 100, 3, keccak256("Strategy2"), 7, 50);
        strategyNFT.createStrategy(adapters, ratios, 100, 3, keccak256("Strategy3"), 7, 50);

        assertEq(strategyNFT.getTotalStrategies(), 3, "Should have 3 total strategies");
    }
}

/**
 * @title StrategyVaultTest
 * @notice Comprehensive tests for StrategyVault contract
 */
contract StrategyVaultTest is Test {
    StrategyNFT strategyNFT;
    StrategyVault vault;
    MockERC20Test token;

    address creator = address(0x1);
    address user1 = address(0x2);
    address user2 = address(0x3);
    address adapter1 = address(0x4);

    function setUp() public {
        token = new MockERC20Test();
        strategyNFT = new StrategyNFT(address(this));
        vault = new StrategyVault(address(strategyNFT), address(token));

        // Whitelist adapter
        strategyNFT.whitelistAdapter(adapter1);

        // Give users tokens
        vm.prank(address(this));
        token.transfer(user1, 1000 * 10 ** 18);
        token.transfer(user2, 1000 * 10 ** 18);
    }

    function _createStrategy(address _creator, address _adapter) internal returns (uint256) {
        vm.prank(_creator);
        
        address[] memory adapters = new address[](1);
        adapters[0] = _adapter;
        
        uint16[] memory ratios = new uint16[](1);
        ratios[0] = 10000;

        return strategyNFT.createStrategy(
            adapters,
            ratios,
            250,  // 2.5% creator fee
            3,    // medium risk
            keccak256("TestStrategy"),
            7,
            50
        );
    }

    // ========================================================================
    // TESTS: Deposit & Withdrawal
    // ========================================================================

    function test_deposit_success() public {
        uint256 strategyTokenId = _createStrategy(creator, adapter1);
        
        uint256 depositAmount = 100 * 10 ** 18;
        
        vm.prank(user1);
        token.approve(address(vault), depositAmount);
        vault.deposit(strategyTokenId, depositAmount);

        assertEq(vault.totalDeposits(), depositAmount, "Total deposits should match");
        assertEq(vault.getTVL(), depositAmount, "TVL should match");
    }

    function test_deposit_multipleUsers() public {
        uint256 strategyTokenId = _createStrategy(creator, adapter1);
        
        uint256 deposit1 = 100 * 10 ** 18;
        uint256 deposit2 = 150 * 10 ** 18;

        vm.prank(user1);
        token.approve(address(vault), deposit1);
        vault.deposit(strategyTokenId, deposit1);

        vm.prank(user2);
        token.approve(address(vault), deposit2);
        vault.deposit(strategyTokenId, deposit2);

        assertEq(vault.getTVL(), deposit1 + deposit2, "Total TVL should be sum of deposits");
    }

    function test_withdraw_success() public {
        uint256 strategyTokenId = _createStrategy(creator, adapter1);
        uint256 depositAmount = 100 * 10 ** 18;

        vm.prank(user1);
        token.approve(address(vault), depositAmount);
        uint256 positionId = vault.deposit(strategyTokenId, depositAmount);

        uint256 sharesToWithdraw = vault.userShares(user1);

        vm.prank(user1);
        vault.withdraw(positionId, sharesToWithdraw);

        assertEq(vault.getTVL(), 0, "TVL should be 0 after withdrawal");
    }

    function test_deposit_revertOnInvalidStrategy() public {
        vm.prank(user1);
        token.approve(address(vault), 100 * 10 ** 18);

        vm.expectRevert("Strategy invalid");
        vault.deposit(999, 100 * 10 ** 18);
    }

    // ========================================================================
    // TESTS: Share Accounting
    // ========================================================================

    function test_sharePrice_calculation() public {
        uint256 strategyTokenId = _createStrategy(creator, adapter1);
        
        vm.prank(user1);
        token.approve(address(vault), 100 * 10 ** 18);
        vault.deposit(strategyTokenId, 100 * 10 ** 18);

        uint256 sharePrice = vault.getSharePrice();
        assertEq(sharePrice, 1e18, "Initial share price should be 1");
    }

    function test_userBalance_tracking() public {
        uint256 strategyTokenId = _createStrategy(creator, adapter1);
        uint256 depositAmount = 100 * 10 ** 18;

        vm.prank(user1);
        token.approve(address(vault), depositAmount);
        vault.deposit(strategyTokenId, depositAmount);

        uint256 userBalance = vault.getUserBalance(user1);
        assertEq(userBalance, depositAmount, "User balance should match deposit");
    }

    // ========================================================================
    // TESTS: Creator Fees
    // ========================================================================

    function test_creatorFee_collection() public {
        uint256 strategyTokenId = _createStrategy(creator, adapter1);
        uint256 depositAmount = 100 * 10 ** 18;

        vm.prank(user1);
        token.approve(address(vault), depositAmount);
        uint256 positionId = vault.deposit(strategyTokenId, depositAmount);

        // Withdraw with fees
        uint256 sharesToWithdraw = vault.userShares(user1);
        
        vm.prank(user1);
        vault.withdraw(positionId, sharesToWithdraw);

        uint256 creatorFeeBalance = vault.getCreatorFeeBalance(creator);
        
        // Creator fee should be 2.5% of deposit
        uint256 expectedFee = (depositAmount * 250) / 10000;
        assertGe(creatorFeeBalance, expectedFee - 1, "Creator fee should be approximately 2.5%");
    }

    function test_withdrawCreatorFees() public {
        uint256 strategyTokenId = _createStrategy(creator, adapter1);
        uint256 depositAmount = 100 * 10 ** 18;

        vm.prank(user1);
        token.approve(address(vault), depositAmount);
        uint256 positionId = vault.deposit(strategyTokenId, depositAmount);

        vm.prank(user1);
        vault.withdraw(positionId, vault.userShares(user1));

        uint256 balanceBefore = token.balanceOf(creator);

        vm.prank(creator);
        vault.withdrawCreatorFees();

        uint256 balanceAfter = token.balanceOf(creator);
        assertGt(balanceAfter, balanceBefore, "Creator balance should increase");
    }

    // ========================================================================
    // TESTS: Pausable
    // ========================================================================

    function test_pause_preventDeposits() public {
        uint256 strategyTokenId = _createStrategy(creator, adapter1);
        
        vault.pause();

        vm.prank(user1);
        token.approve(address(vault), 100 * 10 ** 18);
        
        vm.expectRevert("Pausable: paused");
        vault.deposit(strategyTokenId, 100 * 10 ** 18);
    }

    function test_unpause_allowsDeposits() public {
        uint256 strategyTokenId = _createStrategy(creator, adapter1);
        
        vault.pause();
        vault.unpause();

        uint256 depositAmount = 100 * 10 ** 18;
        
        vm.prank(user1);
        token.approve(address(vault), depositAmount);
        vault.deposit(strategyTokenId, depositAmount);

        assertEq(vault.getTVL(), depositAmount, "Deposit should succeed after unpause");
    }
}
