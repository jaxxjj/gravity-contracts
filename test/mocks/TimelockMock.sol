// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

contract TimelockMock {
    uint256 private _minDelay = 24 hours;
    mapping(bytes32 => bool) private _timestamps;
    mapping(bytes32 => uint256) private _operationTimestamps;

    function initialize() external {
        // Mock implementation
    }

    function getMinDelay() external view returns (uint256) {
        return _minDelay;
    }

    function setMinDelay(
        uint256 newDelay
    ) external {
        _minDelay = newDelay;
    }

    function isOperation(
        bytes32 /* id */
    ) external pure returns (bool) {
        return true;
    }

    function isOperationPending(
        bytes32 /* id */
    ) external pure returns (bool) {
        return true;
    }

    function isOperationReady(
        bytes32 /* id */
    ) external pure returns (bool) {
        return true;
    }

    function isOperationDone(
        bytes32 /* id */
    ) external pure returns (bool) {
        return false;
    }

    function getTimestamp(
        bytes32 id
    ) external view returns (uint256) {
        return _operationTimestamps[id];
    }

    function hashOperation(
        address target,
        uint256 value,
        bytes calldata data,
        bytes32 predecessor,
        bytes32 salt
    ) external pure returns (bytes32) {
        return keccak256(abi.encode(target, value, data, predecessor, salt));
    }

    function hashOperationBatch(
        address[] calldata targets,
        uint256[] calldata values,
        bytes[] calldata payloads,
        bytes32 predecessor,
        bytes32 salt
    ) external pure returns (bytes32) {
        return keccak256(abi.encode(targets, values, payloads, predecessor, salt));
    }

    function schedule(
        address, /* target */
        uint256, /* value */
        bytes calldata, /* data */
        bytes32, /* predecessor */
        bytes32, /* salt */
        uint256 /* delay */
    ) external {
        // Mock implementation - just return
    }

    function scheduleBatch(
        address[] calldata, /* targets */
        uint256[] calldata, /* values */
        bytes[] calldata, /* payloads */
        bytes32, /* predecessor */
        bytes32, /* salt */
        uint256 /* delay */
    ) external {
        // Mock implementation - just return
    }

    function execute(
        address, /* target */
        uint256, /* value */
        bytes calldata, /* payload */
        bytes32, /* predecessor */
        bytes32 /* salt */
    ) external payable {
        // Mock implementation - just return
    }

    function executeBatch(
        address[] calldata, /* targets */
        uint256[] calldata, /* values */
        bytes[] calldata, /* payloads */
        bytes32, /* predecessor */
        bytes32 /* salt */
    ) external payable {
        // Mock implementation - just return
    }

    function cancel(
        bytes32 /* id */
    ) external {
        // Mock implementation - just return
    }

    function updateDelay(
        uint256 newDelay
    ) external {
        _minDelay = newDelay;
    }

    // Required for AccessControl
    function hasRole(bytes32, /* role */ address /* account */ ) external pure returns (bool) {
        return true;
    }

    function getRoleAdmin(
        bytes32 /* role */
    ) external pure returns (bytes32) {
        return 0x00;
    }

    function grantRole(bytes32, /* role */ address /* account */ ) external {
        // Mock implementation
    }

    function revokeRole(bytes32, /* role */ address /* account */ ) external {
        // Mock implementation
    }

    function renounceRole(bytes32, /* role */ address /* account */ ) external {
        // Mock implementation
    }

    // Required role constants
    function PROPOSER_ROLE() external pure returns (bytes32) {
        return keccak256("PROPOSER_ROLE");
    }

    function EXECUTOR_ROLE() external pure returns (bytes32) {
        return keccak256("EXECUTOR_ROLE");
    }

    function DEFAULT_ADMIN_ROLE() external pure returns (bytes32) {
        return 0x00;
    }
}
