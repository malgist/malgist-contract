// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/*
 * @script-status ACTIVE
 * @network Mantle Sepolia
 * @usage forge script script/DeployAdapterGovernance.s.sol --broadcast --rpc-url $MANTLE_SEPOLIA_RPC
 * @env PRIVATE_KEY
 * @notes Deploys timelock/guardian contract managing adapter approvals.
 */

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

        // Deploy AdapterGovernance contract (emergency guardian is deployer)
        AdapterGovernance governance = new AdapterGovernance(deployer);
        
        console.log("AdapterGovernance deployed at:", address(governance));

        vm.stopBroadcast();

        // Summary
        console.log("");
        console.log("========================================");
        console.log("DEPLOYMENT COMPLETE");
        console.log("========================================");
        console.log("AdapterGovernance:", address(governance));
        console.log("");
        console.log("IMPORTANT: 2-day timelock delay for adapter approvals");
        console.log("Default emergency guardian:", deployer);
        console.log("");
    }
}
