// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/**
 * @title TestConstants
 * @dev Centralized constants for testing, extracted from System.sol and custom test values
 */
contract TestConstants {
    // ======== System Contract Addresses (from System.sol) ========
    address public constant DEAD_ADDRESS = 0x000000000000000000000000000000000000dEaD;
    address public constant GENESIS_ADDR = 0x0000000000000000000000000000000000000001;
    address public constant SYSTEM_CALLER = 0x0000000000000000000000000000000000000000;
    address public constant PERFORMANCE_TRACKER_ADDR = 0x00000000000000000000000000000000000000f1;
    address public constant EPOCH_MANAGER_ADDR = 0x00000000000000000000000000000000000000f3;
    address public constant STAKE_CONFIG_ADDR = 0x0000000000000000000000000000000000002008;
    address public constant DELEGATION_ADDR = 0x0000000000000000000000000000000000002009;
    address public constant VALIDATOR_MANAGER_ADDR = 0x0000000000000000000000000000000000002009;
    address public constant VALIDATOR_PERFORMANCE_TRACKER_ADDR = 0x000000000000000000000000000000000000200b;
    address public constant BLOCK_ADDR = 0x0000000000000000000000000000000000002003;
    address public constant TIMESTAMP_ADDR = 0x0000000000000000000000000000000000002004;
    address public constant JWK_MANAGER_ADDR = 0x0000000000000000000000000000000000002005;
    address public constant KEYLESS_ACCOUNT_ADDR = 0x000000000000000000000000000000000000200A;
    address public constant SLASH_CONTRACT_ADDR = 0x0000000000000000000000000000000000001001;
    address public constant SYSTEM_REWARD_ADDR = 0x0000000000000000000000000000000000001002;
    address public constant GOV_HUB_ADDR = 0x0000000000000000000000000000000000001007;
    address public constant STAKE_CREDIT_ADDR = 0x0000000000000000000000000000000000002003;
    address public constant GOV_TOKEN_ADDR = 0x0000000000000000000000000000000000002005;
    address public constant GOVERNOR_ADDR = 0x0000000000000000000000000000000000002006;
    address public constant TIMELOCK_ADDR = 0x0000000000000000000000000000000000002007;

    // ======== Test-Specific Constants ========
    address public constant VALID_PROPOSER = address(0x123);
    address public constant INVALID_PROPOSER = address(0x456);
    address public constant TEST_VALIDATOR_1 = address(0x1001);
    address public constant TEST_VALIDATOR_2 = address(0x1002);
    address public constant TEST_DELEGATOR_1 = address(0x2001);
    address public constant TEST_DELEGATOR_2 = address(0x2002);
    address public constant NOT_SYSTEM_CALLER = address(0x888);
    address public constant NOT_GENESIS = address(0x999);

    // ======== Test Values ========
    uint256 public constant DEFAULT_STAKE_AMOUNT = 1 ether;
    uint256 public constant MIN_STAKE_AMOUNT = 0.1 ether;
    uint256 public constant MAX_STAKE_AMOUNT = 100 ether;
    uint64 public constant DEFAULT_COMMISSION_RATE = 1000; // 10%
    uint64 public constant MAX_COMMISSION_RATE = 5000; // 50%
    uint64 public constant DEFAULT_VALIDATOR_INDEX = 1;
    uint256 public constant DEFAULT_TIMESTAMP_MICROS = 1000000;

    // ======== Gas Values for Testing ========
    uint256 public constant DEFAULT_GAS_LIMIT = 300000;
    uint256 public constant HIGH_GAS_LIMIT = 1000000;
}
