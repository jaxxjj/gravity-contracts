// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

contract System {
    bool public alreadyInit;

    uint8 internal constant CODE_OK = 0;
    uint64 public constant MICRO_CONVERSION_FACTOR = 1000000;
    /*----------------- constants -----------------*/
    address public constant DEAD_ADDRESS = 0x000000000000000000000000000000000000dEaD;
    address public constant GENESIS_ADDR = 0x0000000000000000000000000000000000000001;
    address public constant SYSTEM_CALLER = 0x0000000000000000000000000000000000000000;
    address internal constant PERFORMANCE_TRACKER_ADDR = 0x00000000000000000000000000000000000000f1;
    address internal constant EPOCH_MANAGER_ADDR = 0x00000000000000000000000000000000000000f3;
    address internal constant STAKE_CONFIG_ADDR = 0x0000000000000000000000000000000000002008;
    address internal constant DELEGATION_ADDR = 0x0000000000000000000000000000000000002009;
    address internal constant VALIDATOR_MANAGER_ADDR = 0x0000000000000000000000000000000000002009;
    address internal constant VALIDATOR_PERFORMANCE_TRACKER_ADDR = 0x000000000000000000000000000000000000200b;
    address internal constant BLOCK_ADDR = 0x0000000000000000000000000000000000002003;
    address internal constant TIMESTAMP_ADDR = 0x0000000000000000000000000000000000002004;
    address internal constant JWK_MANAGER_ADDR = 0x0000000000000000000000000000000000002005;
    address internal constant KEYLESS_ACCOUNT_ADDR = 0x000000000000000000000000000000000000200A;
    address internal constant SLASH_CONTRACT_ADDR = 0x0000000000000000000000000000000000001001;
    address internal constant SYSTEM_REWARD_ADDR = 0x0000000000000000000000000000000000001002;
    address internal constant GOV_HUB_ADDR = 0x0000000000000000000000000000000000001007;
    address internal constant STAKE_CREDIT_ADDR = 0x0000000000000000000000000000000000002003;
    address internal constant GOV_TOKEN_ADDR = 0x0000000000000000000000000000000000002005;
    address internal constant GOVERNOR_ADDR = 0x0000000000000000000000000000000000002006;
    address internal constant TIMELOCK_ADDR = 0x0000000000000000000000000000000000002007;

    /*----------------- errors -----------------*/
    error OnlySystemCaller();
    // @notice signature: 0x97b88354
    error UnknownParam(string key, bytes value);
    // @notice signature: 0x0a5a6041
    error InvalidValue(string key, bytes value);
    // @notice signature: 0x116c64a8
    error OnlyCoinbase();
    // @notice signature: 0x83f1b1d3
    error OnlyZeroGasPrice();
    // @notice signature: 0xf22c4390
    error OnlySystemContract(address systemContract);

    /*----------------- events -----------------*/
    event ParamChange(string key, bytes value);

    /*----------------- modifiers -----------------*/
    modifier onlySystemCaller() {
        if (msg.sender != SYSTEM_CALLER) revert OnlySystemCaller();
        _;
    }

    modifier onlyJWKManager() {
        if (msg.sender != JWK_MANAGER_ADDR) revert OnlySystemContract(JWK_MANAGER_ADDR);
        _;
    }

    modifier onlyValidatorManager() {
        if (msg.sender != VALIDATOR_MANAGER_ADDR) revert OnlySystemContract(VALIDATOR_MANAGER_ADDR);
        _;
    }

    modifier onlyEpochManager() {
        if (msg.sender != EPOCH_MANAGER_ADDR) revert OnlySystemContract(EPOCH_MANAGER_ADDR);
        _;
    }

    modifier onlySlash() {
        if (msg.sender != SLASH_CONTRACT_ADDR) revert OnlySystemContract(SLASH_CONTRACT_ADDR);
        _;
    }

    modifier onlyBlock() {
        if (msg.sender != BLOCK_ADDR) revert OnlySystemContract(BLOCK_ADDR);
        _;
    }

    modifier onlyDelegation() {
        if (msg.sender != DELEGATION_ADDR) revert OnlySystemContract(DELEGATION_ADDR);
        _;
    }

    modifier onlyDelegationOrValidatorManager() {
        if (msg.sender != DELEGATION_ADDR && msg.sender != VALIDATOR_MANAGER_ADDR) {
            revert OnlySystemContract(msg.sender == DELEGATION_ADDR ? DELEGATION_ADDR : VALIDATOR_MANAGER_ADDR);
        }
        _;
    }

    modifier onlyGenesis() {
        if (msg.sender != GENESIS_ADDR) revert OnlySystemContract(GENESIS_ADDR);
        _;
    }

    modifier onlyNotInit() {
        require(!alreadyInit, "the contract already init");
        _;
    }

    modifier onlyInit() {
        require(alreadyInit, "the contract not init yet");
        _;
    }

    modifier onlyGov() {
        if (msg.sender != GOV_HUB_ADDR) revert OnlySystemContract(GOV_HUB_ADDR);
        _;
    }

    modifier onlyGovernorTimelock() {
        require(msg.sender == TIMELOCK_ADDR, "the msg sender must be governor timelock contract");
        _;
    }
}
