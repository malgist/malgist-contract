// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IFeeManager} from "./interfaces/IFeeManager.sol";

/**
 * @title FeeManager
 * @notice Isolates fee calculation and distribution for MALGIST
 * @dev Vault transfers gross yield to this contract and calls `chargeFees`.
 */
contract FeeManager is IFeeManager {
    using SafeERC20 for IERC20;

    // ======== CONSTANTS ========
    uint16 public constant MAX_CREATOR_FEE_BPS = 1000; // 10%
    uint16 public constant MAX_PROTOCOL_FEE_BPS = 500; // 5%
    uint16 public constant TOTAL_BPS = 10000;

    address public admin;
    address public operator;

    // ======== ERRORS ========
    error UnauthorizedCaller(address caller);
    error InvalidBps(uint16 bps);
    error InsufficientBalance(uint256 required, uint256 available);

    // ======== STATE ========
    IERC20 public immutable ASSET;
    address public treasury;
    uint16 public protocolFeeBps;

    // Authorized vaults that may call `chargeFees`
    mapping(address => bool) public authorizedVaults;

    // ======== EVENTS ========
    event FeeCharged(uint256 indexed strategyId, uint256 grossYield, uint256 creatorFee, uint256 protocolFee, uint256 netYield);
    event CreatorFeePaid(address indexed creator, uint256 amount);
    event ProtocolFeePaid(address indexed treasury, uint256 amount);
    event ProtocolFeeUpdated(uint16 newBps);
    event TreasuryUpdated(address newTreasury);
    event VaultAuthorizationUpdated(address vault, bool authorized);

    // ======== CONSTRUCTOR ========
    constructor(address _asset, address _treasury, uint16 _protocolFeeBps, address _admin) {
        require(_asset != address(0), "zero asset");
        require(_treasury != address(0), "zero treasury");
        if (_protocolFeeBps > MAX_PROTOCOL_FEE_BPS) revert InvalidBps(_protocolFeeBps);

        ASSET = IERC20(_asset);
        treasury = _treasury;
        protocolFeeBps = _protocolFeeBps;
        admin = _admin;
        operator = _admin;
    }

    // ======== ACCESSORS / GOV ========
    modifier onlyAdmin() {
        if (msg.sender != admin) revert UnauthorizedCaller(msg.sender);
        _;
    }

    modifier onlyOperator() {
        if (msg.sender != operator && msg.sender != admin) revert UnauthorizedCaller(msg.sender);
        _;
    }

    function setProtocolFeeBps(uint16 bps) external onlyAdmin {
        if (bps > MAX_PROTOCOL_FEE_BPS) revert InvalidBps(bps);
        protocolFeeBps = bps;
        emit ProtocolFeeUpdated(bps);
    }

    function setTreasury(address _treasury) external onlyAdmin {
        require(_treasury != address(0), "zero treasury");
        treasury = _treasury;
        emit TreasuryUpdated(_treasury);
    }

    function setAuthorizedVault(address vault, bool authorized) external onlyOperator {
        authorizedVaults[vault] = authorized;
        emit VaultAuthorizationUpdated(vault, authorized);
    }

    // ======== CORE: CHARGE FEES ========
    /**
     * @notice Charge creator + protocol fees on a gross yield amount
     * @dev Vault SHOULD transfer `grossYield` to this contract before calling this function.
     */
    function chargeFees(uint256 strategyId, uint256 grossYield, address creator, uint16 creatorFeeBps)
        external
        override
        returns (uint256 netYield)
    {
        if (!authorizedVaults[msg.sender]) revert UnauthorizedCaller(msg.sender);

        if (creatorFeeBps > MAX_CREATOR_FEE_BPS) revert InvalidBps(creatorFeeBps);

        if (grossYield == 0) {
            emit FeeCharged(strategyId, 0, 0, 0, 0);
            return 0;
        }

        uint256 bal = ASSET.balanceOf(address(this));
        if (bal < grossYield) revert InsufficientBalance(grossYield, bal);

        uint256 creatorFee = (grossYield * uint256(creatorFeeBps)) / TOTAL_BPS;
        uint256 protocolFee = (grossYield * uint256(protocolFeeBps)) / TOTAL_BPS;

        uint256 totalFee = creatorFee + protocolFee;
        if (totalFee > grossYield) {
            // rounding guard: cap totalFee
            totalFee = grossYield;
        }

        netYield = grossYield - totalFee;

        // Transfers (gas-optimized ordering: pay smaller recipients first?)
        if (creatorFee > 0) {
            ASSET.safeTransfer(creator, creatorFee);
            emit CreatorFeePaid(creator, creatorFee);
        }

        if (protocolFee > 0) {
            ASSET.safeTransfer(treasury, protocolFee);
            emit ProtocolFeePaid(treasury, protocolFee);
        }

        // Return net to caller (vault) so vault only handles the net amount after fees
        if (netYield > 0) {
            ASSET.safeTransfer(msg.sender, netYield);
        }

        emit FeeCharged(strategyId, grossYield, creatorFee, protocolFee, netYield);
        return netYield;
    }
}
