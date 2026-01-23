// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @test-type CORE-INTEGRATION
/// @covers UserVault, StrategyRegistry
/// @notes Ensures creation phases + caps remain enforced for permissionless flows.


import {Test} from "forge-std/Test.sol";
import {UserVault} from "../../src/UserVault.sol";
import {MockERC20} from "../../src/mocks/MockERC20.sol";
import {MockLendingPool} from "../../src/mocks/MockLendingPool.sol";
import {LendleAdapter} from "../../src/adapters/LendleAdapter.sol";
import {StrategyRegistry} from "../../src/StrategyRegistry.sol";

contract PermissionlessStrategyTest is Test {
    UserVault public vault;
    MockERC20 public usdc;
    MockERC20 public aUsdc;
    MockLendingPool public lendingPool;
    LendleAdapter public lendleAdapter;
    StrategyRegistry public registry;

    address public alice = address(0x1);
    address public bob = address(0x2);
    address public guardian = address(0x999);

    uint256 constant INITIAL_BALANCE = 10000e6;

    function setUp() public {
        usdc = new MockERC20("USD Coin", "USDC", 6);
        aUsdc = new MockERC20("Aave USDC", "aUSDC", 6);
        lendingPool = new MockLendingPool();
        lendingPool.setReserveToken(address(usdc), address(aUsdc));

        vault = new UserVault(address(usdc), guardian);

        lendleAdapter = new LendleAdapter(address(usdc), address(lendingPool), address(vault));

        // Mint
        usdc.mint(alice, INITIAL_BALANCE);
        usdc.mint(bob, INITIAL_BALANCE);

        vm.prank(alice);
        usdc.approve(address(vault), type(uint256).max);
        vm.prank(bob);
        usdc.approve(address(vault), type(uint256).max);

        // Deploy registry and wire to vault
        registry = new StrategyRegistry();
        vm.prank(guardian);
        vault.setStrategyRegistry(address(registry));

        // Allow vault to register strategies on behalf of creators
        registry.setRegistrar(address(vault), true);
    }

    function testRestrictedPhaseRequiresApproval() public {
        // default phase is Restricted in registry constructor
        address[] memory adapters = new address[](1);
        adapters[0] = address(lendleAdapter);
        uint16[] memory ratios = new uint16[](1);
        ratios[0] = 10000;

        vm.prank(alice);
        vm.expectRevert();
        vault.setStrategy(adapters, ratios, true, "Alice Strat", 0);

        // Approve alice as creator and retry
        registry.approveCreator(alice, true);

        vm.prank(alice);
        vault.setStrategy(adapters, ratios, true, "Alice Strat", 0);
    }

    function testLimitedPhaseTVLCapEnforced() public {
        // Move to Limited
        registry.setPhase(StrategyRegistry.StrategyPhase.Limited);

        // Set small caps (token has 6 decimals)
        registry.setLimitedCaps(500e6, 5000e6);

        address[] memory adapters = new address[](1);
        adapters[0] = address(lendleAdapter);
        uint16[] memory ratios = new uint16[](1);
        ratios[0] = 10000;

        // Bob creates strategy (permissionless in Limited)
        vm.prank(bob);
        vault.setStrategy(adapters, ratios, true, "Bob Strat", 0);

        // fund lending pool to accept deposits
        uint256 depositAmount = 600e6;
        vm.prank(bob);
        // deposit should revert due to cap 500e6
        vm.expectRevert();
        vault.deposit(depositAmount);

        // smaller deposit should succeed
        vm.prank(bob);
        uint256 shares = vault.deposit(400e6);
        assertGt(shares, 0);
    }

    function testCommunityReviewedAllowsHigherCap() public {
        // Limited phase
        registry.setPhase(StrategyRegistry.StrategyPhase.Limited);
        registry.setLimitedCaps(500e6, 5000e6);

        address[] memory adapters = new address[](1);
        adapters[0] = address(lendleAdapter);
        uint16[] memory ratios = new uint16[](1);
        ratios[0] = 10000;

        vm.prank(bob);
        vault.setStrategy(adapters, ratios, true, "Bob Strat", 0);

        uint256 strategyId = uint256(uint160(bob));
        // mark community reviewed to raise cap
        registry.setCommunityReviewed(strategyId, true);

        vm.prank(bob);
        uint256 shares = vault.deposit(2000e6); // under reviewed cap 5000e6
        assertGt(shares, 0);
    }
}
