// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin-upgrades/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin-upgrades/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin-upgrades/proxy/utils/Initializable.sol";
import "@src/interfaces/IStakeConfig.sol";
import "@src/System.sol";
import "@src/interfaces/IValidatorManager.sol";
import "@src/interfaces/IStakeCredit.sol";
import "@src/interfaces/ITimestamp.sol";
/**
 * Aptos StakePool状态模型：
 * - active: 当前epoch中参与共识的质押
 * - inactive: 可以提取的质押
 * - pending_active: 下一个epoch将变为active的质押
 * - pending_inactive: 下一个epoch将变为inactive的质押
 *
 * 与Aptos的主要对应关系：
 * - 本合约 = Aptos StakePool资源
 * - ERC20份额 = Aptos中质押凭证的概念
 * - 四状态余额 = 直接对应Aptos四个Coin<AptosCoin>字段
 */

contract StakeCredit is Initializable, ERC20Upgradeable, ReentrancyGuardUpgradeable, System, IStakeCredit {
    uint256 private constant COMMISSION_RATE_BASE = 10_000; // 100% (对应Aptos COMMISSION_RATE_BASE)

    // ======== Aptos StakePool四状态模型 ========
    /// 对应Aptos StakePool.active
    uint256 public active;

    /// 对应Aptos StakePool.inactive
    uint256 public inactive;

    /// 对应Aptos StakePool.pending_active
    uint256 public pendingActive;

    /// 对应Aptos StakePool.pending_inactive
    uint256 public pendingInactive;

    // ======== 验证者信息 (对应Aptos operator_address/delegated_voter) ========
    address public stakeHubAddress;
    address public validator;

    // ======== 奖励记录 (对应Aptos distribute_rewards_events) ========
    mapping(uint256 => uint256) public rewardRecord;
    mapping(uint256 => uint256) public totalPooledGRecord;

    // ======== 佣金受益人信息 ========
    address public commissionBeneficiary;

    bool public hasUnlockRequest;
    uint256 public unlockRequestedAt;

    // ======== Delegator状态追踪 ========
    struct DelegatorStateShares {
        uint256 activeShares;
        uint256 inactiveShares;
        uint256 pendingActiveShares;
        uint256 pendingInactiveShares;
    }

    mapping(address => DelegatorStateShares) public delegatorStates;

    // ======== 各状态的总份额追踪 ========
    uint256 public totalActiveShares;
    uint256 public totalInactiveShares;
    uint256 public totalPendingActiveShares;
    uint256 public totalPendingInactiveShares;

    // ======== 状态一致性修饰符 ========
    modifier stateConsistencyCheck() {
        _;
        uint256 totalStates = active + inactive + pendingActive + pendingInactive;
        require(totalStates == address(this).balance, "State inconsistency");
    }

    // 同步修饰符，确保在任何操作前delegator状态已同步
    modifier syncDelegatorState(address delegator) {
        _syncDelegatorState(delegator);
        _;
    }

    constructor() {
        _disableInitializers();
    }

    /**
     * @dev 接收G作为奖励 (对应Aptos distribute_rewards)
     */
    receive() external payable onlyValidatorManager {
        uint256 index = ITimestamp(TIMESTAMP_ADDR).nowSeconds() / 86400; // 按天索引，使用ITimestamp
        totalPooledGRecord[index] = getTotalPooledG();
        rewardRecord[index] += msg.value;
    }

    /**
     * @dev 初始化函数，替代构造函数用于代理模式
     * @param _validator 验证者地址
     * @param _moniker 验证者名称
     * @param _beneficiary 佣金受益人地址
     */
    function initialize(address _validator, string memory _moniker, address _beneficiary) external payable initializer {
        // 初始化ERC20基础部分
        _initializeERC20(_moniker);

        // 设置验证者地址
        validator = _validator;

        // 初始化四状态为0
        _initializeStakeStates();

        // 处理初始质押
        _bootstrapInitialStake(msg.value);

        // 设置佣金受益人
        commissionBeneficiary = _beneficiary;

        emit Initialized(_validator, _moniker, _beneficiary);
    }

    /**
     * @dev 初始化ERC20组件
     */
    function _initializeERC20(string memory _moniker) private {
        string memory name_ = string.concat("Stake ", _moniker, " Credit");
        string memory symbol_ = string.concat("st", _moniker);
        __ERC20_init(name_, symbol_);
        __ReentrancyGuard_init();
    }

    /**
     * @dev 初始化质押状态
     */
    function _initializeStakeStates() private {
        active = 0;
        inactive = 0;
        pendingActive = 0;
        pendingInactive = 0;
    }

    /**
     * @dev 初始化初始质押
     */
    function _bootstrapInitialStake(uint256 _initialAmount) private {
        // 初始化初始质押
        _bootstrapInitialHolder(_initialAmount);
    }

    /**
     * @dev 引导初始质押
     */
    function _bootstrapInitialHolder(uint256 initialAmount) private {
        uint256 toLock = IStakeConfig(STAKE_CONFIG_ADDR).lockAmount();
        if (initialAmount <= toLock || validator == address(0)) {
            revert StakeCredit__WrongInitContext();
        }

        // 铸造初始份额
        _mint(DEAD_ADDRESS, toLock);
        uint256 initShares = initialAmount - toLock;
        _mint(validator, initShares);

        // 更新四状态余额
        active = initialAmount; // 所有初始质押进入active状态
    }

    /**
     * @dev 添加质押 (对应Aptos add_stake_with_cap)
     * @param delegator 委托人地址
     * @return shares 铸造的份额数量
     */
    function delegate(
        address delegator
    ) external payable onlyValidatorManager stateConsistencyCheck returns (uint256 shares) {
        if (msg.value == 0) revert ZeroAmount();

        // 份额计算
        shares = _calculateShares(msg.value);

        // 更新状态 - 使用验证者状态判断
        bool isCurrentValidator = _isCurrentEpochValidator();

        // 如果验证者是当前epoch验证者，新质押进入pending_active
        // 否则直接进入active（验证者不在当前epoch中）
        if (isCurrentValidator) {
            pendingActive += msg.value;
            // 更新delegator的pendingActive份额
            delegatorStates[delegator].pendingActiveShares += shares;
            // 更新总pendingActive份额
            totalPendingActiveShares += shares;
        } else {
            active += msg.value;
            // 更新delegator的active份额
            delegatorStates[delegator].activeShares += shares;
            // 更新总active份额
            totalActiveShares += shares;
        }

        // 铸造份额并发出事件
        _mint(delegator, shares);
        emit StakeAdded(delegator, shares, msg.value);

        return shares;
    }

    /**
     * @dev 计算质押对应的份额
     * @param amount 质押金额
     * @return 份额数量
     */
    function _calculateShares(uint256 amount) private view returns (uint256) {
        uint256 totalPooled = getTotalPooledG();
        if (totalSupply() == 0 || totalPooled == 0) {
            return amount;
        }
        return (amount * totalSupply()) / totalPooled;
    }

    /**
     * @dev 更新质押状态
     * @param amount 质押金额
     */
    function _updateStakeState(uint256 amount) private {
        // 基于验证者当前状态判断资金去向
        bool isCurrentValidator = _isCurrentEpochValidator();

        // 如果验证者是当前epoch验证者，新质押进入pending_active
        // 否则直接进入active（验证者不在当前epoch中）
        if (isCurrentValidator) {
            pendingActive += amount;
        } else {
            active += amount;
        }
    }

    /**
     * @dev 解除质押 (对应Aptos unlock_with_cap)
     * @param delegator 委托人地址
     * @param shares 要解绑的份额数量
     * @return gAmount 解绑的G数量
     */
    function unlock(
        address delegator,
        uint256 shares
    ) external onlyValidatorManager stateConsistencyCheck returns (uint256 gAmount) {
        // 基础验证
        _validateUnlock(delegator, shares);

        // 计算G数量
        gAmount = getPooledGByShares(shares);

        // 获取delegator的状态份额
        DelegatorStateShares storage delegatorState = delegatorStates[delegator];

        // 按比例从各状态中扣除份额
        uint256 totalDelegatorShares = balanceOf(delegator);
        uint256 sharesToUnlock = shares;

        // 优先从active份额中扣除
        if (delegatorState.activeShares > 0) {
            uint256 activeSharesRatio = (delegatorState.activeShares * shares) / totalDelegatorShares;
            uint256 activeToUnlock = activeSharesRatio > delegatorState.activeShares
                ? delegatorState.activeShares
                : activeSharesRatio;

            delegatorState.activeShares -= activeToUnlock;
            delegatorState.pendingInactiveShares += activeToUnlock;
            totalActiveShares -= activeToUnlock;
            totalPendingInactiveShares += activeToUnlock;
            sharesToUnlock -= activeToUnlock;

            // 从active状态移动相应的G到pending_inactive
            uint256 activeGAmount = totalActiveShares > 0 ? (activeToUnlock * active) / totalActiveShares : active;
            active -= activeGAmount;
            pendingInactive += activeGAmount;
        }

        // 如果还有剩余，从pendingActive份额中扣除
        if (sharesToUnlock > 0 && delegatorState.pendingActiveShares > 0) {
            uint256 pendingActiveToUnlock = sharesToUnlock > delegatorState.pendingActiveShares
                ? delegatorState.pendingActiveShares
                : sharesToUnlock;

            delegatorState.pendingActiveShares -= pendingActiveToUnlock;
            delegatorState.pendingInactiveShares += pendingActiveToUnlock;
            totalPendingActiveShares -= pendingActiveToUnlock;
            totalPendingInactiveShares += pendingActiveToUnlock;

            // 从pendingActive状态移动相应的G到pending_inactive
            uint256 pendingActiveGAmount = totalPendingActiveShares > 0
                ? (pendingActiveToUnlock * pendingActive) / totalPendingActiveShares
                : pendingActive;
            pendingActive -= pendingActiveGAmount;
            pendingInactive += pendingActiveGAmount;
        }

        // 销毁份额
        _burn(delegator, shares);

        // 标记解锁请求
        if (!hasUnlockRequest) {
            hasUnlockRequest = true;
            unlockRequestedAt = ITimestamp(TIMESTAMP_ADDR).nowSeconds();
            emit UnlockRequestCreated(unlockRequestedAt);
        }

        emit StakeUnlocked(delegator, shares, gAmount);
        return gAmount;
    }

    /**
     * @dev 验证解锁操作的基础条件
     */
    function _validateUnlock(address delegator, uint256 shares) private view {
        if (shares == 0) revert ZeroShares();
        if (shares > balanceOf(delegator)) revert InsufficientBalance();
    }

    /**
     * @dev 处理解锁的状态更新
     */
    function _processUnlockState(uint256 gAmount) private {
        // 确保有足够的活跃资金可以解锁
        uint256 totalActive = active + pendingActive;
        if (gAmount > totalActive) revert InsufficientActiveStake();

        // 从active状态中减少资金
        if (active >= gAmount) {
            active -= gAmount;
        } else {
            uint256 fromActive = active;
            uint256 fromPendingActive = gAmount - fromActive;

            active = 0;
            if (pendingActive >= fromPendingActive) {
                pendingActive -= fromPendingActive;
            } else {
                revert InsufficientBalance();
            }
        }

        // 移到pending_inactive状态
        pendingInactive += gAmount;

        // 标记解锁请求
        if (!hasUnlockRequest) {
            hasUnlockRequest = true;
            unlockRequestedAt = ITimestamp(TIMESTAMP_ADDR).nowSeconds();
            emit UnlockRequestCreated(unlockRequestedAt);
        }
    }

    /**
     * @dev 提取已解锁的资金
     * @param delegator 委托人地址
     * @param amount 要提取的具体金额（0表示提取全部可用）
     * @return withdrawnAmount 提取的G数量
     */
    function withdraw(
        address payable delegator,
        uint256 amount
    ) external onlyValidatorManager nonReentrant stateConsistencyCheck returns (uint256 withdrawnAmount) {
        // 只能从inactive状态提取
        if (inactive == 0) revert NoWithdrawableAmount();

        // 获取delegator的inactive份额
        DelegatorStateShares storage delegatorState = delegatorStates[delegator];
        if (delegatorState.inactiveShares == 0) revert NoWithdrawableAmount();

        // 计算delegator可提取的金额
        uint256 delegatorInactiveAmount = getPooledGByShares(delegatorState.inactiveShares);
        if (delegatorInactiveAmount == 0) revert NoWithdrawableAmount();

        // 如果amount为0或大于可提取金额，则设置为最大可提取金额
        if (amount == 0 || amount > delegatorInactiveAmount) {
            amount = delegatorInactiveAmount;
        }

        // 计算要销毁的份额
        withdrawnAmount = amount;
        uint256 sharesToBurn = getSharesByPooledG(amount);

        // 再次检查份额是否足够（安全检查）
        if (sharesToBurn > delegatorState.inactiveShares) {
            sharesToBurn = delegatorState.inactiveShares;
            withdrawnAmount = getPooledGByShares(sharesToBurn);
        }

        // 更新状态
        inactive -= withdrawnAmount;
        delegatorState.inactiveShares -= sharesToBurn;
        totalInactiveShares -= sharesToBurn;

        // 销毁对应份额
        _burn(delegator, sharesToBurn);

        // 转账
        (bool success, ) = delegator.call{ value: withdrawnAmount }("");
        if (!success) revert TransferFailed();

        emit StakeWithdrawn(delegator, withdrawnAmount);
        return withdrawnAmount;
    }

    /**
     * @dev 立即解绑质押而不进入队列，仅用于重新委托流程
     * @param delegator 委托人地址
     * @param shares 要解绑的份额数量
     * @return gAmount 解绑的G数量
     */
    function unbond(address delegator, uint256 shares) external onlyValidatorManager returns (uint256 gAmount) {
        if (shares == 0) revert ZeroShares();
        if (shares > balanceOf(delegator)) revert InsufficientBalance();

        // 计算G数量
        gAmount = getPooledGByShares(shares);

        // 销毁份额
        _burn(delegator, shares);

        // 从active状态中减少资金
        if (active >= gAmount) {
            active -= gAmount;
        } else {
            uint256 fromActive = active;
            uint256 fromPendingActive = gAmount - fromActive;
            active = 0;
            if (pendingActive >= fromPendingActive) {
                pendingActive -= fromPendingActive;
            } else {
                revert InsufficientBalance();
            }
        }

        // 直接转给调用者(Delegation合约)
        (bool success, ) = msg.sender.call{ value: gAmount }("");
        if (!success) revert TransferFailed();

        return gAmount;
    }

    /**
     * @dev 重新激活待解除的质押 (对应Aptos reactivate_stake_with_cap)
     * @param delegator 委托人地址
     * @param shares 要重新激活的份额数量
     * @return gAmount 重新激活的G数量
     */
    function reactivateStake(
        address delegator,
        uint256 shares
    ) external onlyValidatorManager returns (uint256 gAmount) {
        if (shares == 0) revert ZeroShares();
        if (pendingInactive == 0) revert NoWithdrawableAmount();

        // 计算delegator在pendingInactive池中的可重新激活金额
        uint256 delegatorShares = balanceOf(delegator);
        if (delegatorShares == 0) revert InsufficientBalance();

        uint256 delegatorPendingInactiveAmount = (delegatorShares * pendingInactive) / totalSupply();
        if (delegatorPendingInactiveAmount == 0) revert NoWithdrawableAmount();

        // 计算G数量，确保不超过用户在pendingInactive中的份额
        gAmount = getPooledGByShares(shares);
        if (gAmount > delegatorPendingInactiveAmount) {
            gAmount = delegatorPendingInactiveAmount;
        }

        // 从pendingInactive移到active
        if (pendingInactive >= gAmount) {
            pendingInactive -= gAmount;
            active += gAmount;

            emit StakeReactivated(delegator, shares, gAmount);
            return gAmount;
        } else {
            revert InsufficientBalance();
        }
    }

    /**
     * @dev 分配奖励 (对应Aptos distribute_rewards)
     * @param commissionRate 佣金率
     */
    function distributeReward(uint64 commissionRate) external payable onlyValidatorManager {
        uint256 gAmount = msg.value;
        uint256 commission = (gAmount * uint256(commissionRate)) / COMMISSION_RATE_BASE;
        uint256 reward = gAmount - commission;

        uint256 index = ITimestamp(TIMESTAMP_ADDR).nowSeconds() / 86400; // 使用ITimestamp
        totalPooledGRecord[index] = getTotalPooledG();
        rewardRecord[index] += reward;

        // 立即分配奖励到eligible状态（active和pendingInactive）
        uint256 totalEligible = active + pendingInactive;
        if (totalEligible > 0) {
            uint256 activeReward = (reward * active) / totalEligible;
            uint256 pendingInactiveReward = reward - activeReward;

            active += activeReward;
            pendingInactive += pendingInactiveReward;
        } else {
            // 如果没有eligible状态的质押，奖励全部进入active
            active += reward;
        }

        // 为佣金受益人铸造佣金份额
        if (commission > 0) {
            uint256 totalPooled = getTotalPooledG();
            uint256 commissionShares = totalSupply() > 0 ? (commission * totalSupply()) / totalPooled : commission;

            // 获取佣金受益人地址，如果未设置则默认为validator
            address beneficiary = commissionBeneficiary == address(0) ? validator : commissionBeneficiary;

            _mint(beneficiary, commissionShares);

            // 佣金直接加到active中
            active += commission;
        }

        emit RewardReceived(reward, commission);
    }

    /**
     * @dev 处理epoch转换 (对应Aptos on_new_epoch中的StakePool更新)
     */
    function onNewEpoch() external onlyValidatorManager stateConsistencyCheck {
        uint256 oldActive = active;
        uint256 oldInactive = inactive;
        uint256 oldPendingActive = pendingActive;
        uint256 oldPendingInactive = pendingInactive;

        // 保存epoch转换的时间戳，用于延迟处理
        uint256 epochTransitionTimestamp = ITimestamp(TIMESTAMP_ADDR).nowSeconds();

        // 1. pending_active -> active (新质押生效)
        active += pendingActive;
        pendingActive = 0;

        // 2. 处理解锁请求，将pending_inactive -> inactive
        bool processed = false;
        if (hasUnlockRequest && pendingInactive > 0) {
            uint256 amountProcessed = pendingInactive;
            inactive += pendingInactive;
            pendingInactive = 0;
            hasUnlockRequest = false;
            unlockRequestedAt = 0;
            processed = true;

            emit UnlockRequestProcessed(amountProcessed);
        }

        // 3. 验证状态一致性
        uint256 newTotal = active + inactive + pendingActive + pendingInactive;
        uint256 oldTotal = oldActive + oldInactive + oldPendingActive + oldPendingInactive;
        if (newTotal != oldTotal) revert StateTransitionError();

        // 存储本次epoch转换信息，用于延迟处理
        lastEpochTransition = EpochTransitionInfo({ timestamp: epochTransitionTimestamp, unlockProcessed: processed });

        emit EpochTransitioned(
            oldActive,
            oldInactive,
            oldPendingActive,
            oldPendingInactive,
            active,
            inactive,
            pendingActive,
            pendingInactive
        );
    }

    // 存储上次epoch转换的信息
    struct EpochTransitionInfo {
        uint256 timestamp;
        bool unlockProcessed;
    }

    EpochTransitionInfo public lastEpochTransition;

    /**
     * @dev 批量处理delegator状态转换
     * @param delegators 要处理的delegator地址数组
     */
    function processDelegatorStates(address[] calldata delegators) external onlyValidatorManager {
        for (uint256 i = 0; i < delegators.length; i++) {
            _processDelegatorState(delegators[i]);
        }
    }

    /**
     * @dev 处理单个delegator的状态转换
     * @param delegator delegator地址
     */
    function _processDelegatorState(address delegator) internal {
        DelegatorStateShares storage state = delegatorStates[delegator];

        // pending_active -> active
        if (state.pendingActiveShares > 0) {
            state.activeShares += state.pendingActiveShares;
            totalActiveShares += state.pendingActiveShares;
            totalPendingActiveShares -= state.pendingActiveShares;
            state.pendingActiveShares = 0;
        }

        // pending_inactive -> inactive (如果已处理)
        if (!hasUnlockRequest && state.pendingInactiveShares > 0) {
            state.inactiveShares += state.pendingInactiveShares;
            totalInactiveShares += state.pendingInactiveShares;
            totalPendingInactiveShares -= state.pendingInactiveShares;
            state.pendingInactiveShares = 0;
        }
    }

    /**
     * @dev 强制处理待解除质押 (验证者退出时使用)
     */
    function forceProcessPendingInactive() external onlyValidatorManager {
        if (pendingInactive > 0) {
            inactive += pendingInactive;
            pendingInactive = 0;
        }
    }

    // ======== 查询函数 (对应Aptos view函数) ========

    /**
     * @dev 获取份额对应的G数量 (对应Aptos get_stake)
     */
    function getPooledGByShares(uint256 shares) public view returns (uint256) {
        uint256 totalPooled = getTotalPooledG();
        if (totalSupply() == 0) revert ZeroTotalShares();
        return (shares * totalPooled) / totalSupply();
    }

    /**
     * @dev 获取G数量对应的份额
     */
    function getSharesByPooledG(uint256 gAmount) public view returns (uint256) {
        uint256 totalPooled = getTotalPooledG();
        if (totalPooled == 0) revert ZeroTotalPooledTokens();
        return (gAmount * totalSupply()) / totalPooled;
    }

    /**
     * @dev 获取总质押G (对应Aptos所有状态的总和)
     */
    function getTotalPooledG() public view returns (uint256) {
        return active + inactive + pendingActive + pendingInactive;
    }

    /**
     * @dev 获取四状态余额 (对应Aptos get_stake)
     * @return (active, inactive, pending_active, pending_inactive)
     */
    function getStake() external view returns (uint256, uint256, uint256, uint256) {
        return (active, inactive, pendingActive, pendingInactive);
    }

    /**
     * @dev 获取下一epoch的投票权
     */
    function getNextEpochVotingPower() external view returns (uint256) {
        return active + pendingActive;
    }

    /**
     * @dev 获取当前epoch投票权 (当前active + pending_inactive)
     */
    function getCurrentEpochVotingPower() external view returns (uint256) {
        return active + pendingInactive;
    }

    function getPooledGByDelegator(address delegator) public view returns (uint256) {
        return getPooledGByShares(balanceOf(delegator));
    }

    /**
     * @dev 检查验证者是否为当前epoch验证者
     * 通过调用ValidatorManager合约判断
     */
    function _isCurrentEpochValidator() internal view returns (bool) {
        // 使用ValidatorManager合约进行判断
        return IValidatorManager(VALIDATOR_MANAGER_ADDR).isCurrentEpochValidator(validator);
    }

    function _getUnbondPeriod() internal view returns (uint256) {
        return IStakeConfig(STAKE_CONFIG_ADDR).recurringLockupDuration();
    }

    // ======== ERC20重写 (禁止转账) ========

    function _update(address from, address to, uint256 value) internal virtual override {
        if (from != address(0) && to != address(0)) {
            revert TransferNotAllowed();
        }
        super._update(from, to, value);
    }

    function _approve(address, address, uint256, bool) internal virtual override {
        revert ApproveNotAllowed();
    }

    /**
     * @dev 验证质押状态是否一致
     * @return 状态是否一致
     */
    function validateStakeStates() external view returns (bool) {
        // 验证四个状态的总和等于合约余额
        uint256 totalStates = active + inactive + pendingActive + pendingInactive;
        return totalStates == address(this).balance;
    }

    function getDetailedStakeInfo()
        external
        view
        returns (
            uint256 _active,
            uint256 _inactive,
            uint256 _pendingActive,
            uint256 _pendingInactive,
            uint256 _totalPooled,
            uint256 _contractBalance,
            uint256 _totalShares,
            bool _hasUnlockRequest
        )
    {
        return (
            active,
            inactive,
            pendingActive,
            pendingInactive,
            getTotalPooledG(),
            address(this).balance,
            totalSupply(),
            hasUnlockRequest
        );
    }

    /**
     * @dev 更新佣金受益人地址
     * @param newBeneficiary 新的佣金受益人地址
     */
    function updateBeneficiary(address newBeneficiary) external {
        // 只有validator自己可以调用
        if (msg.sender != validator) {
            revert StakeCredit__UnauthorizedCaller();
        }

        address oldBeneficiary = commissionBeneficiary;
        commissionBeneficiary = newBeneficiary;

        emit BeneficiaryUpdated(validator, oldBeneficiary, newBeneficiary);
    }

    /**
     * @dev 返回当前解锁请求的状态
     * @return hasRequest 是否有未处理的解锁请求
     * @return requestedAt 解锁请求的时间戳
     */
    function getUnlockRequestStatus() external view returns (bool hasRequest, uint256 requestedAt) {
        return (hasUnlockRequest, unlockRequestedAt);
    }

    /**
     * @dev 同步单个delegator的状态
     * @param delegator delegator地址
     */
    function _syncDelegatorState(address delegator) internal {
        DelegatorStateShares storage state = delegatorStates[delegator];

        // 检查是否需要同步
        if (lastEpochTransition.timestamp > 0) {
            // 1. 处理pending_active -> active转换
            if (state.pendingActiveShares > 0) {
                state.activeShares += state.pendingActiveShares;
                totalActiveShares += state.pendingActiveShares;
                totalPendingActiveShares -= state.pendingActiveShares;
                state.pendingActiveShares = 0;
            }

            // 2. 处理pending_inactive -> inactive转换(如果解锁已处理)
            if (lastEpochTransition.unlockProcessed && state.pendingInactiveShares > 0) {
                state.inactiveShares += state.pendingInactiveShares;
                totalInactiveShares += state.pendingInactiveShares;
                totalPendingInactiveShares -= state.pendingInactiveShares;
                state.pendingInactiveShares = 0;
            }
        }
    }
}
