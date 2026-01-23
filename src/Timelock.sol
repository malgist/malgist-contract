// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/*
 * @status LEGACY
 * @network Test only
 * @used-by governance docs, local sims
 * @notes Minimal timelock used in local governance rehearsals only.
 */

/**
 * @title SimpleTimelock
 * @notice Minimal timelock enabling governance (multisig) to schedule actions that execute after a delay.
 * @dev This is a lightweight implementation for tests and integration. For production, prefer OpenZeppelin TimelockController.
 */
contract SimpleTimelock {
    // governance multisig address (must be a contract)
    address public governance;

    // minimum delay for scheduled actions (seconds)
    uint256 public immutable minDelay;

    // scheduled action id => eta timestamp
    mapping(bytes32 => uint256) public etaFor;

    event ActionScheduled(bytes32 indexed id, address indexed target, bytes data, uint256 eta);
    event ActionExecuted(bytes32 indexed id, address indexed target, bytes data);

    error NotGovernance();
    error DelayTooShort();
    error ActionNotScheduled();
    error NotReady();

    constructor(address _governance, uint256 _minDelay) {
        require(_governance != address(0), "governance zero");
        governance = _governance;
        minDelay = _minDelay;
    }

    modifier onlyGovernance() {
        if (msg.sender != governance) revert NotGovernance();
        _;
    }

    /**
     * @notice Schedule a call to `target` with `data` after `delay` seconds (must be >= minDelay)
     * @dev Only callable by `governance` (multisig contract). `salt` can be arbitrary to make unique id.
     */
    function scheduleAction(address target, bytes calldata data, bytes32 salt, uint256 delay) external onlyGovernance returns (bytes32) {
        if (delay < minDelay) revert DelayTooShort();
        bytes32 id = keccak256(abi.encodePacked(target, data, salt));
        uint256 eta = block.timestamp + delay;
        etaFor[id] = eta;
        emit ActionScheduled(id, target, data, eta);
        return id;
    }

    /**
     * @notice Execute a previously scheduled action. Anyone can call once the ETA has passed.
     */
    function executeAction(address target, bytes calldata data, bytes32 salt) external returns (bytes memory) {
        bytes32 id = keccak256(abi.encodePacked(target, data, salt));
        uint256 eta = etaFor[id];
        if (eta == 0) revert ActionNotScheduled();
        if (block.timestamp < eta) revert NotReady();
        delete etaFor[id];

        (bool ok, bytes memory ret) = target.call(data);
        require(ok, "timelock: target call failed");

        emit ActionExecuted(id, target, data);
        return ret;
    }

    /**
     * @notice Update governance multisig. This function is intended to be called via a scheduled timelock action.
     */
    function setGovernance(address newGov) external {
        // allow only this contract itself to call (via executeAction) to change governance
        require(msg.sender == address(this), "only-timelock-self");
        governance = newGov;
    }
}
