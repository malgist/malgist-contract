// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {UserVault} from "../src/UserVault.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {MockAdapter} from "../src/mocks/MockAdapter.sol";
import {StrategyRegistry} from "../src/StrategyRegistry.sol";

contract StrategyVersioningTest is Test {
    UserVault public vault;
    MockERC20 public usdc;
    MockAdapter public a1;
    MockAdapter public a2;
    StrategyRegistry public registry;

    address public alice = address(0xA);
    address public guardian = address(0xB);

    function setUp() public {
        usdc = new MockERC20("USD Coin", "USDC", 6);
        a1 = new MockAdapter(address(usdc));
        a2 = new MockAdapter(address(usdc));

        vault = new UserVault(address(usdc), guardian);

        // Give Alice tokens and approve vault
        usdc.mint(alice, 1000e6);
        vm.prank(alice);
        usdc.approve(address(vault), type(uint256).max);

        // Deploy registry and set on vault
        registry = new StrategyRegistry();
        // registry owner is this test contract
        vm.prank(guardian);
        vault.setStrategyRegistry(address(registry));
    }

    function testMigrateV1ToV2() public {
        // Alice sets initial strategy to adapter a1
        address[] memory adapters = new address[](1);
        adapters[0] = address(a1);
        uint16[] memory ratios = new uint16[](1);
        ratios[0] = 10000;

        vm.prank(alice);
        vault.setStrategy(adapters, ratios, true, "v1", 0);

        // Deposit into v1
        vm.prank(alice);
        vault.deposit(100e6);

        uint256 strategyId = uint256(uint160(alice));

        // Add versions in registry: v1 and v2
        address[] memory v1Adapters = new address[](1);
        v1Adapters[0] = address(a1);
        uint16[] memory v1Ratios = new uint16[](1);
        v1Ratios[0] = 10000;

        address[] memory v2Adapters = new address[](1);
        v2Adapters[0] = address(a2);
        uint16[] memory v2Ratios = new uint16[](1);
        v2Ratios[0] = 10000;

        registry.addVersion(strategyId, 1, v1Adapters, v1Ratios, 1, true);
        registry.addVersion(strategyId, 2, v2Adapters, v2Ratios, 1, true);

        // Now perform migration opt-in by Alice
        vm.prank(alice);
        vault.migrateStrategy(strategyId, 2, 50, block.timestamp + 1 hours);

        // After migration, user's strategy should reference adapter a2
        UserVault.Strategy memory s = vault.getStrategy(alice);
        assertEq(s.adapters.length, 1);
        assertEq(s.adapters[0], address(a2));
    }

    function testDeprecatedVersionRejectsDeposits() public {
        // Start on v1 and deposit
        address[] memory adapters = new address[](1);
        adapters[0] = address(a1);
        uint16[] memory ratios = new uint16[](1);
        ratios[0] = 10000;

        vm.prank(alice);
        vault.setStrategy(adapters, ratios, true, "v1", 0);

        vm.prank(alice);
        vault.deposit(100e6);

        uint256 strategyId = uint256(uint160(alice));

        // Add versions and migrate to v2
        address[] memory v1Adapters = new address[](1);
        v1Adapters[0] = address(a1);
        uint16[] memory v1Ratios = new uint16[](1);
        v1Ratios[0] = 10000;

        address[] memory v2Adapters = new address[](1);
        v2Adapters[0] = address(a2);
        uint16[] memory v2Ratios = new uint16[](1);
        v2Ratios[0] = 10000;

        registry.addVersion(strategyId, 1, v1Adapters, v1Ratios, 1, true);
        registry.addVersion(strategyId, 2, v2Adapters, v2Ratios, 1, true);

        vm.prank(alice);
        vault.migrateStrategy(strategyId, 2, 50, block.timestamp + 1 hours);

        // Deprecate v2
        registry.deprecateVersion(strategyId, 2);

        // Alice tries to deposit into deprecated version -> should revert
        vm.prank(alice);
        vm.expectRevert(UserVault.DeprecatedStrategy.selector);
        vault.deposit(10e6);
    }

    function testPreventDowngrade() public {
        // Alice on v2
        address[] memory adapters = new address[](1);
        adapters[0] = address(a2);
        uint16[] memory ratios = new uint16[](1);
        ratios[0] = 10000;

        vm.prank(alice);
        vault.setStrategy(adapters, ratios, true, "v2", 0);

        uint256 strategyId = uint256(uint160(alice));

        // add v1 and v2
        address[] memory v1Adapters = new address[](1);
        v1Adapters[0] = address(a1);
        uint16[] memory v1Ratios = new uint16[](1);
        v1Ratios[0] = 10000;

        address[] memory v2Adapters = new address[](1);
        v2Adapters[0] = address(a2);
        uint16[] memory v2Ratios = new uint16[](1);
        v2Ratios[0] = 10000;

        registry.addVersion(strategyId, 1, v1Adapters, v1Ratios, 1, true);
        registry.addVersion(strategyId, 2, v2Adapters, v2Ratios, 1, true);

        // Attempt to downgrade from 2 -> 1
        vm.prank(alice);
        vm.expectRevert(UserVault.DowngradeNotAllowed.selector);
        vault.migrateStrategy(strategyId, 1, 50, block.timestamp + 1 hours);
    }
}

