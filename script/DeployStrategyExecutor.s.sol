// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/*
 * @script-status ACTIVE
 * @network Mantle Sepolia
 * @usage forge script script/DeployStrategyExecutor.s.sol --broadcast --rpc-url $MANTLE_SEPOLIA_RPC
 * @env PRIVATE_KEY, USER_VAULT_ADDRESS, USDC_ADDRESS
 * @notes Connects StrategyExecutor to production vault + asset.
 */

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

        // Get existing deployed addresses from environment
        address vault = vm.envAddress("USER_VAULT_ADDRESS");
        address asset = vm.envAddress("USDC_ADDRESS");

        // Deploy StrategyExecutor contract
        StrategyExecutor executor = new StrategyExecutor(vault, asset);
        
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
