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

    /// 待分配的奖励池
    uint256 public pendingRewards;

    /// 对应Aptos StakePool.locked_until_secs
    uint256 public lockedUntilSecs;

    // ======== 验证者信息 (对应Aptos operator_address/delegated_voter) ========
    address public stakeHubAddress;
    address public validator;

    // ======== 奖励记录 (对应Aptos distribute_rewards_events) ========
    mapping(uint256 => uint256) public rewardRecord;
    mapping(uint256 => uint256) public totalPooledGRecord;

    constructor() {
        _disableInitializers();
    }

    /**
     * @dev 接收G作为奖励 (对应Aptos distribute_rewards)
     */
    receive() external payable onlyStakeHub {
        uint256 index = ITimestamp(TIMESTAMP_ADDR).nowSeconds() / 86400; // 按天索引，使用ITimestamp
        totalPooledGRecord[index] = getTotalPooledG();
        rewardRecord[index] += msg.value;

        // 奖励先存入待分配池，而不是直接加到active中
        pendingRewards += msg.value;
    }

    /**
     * @dev 初始化函数，替代构造函数用于代理模式
     * @param _validator 验证者地址
     * @param _moniker 验证者名称
     */
    function initialize(address _validator, string memory _moniker) external payable override initializer {
        // 初始化ERC20基础部分
        _initializeERC20(_moniker);

        // 设置验证者地址
        validator = _validator;

        // 初始化四状态为0
        _initializeStakeStates();

        // 设置初始锁定期并处理初始质押
        _initializeLockupAndStake(_validator, msg.value);

        emit Initialized(_validator, _moniker);
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
     * @dev 初始化锁定期和初始质押
     */
    function _initializeLockupAndStake(address _validator, uint256 _initialAmount) private {
        // 初始化时不设置锁定期，等验证者加入验证者集合时再设置
        lockedUntilSecs = 0;

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
    function delegate(address delegator) external payable onlyStakeHub returns (uint256 shares) {
        if (msg.value == 0) revert ZeroAmount();

        // 份额计算
        shares = _calculateShares(msg.value);

        // 更新状态 - 使用验证者状态判断
        _updateStakeState(msg.value);

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
    function unlock(address delegator, uint256 shares) external onlyStakeHub returns (uint256 gAmount) {
        // 基础验证
        _validateUnlock(delegator, shares);

        // 计算G数量
        gAmount = getPooledGByShares(shares);

        // 验证并更新资金状态
        _processUnlockState(gAmount);

        // 销毁份额
        _burn(delegator, shares);

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
    ) external onlyStakeHub nonReentrant returns (uint256 withdrawnAmount) {
        // 1. 首先检查并处理锁定期状态转换
        _checkAndProcessLockup();

        // 2. 只能从inactive状态提取
        if (inactive == 0) revert NoWithdrawableAmount();

        // 3. 计算delegator在inactive池中的可提取金额
        uint256 delegatorShares = balanceOf(delegator);
        if (delegatorShares == 0) revert InsufficientBalance();

        uint256 delegatorInactiveAmount = (delegatorShares * inactive) / totalSupply();
        if (delegatorInactiveAmount == 0) revert NoWithdrawableAmount();

        // 4. 如果amount为0或大于可提取金额，则设置为最大可提取金额
        if (amount == 0 || amount > delegatorInactiveAmount) {
            amount = delegatorInactiveAmount;
        }

        // 5. 计算要销毁的份额
        withdrawnAmount = amount;
        uint256 sharesToBurn = (amount * totalSupply()) / getTotalPooledG();

        // 6. 再次检查delegator份额是否足够（安全检查）
        if (sharesToBurn > delegatorShares) {
            revert InsufficientBalance();
        }

        // 7. 更新状态 - 从inactive中减少
        inactive -= withdrawnAmount;

        // 8. 销毁对应份额
        _burn(delegator, sharesToBurn);

        // 9. 转账
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
    function unbond(address delegator, uint256 shares) external onlyStakeHub returns (uint256 gAmount) {
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
    function reactivateStake(address delegator, uint256 shares) external onlyStakeHub returns (uint256 gAmount) {
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
    function distributeReward(uint64 commissionRate) external payable onlyStakeHub {
        uint256 gAmount = msg.value;
        uint256 commission = (gAmount * uint256(commissionRate)) / COMMISSION_RATE_BASE;
        uint256 reward = gAmount - commission;

        uint256 index = ITimestamp(TIMESTAMP_ADDR).nowSeconds() / 86400; // 使用ITimestamp
        totalPooledGRecord[index] = getTotalPooledG();
        rewardRecord[index] += reward;

        // 奖励加到待分配池中，而不是直接加到active
        pendingRewards += reward;

        // 为佣金受益人铸造佣金份额
        if (commission > 0) {
            uint256 totalPooled = getTotalPooledG();
            uint256 commissionShares = totalSupply() > 0 ? (commission * totalSupply()) / totalPooled : commission;

            // 获取佣金受益人地址
            address beneficiary = IValidatorManager(VALIDATOR_MANAGER_ADDR).getCommissionBeneficiary(validator);

            _mint(beneficiary, commissionShares);

            // 佣金直接加到active中
            active += commission;
        }

        emit RewardReceived(reward, commission);
    }

    /**
     * @dev 处理epoch转换 (对应Aptos on_new_epoch中的StakePool更新)
     */
    function onNewEpoch() external onlyStakeHub {
        uint256 oldActive = active;
        uint256 oldInactive = inactive;
        uint256 oldPendingActive = pendingActive;
        uint256 oldPendingInactive = pendingInactive;

        // 1. 先分配累积的奖励
        _distributeAccumulatedRewards();

        // 2. pending_active -> active (新质押生效)
        active += pendingActive;
        pendingActive = 0;

        // 3. 检查锁定期，如果到期则 pending_inactive -> inactive
        _checkAndProcessLockup();

        // 4. 更新锁定期（仅针对活跃验证者）
        _updateLockupIfNeeded();

        // 5. 验证状态一致性
        uint256 newTotal = active + inactive + pendingActive + pendingInactive + pendingRewards;
        uint256 oldTotal = oldActive + oldInactive + oldPendingActive + oldPendingInactive + pendingRewards;
        if (newTotal != oldTotal) revert StateTransitionError();

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

    /**
     * @dev 分配累积的奖励
     */
    function _distributeAccumulatedRewards() internal {
        if (pendingRewards == 0) return;

        // 只给 active 和 pending_inactive 分配奖励（符合 Aptos 模型）
        uint256 totalEligible = active + pendingInactive;

        if (totalEligible > 0) {
            // 按比例分配奖励
            uint256 activeReward = (pendingRewards * active) / totalEligible;
            uint256 pendingInactiveReward = pendingRewards - activeReward;

            active += activeReward;
            pendingInactive += pendingInactiveReward;

            emit RewardDistributed(activeReward, pendingInactiveReward);
        } else {
            // 如果没有合格的质押，奖励直接进入 active
            active += pendingRewards;
            emit RewardDistributed(pendingRewards, 0);
        }

        // 重置待分配奖励
        pendingRewards = 0;
    }

    /**
     * @dev 更新锁定期（如果需要）
     * 对应Aptos的on_new_epoch中的锁定期更新逻辑
     */
    function _updateLockupIfNeeded() internal {
        // 只有当验证者为当前epoch验证者时才更新锁定期
        bool isCurrentValidator = _isCurrentEpochValidator();
        if (isCurrentValidator) {
            uint256 currentTime = ITimestamp(TIMESTAMP_ADDR).nowSeconds();

            // 对应Aptos的条件: if (locked_until_secs <= reconfig_start_secs)
            if (lockedUntilSecs <= currentTime) {
                uint256 newLockupTime = currentTime + IStakeConfig(STAKE_CONFIG_ADDR).recurringLockupDuration();

                // 区分首次设置和续期
                if (lockedUntilSecs == 0) {
                    emit LockupStarted(newLockupTime);
                } else {
                    emit LockupRenewed(newLockupTime);
                }

                lockedUntilSecs = newLockupTime;
            }
        }
    }

    /**
     * @dev 强制处理待解除质押 (验证者退出时使用)
     */
    function forceProcessPendingInactive() external onlyStakeHub {
        if (pendingInactive > 0) {
            inactive += pendingInactive;
            pendingInactive = 0;
        }
    }

    /**
     * @dev 延长锁定期 (对应Aptos increase_lockup)
     * @param newLockUntil 新的锁定期结束时间
     */
    function increaseLockup(uint256 newLockUntil) external onlyStakeHub {
        if (newLockUntil <= lockedUntilSecs) revert LockupNotExpired();
        uint256 oldLockup = lockedUntilSecs;
        lockedUntilSecs = newLockUntil;
    }

    /**
     * @dev 更新验证者锁定期
     */
    function renewLockup() external onlyStakeHub {
        if (lockedUntilSecs == 0) {
            // 如果还没有锁定期，调用激活函数
            if (_isCurrentEpochValidator()) {
                lockedUntilSecs =
                    ITimestamp(TIMESTAMP_ADDR).nowSeconds() +
                    IStakeConfig(STAKE_CONFIG_ADDR).recurringLockupDuration();
                emit LockupStarted(lockedUntilSecs);
            }
        } else {
            // 已有锁定期，续期
            uint256 newLockupTime = ITimestamp(TIMESTAMP_ADDR).nowSeconds() +
                IStakeConfig(STAKE_CONFIG_ADDR).recurringLockupDuration();
            lockedUntilSecs = newLockupTime;
            emit LockupRenewed(newLockupTime);
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

    /**
     * @dev 获取剩余锁定时间 (对应Aptos get_remaining_lockup_secs)
     */
    function getRemainingLockupSecs() external view returns (uint256) {
        uint256 currentTime = ITimestamp(TIMESTAMP_ADDR).nowSeconds(); // 使用ITimestamp
        if (lockedUntilSecs <= currentTime) {
            return 0;
        }
        return lockedUntilSecs - currentTime;
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
     * @dev 检查和处理锁定期状态
     */
    function _checkAndProcessLockup() internal {
        uint256 currentTime = ITimestamp(TIMESTAMP_ADDR).nowSeconds(); // 使用ITimestamp
        if (currentTime >= lockedUntilSecs && pendingInactive > 0) {
            inactive += pendingInactive;
            pendingInactive = 0;
            // 不自动续期，由外部调用renewLockup
        }
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
            bool _isLocked
        )
    {
        uint256 currentTime = ITimestamp(TIMESTAMP_ADDR).nowSeconds(); // 使用ITimestamp
        return (
            active,
            inactive,
            pendingActive,
            pendingInactive,
            getTotalPooledG(),
            address(this).balance,
            totalSupply(),
            currentTime < lockedUntilSecs
        );
    }
}
