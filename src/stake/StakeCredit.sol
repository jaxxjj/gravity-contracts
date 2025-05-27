// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin-upgrades/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin-upgrades/utils/ReentrancyGuardUpgradeable.sol";
import "@src/interfaces/IStakeConfig.sol";
import "@src/interfaces/IAccessControl.sol";
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

contract StakeCredit is ERC20Upgradeable, ReentrancyGuardUpgradeable, System, IStakeCredit {
    uint256 private constant COMMISSION_RATE_BASE = 10_000; // 100% (对应Aptos COMMISSION_RATE_BASE)

    bool private _initialized;

    // ======== Aptos StakePool四状态模型 ========
    /// 对应Aptos StakePool.active
    uint256 public active;

    /// 对应Aptos StakePool.inactive
    uint256 public inactive;

    /// 对应Aptos StakePool.pending_active
    uint256 public pendingActive;

    /// 对应Aptos StakePool.pending_inactive
    uint256 public pendingInactive;

    /// 对应Aptos StakePool.locked_until_secs
    uint256 public lockedUntilSecs;

    // ======== 验证者信息 (对应Aptos operator_address/delegated_voter) ========
    address public stakeHubAddress;
    address public validator;

    // ======== 奖励记录 (对应Aptos distribute_rewards_events) ========
    mapping(uint256 => uint256) public rewardRecord;
    mapping(uint256 => uint256) public totalPooledGRecord;

    /**
     * @dev 接收ETH作为奖励 (对应Aptos distribute_rewards)
     */
    receive() external payable onlyStakeHub {
        uint256 index = ITimestamp(TIMESTAMP_ADDR).nowSeconds() / 86400; // 按天索引，使用ITimestamp
        totalPooledGRecord[index] = getTotalPooledG();
        rewardRecord[index] += msg.value;

        // 奖励直接加到active中 (对应Aptos逻辑)
        active += msg.value;
    }

    /**
     * @dev 初始化函数，替代构造函数用于代理模式
     * @param _validator 验证者地址
     * @param _moniker 验证者名称
     */
    function initialize(address _validator, string memory _moniker) external payable override {
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
        // 设置初始锁定期
        lockedUntilSecs = ITimestamp(TIMESTAMP_ADDR).nowSeconds() + IStakeConfig(STAKE_CONFIG_ADDR).recurringLockupDuration(); // 使用ITimestamp

        // 初始化初始质押
        _bootstrapInitialHolder(_initialAmount);
    }

    /**
     * @dev 引导初始质押
     */
    function _bootstrapInitialHolder(uint256 initialAmount) private {
        uint256 toLock = IStakeConfig(STAKE_CONFIG_ADDR).LOCK_AMOUNT();
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

        // 更新状态
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
        // 如果验证者当前有active或pending_inactive（即参与当前epoch），新质押进入pending_active
        // 否则直接进入active（验证者不在当前epoch中）
        if (active > 0 || pendingInactive > 0) {
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
     * @param shares 要提取的份额数量（0表示提取全部可用）
     * @return withdrawnAmount 提取的G数量
     */
    function withdraw(address payable delegator, uint256 shares)
        external
        onlyStakeHub
        nonReentrant
        returns (uint256 withdrawnAmount)
    {
        // 1. 首先检查并处理锁定期状态转换
        _checkAndProcessLockup();

        // 2. 只能从inactive状态提取
        if (inactive == 0) revert NoWithdrawableAmount();

        // 3. 如果shares为0，计算delegator应得的inactive部分
        if (shares == 0) {
            // 计算delegator在总pool中的比例
            uint256 delegatorBalance = balanceOf(delegator);
            uint256 totalShares = totalSupply();
            if (totalShares == 0 || delegatorBalance == 0) revert NoWithdrawableAmount();

            // 计算delegator可提取的inactive金额
            withdrawnAmount = (inactive * delegatorBalance) / totalShares;
            shares = delegatorBalance;
        } else {
            // 4. 检查delegator余额
            if (shares > balanceOf(delegator)) revert InsufficientBalance();
            withdrawnAmount = getPooledGByShares(shares);

            // 5. 检查是否超过delegator应得的inactive部分
            uint256 delegatorBalance = balanceOf(delegator);
            uint256 totalShares = totalSupply();
            uint256 maxWithdrawable = (inactive * delegatorBalance) / totalShares;

            if (withdrawnAmount > maxWithdrawable) {
                withdrawnAmount = maxWithdrawable;
                shares = getSharesByPooledG(withdrawnAmount);
            }
        }

        if (withdrawnAmount == 0) revert NoWithdrawableAmount();

        // 6. 更新状态 - 从inactive中减少
        inactive -= withdrawnAmount;

        // 7. 销毁对应份额
        _burn(delegator, shares);

        // 8. 转账
        (bool success,) = delegator.call{value: withdrawnAmount}("");
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
        (bool success,) = msg.sender.call{value: gAmount}("");
        if (!success) revert TransferFailed();

        return gAmount;
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

        // 奖励加到active中
        active += reward;

        // 为佣金受益人铸造佣金份额
        if (commission > 0) {
            uint256 totalPooled = getTotalPooledG();
            uint256 commissionShares = totalSupply() > 0 ? (commission * totalSupply()) / totalPooled : commission;

            // 获取佣金受益人地址
            address beneficiary = IAccessControl(ACCESS_CONTROL_ADDR).getCommissionBeneficiary(validator);

            _mint(beneficiary, commissionShares);
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

        // 1. pending_active -> active (新质押生效)
        active += pendingActive;
        pendingActive = 0;

        // 2. 检查锁定期，如果到期则 pending_inactive -> inactive
        _checkAndProcessLockup();

        // 3. 验证状态一致性
        uint256 newTotal = active + inactive + pendingActive + pendingInactive;
        uint256 oldTotal = oldActive + oldInactive + oldPendingActive + oldPendingInactive;
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
        emit LockupIncreased(oldLockup, newLockUntil);
    }

    /**
     * @dev 更新验证者锁定期
     */
    function renewLockup() external onlyStakeHub {
        uint256 newLockupTime = ITimestamp(TIMESTAMP_ADDR).nowSeconds() + IStakeConfig(STAKE_CONFIG_ADDR).recurringLockupDuration(); // 使用ITimestamp
        lockedUntilSecs = newLockupTime;
        emit LockupRenewed(newLockupTime);
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


    function _isCurrentEpochValidator() internal view returns (bool) {
        // 基于自身状态判断
        // 如果有active质押或pendingInactive质押(即当前epoch仍有投票权)，则认为是当前epoch的验证者
        return (active > 0 || pendingInactive > 0);
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

    function getOperator() public view returns (address) {
        return IAccessControl(ACCESS_CONTROL_ADDR).getOperator(validator);
    }

    function getDelegatedVoter() public view returns (address) {
        return IAccessControl(ACCESS_CONTROL_ADDR).getDelegatedVoter(validator);
    }

    function getCommissionBeneficiary() public view returns (address) {
        return IAccessControl(ACCESS_CONTROL_ADDR).getCommissionBeneficiary(validator);
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
