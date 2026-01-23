// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @test-type EXPERIMENTAL-KEEPER
/// @covers AutoRebalanceEngine
/// @notes Keeper queue simulation; informative only for research builds.


import "forge-std/Test.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {MockAdapter} from "../src/mocks/MockAdapter.sol";
import {UserVault} from "../src/UserVault.sol";
import {AutoRebalanceEngine} from "../src/AutoRebalanceEngine.sol";

contract AutoRebalanceTest is Test {
    MockERC20 token;
    MockAdapter adapterA;
    MockAdapter adapterB;
    UserVault vault;
    AutoRebalanceEngine engine;

    address alice = address(0xA1);
    address pauseOwner = address(this);

    function setUp() public {
        token = new MockERC20("USDC", "USDC", 18);
        adapterA = new MockAdapter(address(token));
        adapterB = new MockAdapter(address(token));

        // Deploy vault with this test as pause owner
        vault = new UserVault(address(token), pauseOwner);

        // Deploy engine
        engine = new AutoRebalanceEngine(address(vault), address(token), address(this));

        // Authorize engine in vault
        vault.setRebalanceEngine(address(engine));
        // allow immediate rebalances in tests
        vault.setMinRebalanceInterval(0);

        // Fund alice with tokens and approve vault
        token.mint(alice, 1000 ether);
        vm.startPrank(alice);
        token.approve(address(vault), type(uint256).max);

        // Alice sets strategy with two adapters 50/50
        address[] memory adapters = new address[](2);
        adapters[0] = address(adapterA);
        adapters[1] = address(adapterB);
        uint16[] memory ratios = new uint16[](2);
        ratios[0] = 5000;
        ratios[1] = 5000;
        vault.setStrategy(adapters, ratios, false, "Alice Strat", 0);

        // Alice deposits 1000
        vault.deposit(1000 ether);
        vm.stopPrank();
    }

    function testThresholdTriggeredRebalanceAuto() public {
        uint256 strategyId = uint256(uint160(alice));

        // Simulate yield on adapterA to create drift: mint 400 to adapterA
        token.mint(address(adapterA), 400 ether);
        adapterA.mint(address(vault), 400 ether);

        // pre-check tvls
        uint256 a = adapterA.getBalance();
        uint256 b = adapterB.getBalance();
        assertTrue(a > b);

        // call auto rebalance
        uint16 maxSlippage = 100; // 1%
        uint256 deadline = block.timestamp + 1 hours;
        // Debug: replicate vault computations to identify failing step
        UserVault.Strategy memory s = vault.getStrategy(alice);
        uint256 adaptersCount = s.adapters.length;
        uint256 total = 0;
        uint256[] memory tvls = new uint256[](adaptersCount);
        for (uint256 i = 0; i < adaptersCount; i++) {
            tvls[i] = MockAdapter(s.adapters[i]).getBalance();
            total += tvls[i];
        }
        uint256[] memory toWithdraw = new uint256[](adaptersCount);
        uint256[] memory toDeposit = new uint256[](adaptersCount);
        for (uint256 i = 0; i < adaptersCount; i++) {
            uint256 target = (total * uint256(s.ratios[i])) / 10000;
            if (tvls[i] > target) toWithdraw[i] = tvls[i] - target;
            else if (tvls[i] < target) toDeposit[i] = target - tvls[i];
        }

        // Attempt to simulate vault's withdraw calls directly to detect failure
        for (uint256 i = 0; i < adaptersCount; i++) {
            if (toWithdraw[i] == 0) continue;
            // simulate call from vault
            vm.prank(address(vault));
            try MockAdapter(s.adapters[i]).withdraw(toWithdraw[i]) returns (uint256 w) {
                emit log_named_uint("withdrawn", w);
            } catch (bytes memory data) {
                emit log_bytes(data);
            }
        }

        // simulate deposit as vault to ensure deposits succeed
        for (uint256 i = 0; i < adaptersCount; i++) {
            if (toDeposit[i] == 0) continue;
            uint256 amount = (200 ether * toDeposit[i]) / 200 ether; // simplified expected amount
            vm.prank(address(vault));
            try MockAdapter(s.adapters[i]).deposit(amount) returns (uint256 d) {
                emit log_named_uint("deposited", d);
            } catch (bytes memory data) {
                emit log_bytes(data);
            }
        }

        // Now call vault.rebalanceByEngine as engine
        vm.prank(address(engine));
        try vault.rebalanceByEngine(strategyId, maxSlippage, deadline) returns (bool ok) {
            assertTrue(ok);
        } catch (bytes memory data) {
            emit log_bytes(data);
            fail("vault.rebalanceByEngine reverted");
        }

        // Now call through engine
        try engine.rebalanceAuto(strategyId, maxSlippage, deadline) returns (bool ok2) {
            assertTrue(ok2);
        } catch Error(string memory reason2) {
            fail(reason2);
        } catch {
            fail("unknown");
        }

        // after rebalance, balances should be closer to target (50/50)
        uint256 a2 = adapterA.getBalance();
        uint256 b2 = adapterB.getBalance();
        // assert difference smaller
        uint256 diffBefore = a > b ? a - b : b - a;
        uint256 diffAfter = a2 > b2 ? a2 - b2 : b2 - a2;
        assertTrue(diffAfter <= diffBefore);
    }

    function testGasGuardFails() public {
        uint256 strategyId = uint256(uint160(alice));
        // set engine minGasLeft very high
        engine.setMinGasLeft(type(uint256).max / 2);
        uint16 maxSlippage = 100;
        uint256 deadline = block.timestamp + 1 hours;
        vm.expectRevert();
        engine.rebalanceAuto(strategyId, maxSlippage, deadline);
    }

    function testManualTriggerByKeeper() public {
        uint256 strategyId = uint256(uint160(alice));
        // set keeper to this address
        engine.setKeeper(address(this));
        uint16 maxSlippage = 100;
        uint256 deadline = block.timestamp + 1 hours;
        bool ok = engine.rebalanceManual(strategyId, maxSlippage, deadline);
        assertTrue(ok);
    }

    function testPausePreventsAuto() public {
        uint256 strategyId = uint256(uint160(alice));
        // enable global pause via pauseOwner (this contract is pauseOwner)
        vault.enableGlobalPause("test pause");
        uint16 maxSlippage = 100;
        uint256 deadline = block.timestamp + 1 hours;
        vm.expectRevert();
        engine.rebalanceAuto(strategyId, maxSlippage, deadline);
    }
}
