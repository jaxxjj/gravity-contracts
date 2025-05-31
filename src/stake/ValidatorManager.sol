// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "../System.sol";
import "@src/interfaces/IAccessControl.sol";
import "@src/interfaces/IStakeConfig.sol";
import "@src/interfaces/IEpochManager.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@src/access/Protectable.sol";
import "@src/interfaces/IStakeCredit.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@src/stake/StakeCredit.sol";
import "@src/interfaces/IValidatorManager.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@src/interfaces/ITimestamp.sol";
import "@src/interfaces/IValidatorPerformanceTracker.sol";
/**
 * @title ValidatorManager
 * @dev validator set和管理的统一合约
 * 1. 借鉴Aptos stake.move的验证者集合管理逻辑
 * 2. 保留BSC StakeHub的注册和质押功能
 * 3. 注册管理、状态管理、集合管理、Epoch处理
 */

contract ValidatorManager is System, ReentrancyGuard, Protectable, IValidatorManager, Initializable {
    using EnumerableSet for EnumerableSet.AddressSet;

    /// BLS公钥长度
    uint256 private constant BLS_PUBKEY_LENGTH = 48;
    /// BLS签名长度
    uint256 private constant BLS_SIG_LENGTH = 96;
    /// 更新间隔时间
    uint256 private constant BREATHE_BLOCK_INTERVAL = 1 days;

    /// 对应Aptos的MAX_VALIDATOR_SET_SIZE
    uint64 public constant MAX_VALIDATOR_SET_SIZE = 65536;

    /// 主ValidatorSet数据
    ValidatorSetData public validatorSetData;

    /// 验证者信息映射
    mapping(address => ValidatorInfo) public validatorInfos;

    /// BLS投票地址映射
    mapping(bytes => address) public voteToOperator; // 投票地址 => 操作员地址
    mapping(bytes => uint256) public voteExpiration; // 投票地址 => 过期时间

    /// 共识地址映射
    mapping(bytes => address) public consensusToOperator; // 共识地址 => 操作员地址

    /// 验证者名称映射
    mapping(bytes32 => bool) private _monikerSet; // 验证者名称哈希 => 是否存在

    /// 验证者集合管理（借鉴Aptos设计）
    EnumerableSet.AddressSet private activeValidators; // 当前活跃验证者
    EnumerableSet.AddressSet private pendingActive; // 等待激活的验证者
    EnumerableSet.AddressSet private pendingInactive; // 等待移除的验证者

    /// 索引映射（用于快速查找）
    mapping(address => uint256) private activeValidatorIndex;
    mapping(address => uint256) private pendingActiveIndex;
    mapping(address => uint256) private pendingInactiveIndex;

    /// 初始化标志
    bool private initialized;

    // 从 StakeReward 导入的事件
    event RewardsDistributed(address indexed validator, uint256 amount);
    event FinalityRewardDistributed(address indexed validator, uint256 amount);
    event ValidatorDeposit(address indexed validator, uint256 amount);

    // 用于跟踪验证者累积奖励的映射
    uint256 public totalIncoming;

    // 自定义错误
    error DuplicateConsensusAddress(bytes consensusAddress);
    error DuplicateMoniker(string moniker);
    error InvalidMoniker(string moniker);

    /*----------------- 修饰符 -----------------*/

    modifier validatorExists(address validator) {
        if (!validatorInfos[validator].registered) {
            revert ValidatorNotExists(validator);
        }
        _;
    }

    modifier onlyValidatorOperator(address validator) {
        if (!IAccessControl(ACCESS_CONTROL_ADDR).hasOperatorPermission(validator, msg.sender)) {
            revert UnauthorizedCaller(msg.sender, validator);
        }
        _;
    }

    /**
     * @dev 检查是否允许验证者集合变更
     */
    modifier whenValidatorSetChangeAllowed() {
        if (!IStakeConfig(STAKE_CONFIG_ADDR).allowValidatorSetChange()) {
            revert ValidatorSetChangeDisabled();
        }
        _;
    }

    /**
     * @dev 初始化验证者集合（对应Aptos的initialize函数）
     * @param initialValidators 初始验证者地址
     * @param initialVotingPowers 初始投票权重
     * @param initialMonikers 初始验证者名称
     */
    function initialize(
        address[] calldata initialValidators,
        uint64[] calldata initialVotingPowers,
        string[] calldata initialMonikers
    ) external onlySystemCaller {
        if (initialized) revert AlreadyInitialized();

        require(initialValidators.length == initialVotingPowers.length, "Array length mismatch");
        require(initialValidators.length == initialMonikers.length, "Array length mismatch for monikers");

        initialized = true;

        // 初始化ValidatorSet数据
        validatorSetData = ValidatorSetData({consensusScheme: 0, totalVotingPower: 0, totalJoiningPower: 0});

        // 添加初始验证者
        for (uint256 i = 0; i < initialValidators.length; i++) {
            address validator = initialValidators[i];
            uint64 votingPower = initialVotingPowers[i];
            string memory moniker = initialMonikers[i];

            if (votingPower == 0) revert InvalidVotingPower(votingPower);

            // 检查验证者名称格式
            if (!_checkMoniker(moniker)) {
                revert InvalidMoniker(moniker);
            }

            // 检查验证者名称是否重复
            bytes32 monikerHash = keccak256(abi.encodePacked(moniker));
            if (_monikerSet[monikerHash]) {
                revert DuplicateMoniker(moniker);
            }

            // 记录验证者名称
            _monikerSet[monikerHash] = true;

            // 默认佣金设置
            Commission memory defaultCommission = Commission({
                rate: 0,
                maxRate: 5000, // 默认最大佣金率50%
                maxChangeRate: 500 // 默认每日最大变更率5%
            });

            // 创建基本验证者信息
            validatorInfos[validator] = ValidatorInfo({
                consensusPublicKey: "",
                networkAddresses: "",
                fullnodeAddresses: "",
                voteAddress: "", // 初始空BLS地址
                commissionRate: defaultCommission.rate,
                moniker: moniker, // 使用传入的moniker
                createdTime: ITimestamp(TIMESTAMP_ADDR).nowSeconds(),
                registered: true,
                stakeCreditAddress: address(0),
                status: ValidatorStatus.ACTIVE,
                votingPower: votingPower,
                validatorIndex: i,
                lastEpochActive: 0,
                updateTime: ITimestamp(TIMESTAMP_ADDR).nowSeconds() // 添加更新时间字段
            });

            // 添加到活跃验证者集合
            activeValidators.add(validator);
            activeValidatorIndex[validator] = i;

            // 更新总投票权重
            validatorSetData.totalVotingPower += votingPower;
        }
    }

    /**
     * @dev 注册新验证者（添加BLS proof验证）
     */
    function registerValidator(ValidatorRegistrationParams calldata params)
        external
        payable
        nonReentrant
        whenNotPaused
    {
        address validator = msg.sender;

        if (validatorInfos[validator].registered) {
            revert ValidatorAlreadyExists(validator);
        }

        // 检查BLS投票地址是否重复
        if (params.voteAddress.length > 0 && voteToOperator[params.voteAddress] != address(0)) {
            revert DuplicateVoteAddress(params.voteAddress);
        }

        // 检查共识地址是否重复
        if (params.consensusPublicKey.length > 0 && consensusToOperator[params.consensusPublicKey] != address(0)) {
            revert DuplicateConsensusAddress(params.consensusPublicKey);
        }

        // 检查验证者名称格式
        if (!_checkMoniker(params.moniker)) {
            revert InvalidMoniker(params.moniker);
        }

        // 检查验证者名称是否重复
        bytes32 monikerHash = keccak256(abi.encodePacked(params.moniker));
        if (_monikerSet[monikerHash]) {
            revert DuplicateMoniker(params.moniker);
        }

        // 检查佣金设置
        if (
            params.commission.maxRate > IStakeConfig(STAKE_CONFIG_ADDR).MAX_COMMISSION_RATE()
                || params.commission.rate > params.commission.maxRate
                || params.commission.maxChangeRate > params.commission.maxRate
        ) {
            revert InvalidCommission();
        }

        // BLS proof验证
        if (params.voteAddress.length > 0 && !_checkVoteAddress(validator, params.voteAddress, params.blsProof)) {
            revert InvalidVoteAddress();
        }

        // 检查最小质押要求
        uint256 stakeMinusLock = msg.value - IStakeConfig(STAKE_CONFIG_ADDR).lockAmount(); // create validator need to lock 1 BNB
        uint256 minStake = IStakeConfig(STAKE_CONFIG_ADDR).minValidatorStake();
        if (stakeMinusLock < minStake) {
            revert InvalidStakeAmount(stakeMinusLock, minStake);
        }

        // 部署StakeCredit合约
        address stakeCreditAddress = _deployStakeCredit(validator, params.moniker);

        // 在AccessControl中注册角色映射
        _registerRoles(validator, params.initialOperator, params.initialVoter, validator);

        // 存储验证者信息
        validatorInfos[validator] = ValidatorInfo({
            consensusPublicKey: params.consensusPublicKey,
            networkAddresses: params.networkAddresses,
            fullnodeAddresses: params.fullnodeAddresses,
            voteAddress: params.voteAddress,
            commissionRate: params.commission.rate,
            moniker: params.moniker,
            createdTime: ITimestamp(TIMESTAMP_ADDR).nowSeconds(),
            registered: true,
            stakeCreditAddress: stakeCreditAddress,
            status: ValidatorStatus.INACTIVE,
            votingPower: 0,
            validatorIndex: 0,
            lastEpochActive: 0,
            updateTime: ITimestamp(TIMESTAMP_ADDR).nowSeconds() // 添加更新时间字段
        });

        // 注册投票地址映射
        if (params.voteAddress.length > 0) {
            voteToOperator[params.voteAddress] = validator;
        }

        // 注册共识地址映射
        if (params.consensusPublicKey.length > 0) {
            consensusToOperator[params.consensusPublicKey] = validator;
        }

        // 记录验证者名称
        _monikerSet[monikerHash] = true;

        // 初始质押
        StakeCredit(payable(stakeCreditAddress)).delegate{value: msg.value}(validator);

        emit ValidatorRegistered(validator, msg.sender, validator, params.consensusPublicKey, params.moniker);
        emit StakeCreditDeployed(validator, stakeCreditAddress);
    }

    /**
     * @dev 加入验证者集合（对应Aptos的join_validator_set）
     */
    function joinValidatorSet(address validator)
        external
        whenNotPaused
        whenValidatorSetChangeAllowed
        validatorExists(validator)
    {
        require(
            msg.sender == validator || IAccessControl(ACCESS_CONTROL_ADDR).hasOperatorPermission(validator, msg.sender),
            "Not authorized"
        );

        ValidatorInfo storage info = validatorInfos[validator];

        // 检查当前状态
        if (info.status != ValidatorStatus.INACTIVE) {
            revert ValidatorNotInactive(validator);
        }

        // 获取当前质押和检查要求
        uint64 votingPower = uint64(_getValidatorStake(validator));
        uint256 minStake = IStakeConfig(STAKE_CONFIG_ADDR).minValidatorStake();

        if (votingPower < minStake) {
            revert InvalidStakeAmount(votingPower, minStake);
        }

        // 检查验证者集合大小限制
        uint256 totalSize = activeValidators.length() + pendingActive.length();
        if (totalSize >= MAX_VALIDATOR_SET_SIZE) {
            revert ValidatorSetReachedMax(totalSize, MAX_VALIDATOR_SET_SIZE);
        }

        // 检查投票权增长限制
        _checkVotingPowerIncrease(validator, votingPower);

        // 更新状态到PENDING_ACTIVE
        info.status = ValidatorStatus.PENDING_ACTIVE;
        info.votingPower = votingPower;

        // 添加到pending_active集合
        pendingActive.add(validator);
        pendingActiveIndex[validator] = pendingActive.length() - 1;

        // 更新总加入权重
        validatorSetData.totalJoiningPower += votingPower;

        uint64 currentEpoch = uint64(IEpochManager(EPOCH_MANAGER_ADDR).currentEpoch());
        emit ValidatorJoinRequested(validator, votingPower, currentEpoch);
        emit ValidatorStatusChanged(
            validator, uint8(ValidatorStatus.INACTIVE), uint8(ValidatorStatus.PENDING_ACTIVE), currentEpoch
        );
    }

    /**
     * @dev 离开验证者集合（对应Aptos的leave_validator_set）
     */
    function leaveValidatorSet(address validator)
        external
        whenNotPaused
        whenValidatorSetChangeAllowed
        validatorExists(validator)
    {
        require(
            msg.sender == validator || IAccessControl(ACCESS_CONTROL_ADDR).hasOperatorPermission(validator, msg.sender),
            "Not authorized"
        );

        ValidatorInfo storage info = validatorInfos[validator];
        uint8 currentStatus = uint8(info.status);
        uint64 currentEpoch = uint64(IEpochManager(EPOCH_MANAGER_ADDR).currentEpoch());

        if (currentStatus == uint8(ValidatorStatus.PENDING_ACTIVE)) {
            // 如果还在pending状态，直接移除

            // 从集合中移除
            pendingActive.remove(validator);
            delete pendingActiveIndex[validator];

            // 更新总加入权重
            validatorSetData.totalJoiningPower -= info.votingPower;
            info.votingPower = 0;
            info.status = ValidatorStatus.INACTIVE;

            emit ValidatorStatusChanged(
                validator, uint8(ValidatorStatus.PENDING_ACTIVE), uint8(ValidatorStatus.INACTIVE), currentEpoch
            );
        } else if (currentStatus == uint8(ValidatorStatus.ACTIVE)) {
            // 检查是否是最后一个验证者
            if (activeValidators.length() <= 1) {
                revert LastValidatorCannotLeave();
            }

            // 从active移除
            activeValidators.remove(validator);
            delete activeValidatorIndex[validator];

            // 添加到pending_inactive
            pendingInactive.add(validator);
            pendingInactiveIndex[validator] = pendingInactive.length() - 1;

            // 更新总投票权重
            validatorSetData.totalVotingPower -= info.votingPower;
            info.status = ValidatorStatus.PENDING_INACTIVE;

            emit ValidatorStatusChanged(
                validator, uint8(ValidatorStatus.ACTIVE), uint8(ValidatorStatus.PENDING_INACTIVE), currentEpoch
            );
        } else {
            revert ValidatorNotActive(validator);
        }

        emit ValidatorLeaveRequested(validator, currentEpoch);
    }

    /**
     * @dev 新epoch处理（对应Aptos stake.move中on_new_epoch的验证者集合更新部分）
     */
    function onNewEpoch() external onlyStakeHub {
        // 处理StakeCredit的epoch转换
        _processStakeCreditEpochTransitions();

        // 1. 分发基于性能的奖励 (从StakeReward合并)
        _distributeRewards();

        // 2. 分发累积的区块奖励
        _distributeValidatorRewards();

        uint64 currentEpoch = uint64(IEpochManager(EPOCH_MANAGER_ADDR).currentEpoch());
        uint64 newEpoch = currentEpoch + 1;
        uint64 minStakeRequired = uint64(IStakeConfig(STAKE_CONFIG_ADDR).minValidatorStake());

        // 3. 激活pending_active验证者
        _activatePendingValidators(currentEpoch);

        // 4. 移除pending_inactive验证者
        _removePendingInactiveValidators(currentEpoch);

        // 5. 重新计算验证者集合
        _recalculateValidatorSet(minStakeRequired, currentEpoch);

        // 6. 重置加入权重
        validatorSetData.totalJoiningPower = 0;

        emit NewEpoch(newEpoch, activeValidators.length(), validatorSetData.totalVotingPower);
        emit ValidatorSetUpdated(
            newEpoch,
            activeValidators.length(),
            pendingActive.length(),
            pendingInactive.length(),
            validatorSetData.totalVotingPower
        );
    }

    /**
     * @dev 获取验证者状态（对应Aptos的get_validator_state）
     */
    function getValidatorState(address validator) public view returns (uint8) {
        if (!validatorInfos[validator].registered) {
            return uint8(ValidatorStatus.INACTIVE);
        }
        return uint8(validatorInfos[validator].status);
    }

    /**
     * @dev 获取验证者信息
     */
    function getValidatorInfo(address validator) external view returns (ValidatorInfo memory) {
        return validatorInfos[validator];
    }

    /**
     * @dev 获取活跃验证者列表
     */
    function getActiveValidators() external view returns (address[] memory validators, uint64[] memory votingPowers) {
        uint256 length = activeValidators.length();
        validators = new address[](length);
        votingPowers = new uint64[](length);

        for (uint256 i = 0; i < length; i++) {
            address validator = activeValidators.at(i);
            validators[i] = validator;
            votingPowers[i] = validatorInfos[validator].votingPower;
        }

        return (validators, votingPowers);
    }

    /**
     * @dev 检查验证者是否为当前活跃验证者
     */
    function isCurrentValidator(address validator) external view returns (bool) {
        return validatorInfos[validator].status == ValidatorStatus.ACTIVE;
    }

    /**
     * @dev 获取验证者集合数据
     */
    function getValidatorSetData() external view returns (ValidatorSetData memory) {
        return validatorSetData;
    }

    /**
     * @dev 更新共识公钥
     */
    function updateConsensusKey(address validator, bytes calldata newConsensusKey)
        external
        validatorExists(validator)
        onlyValidatorOperator(validator)
    {
        // 检查新的共识地址是否重复且非同一验证者
        if (
            newConsensusKey.length > 0 && consensusToOperator[newConsensusKey] != address(0)
                && consensusToOperator[newConsensusKey] != validator
        ) {
            revert DuplicateConsensusAddress(newConsensusKey);
        }

        // 清除旧的共识地址映射
        bytes memory oldConsensusKey = validatorInfos[validator].consensusPublicKey;
        if (oldConsensusKey.length > 0) {
            delete consensusToOperator[oldConsensusKey];
        }

        // 更新验证者信息
        validatorInfos[validator].consensusPublicKey = newConsensusKey;

        // 更新共识地址映射
        if (newConsensusKey.length > 0) {
            consensusToOperator[newConsensusKey] = validator;
        }

        emit ValidatorInfoUpdated(validator, "consensusKey");
    }

    /**
     * @dev 更新网络地址
     */
    function updateNetworkAddresses(
        address validator,
        bytes calldata newNetworkAddresses,
        bytes calldata newFullnodeAddresses
    ) external validatorExists(validator) onlyValidatorOperator(validator) {
        validatorInfos[validator].networkAddresses = newNetworkAddresses;
        validatorInfos[validator].fullnodeAddresses = newFullnodeAddresses;
        emit ValidatorInfoUpdated(validator, "networkAddresses");
    }

    /**
     * @dev 更新佣金率
     * @param validator 验证者地址
     * @param newCommissionRate 新的佣金率
     */
    function updateCommissionRate(address validator, uint64 newCommissionRate)
        external
        validatorExists(validator)
        onlyValidatorOperator(validator)
    {
        ValidatorInfo storage info = validatorInfos[validator];

        // 检查更新频率
        if (info.updateTime + BREATHE_BLOCK_INTERVAL > ITimestamp(TIMESTAMP_ADDR).nowSeconds()) {
            revert UpdateTooFrequently();
        }

        uint256 maxCommissionRate = IStakeConfig(STAKE_CONFIG_ADDR).maxCommissionRate();
        if (newCommissionRate > maxCommissionRate) {
            revert InvalidCommissionRate(newCommissionRate, uint64(maxCommissionRate));
        }

        // 计算变化量
        uint256 changeRate = newCommissionRate >= info.commissionRate
            ? newCommissionRate - info.commissionRate
            : info.commissionRate - newCommissionRate;

        // 检查变化量是否超过每日最大变更率
        // 注意：由于我们没有在ValidatorInfo中保存maxChangeRate，这里简化为使用默认值或者IStakeConfig中的值
        uint64 maxChangeRate = 500; // 默认5%
        if (changeRate > maxChangeRate) {
            revert InvalidCommission();
        }

        // 更新佣金率
        info.commissionRate = newCommissionRate;
        info.updateTime = ITimestamp(TIMESTAMP_ADDR).nowSeconds();

        emit CommissionRateEdited(validator, newCommissionRate);
        emit ValidatorInfoUpdated(validator, "commissionRate");
    }

    /**
     * @dev 更新BLS投票地址
     * @param validator 验证者地址
     * @param newVoteAddress 新的投票地址
     * @param blsProof BLS proof
     */
    function updateVoteAddress(address validator, bytes calldata newVoteAddress, bytes calldata blsProof)
        external
        validatorExists(validator)
        onlyValidatorOperator(validator)
    {
        // 验证新的投票地址
        if (newVoteAddress.length > 0) {
            // BLS proof验证
            if (!_checkVoteAddress(validator, newVoteAddress, blsProof)) {
                revert InvalidVoteAddress();
            }

            // 检查是否有重复且非同一验证者
            if (voteToOperator[newVoteAddress] != address(0) && voteToOperator[newVoteAddress] != validator) {
                revert DuplicateVoteAddress(newVoteAddress);
            }
        }

        // 清除旧的映射
        bytes memory oldVoteAddress = validatorInfos[validator].voteAddress;
        if (oldVoteAddress.length > 0) {
            delete voteToOperator[oldVoteAddress];
            voteExpiration[oldVoteAddress] = ITimestamp(TIMESTAMP_ADDR).nowSeconds();
        }

        // 更新验证者信息
        validatorInfos[validator].voteAddress = newVoteAddress;

        // 更新投票地址映射
        if (newVoteAddress.length > 0) {
            voteToOperator[newVoteAddress] = validator;
        }

        emit ValidatorInfoUpdated(validator, "voteAddress");
    }

    /**
     * @dev 激活pending_active中的验证者
     */
    function _activatePendingValidators(uint64 currentEpoch) internal {
        address[] memory pendingValidators = pendingActive.values();

        for (uint256 i = 0; i < pendingValidators.length; i++) {
            address validator = pendingValidators[i];
            ValidatorInfo storage info = validatorInfos[validator];

            // 从pending_active移除
            pendingActive.remove(validator);
            delete pendingActiveIndex[validator];

            // 添加到active
            activeValidators.add(validator);
            info.validatorIndex = activeValidators.length() - 1;
            activeValidatorIndex[validator] = info.validatorIndex;

            // 更新状态
            info.status = ValidatorStatus.ACTIVE;
            info.lastEpochActive = currentEpoch;

            emit ValidatorStatusChanged(
                validator, uint8(ValidatorStatus.PENDING_ACTIVE), uint8(ValidatorStatus.ACTIVE), currentEpoch
            );
        }
    }

    /**
     * @dev 移除pending_inactive中的验证者
     */
    function _removePendingInactiveValidators(uint64 currentEpoch) internal {
        address[] memory pendingInactiveValidators = pendingInactive.values();

        for (uint256 i = 0; i < pendingInactiveValidators.length; i++) {
            address validator = pendingInactiveValidators[i];
            ValidatorInfo storage info = validatorInfos[validator];

            // 从pending_inactive移除
            pendingInactive.remove(validator);
            delete pendingInactiveIndex[validator];

            // 更新状态
            info.status = ValidatorStatus.INACTIVE;
            info.lastEpochActive = currentEpoch;

            emit ValidatorStatusChanged(
                validator, uint8(ValidatorStatus.PENDING_INACTIVE), uint8(ValidatorStatus.INACTIVE), currentEpoch
            );
        }
    }

    /**
     * @dev 重新计算验证者集合
     */
    function _recalculateValidatorSet(uint64 minStakeRequired, uint64 currentEpoch) internal {
        uint128 newTotalVotingPower = 0;
        address[] memory currentActive = activeValidators.values();

        for (uint256 i = 0; i < currentActive.length; i++) {
            address validator = currentActive[i];
            ValidatorInfo storage info = validatorInfos[validator];

            // 更新投票权重
            uint64 currentStake = uint64(_getValidatorStake(validator));

            if (currentStake >= minStakeRequired) {
                info.votingPower = currentStake;
                newTotalVotingPower += currentStake;
            } else {
                // 投票权重不足，移除验证者
                activeValidators.remove(validator);
                delete activeValidatorIndex[validator];

                info.status = ValidatorStatus.INACTIVE;
                info.votingPower = 0;
                info.lastEpochActive = currentEpoch;

                emit ValidatorStatusChanged(
                    validator, uint8(ValidatorStatus.ACTIVE), uint8(ValidatorStatus.INACTIVE), currentEpoch
                );
            }
        }

        // 更新总投票权重
        validatorSetData.totalVotingPower = newTotalVotingPower;
    }

    /**
     * @dev 部署StakeCredit合约
     */
    function _deployStakeCredit(address validator, string memory moniker) internal returns (address) {
        address creditProxy = address(new TransparentUpgradeableProxy(STAKE_CREDIT_ADDR, DEAD_ADDRESS, ""));
        IStakeCredit(creditProxy).initialize{value: msg.value}(validator, moniker);
        emit StakeCreditDeployed(validator, creditProxy);

        return creditProxy;
    }

    /**
     * @dev 注册验证者角色
     */
    function _registerRoles(
        address validator,
        address initialOperator,
        address initialVoter,
        address initialBeneficiary
    ) internal {
        IAccessControl(ACCESS_CONTROL_ADDR).registerValidatorRoles(
            validator, msg.sender, initialOperator, initialVoter, initialBeneficiary
        );
    }

    /**
     * @dev 获取验证者质押
     */
    function _getValidatorStake(address validator) internal view returns (uint256) {
        address stakeCreditAddress = validatorInfos[validator].stakeCreditAddress;
        if (stakeCreditAddress == address(0)) {
            return 0;
        }

        // 直接从StakeCredit获取下一epoch的投票权重
        return StakeCredit(payable(stakeCreditAddress)).getNextEpochVotingPower();
    }

    /**
     * @dev 检查投票权增长限制
     */
    function _checkVotingPowerIncrease(address validator, uint256 increaseAmount) internal view {
        uint256 votingPowerIncreaseLimit = IStakeConfig(STAKE_CONFIG_ADDR).votingPowerIncreaseLimit();

        if (validatorSetData.totalVotingPower > 0) {
            uint256 currentJoining = validatorSetData.totalJoiningPower + increaseAmount;

            if (currentJoining * 100 > validatorSetData.totalVotingPower * votingPowerIncreaseLimit) {
                revert VotingPowerIncreaseExceedsLimit();
            }
        }
    }

    /**
     * @dev 验证BLS投票地址和proof（借鉴BSC实现）
     * @param operatorAddress 操作员地址
     * @param voteAddress BLS投票地址
     * @param blsProof BLS proof
     * @return 验证是否成功
     */
    function _checkVoteAddress(address operatorAddress, bytes calldata voteAddress, bytes calldata blsProof)
        internal
        view
        returns (bool)
    {
        // 检查长度
        if (voteAddress.length != BLS_PUBKEY_LENGTH || blsProof.length != BLS_SIG_LENGTH) {
            return false;
        }

        // 生成消息哈希
        bytes32 msgHash = keccak256(abi.encodePacked(operatorAddress, voteAddress, block.chainid));
        bytes memory msgBz = new bytes(32);
        assembly {
            mstore(add(msgBz, 32), msgHash)
        }

        // 调用预编译合约验证BLS签名
        // 预编译合约地址是0x66
        bytes memory input = bytes.concat(msgBz, blsProof, voteAddress); // 长度: 32 + 96 + 48 = 176
        bytes memory output = new bytes(1);
        assembly {
            let len := mload(input)
            if iszero(staticcall(not(0), 0x66, add(input, 0x20), len, add(output, 0x20), 0x01)) { revert(0, 0) }
        }
        uint8 result = uint8(output[0]);
        if (result != uint8(1)) {
            return false;
        }
        return true;
    }

    /**
     * @dev 处理所有StakeCredit合约的epoch转换
     */
    function _processStakeCreditEpochTransitions() internal {
        address[] memory allValidators = activeValidators.values();

        for (uint256 i = 0; i < allValidators.length; i++) {
            address validator = allValidators[i];
            address stakeCreditAddress = validatorInfos[validator].stakeCreditAddress;
            if (stakeCreditAddress != address(0)) {
                StakeCredit(payable(stakeCreditAddress)).onNewEpoch();
            }
        }
    }

    /**
     * @dev 检查验证者是否满足最小质押要求
     */
    function checkValidatorMinStake(address validator) external {
        _checkValidatorMinStake(validator);
    }

    function _checkValidatorMinStake(address validator) internal {
        ValidatorInfo storage info = validatorInfos[validator];
        if (info.status == ValidatorStatus.ACTIVE) {
            uint256 validatorStake = _getValidatorStake(validator);
            uint256 minStake = IStakeConfig(STAKE_CONFIG_ADDR).minValidatorStake();

            if (validatorStake < minStake) {
                uint8 oldStatus = uint8(info.status);
                info.status = ValidatorStatus.PENDING_INACTIVE;

                // 添加到pending_inactive集合
                pendingInactive.add(validator);
                pendingInactiveIndex[validator] = pendingInactive.length() - 1;

                // 只更新totalVotingPower
                validatorSetData.totalVotingPower -= info.votingPower;

                uint64 currentEpoch = uint64(IEpochManager(EPOCH_MANAGER_ADDR).currentEpoch());
                emit ValidatorStatusChanged(validator, oldStatus, uint8(ValidatorStatus.PENDING_INACTIVE), currentEpoch);
            }
        }
    }

    /**
     * @dev 获取验证者的StakeCredit地址
     */
    function getValidatorStakeCredit(address validator) external view returns (address) {
        return validatorInfos[validator].stakeCreditAddress;
    }

    /**
     * @dev 公开的投票权增长检查方法
     * @param validator 验证者地址
     * @param increaseAmount 增加的质押金额
     */
    function checkVotingPowerIncrease(address validator, uint256 increaseAmount) external view {
        _checkVotingPowerIncrease(validator, increaseAmount);
    }

    /**
     * @dev 检查验证者是否注册
     */
    function isValidatorRegistered(address validator) external view override returns (bool) {
        return validatorInfos[validator].registered;
    }

    /**
     * @dev 检查验证者是否存在(别名)
     */
    function isValidatorExists(address validator) external view returns (bool) {
        return validatorInfos[validator].registered;
    }

    /**
     * @dev 获取总投票权重
     */
    function getTotalVotingPower() external view override returns (uint256) {
        return validatorSetData.totalVotingPower;
    }

    /**
     * @dev 获取待处理验证者列表
     */
    function getPendingValidators() external view override returns (address[] memory) {
        return pendingActive.values();
    }

    /**
     * @dev 检查验证者是否为当前活跃验证者
     */
    function isCurrentEpochValidator(address validator) public view override returns (bool) {
        return validatorInfos[validator].status == ValidatorStatus.ACTIVE;
    }

    /**
     * @dev 获取验证者状态
     * @return 验证者状态
     */
    function getValidatorStatus(address validator) external view override returns (ValidatorStatus) {
        if (!validatorInfos[validator].registered) {
            return ValidatorStatus.INACTIVE;
        }
        return validatorInfos[validator].status;
    }

    /**
     * @dev 获取验证者的投票地址
     */
    function getValidatorVoteAddress(address validator) external view returns (bytes memory) {
        return validatorInfos[validator].voteAddress;
    }

    /**
     * @dev 存储验证者基本信息（更新版本）
     */
    function _storeValidatorInfo(
        address validator,
        bytes memory consensusPublicKey,
        bytes memory networkAddresses,
        bytes memory fullnodeAddresses,
        bytes memory voteAddress,
        uint64 commissionRate,
        string memory moniker,
        address stakeCreditAddress,
        ValidatorStatus status
    ) internal {
        validatorInfos[validator] = ValidatorInfo({
            consensusPublicKey: consensusPublicKey,
            networkAddresses: networkAddresses,
            fullnodeAddresses: fullnodeAddresses,
            voteAddress: voteAddress,
            commissionRate: commissionRate,
            moniker: moniker,
            createdTime: ITimestamp(TIMESTAMP_ADDR).nowSeconds(),
            registered: true,
            stakeCreditAddress: stakeCreditAddress,
            status: status,
            votingPower: 0,
            validatorIndex: 0,
            lastEpochActive: 0,
            updateTime: ITimestamp(TIMESTAMP_ADDR).nowSeconds() // 添加更新时间字段
        });
    }

    /**
     * @dev 获取验证者在当前活跃验证者集合中的索引
     * @param validator 验证者地址
     * @return 验证者索引，如果不是活跃验证者则可能返回0或revert
     */
    function getValidatorIndex(address validator) external view returns (uint64) {
        if (!isCurrentEpochValidator(validator)) {
            revert ValidatorNotActive(validator);
        }
        return uint64(activeValidatorIndex[validator]);
    }

    /**
     * @dev 区块生产者调用，存入当前区块的交易费用作为奖励
     */
    function deposit() external payable onlySystemCaller {
        // 直接累积到总奖励池，不分配给特定验证者
        totalIncoming += msg.value;

        emit RewardsCollected(msg.value, totalIncoming);
    }

    /**
     * @dev 分发基于性能的奖励给所有活跃验证者
     * 集成自 StakeReward.distributeRewards()
     */
    function distributeRewards() public onlyStakeHub nonReentrant whenNotPaused {
        _distributeRewards();
    }

    /**
     * @dev 内部方法，实现奖励分发逻辑
     * 集成自 StakeReward._distributeRewards()
     */
    function _distributeRewards() internal {
        address[] memory validators = activeValidators.values();

        for (uint256 i = 0; i < validators.length; i++) {
            address validator = validators[i];
            address stakeCreditAddress = validatorInfos[validator].stakeCreditAddress;

            if (stakeCreditAddress != address(0)) {
                uint256 stakeAmount = _getValidatorCurrentEpochVotingPower(validator);

                // 直接使用接口调用，不创建局部变量
                (uint64 successfulProposals, uint64 failedProposals,, bool exists) =
                    IValidatorPerformanceTracker(PERFORMANCE_TRACKER_ADDR).getValidatorPerformance(validator);

                if (exists) {
                    uint64 totalProposals = successfulProposals + failedProposals;

                    // 计算奖励（如果没有提案，使用默认值）
                    uint256 rewardAmount;
                    if (totalProposals > 0) {
                        rewardAmount = IStakeConfig(STAKE_CONFIG_ADDR).calculateRewardsAmount(
                            stakeAmount, successfulProposals, totalProposals
                        );
                    } else {
                        // 如果没有提案记录，使用100%成功率
                        rewardAmount = IStakeConfig(STAKE_CONFIG_ADDR).calculateRewardsAmount(stakeAmount, 1, 1);
                    }

                    if (rewardAmount > 0) {
                        // 获取验证者的佣金率
                        uint64 commissionRate = validatorInfos[validator].commissionRate;

                        // 发送奖励到StakeCredit合约
                        StakeCredit(payable(stakeCreditAddress)).distributeReward{value: rewardAmount}(commissionRate);
                        emit RewardsDistributed(validator, rewardAmount);
                    }
                }
            }
        }
    }

    /**
     * @dev 获取验证者的当前epoch投票权
     * 集成自 StakeReward._getValidatorCurrentEpochVotingPower()
     */
    function _getValidatorCurrentEpochVotingPower(address validator) internal view returns (uint256) {
        address stakeCreditAddress = validatorInfos[validator].stakeCreditAddress;
        if (stakeCreditAddress == address(0)) {
            return 0;
        }
        return StakeCredit(payable(stakeCreditAddress)).getCurrentEpochVotingPower();
    }

    /**
     * @dev 分发累积的区块奖励
     */
    function _distributeValidatorRewards() internal {
        if (totalIncoming == 0) return;

        address[] memory validators = activeValidators.values();
        uint256 totalWeight = 0;
        uint256[] memory weights = new uint256[](validators.length);

        // 第一步：计算每个验证者的权重（基于性能）
        for (uint256 i = 0; i < validators.length; i++) {
            address validator = validators[i];

            // 获取验证者性能数据
            (uint64 successfulProposals, uint64 failedProposals,, bool exists) =
                IValidatorPerformanceTracker(PERFORMANCE_TRACKER_ADDR).getValidatorPerformance(validator);

            if (exists && (successfulProposals + failedProposals > 0)) {
                // 计算性能权重（可根据需要调整公式）
                uint256 performance = successfulProposals * 100 / (successfulProposals + failedProposals);
                uint256 stake = _getValidatorCurrentEpochVotingPower(validator);

                // 权重 = 性能 * 质押量（可以根据需要调整）
                weights[i] = performance * stake;
                totalWeight += weights[i];
            }
        }

        // 第二步：根据权重分配奖励
        if (totalWeight > 0) {
            for (uint256 i = 0; i < validators.length; i++) {
                if (weights[i] > 0) {
                    address validator = validators[i];
                    address stakeCreditAddress = validatorInfos[validator].stakeCreditAddress;

                    if (stakeCreditAddress != address(0)) {
                        // 计算该验证者应得奖励
                        uint256 reward = totalIncoming * weights[i] / totalWeight;

                        // 获取佣金率
                        uint64 commissionRate = validatorInfos[validator].commissionRate;

                        // 发送奖励
                        StakeCredit(payable(stakeCreditAddress)).distributeReward{value: reward}(commissionRate);

                        emit RewardsDistributed(validator, reward);
                    }
                }
            }
        }

        // 重置奖励池
        totalIncoming = 0;
    }

    /**
     * @dev 分发最终性奖励给验证者
     * 集成自 StakeReward.distributeFinalityReward()
     */
    function distributeFinalityReward(address[] calldata validators, uint256[] calldata weights)
        external
        onlyCoinbase
        nonReentrant
        whenNotPaused
    {
        // 1. 从系统奖励池获取奖励
        uint256 totalReward = _getFinalityReward();
        if (totalReward == 0) return;

        // 2. 计算总权重
        uint256 totalWeight = 0;
        for (uint256 i = 0; i < weights.length; i++) {
            totalWeight += weights[i];
        }
        if (totalWeight == 0) return;

        // 3. 按权重分配奖励
        for (uint256 i = 0; i < validators.length; i++) {
            address validator = validators[i];

            // 计算该验证者应得奖励
            uint256 validatorReward = totalReward * weights[i] / totalWeight;

            // 获取验证者 StakeCredit 地址
            address stakeCreditAddress = validatorInfos[validator].stakeCreditAddress;

            if (stakeCreditAddress != address(0) && validatorReward > 0) {
                // 获取佣金率
                uint64 commissionRate = validatorInfos[validator].commissionRate;

                // 发送奖励
                StakeCredit(payable(stakeCreditAddress)).distributeReward{value: validatorReward}(commissionRate);

                emit FinalityRewardDistributed(validator, validatorReward);
            }
        }
    }

    /**
     * @dev 获取可用的最终确定奖励
     * 需要根据实际系统设计实现
     */
    function _getFinalityReward() internal returns (uint256) {
        // 实现根据系统设计获取最终确定奖励的逻辑
        // 可以从系统奖励合约调用或使用其他机制
        return 0; // 临时返回值，需要根据实际情况实现
    }

    /**
     * @dev 检查验证者名称是否符合规则
     * @param moniker 验证者名称
     * @return 是否符合规则
     */
    function _checkMoniker(string memory moniker) internal pure returns (bool) {
        bytes memory bz = bytes(moniker);

        // 1. moniker length should be between 3 and 9
        if (bz.length < 3 || bz.length > 9) {
            return false;
        }

        // 2. first character should be uppercase
        if (uint8(bz[0]) < 65 || uint8(bz[0]) > 90) {
            return false;
        }

        // 3. only alphanumeric characters are allowed
        for (uint256 i = 1; i < bz.length; ++i) {
            // Check if the ASCII value of the character falls outside the range of alphanumeric characters
            if (
                (uint8(bz[i]) < 48 || uint8(bz[i]) > 57) && (uint8(bz[i]) < 65 || uint8(bz[i]) > 90)
                    && (uint8(bz[i]) < 97 || uint8(bz[i]) > 122)
            ) {
                // Character is a special character
                return false;
            }
        }

        // No special characters found
        return true;
    }

    /**
     * @dev 检查验证者名称是否已存在
     * @param moniker 验证者名称
     * @return 名称是否已存在
     */
    function isMonikerExists(string calldata moniker) external view returns (bool) {
        bytes32 monikerHash = keccak256(abi.encodePacked(moniker));
        return _monikerSet[monikerHash];
    }

    /**
     * @dev 检查验证者名称是否符合格式要求
     * @param moniker 验证者名称
     * @return 是否符合格式要求
     */
    function checkMonikerFormat(string calldata moniker) external pure returns (bool) {
        return _checkMoniker(moniker);
    }
}
