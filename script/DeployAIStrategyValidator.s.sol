// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/*
 * @script-status ACTIVE
 * @network Mantle Sepolia
 * @usage forge script script/DeployAIStrategyValidator.s.sol --broadcast --rpc-url $MANTLE_SEPOLIA_RPC
 * @env PRIVATE_KEY
 * @notes Ships AIStrategyValidator used by registry + UserVault.
 */

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {AIStrategyValidator} from "../src/validators/AIStrategyValidator.sol";

/**
 * @title DeployAIStrategyValidator
 * @notice Deployment script for AIStrategyValidator contract
 * @dev Deploys 12-point zero-trust validation contract for AI outputs
 */
contract DeployAIStrategyValidator is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("========================================");
        console.log("Deploying AIStrategyValidator");
        console.log("========================================");
        console.log("Deployer:", deployer);
        console.log("Network: Mantle Sepolia");
        console.log("");

        vm.startBroadcast(deployerPrivateKey);

        // Deploy AIStrategyValidator contract
        AIStrategyValidator validator = new AIStrategyValidator();
        
        console.log("AIStrategyValidator deployed at:", address(validator));

        vm.stopBroadcast();

        // Summary
        console.log("");
        console.log("========================================");
        console.log("DEPLOYMENT COMPLETE");
        console.log("========================================");
        console.log("AIStrategyValidator:", address(validator));
        console.log("");
    }
}
