// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {PriceOracle} from "../src/oracles/PriceOracle.sol";

/**
 * @title DeployPriceOracle
 * @notice Deployment script for PriceOracle contract
 * @dev Deploys Chainlink/Pyth integrated price oracle with slippage protection
 */
contract DeployPriceOracle is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("========================================");
        console.log("Deploying PriceOracle");
        console.log("========================================");
        console.log("Deployer:", deployer);
        console.log("Network: Mantle Sepolia");
        console.log("");

        vm.startBroadcast(deployerPrivateKey);

        // Deploy PriceOracle contract
        PriceOracle oracle = new PriceOracle();
        
        console.log("PriceOracle deployed at:", address(oracle));

        vm.stopBroadcast();

        // Summary
        console.log("");
        console.log("========================================");
        console.log("DEPLOYMENT COMPLETE");
        console.log("========================================");
        console.log("PriceOracle:", address(oracle));
        console.log("");
        console.log("IMPORTANT: Configure price feeds after deployment!");
        console.log("Call: setPriceFeed(asset, chainlinkFeed, heartbeat, maxDeviation)");
        console.log("");
    }
}
