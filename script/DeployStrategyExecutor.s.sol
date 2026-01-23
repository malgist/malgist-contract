// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {StrategyExecutor} from "../src/StrategyExecutor.sol";

/**
 * @title DeployStrategyExecutor
 * @notice Deployment script for StrategyExecutor contract
 * @dev Deploys multi-protocol execution routing contract
 */
contract DeployStrategyExecutor is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("========================================");
        console.log("Deploying StrategyExecutor");
        console.log("========================================");
        console.log("Deployer:", deployer);
        console.log("Network: Mantle Sepolia");
        console.log("");

        vm.startBroadcast(deployerPrivateKey);

        // Deploy StrategyExecutor contract
        StrategyExecutor executor = new StrategyExecutor(deployer);
        
        console.log("StrategyExecutor deployed at:", address(executor));

        vm.stopBroadcast();

        // Summary
        console.log("");
        console.log("========================================");
        console.log("DEPLOYMENT COMPLETE");
        console.log("========================================");
        console.log("StrategyExecutor:", address(executor));
        console.log("");
    }
}
