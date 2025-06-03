// // SPDX-License-Identifier: MIT
// pragma solidity ^0.8.17;

// import "@src/System.sol";
// import "@src/interfaces/IValidatorManager.sol";
// import "@src/interfaces/IStakeConfig.sol";
// import "@src/interfaces/IEpochManager.sol";
// import "@src/interfaces/ITimestamp.sol";
// import "@src/interfaces/IBlock.sol";
// import "@src/interfaces/IValidatorPerformanceTracker.sol";
// import "@src/stake/StakeCredit.sol";
// import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

// /**
//  * @title Genesis
//  * @dev 创世初始化合约，对应Aptos genesis.move
//  * 负责在链启动时初始化所有核心组件和初始验证者集合
//  */
// contract Genesis is System {
//     // 创世状态标志
//     bool private genesisCompleted;

//     // 错误定义
//     error GenesisAlreadyCompleted();
//     error InvalidInitialValidators();
//     error InvalidStakeAmount();
//     error GenesisNotCompleted();

//     event GenesisCompleted(uint256 timestamp, uint256 validatorCount);

//     // 事件
//     // 验证者配置结构（对应Aptos ValidatorConfiguration）
//     struct ValidatorConfigurationWithCommission {
//         address ownerAddress;
//         address operatorAddress;
//         address voterAddress;
//         uint256 stakeAmount;
//         bytes consensusPublicKey;
//         bytes proofOfPossession;
//         bytes networkAddresses;
//         bytes fullnodeAddresses;
//     }

//     /**
//      * @dev 创世初始化入口函数
//      * 对应Aptos genesis中的完整初始化流程
//      */
//     function initialize(
//         // 初始验证者配置
//         ValidatorConfigurationWithCommission[] calldata validators
//     ) external onlySystemCaller {
//         if (genesisCompleted) revert GenesisAlreadyCompleted();

//         // 2. 初始化验证者（对应Aptos create_initialize_validators）
//         _initializeValidators(validators);

//         genesisCompleted = true;

//         // 触发第一个epoch
//         IEpochManager(EPOCH_MANAGER_ADDR).triggerEpochTransition();

//         emit GenesisCompleted(block.timestamp, IValidatorManager(VALIDATOR_MANAGER_ADDR).getActiveValidators().length);
//     }

//     /**
//      * @dev 初始化验证者集合
//      * 对应Aptos create_initialize_validators_with_commission
//      */
//     function _initializeValidators(ValidatorConfigurationWithCommission[] calldata validators) internal {
//         if (validators.length == 0) revert InvalidInitialValidators();

//         // 准备初始化数据
//         address[] memory addresses = new address[](validators.length);
//         uint64[] memory votingPowers = new uint64[](validators.length);
//         string[] memory monikers = new string[](validators.length);

//         // 初始化ValidatorManager
//         for (uint256 i = 0; i < validators.length; i++) {
//             ValidatorConfigurationWithCommission calldata validatorWithCommission = validators[i];
//             ValidatorConfiguration calldata validator = validatorWithCommission.validatorConfig;

//             addresses[i] = validator.ownerAddress;
//             votingPowers[i] = uint64(validator.stakeAmount / 1e18); // 转换为简化的投票权重
//             monikers[i] = string(abi.encodePacked("VAL", i)); // 生成默认名称
//         }

//         // 初始化ValidatorManager
//         IValidatorManager(VALIDATOR_MANAGER_ADDR).initialize(addresses, votingPowers, monikers);

//         // 初始化性能追踪器
//         IValidatorPerformanceTracker(VALIDATOR_PERFORMANCE_TRACKER_ADDR).initialize(addresses);

//         // 为每个验证者创建StakeCredit并初始化
//         for (uint256 i = 0; i < validators.length; i++) {
//             _initializeValidator(validators[i], i);
//         }
//     }

//     /**
//      * @dev 初始化单个验证者
//      * 对应Aptos create_initialize_validator
//      */
//     function _initializeValidator(
//         ValidatorConfigurationWithCommission calldata validatorWithCommission,
//         uint256 index
//     ) internal {
//         ValidatorConfiguration calldata config = validatorWithCommission.validatorConfig;

//         // 检查质押金额
//         if (config.stakeAmount < IStakeConfig(STAKE_CONFIG_ADDR).minValidatorStake()) {
//             revert InvalidStakeAmount();
//         }

//         // 部署StakeCredit合约
//         address stakeCreditImpl = address(new StakeCredit());
//         address stakeCreditProxy = address(new TransparentUpgradeableProxy(stakeCreditImpl, DEAD_ADDRESS, ""));

//         // 初始化StakeCredit
//         string memory moniker = string(abi.encodePacked("VAL", uint256(index)));
//         IStakeCredit(stakeCreditProxy).initialize{ value: config.stakeAmount }(
//             config.ownerAddress,
//             moniker,
//             config.ownerAddress // beneficiary默认为owner
//         );

//         // 在ValidatorManager中设置验证者信息
//         IValidatorManager(VALIDATOR_MANAGER_ADDR).setGenesisValidator(
//             config.ownerAddress,
//             stakeCreditProxy,
//             config.operatorAddress,
//             config.consensusPublicKey,
//             config.networkAddresses,
//             config.fullnodeAddresses,
//             validatorWithCommission.commissionPercentage
//         );

//         // 如果需要在创世时加入验证者集合
//         if (validatorWithCommission.joinDuringGenesis) {
//             IValidatorManager(VALIDATOR_MANAGER_ADDR).joinValidatorSetGenesis(config.ownerAddress);
//         }

//         emit ValidatorInitialized(config.ownerAddress, config.stakeAmount, moniker);
//     }

//     /**
//      * @dev 检查创世是否完成
//      */
//     function isGenesisCompleted() external view returns (bool) {
//         return genesisCompleted;
//     }
// }
