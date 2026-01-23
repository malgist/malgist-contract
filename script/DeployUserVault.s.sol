// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {UserVault} from "../src/UserVault.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {MockLendingPool} from "../src/mocks/MockLendingPool.sol";
import {MockUniswapV2Router} from "../src/mocks/MockUniswapV2Router.sol";
import {MockUniswapV2Pair} from "../src/mocks/MockUniswapV2Pair.sol";
import {LendleAdapter} from "../src/adapters/LendleAdapter.sol";
import {FusionXAdapter} from "../src/adapters/FusionXAdapter.sol";

/**
 * @title DeployUserVault
 * @notice Deployment script for Malgist copy-trading platform on Mantle Sepolia
 * @dev Deploys mock ecosystem + UserVault + Adapters
 */
contract DeployUserVault is Script {
    // Deployed contracts
    MockERC20 public usdc;
    MockERC20 public aUsdc;
    MockERC20 public wmnt;
    MockLendingPool public lendingPool;
    MockUniswapV2Pair public lpToken;
    MockUniswapV2Router public dexRouter;
    UserVault public vault;
    LendleAdapter public lendleAdapter;
    FusionXAdapter public fusionXAdapter;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("========================================");
        console.log("Deploying Malgist Copy-Trading Platform");
        console.log("========================================");
        console.log("Deployer:", deployer);
        console.log("Network: Mantle Sepolia");
        console.log("");

        vm.startBroadcast(deployerPrivateKey);

        // ============ STEP 1: Deploy Mock Tokens ============
        console.log("[1/7] Deploying mock tokens...");
        usdc = new MockERC20("USD Coin", "USDC", 6);
        aUsdc = new MockERC20("Aave USDC", "aUSDC", 6);
        wmnt = new MockERC20("Wrapped Mantle", "WMNT", 18);
        console.log("  USDC:", address(usdc));
        console.log("  aUSDC:", address(aUsdc));
        console.log("  WMNT:", address(wmnt));
        console.log("");

        // ============ STEP 2: Deploy Mock Lending Pool ============
        console.log("[2/7] Deploying mock lending pool...");
        lendingPool = new MockLendingPool();
        lendingPool.setReserveToken(address(usdc), address(aUsdc));
        console.log("  LendingPool:", address(lendingPool));
        console.log("");

        // ============ STEP 3: Deploy Mock DEX ============
        console.log("[3/7] Deploying mock DEX...");
        dexRouter = new MockUniswapV2Router();
        lpToken = new MockUniswapV2Pair(address(usdc), address(wmnt), "FusionX USDC-WMNT LP", "FUSION-LP");
        dexRouter.createPair(address(usdc), address(wmnt), address(lpToken));
        console.log("  DEX Router:", address(dexRouter));
        console.log("  LP Token:", address(lpToken));
        console.log("");

        // ============ STEP 4: Deploy UserVault ============
        console.log("[4/7] Deploying UserVault...");
        // Deploy with msg.sender as initial pause owner (Guardian/Multisig)
        vault = new UserVault(address(usdc), msg.sender);
        console.log("  UserVault:", address(vault));
        console.log("  Pause Owner:", msg.sender);
        console.log("");

        // ============ STEP 5: Deploy Adapters ============
        console.log("[5/7] Deploying adapters...");

        lendleAdapter = new LendleAdapter(address(usdc), address(lendingPool), address(vault));
        console.log("  LendleAdapter:", address(lendleAdapter));

        // For FusionXAdapter, priceOracle can be address(0) for now (optional), owner is deployer
        fusionXAdapter =
            new FusionXAdapter(address(usdc), address(wmnt), address(lpToken), address(dexRouter), address(vault), address(0), msg.sender);
        console.log("  FusionXAdapter:", address(fusionXAdapter));
        console.log("");

        // ============ STEP 6: Mint Test Tokens ============
        console.log("[6/7] Minting test tokens to deployer...");
        usdc.mint(deployer, 10_000 * 10 ** 6); // 10,000 USDC
        wmnt.mint(deployer, 100 * 10 ** 18); // 100 WMNT
        aUsdc.mint(address(lendingPool), 1_000_000 * 10 ** 6); // Pool liquidity
        wmnt.mint(address(dexRouter), 1_000 * 10 ** 18); // DEX liquidity
        console.log("  Deployer USDC: 10,000");
        console.log("  Deployer WMNT: 100");
        console.log("");

        // ============ STEP 7: Setup Complete ============
        console.log("[7/7] Deployment complete!");
        console.log("");

        vm.stopBroadcast();

        // ============ SUMMARY ============
        console.log("========================================");
        console.log("DEPLOYMENT SUMMARY");
        console.log("========================================");
        console.log("");
        console.log("Mock Tokens:");
        console.log("  USDC:", address(usdc));
        console.log("  aUSDC:", address(aUsdc));
        console.log("  WMNT:", address(wmnt));
        console.log("");
        console.log("Mock Protocols:");
        console.log("  Lending Pool:", address(lendingPool));
        console.log("  DEX Router:", address(dexRouter));
        console.log("  LP Token:", address(lpToken));
        console.log("");
        console.log("Core Contracts:");
        console.log("  UserVault:", address(vault));
        console.log("");
        console.log("Adapters:");
        console.log("  LendleAdapter:", address(lendleAdapter));
        console.log("  FusionXAdapter:", address(fusionXAdapter));
        console.log("");
        console.log("========================================");
        console.log("NEXT STEPS");
        console.log("========================================");
        console.log("");
        console.log("1. Create a strategy:");
        console.log("   vault.setStrategy(");
        console.log("     [lendleAdapter, fusionXAdapter],");
        console.log("     [5000, 5000],  // 50/50 split");
        console.log("     true,          // public");
        console.log('     "My Strategy",');
        console.log("     10             // 0.1% copy fee");
        console.log("   )");
        console.log("");
        console.log("2. Approve USDC:");
        console.log("   usdc.approve(vault, amount)");
        console.log("");
        console.log("3. Deposit:");
        console.log("   vault.deposit(amount)");
        console.log("");
        console.log("4. Copy another strategy:");
        console.log("   vault.copyStrategy(creatorAddress)");
        console.log("");
        console.log("========================================");
        console.log("Save these addresses for frontend:");
        console.log("========================================");
        console.log("");
        console.log("USDC:", address(usdc));
        console.log("aUSDC:", address(aUsdc));
        console.log("WMNT:", address(wmnt));
        console.log("LendingPool:", address(lendingPool));
        console.log("DEX Router:", address(dexRouter));
        console.log("LP Token:", address(lpToken));
        console.log("UserVault:", address(vault));
        console.log("LendleAdapter:", address(lendleAdapter));
        console.log("FusionXAdapter:", address(fusionXAdapter));
        console.log("");
        console.log("Deployment successful!");
    }
}
