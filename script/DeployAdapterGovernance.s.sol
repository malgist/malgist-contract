// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {AdapterGovernance} from "../src/governance/AdapterGovernance.sol";

/**
 * @title DeployAdapterGovernance
 * @notice Deployment script for AdapterGovernance contract
 * @dev Deploys timelock-protected adapter whitelist management
 */
contract DeployAdapterGovernance is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("========================================");
        console.log("Deploying AdapterGovernance");
        console.log("========================================");
        console.log("Deployer:", deployer);
        console.log("Network: Mantle Sepolia");
        console.log("");

        vm.startBroadcast(deployerPrivateKey);

        // Deploy AdapterGovernance contract (with 2-day timelock)
        // 2 days = 172,800 seconds
        uint48 timelockDuration = 2 days;
        
        AdapterGovernance governance = new AdapterGovernance(deployer, timelockDuration, deployer);
        
        console.log("AdapterGovernance deployed at:", address(governance));
        console.log("Timelock duration:", timelockDuration, "seconds (2 days)");

        vm.stopBroadcast();

        // Summary
        console.log("");
        console.log("========================================");
        console.log("DEPLOYMENT COMPLETE");
        console.log("========================================");
        console.log("AdapterGovernance:", address(governance));
        console.log("Timelock duration: 2 days");
        console.log("");
    }
}
