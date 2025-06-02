// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

/**
 * @title IValidatorManager
 * @dev Interface for ValidatorManager
 */
interface IValidatorManager {
    // 统一的验证者状态枚举
    enum ValidatorStatus {
        PENDING_ACTIVE, // 0
        ACTIVE, // 1
        PENDING_INACTIVE, // 2
        INACTIVE // 3

    }

    // 验证者角色结构
    struct ValidatorRoles {
        address operator; // 验证者操作员，负责日常操作
        address commissionBeneficiary; // 佣金受益人，接收验证者佣金
    }

    // 新增：Commission结构体
    struct Commission {
        uint64 rate; // the commission rate charged to delegators(10000 is 100%)
        uint64 maxRate; // maximum commission rate which validator can ever charge
        uint64 maxChangeRate; // maximum daily increase of the validator commission
    }

    /// 验证者完整信息（整合两个合约的字段）
    struct ValidatorInfo {
        // 基本信息（来自ValidatorManager）
        bytes consensusPublicKey;
        bytes networkAddresses;
        bytes fullnodeAddresses;
        bytes voteAddress; // 新增：BLS投票地址
        Commission commission; // 修改：从uint64 commissionRate改为Commission结构体
        string moniker;
        uint256 createdTime;
        bool registered;
        address stakeCreditAddress;
        // 集合管理信息（来自ValidatorSet）
        ValidatorStatus status; // 使用枚举类型
        uint64 votingPower;
        uint256 validatorIndex;
        uint256 lastEpochActive;
        uint256 updateTime; // 新增：最后一次更新时间
        // 操作员地址
        address operator; // 直接包含operator，不再使用ValidatorRoles
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
        bytes voteAddress; // BLS投票地址
        bytes blsProof; // BLS proof
        Commission commission; // 修改：从uint64 commissionRate修改为Commission结构体
        string moniker;
        address initialOperator;
        address initialVoter;
        address initialBeneficiary; // 保留这个，直接传给StakeCredit
    }

    /// 验证者注册相关事件
    event ValidatorRegistered(
        address indexed validator, address indexed operator, bytes consensusPublicKey, string moniker
    );

    event StakeCreditDeployed(address indexed validator, address stakeCreditAddress);
    event ValidatorInfoUpdated(address indexed validator, string field);
    event RewardsCollected(uint256 amount, uint256 totalIncoming);
    event CommissionRateEdited(address indexed operatorAddress, uint64 newCommissionRate);

    // 角色管理事件
    event OperatorUpdated(address indexed validator, address indexed oldOperator, address indexed newOperator);

    /// 验证者集合管理事件（借鉴Aptos）
    event ValidatorJoinRequested(address indexed validator, uint64 votingPower, uint64 epoch);
    event ValidatorLeaveRequested(address indexed validator, uint64 epoch);
    event ValidatorStatusChanged(address indexed validator, uint8 oldStatus, uint8 newStatus, uint64 epoch);

    /// Epoch转换事件
    event ValidatorSetUpdated(
        uint64 indexed epoch,
        uint256 activeCount,
        uint256 pendingActiveCount,
        uint256 pendingInactiveCount,
        uint128 totalVotingPower
    );

    // 注册相关错误
    error ValidatorAlreadyExists(address validator);
    error ValidatorNotExists(address validator);
    error InvalidCommissionRate(uint64 rate, uint64 maxRate);
    error InvalidStakeAmount(uint256 provided, uint256 required);
    error StakeCreditDeployFailed();
    error UnauthorizedCaller(address caller, address validator);
    error InvalidCommission(); // 新增：无效的佣金设置错误
    error UpdateTooFrequently(); // 新增：更新过于频繁错误
    error InvalidAddress(address addr);
    error AddressAlreadyInUse(address addr, address currentValidator);
    error NotValidator(address caller, address validator);

    // BLS验证相关错误
    error InvalidVoteAddress();
    error DuplicateVoteAddress(bytes voteAddress);

    // 集合管理相关错误（借鉴Aptos）
    error AlreadyInitialized();
    error NotInitialized();
    error ValidatorNotInactive(address validator);
    error ValidatorAlreadyPending(address validator);
    error ValidatorNotActive(address validator);
    error ValidatorSetReachedMax(uint256 current, uint256 max);
    error InvalidVotingPower(uint64 votingPower);
    error LastValidatorCannotLeave();
    error VotingPowerIncreaseExceedsLimit();
    error ValidatorSetChangeDisabled();
    error NewOperatorIsValidatorSelf();

    /**
     * @dev 初始化验证者集合
     */
    function initialize(
        address[] calldata initialValidators,
        uint64[] calldata initialVotingPowers,
        string[] calldata initialMonikers
    ) external;

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
     * @param validator 验证者地址
     * @param newCommissionRate 新的佣金率
     */
    function updateCommissionRate(address validator, uint64 newCommissionRate) external;

    /**
     * @dev 更新BLS投票地址
     * @param validator 验证者地址
     * @param newVoteAddress 新的投票地址
     * @param blsProof BLS proof
     */
    function updateVoteAddress(address validator, bytes calldata newVoteAddress, bytes calldata blsProof) external;

    // ======== 角色查询功能 ========

    /**
     * @dev 检查是否为验证者本身
     */
    function isValidator(address validator, address account) external view returns (bool);

    /**
     * @dev 获取验证者信息
     */
    function getValidatorInfo(address validator) external view returns (ValidatorInfo memory);

    /**
     * @dev 获取活跃验证者列表
     */
    function getActiveValidators() external view returns (address[] memory validators);

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
    function checkVotingPowerIncrease(uint256 increaseAmount) external view;

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

    /**
     * @dev 区块生产者存入区块奖励
     */
    function deposit() external payable;

    /**
     * @dev 获取验证者的操作员
     */
    function getOperator(address validator) external view returns (address);
}
