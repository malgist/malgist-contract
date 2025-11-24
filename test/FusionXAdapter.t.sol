// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {MockUniswapV2Pair} from "../src/mocks/MockUniswapV2Pair.sol";
import {MockUniswapV2Router} from "../src/mocks/MockUniswapV2Router.sol";
import {FusionXAdapter} from "../src/adapters/FusionXAdapter.sol";
import {UniversalVault} from "../src/UniversalVault.sol";
import {StrategyNFT} from "../src/StrategyNFT.sol";

/**
 * @title FusionXAdapterTest
 * @notice Test suite for the FusionX DEX zap adapter
 */
contract FusionXAdapterTest is Test {
    // Contracts
    MockERC20 public usdc;
    MockERC20 public mnt;
    MockUniswapV2Pair public lpToken;
    MockUniswapV2Router public router;
    FusionXAdapter public fusionXAdapter;
    UniversalVault public vault;
    StrategyNFT public strategyNFT;

    // Test accounts
    address public alice = address(0x1);
    address public bob = address(0x2);
    address public creator = address(0x3);

    // Constants
    uint256 constant INITIAL_BALANCE = 10000e6; // 10,000 USDC
    uint256 constant DEPOSIT_AMOUNT = 1000e6; // 1,000 USDC

    function setUp() public {
        // Deploy mock tokens
        usdc = new MockERC20("USD Coin", "USDC", 6);
        mnt = new MockERC20("Mantle", "MNT", 18);

        // Deploy LP token
        lpToken = new MockUniswapV2Pair(
            address(usdc),
            address(mnt),
            "FusionX USDC-MNT LP",
            "FUSION-LP"
        );

        // Deploy router
        router = new MockUniswapV2Router();
        router.createPair(address(usdc), address(mnt), address(lpToken));

        // Deploy core contracts
        strategyNFT = new StrategyNFT();
        vault = new UniversalVault(address(usdc), address(strategyNFT));

        // Deploy FusionX adapter
        fusionXAdapter = new FusionXAdapter(
            address(usdc),
            address(mnt),
            address(lpToken),
            address(router),
            address(vault)
        );

        // Whitelist adapter
        strategyNFT.setAdapterWhitelist(address(fusionXAdapter), true);

        // Mint initial tokens
        usdc.mint(alice, INITIAL_BALANCE);
        usdc.mint(bob, INITIAL_BALANCE);
        mnt.mint(address(router), INITIAL_BALANCE * 10); // Router needs MNT for swaps

        // Approve vault
        vm.prank(alice);
        usdc.approve(address(vault), type(uint256).max);

        vm.prank(bob);
        usdc.approve(address(vault), type(uint256).max);
    }

    /**
     * @notice Test direct adapter deposit (zap)
     */
    function testDirectZapDeposit() public {
        uint256 amount = 100e6;

        console.log("=== DIRECT ZAP TEST ===");
        console.log("USDC deposited:", amount);

        // Mint USDC to vault
        usdc.mint(address(vault), amount);

        vm.prank(address(vault));
        usdc.approve(address(fusionXAdapter), amount);

        vm.prank(address(vault));
        uint256 lpReceived = fusionXAdapter.deposit(amount);

        console.log("LP tokens received:", lpReceived);

        // Verify LP tokens were received
        assertGt(lpReceived, 0, "Should receive LP tokens");
        assertEq(
            fusionXAdapter.getBalance(),
            lpReceived,
            "Adapter should hold LP tokens"
        );

        console.log("Adapter LP balance:", fusionXAdapter.getBalance());
    }

    /**
     * @notice Test full integration: Vault → Strategy → FusionX
     */
    function testFullIntegrationWithFusionX() public {
        // Create strategy with 100% FusionX
        address[] memory adapters = new address[](1);
        adapters[0] = address(fusionXAdapter);

        uint16[] memory ratios = new uint16[](1);
        ratios[0] = 10000; // 100%

        vm.prank(creator);
        uint256 strategyId = strategyNFT.mintStrategy(
            "Pure FusionX",
            adapters,
            ratios,
            10
        );

        console.log("=== FULL INTEGRATION TEST ===");
        console.log("Alice balance before:", usdc.balanceOf(alice));

        // Alice deposits via vault
        vm.prank(alice);
        uint256 shares = vault.deposit(strategyId, DEPOSIT_AMOUNT);

        uint256 expectedNet = DEPOSIT_AMOUNT - (DEPOSIT_AMOUNT * 1) / 100; // 1% fee

        console.log("Deposited:", DEPOSIT_AMOUNT);
        console.log("Creator fee (1%):", DEPOSIT_AMOUNT - expectedNet);
        console.log("Net to FusionX:", expectedNet);
        console.log("Shares received:", shares);

        // Verify balances
        assertEq(shares, expectedNet, "Shares should equal net amount");
        assertGt(
            fusionXAdapter.getBalance(),
            0,
            "FusionX should have LP tokens"
        );

        console.log("LP tokens in adapter:", fusionXAdapter.getBalance());
    }

    /**
     * @notice Test withdrawal (un-zap)
     */
    function testZapWithdrawal() public {
        // Setup strategy
        address[] memory adapters = new address[](1);
        adapters[0] = address(fusionXAdapter);
        uint16[] memory ratios = new uint16[](1);
        ratios[0] = 10000;

        vm.prank(creator);
        uint256 strategyId = strategyNFT.mintStrategy(
            "Test",
            adapters,
            ratios,
            10
        );

        // Alice deposits
        vm.prank(alice);
        uint256 shares = vault.deposit(strategyId, DEPOSIT_AMOUNT);

        console.log("=== WITHDRAWAL TEST ===");
        console.log("Shares to withdraw:", shares);

        uint256 balanceBefore = usdc.balanceOf(alice);

        // Withdraw
        vm.prank(alice);
        uint256 withdrawn = vault.withdraw(strategyId, shares);

        uint256 balanceAfter = usdc.balanceOf(alice);
        uint256 actualReceived = balanceAfter - balanceBefore;

        console.log("Withdrawn amount:", withdrawn);
        console.log("Actually received:", actualReceived);

        // Should receive close to original deposit (minus fees)
        assertGt(withdrawn, 0, "Should receive USDC back");
        assertEq(fusionXAdapter.getBalance(), 0, "Adapter should be empty");
    }

    /**
     * @notice Test swap functionality
     */
    function testSwapMechanism() public {
        uint256 swapAmount = 50e6;

        // Setup: give adapter some USDC
        usdc.mint(address(fusionXAdapter), swapAmount);

        // Need to do the swap as if from vault
        vm.prank(address(fusionXAdapter));
        usdc.approve(address(router), swapAmount);

        address[] memory path = new address[](2);
        path[0] = address(usdc);
        path[1] = address(mnt);

        vm.prank(address(fusionXAdapter));
        uint256[] memory amounts = router.swapExactTokensForTokens(
            swapAmount,
            0,
            path,
            address(fusionXAdapter),
            block.timestamp
        );

        console.log("Swapped USDC:", swapAmount);
        console.log("Received MNT:", amounts[1]);

        assertGt(amounts[1], 0, "Should receive MNT");
    }

    /**
     * @notice Test mixed strategy: Lendle + FusionX
     */
    function testMixedStrategy() public {
        // We'd need to deploy LendleAdapter too for this test
        // Skipping for now, but this would test 50% Lendle + 50% FusionX
    }

    /**
     * @notice Test adapter view functions
     */
    function testAdapterViewFunctions() public {
        assertEq(fusionXAdapter.token(), address(usdc), "Token should be USDC");
        assertEq(
            fusionXAdapter.getLPToken(),
            address(lpToken),
            "LP token should match"
        );
        assertEq(
            fusionXAdapter.getTokenB(),
            address(mnt),
            "TokenB should be MNT"
        );
        assertEq(
            fusionXAdapter.getRouter(),
            address(router),
            "Router should match"
        );
    }

    /**
     * @notice Test revert on zero deposit
     */
    function testRevertZeroDeposit() public {
        vm.prank(address(vault));
        vm.expectRevert(FusionXAdapter.InvalidAmount.selector);
        fusionXAdapter.deposit(0);
    }

    /**
     * @notice Test only vault can call
     */
    function testRevertOnlyVault() public {
        vm.prank(alice);
        vm.expectRevert(FusionXAdapter.OnlyVault.selector);
        fusionXAdapter.deposit(100e6);
    }

    /**
     * @notice Test LP token balance tracking
     */
    function testLPBalanceTracking() public {
        // Create strategy
        address[] memory adapters = new address[](1);
        adapters[0] = address(fusionXAdapter);
        uint16[] memory ratios = new uint16[](1);
        ratios[0] = 10000;

        vm.prank(creator);
        uint256 strategyId = strategyNFT.mintStrategy("LP Test", adapters, ratios, 10);

        // Deposit
        vm.prank(alice);
        vault.deposit(strategyId, DEPOSIT_AMOUNT);

        uint256 lpBalance = fusionXAdapter.getBalance();
        console.log("LP balance after deposit:", lpBalance);

        assertGt(lpBalance, 0, "Should have LP tokens");

        // Partial withdrawal
        uint256 withdrawAmount = lpBalance / 2;

        vm.prank(alice);
        vault.withdraw(strategyId, withdrawAmount);

        uint256 lpBalanceAfter = fusionXAdapter.getBalance();
        console.log("LP balance after partial withdraw:", lpBalanceAfter);

        assertLt(lpBalanceAfter, lpBalance, "LP balance should decrease");
    }

    /**
     * @notice Test multiple users
     */
    function testMultipleUsers() public {
        address[] memory adapters = new address[](1);
        adapters[0] = address(fusionXAdapter);
        uint16[] memory ratios = new uint16[](1);
        ratios[0] = 10000;

        vm.prank(creator);
        uint256 strategyId = strategyNFT.mintStrategy("Multi", adapters, ratios, 10);

        // Alice deposits
        vm.prank(alice);
        vault.deposit(strategyId, DEPOSIT_AMOUNT);

        uint256 lpBalanceAfterAlice = fusionXAdapter.getBalance();

        // Bob deposits
        vm.prank(bob);
        vault.deposit(strategyId, DEPOSIT_AMOUNT * 2);

        uint256 lpBalanceAfterBob = fusionXAdapter.getBalance();

        console.log("LP balance after Alice:", lpBalanceAfterAlice);
        console.log("LP balance after Bob:", lpBalanceAfterBob);

        assertGt(
            lpBalanceAfterBob,
            lpBalanceAfterAlice,
            "LP balance should increase"
        );
    }
}
