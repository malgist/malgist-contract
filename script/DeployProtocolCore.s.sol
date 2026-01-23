// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/*
 * @script-status ACTIVE
 * @network Mantle Sepolia
 * @usage forge script script/DeployProtocolCore.s.sol --broadcast --rpc-url $MANTLE_SEPOLIA_RPC
 * @env PRIVATE_KEY, UNIVERSAL_VAULT_ADDRESS, USDC_ADDRESS
 * @notes Deploys AdapterRegistry, FeeManager, and Faucet around an existing UserVault.
 */

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {AdapterRegistry} from "../src/AdapterRegistry.sol";
import {FeeManager} from "../src/FeeManager.sol";
import {Faucet} from "../src/Faucet.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title DeployProtocolCore
 * @notice Deploy core protocol infrastructure: AdapterRegistry, FeeManager, Faucet
 * @dev Usage:
 *      forge script script/DeployProtocolCore.s.sol --broadcast --rpc-url $MANTLE_SEPOLIA_RPC
 */
contract DeployProtocolCore is Script {
    // ============ State Variables ============

    address public universalVault;
    address public usdc;
    address public adapterRegistry;
    address public feeManager;
    address public faucet;

    // ============ Setup ============

    function setUp() public {
        // Read from .env
        universalVault = vm.envAddress("UNIVERSAL_VAULT_ADDRESS");
        usdc = vm.envAddress("USDC_ADDRESS");

        require(universalVault != address(0), "UNIVERSAL_VAULT_ADDRESS not set");
        require(usdc != address(0), "USDC_ADDRESS not set");
    }

    // ============ Main Deployment ============

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        address treasury = deployer; // Treasury = deployer

        vm.startBroadcast(deployerPrivateKey);

        // ========== 1. Deploy AdapterRegistry ==========
        console.log("Deploying AdapterRegistry...");
        adapterRegistry = address(new AdapterRegistry());
        console.log("AdapterRegistry deployed at:", adapterRegistry);

        // ========== 2. Deploy FeeManager ==========
        console.log("Deploying FeeManager...");
        // FeeManager(address _asset, address _treasury, uint16 _protocolFeeBps, address _admin)
        feeManager = address(new FeeManager(usdc, treasury, 500, deployer)); // 5% fee
        console.log("FeeManager deployed at:", feeManager);

        // ========== 3. Deploy Faucet ==========
        console.log("Deploying Faucet...");
        // Faucet(address _usdc)
        faucet = address(new Faucet(usdc));
        console.log("Faucet deployed at:", faucet);

        // ========== 4. Fund Faucet ==========
        console.log("Funding Faucet with USDC...");
        IERC20(usdc).transfer(faucet, 100_000e6); // 100k USDC
        console.log("Faucet funded with 100,000 USDC");

        vm.stopBroadcast();

        // ========== Log Results ==========
        console.log("=====================================");
        console.log("DEPLOYMENT COMPLETE");
        console.log("=====================================");
        console.log("AdapterRegistry:", adapterRegistry);
        console.log("FeeManager:", feeManager);
        console.log("Faucet:", faucet);
        console.log("");
        console.log("UPDATE .env WITH:");
        console.log(
            string(abi.encodePacked(
                "ADAPTER_REGISTRY_ADDRESS=", addressToString(adapterRegistry)
            ))
        );
        console.log(
            string(abi.encodePacked(
                "FEE_MANAGER_ADDRESS=", addressToString(feeManager)
            ))
        );
        console.log(
            string(abi.encodePacked(
                "FAUCET_ADDRESS=", addressToString(faucet)
            ))
        );
    }

    // ============ Helpers ============

    function addressToString(address _addr) internal pure returns (string memory) {
        bytes memory s = new bytes(40);
        for (uint256 i = 0; i < 20; i++) {
            bytes1 b = bytes1(uint8(uint256(uint160(_addr)) / (2 ** (8 * (19 - i)))));
            bytes1 hi = bytes1(uint8(b) / 16);
            bytes1 lo = bytes1(uint8(b) - 16 * uint8(hi));
            s[2 * i] = char(hi);
            s[2 * i + 1] = char(lo);
        }
        return string(abi.encodePacked("0x", s));
    }

    function char(bytes1 b) internal pure returns (bytes1 c) {
        if (uint8(b) < 10) return bytes1(uint8(b) + 0x30);
        else return bytes1(uint8(b) + 0x57);
    }
}
