// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

contract System {
    bool public alreadyInit;

    uint8 internal constant CODE_OK = 0;
    /*----------------- constants -----------------*/
    address public constant DEAD_ADDRESS = 0x000000000000000000000000000000000000dEaD;

    address public constant SYSTEM_CALLER = 0x0000000000000000000000000000000000000000;
    address internal constant PERFORMANCE_TRACKER_ADDR = 0x00000000000000000000000000000000000000f1;
    address internal constant EPOCH_MANAGER_ADDR = 0x00000000000000000000000000000000000000f3;
    address internal constant ACCESS_CONTROL_ADDR = 0x0000000000000000000000000000000000002007;
    address internal constant STAKE_CONFIG_ADDR = 0x0000000000000000000000000000000000002008;
    address internal constant VALIDATOR_MANAGER_ADDR = 0x0000000000000000000000000000000000002009;
    address internal constant VALIDATOR_PERFORMANCE_TRACKER_ADDR = 0x000000000000000000000000000000000000200b;
    address internal constant STAKE_HUB_ADDR = 0x0000000000000000000000000000000000002002;
    address internal constant BLOCK_ADDR = 0x0000000000000000000000000000000000002003;
    address internal constant TIMESTAMP_ADDR = 0x0000000000000000000000000000000000002004;

    address internal constant SLASH_CONTRACT_ADDR = 0x0000000000000000000000000000000000001001;
    address internal constant SYSTEM_REWARD_ADDR = 0x0000000000000000000000000000000000001002;

    address internal constant INCENTIVIZE_ADDR = 0x0000000000000000000000000000000000001005;
    address internal constant RELAYERHUB_CONTRACT_ADDR = 0x0000000000000000000000000000000000001006;
    address internal constant GOV_HUB_ADDR = 0x0000000000000000000000000000000000001007;

    address internal constant STAKE_CREDIT_ADDR = 0x0000000000000000000000000000000000002003;
    address internal constant GOVERNOR_ADDR = 0x0000000000000000000000000000000000002004;
    address internal constant GOV_TOKEN_ADDR = 0x0000000000000000000000000000000000002005;
    address internal constant TIMELOCK_ADDR = 0x0000000000000000000000000000000000002006;
    address internal constant TOKEN_RECOVER_PORTAL_ADDR = 0x0000000000000000000000000000000000003000;

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

    modifier onlyValidatorManager() {
        if (msg.sender != VALIDATOR_MANAGER_ADDR) revert OnlySystemContract(VALIDATOR_MANAGER_ADDR);
        _;
    }

    modifier onlyCoinbase() {
        if (msg.sender != block.coinbase) revert OnlyCoinbase();
        _;
    }

    modifier onlyZeroGasPrice() {
        if (tx.gasprice != 0) revert OnlyZeroGasPrice();
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

    modifier onlyGov() {
        if (msg.sender != GOV_HUB_ADDR) revert OnlySystemContract(GOV_HUB_ADDR);
        _;
    }

    modifier onlyGovernor() {
        if (msg.sender != GOVERNOR_ADDR) revert OnlySystemContract(GOVERNOR_ADDR);
        _;
    }

    modifier onlyGovernorTimelock() {
        require(msg.sender == TIMELOCK_ADDR, "the msg sender must be governor timelock contract");
        _;
    }

    modifier onlyStakeHub() {
        if (msg.sender != STAKE_HUB_ADDR) revert OnlySystemContract(STAKE_HUB_ADDR);
        _;
    }

    modifier onlyTokenRecoverPortal() {
        require(msg.sender == TOKEN_RECOVER_PORTAL_ADDR, "the msg sender must be token recover portal");
        _;
    }
}
