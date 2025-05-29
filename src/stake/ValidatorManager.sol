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

    /// 对应Aptos的MAX_VALIDATOR_SET_SIZE
    uint64 public constant MAX_VALIDATOR_SET_SIZE = 65536;

    /// 主ValidatorSet数据
    ValidatorSetData public validatorSetData;

    /// 验证者信息映射
    mapping(address => ValidatorInfo) public validatorInfos;

    /// BLS投票地址映射
    mapping(bytes => address) public voteToOperator; // 投票地址 => 操作员地址
    mapping(bytes => uint256) public voteExpiration; // 投票地址 => 过期时间

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

    /*----------------- 修饰符 -----------------*/

    modifier onlyInitialized() {
        if (!initialized) revert NotInitialized();
        _;
    }

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
     * @dev 初始化验证者集合（对应Aptos的initialize函数）
     * @param initialValidators 初始验证者地址
     * @param initialVotingPowers 初始投票权重
     */
    function initialize(address[] calldata initialValidators, uint64[] calldata initialVotingPowers)
        external
        onlySystemCaller
    {
        if (initialized) revert AlreadyInitialized();

        require(initialValidators.length == initialVotingPowers.length, "Array length mismatch");

        initialized = true;

        // 初始化ValidatorSet数据
        validatorSetData = ValidatorSetData({consensusScheme: 0, totalVotingPower: 0, totalJoiningPower: 0});

        // 添加初始验证者
        for (uint256 i = 0; i < initialValidators.length; i++) {
            address validator = initialValidators[i];
            uint64 votingPower = initialVotingPowers[i];

            if (votingPower == 0) revert InvalidVotingPower(votingPower);

            // 创建基本验证者信息
            validatorInfos[validator] = ValidatorInfo({
                consensusPublicKey: "",
                networkAddresses: "",
                fullnodeAddresses: "",
                voteAddress: "", // 初始空BLS地址
                commissionRate: 0,
                moniker: "",
                createdTime: ITimestamp(TIMESTAMP_ADDR).nowSeconds(),
                registered: true,
                stakeCreditAddress: address(0),
                status: ValidatorStatus.ACTIVE,
                votingPower: votingPower,
                validatorIndex: i,
                lastEpochActive: 0
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
        onlyInitialized
    {
        address validator = msg.sender;

        if (validatorInfos[validator].registered) {
            revert ValidatorAlreadyExists(validator);
        }

        // 检查BLS投票地址是否重复
        if (params.voteAddress.length > 0 && voteToOperator[params.voteAddress] != address(0)) {
            revert DuplicateVoteAddress(params.voteAddress);
        }

        // BLS proof验证
        if (params.voteAddress.length > 0 && !_checkVoteAddress(validator, params.voteAddress, params.blsProof)) {
            revert InvalidVoteAddress();
        }

        // 检查最小质押要求
        uint256 minStake = IStakeConfig(STAKE_CONFIG_ADDR).minValidatorStake();
        if (msg.value < minStake) {
            revert InvalidStakeAmount(msg.value, minStake);
        }

        uint256 maxCommissionRate = IStakeConfig(STAKE_CONFIG_ADDR).maxCommissionRate();
        if (params.commissionRate > maxCommissionRate) {
            revert InvalidCommissionRate(params.commissionRate, uint64(maxCommissionRate));
        }

        // 部署StakeCredit合约
        address stakeCreditAddress = _deployStakeCredit(validator, params.moniker);

        // 在AccessControl中注册角色映射
        _registerRoles(validator, params.initialOperator, params.initialVoter, validator);

        // 存储验证者信息（添加voteAddress）
        _storeValidatorInfo(
            validator,
            params.consensusPublicKey,
            params.networkAddresses,
            params.fullnodeAddresses,
            params.voteAddress, // 新增
            params.commissionRate,
            params.moniker,
            stakeCreditAddress,
            ValidatorStatus.INACTIVE
        );

        // 注册投票地址映射
        if (params.voteAddress.length > 0) {
            voteToOperator[params.voteAddress] = validator;
        }

        // 初始质押
        StakeCredit(payable(stakeCreditAddress)).delegate{value: msg.value}(validator);

        emit ValidatorRegistered(validator, msg.sender, validator, params.consensusPublicKey, params.moniker);
        emit StakeCreditDeployed(validator, stakeCreditAddress);
    }

    /**
     * @dev 加入验证者集合（对应Aptos的join_validator_set）
     */
    function joinValidatorSet(address validator) external whenNotPaused onlyInitialized validatorExists(validator) {
        require(
            msg.sender == validator || IAccessControl(ACCESS_CONTROL_ADDR).hasOperatorPermission(validator, msg.sender),
            "Not authorized"
        );

        ValidatorInfo storage info = validatorInfos[validator];

        // 检查当前状态
        if (info.status == ValidatorStatus.ACTIVE || info.status == ValidatorStatus.PENDING_ACTIVE) {
            revert ValidatorAlreadyActive(validator);
        }

        // 检查是否允许验证者集变更
        if (!IStakeConfig(STAKE_CONFIG_ADDR).allowValidatorSetChange()) {
            revert ValidatorSetChangeDisabled();
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
            revert ValidatorSetTooLarge(totalSize, MAX_VALIDATOR_SET_SIZE);
        }

        // 检查投票权增长限制
        _checkVotingPowerIncrease(validator, votingPower);

        // 更新状态到PENDING_ACTIVE
        uint64 oldStatus = uint64(info.status);
        info.status = ValidatorStatus.PENDING_ACTIVE;
        info.votingPower = votingPower;

        // 添加到pending_active集合
        pendingActive.add(validator);
        pendingActiveIndex[validator] = pendingActive.length() - 1;

        // 更新总加入权重
        validatorSetData.totalJoiningPower += votingPower;

        uint64 currentEpoch = uint64(IEpochManager(EPOCH_MANAGER_ADDR).currentEpoch());
        emit ValidatorJoinRequested(validator, votingPower, currentEpoch);
        emit ValidatorStatusChanged(validator, oldStatus, uint64(ValidatorStatus.PENDING_ACTIVE), currentEpoch);
    }

    /**
     * @dev 离开验证者集合（对应Aptos的leave_validator_set）
     */
    function leaveValidatorSet(address validator) external whenNotPaused onlyInitialized validatorExists(validator) {
        require(
            msg.sender == validator || IAccessControl(ACCESS_CONTROL_ADDR).hasOperatorPermission(validator, msg.sender),
            "Not authorized"
        );

        if (!IStakeConfig(STAKE_CONFIG_ADDR).allowValidatorSetChange()) {
            revert ValidatorSetChangeDisabled();
        }

        ValidatorInfo storage info = validatorInfos[validator];
        uint64 currentStatus = uint64(info.status);
        uint64 currentEpoch = uint64(IEpochManager(EPOCH_MANAGER_ADDR).currentEpoch());

        if (currentStatus == uint64(ValidatorStatus.PENDING_ACTIVE)) {
            // 如果还在pending状态，直接移除
            _removeFromPendingActive(validator);
            info.status = ValidatorStatus.INACTIVE;

            emit ValidatorStatusChanged(
                validator, uint64(ValidatorStatus.PENDING_ACTIVE), uint64(ValidatorStatus.INACTIVE), currentEpoch
            );
        } else if (currentStatus == uint64(ValidatorStatus.ACTIVE)) {
            // 检查是否是最后一个验证者
            if (activeValidators.length() <= 1) {
                revert LastValidatorCannotLeave();
            }

            // 移动到pending_inactive
            _moveFromActiveToPendingInactive(validator);
            info.status = ValidatorStatus.PENDING_INACTIVE;

            emit ValidatorStatusChanged(
                validator, uint64(ValidatorStatus.ACTIVE), uint64(ValidatorStatus.PENDING_INACTIVE), currentEpoch
            );
        } else {
            revert ValidatorNotActive(validator);
        }

        emit ValidatorLeaveRequested(validator, currentEpoch);
    }

    /**
     * @dev 新epoch处理（对应Aptos stake.move中on_new_epoch的验证者集合更新部分）
     */
    function onNewEpoch() external onlyStakeHub onlyInitialized {
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
    function getValidatorState(address validator) public view onlyInitialized returns (uint64) {
        if (!validatorInfos[validator].registered) {
            return uint64(ValidatorStatus.INACTIVE);
        }
        return uint64(validatorInfos[validator].status);
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
    function getActiveValidators()
        external
        view
        onlyInitialized
        returns (address[] memory validators, uint64[] memory votingPowers)
    {
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
    function isCurrentValidator(address validator) external view onlyInitialized returns (bool) {
        return validatorInfos[validator].status == ValidatorStatus.ACTIVE;
    }

    /**
     * @dev 获取验证者集合数据
     */
    function getValidatorSetData() external view onlyInitialized returns (ValidatorSetData memory) {
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
        validatorInfos[validator].consensusPublicKey = newConsensusKey;
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
     */
    function updateCommissionRate(address validator, uint64 newCommissionRate)
        external
        validatorExists(validator)
        onlyValidatorOperator(validator)
    {
        uint256 maxCommissionRate = IStakeConfig(STAKE_CONFIG_ADDR).maxCommissionRate();
        if (newCommissionRate > maxCommissionRate) {
            revert InvalidCommissionRate(newCommissionRate, uint64(maxCommissionRate));
        }

        validatorInfos[validator].commissionRate = newCommissionRate;
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
            if (!_checkVoteAddress(validator, newVoteAddress, blsProof)) {
                revert InvalidVoteAddress();
            }

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

        // 设置新的映射
        validatorInfos[validator].voteAddress = newVoteAddress;
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
                validator, uint64(ValidatorStatus.PENDING_ACTIVE), uint64(ValidatorStatus.ACTIVE), currentEpoch
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
                validator, uint64(ValidatorStatus.PENDING_INACTIVE), uint64(ValidatorStatus.INACTIVE), currentEpoch
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
                    validator, uint64(ValidatorStatus.ACTIVE), uint64(ValidatorStatus.INACTIVE), currentEpoch
                );
            }
        }

        // 更新总投票权重
        validatorSetData.totalVotingPower = newTotalVotingPower;
    }

    /**
     * @dev 从pending_active列表中移除验证者
     */
    function _removeFromPendingActive(address validator) internal {
        ValidatorInfo storage info = validatorInfos[validator];

        // 从集合中移除
        pendingActive.remove(validator);
        delete pendingActiveIndex[validator];

        // 更新总加入权重
        validatorSetData.totalJoiningPower -= info.votingPower;
        info.votingPower = 0;
    }

    /**
     * @dev 将验证者从active移动到pending_inactive
     */
    function _moveFromActiveToPendingInactive(address validator) internal {
        ValidatorInfo storage info = validatorInfos[validator];

        // 从active移除
        activeValidators.remove(validator);
        delete activeValidatorIndex[validator];

        // 添加到pending_inactive
        pendingInactive.add(validator);
        pendingInactiveIndex[validator] = pendingInactive.length() - 1;

        // 更新总投票权重
        validatorSetData.totalVotingPower -= info.votingPower;
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
                uint64 oldStatus = uint64(info.status);
                info.status = ValidatorStatus.PENDING_INACTIVE;

                // 添加到pending_inactive集合
                pendingInactive.add(validator);
                pendingInactiveIndex[validator] = pendingInactive.length() - 1;

                // 只更新totalVotingPower
                validatorSetData.totalVotingPower -= info.votingPower;

                uint64 currentEpoch = uint64(IEpochManager(EPOCH_MANAGER_ADDR).currentEpoch());
                emit ValidatorStatusChanged(
                    validator, oldStatus, uint64(ValidatorStatus.PENDING_INACTIVE), currentEpoch
                );
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
            lastEpochActive: 0
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
}
