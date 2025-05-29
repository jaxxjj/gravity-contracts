// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

/**
 * @title IValidatorManager
 * @dev Interface for ValidatorManager
 */
interface IValidatorManager {
    // 统一的验证者状态枚举
    enum ValidatorStatus {
        UNDEFINED,
        PENDING_ACTIVE,
        ACTIVE,
        PENDING_INACTIVE,
        INACTIVE
    }

    /// 验证者完整信息（整合两个合约的字段）
    struct ValidatorInfo {
        // 基本信息（来自ValidatorManager）
        bytes consensusPublicKey;
        bytes networkAddresses;
        bytes fullnodeAddresses;
        bytes voteAddress; // 新增：BLS投票地址
        uint64 commissionRate;
        string moniker;
        uint256 createdTime;
        bool registered;
        address stakeCreditAddress;
        // 集合管理信息（来自ValidatorSet）
        ValidatorStatus status; // 使用枚举类型
        uint64 votingPower;
        uint256 validatorIndex;
        uint256 lastEpochActive;
    }

    // 在接口中定义ValidatorSetData结构
    struct ValidatorSetData {
        uint8 consensusScheme; // 共识方案
        uint128 totalVotingPower; // 总投票权重
        uint128 totalJoiningPower; // 等待加入的总权重
    }

    // 验证者注册参数结构
    struct ValidatorRegistrationParams {
        bytes consensusPublicKey;
        bytes networkAddresses;
        bytes fullnodeAddresses;
        bytes voteAddress; // 新增：BLS投票地址
        bytes blsProof; // 新增：BLS proof
        uint64 commissionRate;
        string moniker;
        address initialOperator;
        address initialVoter;
    }

    /// 验证者注册相关事件
    event ValidatorRegistered(
        address indexed validator,
        address indexed owner,
        address indexed operator,
        bytes consensusPublicKey,
        string moniker
    );

    event StakeCreditDeployed(address indexed validator, address stakeCreditAddress);
    event ValidatorInfoUpdated(address indexed validator, string field);
    event RewardsCollected(uint256 amount, uint256 totalIncoming);

    /// 验证者集合管理事件（借鉴Aptos）
    event ValidatorJoinRequested(address indexed validator, uint64 votingPower, uint64 epoch);

    event ValidatorLeaveRequested(address indexed validator, uint64 epoch);

    event ValidatorStatusChanged(address indexed validator, uint64 oldStatus, uint64 newStatus, uint64 epoch);

    /// Epoch转换事件
    event ValidatorSetUpdated(
        uint64 indexed epoch,
        uint256 activeCount,
        uint256 pendingActiveCount,
        uint256 pendingInactiveCount,
        uint128 totalVotingPower
    );

    event NewEpoch(uint64 indexed epoch, uint256 activeValidators, uint128 totalVotingPower);

    // 注册相关错误
    error ValidatorAlreadyExists(address validator);
    error ValidatorNotExists(address validator);
    error InvalidCommissionRate(uint64 rate, uint64 maxRate);
    error InvalidStakeAmount(uint256 provided, uint256 required);
    error StakeCreditDeployFailed();
    error UnauthorizedCaller(address caller, address validator);

    // BLS验证相关错误
    error InvalidVoteAddress();
    error DuplicateVoteAddress(bytes voteAddress);

    // 集合管理相关错误（借鉴Aptos）
    error AlreadyInitialized();
    error NotInitialized();
    error ValidatorAlreadyActive(address validator);
    error ValidatorAlreadyPending(address validator);
    error ValidatorNotActive(address validator);
    error ValidatorSetTooLarge(uint256 current, uint256 max);
    error InvalidVotingPower(uint64 votingPower);
    error LastValidatorCannotLeave();
    error VotingPowerIncreaseExceedsLimit();
    error ValidatorSetChangeDisabled();

    /**
     * @dev 初始化验证者集合
     */
    function initialize(address[] calldata initialValidators, uint64[] calldata initialVotingPowers) external;

    // ======== 验证者注册 ========

    /**
     * @dev 注册新验证者
     */
    function registerValidator(ValidatorRegistrationParams calldata params) external payable;

    /**
     * @dev 加入验证者集合
     */
    function joinValidatorSet(address validator) external;

    /**
     * @dev 离开验证者集合
     */
    function leaveValidatorSet(address validator) external;

    /**
     * @dev 处理新epoch事件
     */
    function onNewEpoch() external;

    /**
     * @dev 检查验证者是否满足最小质押要求
     */
    function checkValidatorMinStake(address validator) external;

    // ======== 验证者信息更新 ========

    /**
     * @dev 更新共识公钥
     */
    function updateConsensusKey(address validator, bytes calldata newConsensusKey) external;

    /**
     * @dev 更新网络地址
     */
    function updateNetworkAddresses(
        address validator,
        bytes calldata newNetworkAddresses,
        bytes calldata newFullnodeAddresses
    ) external;

    /**
     * @dev 更新佣金率
     */
    function updateCommissionRate(address validator, uint64 newCommissionRate) external;

    /**
     * @dev 更新BLS投票地址
     * @param validator 验证者地址
     * @param newVoteAddress 新的投票地址
     * @param blsProof BLS proof
     */
    function updateVoteAddress(address validator, bytes calldata newVoteAddress, bytes calldata blsProof) external;

    /**
     * @dev 获取验证者信息
     */
    function getValidatorInfo(address validator) external view returns (ValidatorInfo memory);

    /**
     * @dev 获取活跃验证者列表
     */
    function getActiveValidators() external view returns (address[] memory validators, uint64[] memory votingPowers);

    /**
     * @dev 获取待处理验证者列表
     */
    function getPendingValidators() external view returns (address[] memory);

    /**
     * @dev 检查验证者是否为当前活跃验证者
     */
    function isCurrentEpochValidator(address validator) external view returns (bool);

    /**
     * @dev 获取总投票权重
     */
    function getTotalVotingPower() external view returns (uint256);

    /**
     * @dev 获取验证者集合数据
     */
    function getValidatorSetData() external view returns (ValidatorSetData memory);

    /**
     * @dev 获取验证者的StakeCredit地址
     */
    function getValidatorStakeCredit(address validator) external view returns (address);

    /**
     * @dev 检查投票权增长限制
     */
    function checkVotingPowerIncrease(address validator, uint256 increaseAmount) external view;

    /**
     * @dev 检查验证者是否注册
     */
    function isValidatorRegistered(address validator) external view returns (bool);

    /**
     * @dev 检查验证者是否存在
     */
    function isValidatorExists(address validator) external view returns (bool);

    /**
     * @dev 获取验证者状态
     */
    function getValidatorStatus(address validator) external view returns (ValidatorStatus);

    /**
     * @dev 获取验证者的投票地址
     */
    function getValidatorVoteAddress(address validator) external view returns (bytes memory);

    /**
     * @dev 获取验证者在当前活跃验证者集合中的索引
     * @param validator 验证者地址
     * @return 验证者索引，如果不是活跃验证者则可能返回0或revert
     */
    function getValidatorIndex(address validator) external view returns (uint64);
    function deposit() external payable;
}
