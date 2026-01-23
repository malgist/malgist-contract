// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/*
 * @script-status ACTIVE
 * @network Mantle Sepolia
 * @usage forge script script/DeployStrategyNFT.s.sol --broadcast --rpc-url $MANTLE_SEPOLIA_RPC
 * @env PRIVATE_KEY
 * @notes Deploys ERC721 registry for curated strategies.
 */

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {StrategyNFT} from "../src/StrategyNFT.sol";

/**
 * @title DeployStrategyNFT
 * @notice Deployment script for StrategyNFT contract
 * @dev Deploys ERC721 contract for immutable strategy ownership
 */
contract DeployStrategyNFT is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("========================================");
        console.log("Deploying StrategyNFT");
        console.log("========================================");
        console.log("Deployer:", deployer);
        console.log("Network: Mantle Sepolia");
        console.log("");

        vm.startBroadcast(deployerPrivateKey);

        // Deploy StrategyNFT contract
        StrategyNFT strategyNFT = new StrategyNFT(deployer);
        
        console.log("StrategyNFT deployed at:", address(strategyNFT));

        vm.stopBroadcast();

        // Summary
        console.log("");
        console.log("========================================");
        console.log("DEPLOYMENT COMPLETE");
        console.log("========================================");
        console.log("StrategyNFT:", address(strategyNFT));
        console.log("");
    }
}
