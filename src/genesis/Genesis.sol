// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@src/System.sol";
import "@src/interfaces/IValidatorManager.sol";
import "@src/interfaces/IStakeConfig.sol";
import "@src/interfaces/IEpochManager.sol";
import "@src/interfaces/ITimestamp.sol";
import "@src/interfaces/IBlock.sol";
import "@src/interfaces/IValidatorPerformanceTracker.sol";
import "@src/interfaces/IGovToken.sol";
import "@src/interfaces/IJWKManager.sol";
import "@src/interfaces/IKeylessAccount.sol";
import "@src/governance/GravityGovernor.sol";
import "@src/governance/Timelock.sol";

/**
 * @title Genesis
 * @dev 创世初始化合约
 * 负责在链启动时初始化所有核心组件和初始验证者集合
 */
contract Genesis is System {
    // 创世状态标志
    bool private genesisCompleted;

    // 错误定义
    error GenesisAlreadyCompleted();
    error InvalidInitialValidators();

    event GenesisCompleted(uint256 timestamp, uint256 validatorCount);

    /**
     * @dev 创世初始化入口函数
     */
    function initialize(
        address[] calldata consensusAddresses,
        address payable[] calldata feeAddresses,
        uint64[] calldata votingPowers,
        bytes[] calldata voteAddresses
    ) external onlySystemCaller {
        if (genesisCompleted) revert GenesisAlreadyCompleted();
        if (consensusAddresses.length == 0) revert InvalidInitialValidators();

        // 1. 初始化质押模块
        _initializeStake(consensusAddresses, feeAddresses, votingPowers, voteAddresses);

        // 2. 初始化周期模块
        _initializeEpoch();

        // 3. 初始化治理模块
        _initializeGovernance();

        // 4. 初始化JWK模块
        _initializeJWK();

        // 5. 初始化Block合约
        IBlock(BLOCK_ADDR).init();

        genesisCompleted = true;

        // 触发第一个epoch
        IEpochManager(EPOCH_MANAGER_ADDR).triggerEpochTransition();

        emit GenesisCompleted(block.timestamp, consensusAddresses.length);
    }

    /**
     * @dev 初始化质押模块
     */
    function _initializeStake(
        address[] calldata consensusAddresses,
        address payable[] calldata feeAddresses,
        uint64[] calldata votingPowers,
        bytes[] calldata voteAddresses
    ) internal {
        // 初始化StakeConfig
        IStakeConfig(STAKE_CONFIG_ADDR).initialize();

        // 初始化ValidatorManager，同时传入初始验证者数据
        IValidatorManager(VALIDATOR_MANAGER_ADDR).initialize(
            consensusAddresses,
            feeAddresses,
            votingPowers,
            voteAddresses
        );

        // 初始化ValidatorPerformanceTracker
        IValidatorPerformanceTracker(VALIDATOR_PERFORMANCE_TRACKER_ADDR).initialize(consensusAddresses);
    }

    /**
     * @dev 初始化周期模块
     */
    function _initializeEpoch() internal {
        // 初始化EpochManager
        IEpochManager(EPOCH_MANAGER_ADDR).initialize();
    }

    /**
     * @dev 初始化治理模块
     */
    function _initializeGovernance() internal {
        // 初始化GovToken
        IGovToken(GOV_TOKEN_ADDR).initialize();

        // 初始化Timelock
        Timelock(payable(TIMELOCK_ADDR)).initialize();

        // 初始化GravityGovernor
        GravityGovernor(payable(GOVERNOR_ADDR)).initialize();
    }

    /**
     * @dev 初始化JWK模块
     */
    function _initializeJWK() internal {
        // 初始化JWKManager
        IJWKManager(JWK_MANAGER_ADDR).initialize();

        // 初始化KeylessAccount
        IKeylessAccount(KEYLESS_ACCOUNT_ADDR).initialize();
    }

    /**
     * @dev 检查创世是否完成
     */
    function isGenesisCompleted() external view returns (bool) {
        return genesisCompleted;
    }
}
