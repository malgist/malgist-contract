// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IUniversalAdapter} from "../interfaces/IUniversalAdapter.sol";

/**
 * @title AaveV3LendingAdapter
 * @notice Adapter for Aave V3 protocol (lending)
 *
 * PROTOCOL: Aave V3 (Ethereum, Arbitrum, Optimism, Polygon, Avalanche, Base)
 * RISK TIER: LOW (0) - Battle-tested, $10B+ TVL, extensive audits
 *
 * INTEGRATION POINTS:
 * - Deposit: supply() → receive aToken
 * - Withdraw: withdraw() → burn aToken, receive underlying
 * - Quote: getReserveNormalizedVariableDebtPerUnit() for interest rates
 * - Health: Check reserve is active and not paused
 *
 * SECURITY:
 * - Interest accrual handled transparently (aToken grows)
 * - Flash loan exposure: yes (but external, not our concern)
 * - Oracle manipulation: Aave uses price oracles, trust assumption
 * - Slippage: Minimal (stable lending), but can occur during market stress
 */
contract AaveV3LendingAdapter is IUniversalAdapter {
    using SafeERC20 for IERC20;

    // ============ CONSTANTS ============
    address public constant AAVE_POOL = address(0); // Set to actual Aave Pool address
    address public constant AAVE_DATA_PROVIDER = address(0); // Set to actual DataProvider
    
    // ============ STATE ============
    address public immutable baseAsset;
    address public immutable aToken;
    address public immutable vault;

    constructor(address _baseAsset, address _aToken, address _vault) {
        baseAsset = _baseAsset;
        aToken = _aToken;
        vault = _vault;
    }

    // ============ CORE FUNCTIONS ============

    function deposit(uint256 amount, uint256 minAmountOut, uint256 deadline)
        external
        returns (uint256 shares)
    {
        require(msg.sender == vault, "Only vault");
        require(amount > 0, "Invalid amount");
        require(block.timestamp <= deadline, "Deadline expired");

        // Transfer from vault
        IERC20(baseAsset).safeTransferFrom(vault, address(this), amount);

        // Approve Aave Pool (using forceApprove from SafeERC20)
        IERC20(baseAsset).forceApprove(AAVE_POOL, amount);

        // Deposit into Aave: IAavePool(AAVE_POOL).supply(baseAsset, amount, address(this), 0);
        // Mock: we'll return proportional shares
        shares = amount; // 1:1 assumption; actual = aToken received

        require(shares >= minAmountOut, "Slippage exceeded");

        // Transfer aToken (shares) to vault
        IERC20(aToken).safeTransfer(vault, shares);

        return shares;
    }

    function withdraw(uint256 shareAmount, uint256 minAmountOut, uint256 deadline)
        external
        returns (uint256 withdrawn)
    {
        require(msg.sender == vault, "Only vault");
        require(shareAmount > 0, "Invalid amount");
        require(block.timestamp <= deadline, "Deadline expired");

        // Transfer aToken from vault
        IERC20(aToken).safeTransferFrom(vault, address(this), shareAmount);

        // Withdraw from Aave: IAavePool(AAVE_POOL).withdraw(baseAsset, shareAmount, address(this));
        // Mock: we'll return proportional base tokens
        withdrawn = shareAmount; // 1:1 assumption; actual = based on interest accrual

        require(withdrawn >= minAmountOut, "Slippage exceeded");

        // Transfer base tokens to vault
        IERC20(baseAsset).safeTransfer(vault, withdrawn);

        return withdrawn;
    }

    function getExpectedDepositOutput(uint256 amountIn) external view returns (uint256 expectedOutput) {
        // In Aave, 1 token = 1 aToken (approximately, without interest accrual in same block)
        return amountIn;
    }

    function getExpectedWithdrawOutput(uint256 shareAmount) external view returns (uint256 expectedOutput) {
        // In Aave, aToken balance grows with interest
        // For simplicity: 1 aToken ≈ 1 + (interest rate * time)
        // Mock: return 1:1; actual would factor in interest
        return shareAmount;
    }

    function getTVL() external view returns (uint256 tvl) {
        // TVL = aToken balance
        return IERC20(aToken).balanceOf(address(this));
    }

    function token() external view returns (address tokenAddress) {
        return baseAsset;
    }

    function protocolType() external pure returns (ProtocolType) {
        return ProtocolType.LENDING;
    }

    function protocolName() external pure returns (string memory) {
        return "Aave V3";
    }

    function getRiskTier() external pure returns (uint8) {
        return 0; // LOW
    }

    function isOperational() external view returns (bool) {
        // Check if Aave reserve is active and not paused
        // In production: query DataProvider for reserve status
        return true; // Mock: always operational
    }

    function getHealthStatus() external pure returns (string memory) {
        return ""; // Operational
    }
}

/**
 * @title LidoStakingAdapter
 * @notice Adapter for Lido Liquid Staking
 *
 * PROTOCOL: Lido (Ethereum)
 * RISK TIER: LOW (0) - $30B+ TVL, battle-tested, audited
 *
 * INTEGRATION POINTS:
 * - Deposit: submit() → receive stETH
 * - Withdraw: requestWithdrawal() → NFT receipt → claimWithdrawal() (async)
 * - Quote: getSharesByPooledEth() for conversion
 * - Health: Check withdrawal queue not backlogged
 *
 * SECURITY:
 * - Staking yield: automatically compounded into stETH
 * - Withdrawal delay: 1-7 days (not instant)
 * - slashing risk: ETH consensus layer; Lido has insurance
 * - Note: Async withdrawals not supported in simple adapter; use sync for MVP
 */
contract LidoStakingAdapter is IUniversalAdapter {
    using SafeERC20 for IERC20;

    // ============ CONSTANTS ============
    address public constant LIDO_STETH = address(0); // Set to actual stETH address
    address public constant ETH_ADDRESS = address(0);
    
    // ============ STATE ============
    address public immutable baseAsset; // WETH or ETH
    address public immutable vault;

    constructor(address _baseAsset, address _vault) {
        baseAsset = _baseAsset;
        vault = _vault;
    }

    // ============ CORE FUNCTIONS ============

    function deposit(uint256 amount, uint256 minAmountOut, uint256 deadline)
        external
        returns (uint256 shares)
    {
        require(msg.sender == vault, "Only vault");
        require(amount > 0, "Invalid amount");
        require(block.timestamp <= deadline, "Deadline expired");

        // Convert WETH to ETH if needed
        // Then call Lido.submit{value: amount}(referral)
        // Receive stETH proportional to ETH deposit

        shares = amount; // 1:1 assumption
        require(shares >= minAmountOut, "Slippage exceeded");

        // Transfer stETH to vault
        IERC20(LIDO_STETH).safeTransfer(vault, shares);

        return shares;
    }

    function withdraw(uint256 shareAmount, uint256 minAmountOut, uint256 deadline)
        external
        returns (uint256 withdrawn)
    {
        require(msg.sender == vault, "Only vault");
        require(shareAmount > 0, "Invalid amount");
        require(block.timestamp <= deadline, "Deadline expired");

        // Transfer stETH from vault
        IERC20(LIDO_STETH).safeTransferFrom(vault, address(this), shareAmount);

        // Unstake via Lido: would require async withdrawal
        // For MVP: use 1:1 rate; in production: integrate withdrawal NFT system

        withdrawn = shareAmount;
        require(withdrawn >= minAmountOut, "Slippage exceeded");

        // Transfer ETH/WETH to vault
        // Assuming baseAsset is WETH
        IERC20(baseAsset).safeTransfer(vault, withdrawn);

        return withdrawn;
    }

    function getExpectedDepositOutput(uint256 amountIn) external view returns (uint256 expectedOutput) {
        // stETH conversion rate via Lido oracle
        // Mock: 1 ETH ≈ 0.95-0.99 stETH (discount due to staking opportunity cost)
        return (amountIn * 99) / 100; // 1% discount
    }

    function getExpectedWithdrawOutput(uint256 shareAmount) external view returns (uint256 expectedOutput) {
        // Reverse rate: stETH → ETH
        // With accrued rewards: 1 stETH > 1 ETH (yields)
        return (shareAmount * 102) / 100; // 2% premium from yield
    }

    function getTVL() external view returns (uint256) {
        // stETH balance * ETH/stETH rate
        return IERC20(LIDO_STETH).balanceOf(address(this));
    }

    function token() external view returns (address) {
        return baseAsset;
    }

    function protocolType() external pure returns (ProtocolType) {
        return ProtocolType.STAKING;
    }

    function protocolName() external pure returns (string memory) {
        return "Lido";
    }

    function getRiskTier() external pure returns (uint8) {
        return 0; // LOW
    }

    function isOperational() external view returns (bool) {
        // Check Lido is not in pause/emergency mode
        return true; // Mock
    }

    function getHealthStatus() external pure returns (string memory) {
        return ""; // Operational
    }
}

/**
 * @title YearnFinanceAdapter
 * @notice Adapter for Yearn Finance vaults
 *
 * PROTOCOL: Yearn Finance (Multi-chain)
 * RISK TIER: LOW (0) - $5B+ TVL, automated strategies, audited
 *
 * INTEGRATION POINTS:
 * - Deposit: deposit() → receive yToken
 * - Withdraw: withdraw() → burn yToken, receive underlying
 * - Quote: pricePerShare() for conversion
 * - Health: Check vault is not emergency-paused
 *
 * SECURITY:
 * - Strategy risk: Yearn manages; assumes strategies are vetted
 * - Withdrawal delay: Generally 1 block, but can defer if liquidity stress
 * - Performance fees: Already deducted from yield
 */
contract YearnFinanceAdapter is IUniversalAdapter {
    using SafeERC20 for IERC20;

    // ============ CONSTANTS ============
    address public constant YEARN_USDC_VAULT = address(0); // Example: Yearn USDC vault
    
    // ============ STATE ============
    address public immutable baseAsset;
    address public immutable yToken;
    address public immutable vault;

    constructor(address _baseAsset, address _yToken, address _vault) {
        baseAsset = _baseAsset;
        yToken = _yToken;
        vault = _vault;
    }

    function deposit(uint256 amount, uint256 minAmountOut, uint256 deadline)
        external
        returns (uint256 shares)
    {
        require(msg.sender == vault, "Only vault");
        require(amount > 0, "Invalid amount");
        require(block.timestamp <= deadline, "Deadline expired");

        IERC20(baseAsset).safeTransferFrom(vault, address(this), amount);
        IERC20(baseAsset).forceApprove(yToken, amount);

        // Deposit into Yearn: IYearnVault(yToken).deposit(amount, address(this))
        shares = amount; // Mock; actual would call vault
        require(shares >= minAmountOut, "Slippage exceeded");

        IERC20(yToken).safeTransfer(vault, shares);
        return shares;
    }

    function withdraw(uint256 shareAmount, uint256 minAmountOut, uint256 deadline)
        external
        returns (uint256 withdrawn)
    {
        require(msg.sender == vault, "Only vault");
        require(shareAmount > 0, "Invalid amount");
        require(block.timestamp <= deadline, "Deadline expired");

        IERC20(yToken).safeTransferFrom(vault, address(this), shareAmount);

        // Withdraw: IYearnVault(yToken).withdraw(shareAmount, address(this))
        withdrawn = shareAmount;
        require(withdrawn >= minAmountOut, "Slippage exceeded");

        IERC20(baseAsset).safeTransfer(vault, withdrawn);
        return withdrawn;
    }

    function getExpectedDepositOutput(uint256 amountIn) external view returns (uint256) {
        // pricePerShare() tells us how much yToken per baseAsset
        return amountIn; // Mock; actual = amountIn / pricePerShare()
    }

    function getExpectedWithdrawOutput(uint256 shareAmount) external view returns (uint256) {
        // Reverse: yToken → baseAsset
        return shareAmount; // Mock; actual = shareAmount * pricePerShare()
    }

    function getTVL() external view returns (uint256) {
        return IERC20(yToken).balanceOf(address(this));
    }

    function token() external view returns (address) {
        return baseAsset;
    }

    function protocolType() external pure returns (ProtocolType) {
        return ProtocolType.YIELD;
    }

    function protocolName() external pure returns (string memory) {
        return "Yearn Finance";
    }

    function getRiskTier() external pure returns (uint8) {
        return 0; // LOW
    }

    function isOperational() external view returns (bool) {
        return true; // Mock
    }

    function getHealthStatus() external pure returns (string memory) {
        return ""; // Operational
    }
}

/**
 * @title GMXDerivativesAdapter
 * @notice Adapter for GMX V2 perp protocol (HIGH-RISK)
 *
 * PROTOCOL: GMX V2 (Arbitrum, Avalanche)
 * RISK TIER: HIGH (2) - Derivatives, leveraged positions, liquidation risk
 *
 * INTEGRATION POINTS:
 * - Deposit: Provide liquidity via liquidity pool → receive LP tokens
 * - Withdraw: Burn LP tokens → receive USDC
 * - Quote: getLiquidityStats() for pool metrics
 * - Health: Check liquidation risk, slashing events
 *
 * SECURITY:
 * - CRITICAL: Subject to per-adapter TVL caps
 * - Liquidation risk: If perp traders get liquidated, LP value can drop
 * - Slippage: Higher on large trades
 * - Oracle risk: Uses Chainlink + Pyth; can be stale/manipulated
 *
 * GOVERNANCE CONTROL:
 * - Can be emergency-paused independently
 * - Allocation capped at 20% of strategy (MAX_HIGH_RISK_ALLOCATION_BPS)
 */
contract GMXDerivativesAdapter is IUniversalAdapter {
    using SafeERC20 for IERC20;

    // ============ CONSTANTS ============
    address public constant GMX_EXCHANGE_ROUTER = address(0);
    address public constant GMX_ROUTER = address(0);
    
    // ============ STATE ============
    address public immutable baseAsset;
    address public immutable glpToken; // GMX Liquidity Provider token
    address public immutable vault;
    address public governance;

    constructor(address _baseAsset, address _glpToken, address _vault) {
        baseAsset = _baseAsset;
        glpToken = _glpToken;
        vault = _vault;
        governance = msg.sender;
    }

    // ============ HIGH-RISK SPECIFIC: Governance pause ============
    bool public isPaused;

    function pauseAdapter() external {
        require(msg.sender == governance, "Only governance");
        isPaused = true;
    }

    function unpauseAdapter() external {
        require(msg.sender == governance, "Only governance");
        isPaused = false;
    }

    // ============ CORE FUNCTIONS ============

    function deposit(uint256 amount, uint256 minAmountOut, uint256 deadline)
        external
        returns (uint256 shares)
    {
        require(msg.sender == vault, "Only vault");
        require(!isPaused, "Adapter paused");
        require(amount > 0, "Invalid amount");
        require(block.timestamp <= deadline, "Deadline expired");

        IERC20(baseAsset).safeTransferFrom(vault, address(this), amount);
        IERC20(baseAsset).forceApprove(GMX_ROUTER, amount);

        // Deposit into GMX LP: IGMXRouter(GMX_ROUTER).mintAndStakeGlp(amount, minAmountOut)
        shares = amount; // Mock; actual = GLP received
        require(shares >= minAmountOut, "Slippage exceeded");

        IERC20(glpToken).safeTransfer(vault, shares);
        return shares;
    }

    function withdraw(uint256 shareAmount, uint256 minAmountOut, uint256 deadline)
        external
        returns (uint256 withdrawn)
    {
        require(msg.sender == vault, "Only vault");
        require(!isPaused, "Adapter paused");
        require(shareAmount > 0, "Invalid amount");
        require(block.timestamp <= deadline, "Deadline expired");

        IERC20(glpToken).safeTransferFrom(vault, address(this), shareAmount);

        // Redeem GLP: IGMXRouter(GMX_ROUTER).unstakeAndRedeemGlp(shareAmount, minAmountOut)
        withdrawn = shareAmount;
        require(withdrawn >= minAmountOut, "Slippage exceeded");

        IERC20(baseAsset).safeTransfer(vault, withdrawn);
        return withdrawn;
    }

    function getExpectedDepositOutput(uint256 amountIn) external view returns (uint256) {
        // GLP price volatility: can be 98-102% of net asset value
        return (amountIn * 99) / 100; // 1% discount for slippage/fees
    }

    function getExpectedWithdrawOutput(uint256 shareAmount) external view returns (uint256) {
        // Can be higher if LP profits from trader losses
        return (shareAmount * 101) / 100; // 1% premium
    }

    function getTVL() external view returns (uint256) {
        return IERC20(glpToken).balanceOf(address(this));
    }

    function token() external view returns (address) {
        return baseAsset;
    }

    function protocolType() external pure returns (ProtocolType) {
        return ProtocolType.DERIVATIVES;
    }

    function protocolName() external pure returns (string memory) {
        return "GMX V2";
    }

    function getRiskTier() external pure returns (uint8) {
        return 2; // HIGH
    }

    function isOperational() external view returns (bool) {
        return !isPaused; // Governance-controlled pause
    }

    function getHealthStatus() external view returns (string memory) {
        if (isPaused) return "Adapter paused by governance";
        return ""; // Operational
    }
}
