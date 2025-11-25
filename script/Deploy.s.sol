// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";

import {StrategyNFT} from "../src/StrategyNFT.sol";
import {UniversalVault} from "../src/UniversalVault.sol";
import {LendleAdapter} from "../src/adapters/LendleAdapter.sol";
import {FusionXAdapter} from "../src/adapters/FusionXAdapter.sol";

// Import mocks
import {MockERC20, MockLendingPool} from "../src/mocks/MockLendingPool.sol";
import {MockUniswapV2Pair} from "../src/mocks/MockUniswapV2Pair.sol";
import {MockUniswapV2Router} from "../src/mocks/MockUniswapV2Router.sol";

/**
 * @title DeployScript
 * @notice Deployment script for Mantle Strategy Studio on Mantle Sepolia Testnet
 * @dev Deploys complete ecosystem including mocks for demonstration
 * 
 * Usage:
 * forge script script/Deploy.s.sol --rpc-url $MANTLE_SEPOLIA_RPC --broadcast --verify -vvvv
 */
contract DeployScript is Script {
    function run() external {
        // Get deployer private key from environment
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("=== DEPLOYING TO MANTLE SEPOLIA TESTNET ===");
        console.log("Deployer:", deployer);
        console.log("Balance:", deployer.balance);
        console.log("");

        vm.startBroadcast(deployerPrivateKey);

        // ========================================
        // 1. Deploy Mock Tokens
        // ========================================
        console.log("1. Deploying Mock Tokens...");
        
        MockERC20 usdc = new MockERC20("USD Coin", "USDC", 6);
        console.log("   USDC deployed at:", address(usdc));
        
        MockERC20 aUsdc = new MockERC20("Aave USDC", "aUSDC", 6);
        console.log("   aUSDC deployed at:", address(aUsdc));
        
        MockERC20 mnt = new MockERC20("Wrapped Mantle", "WMNT", 18);
        console.log("   WMNT deployed at:", address(mnt));
        console.log("");

        // ========================================
        // 2. Deploy Mock Lending Pool (Lendle/Aave style)
        // ========================================
        console.log("2. Deploying Mock Lending Pool...");
        
        MockLendingPool lendingPool = new MockLendingPool();
        lendingPool.setReserveToken(address(usdc), address(aUsdc));
        console.log("   LendingPool deployed at:", address(lendingPool));
        console.log("   Reserve configured: USDC -> aUSDC");
        console.log("");

        // ========================================
        // 3. Deploy Mock DEX (FusionX/Uniswap V2 style)
        // ========================================
        console.log("3. Deploying Mock DEX...");
        
        MockUniswapV2Pair lpToken = new MockUniswapV2Pair(
            address(usdc),
            address(mnt),
            "FusionX USDC-WMNT LP",
            "FUSION-LP"
        );
        console.log("   LP Token deployed at:", address(lpToken));
        
        MockUniswapV2Router dexRouter = new MockUniswapV2Router();
        dexRouter.createPair(address(usdc), address(mnt), address(lpToken));
        console.log("   DEX Router deployed at:", address(dexRouter));
        console.log("   Pair created: USDC/WMNT");
        console.log("");

        // Mint MNT to router for swaps
        mnt.mint(address(dexRouter), 1000000e18); // 1M MNT
        console.log("   Minted 1M WMNT to router for swaps");
        console.log("");

        // ========================================
        // 4. Deploy Core Contracts
        // ========================================
        console.log("4. Deploying Core Contracts...");
        
        StrategyNFT strategyNFT = new StrategyNFT();
        console.log("   StrategyNFT deployed at:", address(strategyNFT));
        
        UniversalVault vault = new UniversalVault(address(usdc), address(strategyNFT));
        console.log("   UniversalVault deployed at:", address(vault));
        console.log("");

        // ========================================
        // 5. Deploy Adapters
        // ========================================
        console.log("5. Deploying Adapters...");
        
        LendleAdapter lendleAdapter = new LendleAdapter(
            address(usdc),
            address(lendingPool),
            address(vault)
        );
        console.log("   LendleAdapter deployed at:", address(lendleAdapter));
        
        FusionXAdapter fusionXAdapter = new FusionXAdapter(
            address(usdc),
            address(mnt),
            address(lpToken),
            address(dexRouter),
            address(vault)
        );
        console.log("   FusionXAdapter deployed at:", address(fusionXAdapter));
        console.log("");

        // ========================================
        // 6. Configure System
        // ========================================
        console.log("6. Configuring System...");
        
        strategyNFT.setAdapterWhitelist(address(lendleAdapter), true);
        console.log("   LendleAdapter whitelisted");
        
        strategyNFT.setAdapterWhitelist(address(fusionXAdapter), true);
        console.log("   FusionXAdapter whitelisted");
        console.log("");

        // ========================================
        // 7. Mint Test Tokens (Optional)
        // ========================================
        console.log("7. Minting test tokens to deployer...");
        usdc.mint(deployer, 10000e6); // 10,000 USDC
        console.log("   Minted 10,000 USDC to deployer");
        console.log("");

        vm.stopBroadcast();

        // ========================================
        // Deployment Summary
        // ========================================
        console.log("========================================");
        console.log("=== DEPLOYMENT COMPLETE ===");
        console.log("========================================");
        console.log("");
        console.log("Token Addresses:");
        console.log("  USDC:        ", address(usdc));
        console.log("  aUSDC:       ", address(aUsdc));
        console.log("  WMNT:        ", address(mnt));
        console.log("  LP Token:    ", address(lpToken));
        console.log("");
        console.log("Protocol Addresses:");
        console.log("  LendingPool: ", address(lendingPool));
        console.log("  DEX Router:  ", address(dexRouter));
        console.log("");
        console.log("Core Contracts:");
        console.log("  StrategyNFT: ", address(strategyNFT));
        console.log("  Vault:       ", address(vault));
        console.log("");
        console.log("Adapters:");
        console.log("  Lendle:      ", address(lendleAdapter));
        console.log("  FusionX:     ", address(fusionXAdapter));
        console.log("");
        console.log("========================================");
        console.log("Save these addresses for frontend integration!");
        console.log("========================================");
    }
}
