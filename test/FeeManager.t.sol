// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @test-type CORE-ACCOUNTING
/// @covers FeeManager
/// @notes Validates treasury/strategist fee routing math.


import "forge-std/Test.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {FeeManager} from "../src/FeeManager.sol";
import {IFeeManager} from "../src/interfaces/IFeeManager.sol";

contract MockVault {
    MockERC20 public token;

    constructor(address _token) {
        token = MockERC20(_token);
    }

    // Transfer gross to FeeManager and call chargeFees
    function callCharge(address feeManager, uint256 strategyId, uint256 gross, address creator, uint16 creatorFeeBps) external returns (uint256) {
        if (gross > 0) {
            token.transfer(feeManager, gross);
        }
        uint256 net = IFeeManager(feeManager).chargeFees(strategyId, gross, creator, creatorFeeBps);
        return net;
    }
}

contract FeeManagerTest is Test {
    MockERC20 token;
    FeeManager feeManager;
    MockVault vault;

    address treasury = address(0xBEEF);
    address creator = address(0xCAFE);

    function setUp() public {
        token = new MockERC20("Mock", "MCK", 18);

        // Deploy FeeManager with 200 bps protocol fee and admin = address(this)
        feeManager = new FeeManager(address(token), treasury, 200, address(this));

        // Deploy mock vault
        vault = new MockVault(address(token));

        // Authorize vault
        feeManager.setAuthorizedVault(address(vault), true);
    }

    function testFeeCalculationAndDistribution() public {
        uint256 gross = 1_000 ether; // 1000 tokens (1e18)
        uint16 creatorFeeBps = 500; // 5%

        // Mint to vault
        token.mint(address(vault), gross);

        // Pre balances
        uint256 beforeCreator = token.balanceOf(creator);
        uint256 beforeTreasury = token.balanceOf(treasury);

        // Call as vault
        uint256 net = vault.callCharge(address(feeManager), 1, gross, creator, creatorFeeBps);

        uint256 expectedCreator = (gross * uint256(creatorFeeBps)) / 10000;
        uint256 expectedProtocol = (gross * uint256(200)) / 10000; // feeManager set to 200 bps
        uint256 expectedNet = gross - expectedCreator - expectedProtocol;

        assertEq(token.balanceOf(creator) - beforeCreator, expectedCreator);
        assertEq(token.balanceOf(treasury) - beforeTreasury, expectedProtocol);

        // Vault (caller) should have net returned
        assertEq(token.balanceOf(address(vault)), expectedNet);
        assertEq(net, expectedNet);
    }

    function testUnauthorizedCallerReverts() public {
        uint256 gross = 100 ether;
        // Mint to this test contract
        token.mint(address(this), gross);
        token.transfer(address(feeManager), gross);

        // Expect revert when calling directly (not an authorized vault)
        vm.expectRevert();
        feeManager.chargeFees(1, gross, creator, 100);
    }

    function testZeroYieldReturnsZero() public {
        uint256 gross = 0;
        token.mint(address(vault), 0);
        uint256 net = vault.callCharge(address(feeManager), 2, gross, creator, 0);
        assertEq(net, 0);
    }

    function testCreatorFeeBpsTooLargeReverts() public {
        uint256 gross = 100 ether;
        token.mint(address(vault), gross);
        // creator fee > 1000 should revert
        vm.expectRevert();
        vault.callCharge(address(feeManager), 3, gross, creator, 2000);
    }

    function testProtocolFeeUpdateAndCap() public {
        // setting > max should revert
        vm.expectRevert();
        feeManager.setProtocolFeeBps(1000);

        // setting acceptable value
        feeManager.setProtocolFeeBps(300);
        assertEq(uint256(feeManager.protocolFeeBps()), 300);
    }
}
