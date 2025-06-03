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

    // ======== Principal跟踪 ========
    uint256 public validatorPrincipal; // 验证者投入的本金（扣除佣金后）

    bool public hasUnlockRequest;
    uint256 public unlockRequestedAt;

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

        // 初始化principal
        validatorPrincipal = initialAmount;
    }

    /**
     * @dev 添加质押 (对应Aptos add_stake_with_cap)
     * @param delegator 委托人地址
     * @return shares 铸造的份额数量
     */
    function delegate(address delegator) external payable onlyDelegationOrValidatorManager returns (uint256 shares) {
        if (msg.value == 0) revert ZeroAmount();

        // 计算份额（基于当前池子总值）
        uint256 totalPooled = getTotalPooledG();
        if (totalSupply() == 0 || totalPooled == 0) {
            shares = msg.value;
        } else {
            shares = (msg.value * totalSupply()) / totalPooled;
        }

        // 更新状态
        if (_isCurrentEpochValidator()) {
            pendingActive += msg.value;
        } else {
            active += msg.value;
        }

        // 铸造份额
        _mint(delegator, shares);

        emit StakeAdded(delegator, shares, msg.value);
        return shares;
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
    ) external onlyDelegationOrValidatorManager returns (uint256 gAmount) {
        // 基础验证
        if (shares == 0) revert ZeroShares();
        if (shares > balanceOf(delegator)) revert InsufficientBalance();

        // 计算G数量
        gAmount = getPooledGByShares(shares);

        // 简单的状态转换逻辑：优先从active中扣除
        uint256 totalActive = active + pendingActive;
        if (gAmount > totalActive) revert InsufficientActiveStake();

        if (active >= gAmount) {
            active -= gAmount;
        } else {
            // 需要从active和pendingActive中扣除
            uint256 fromActive = active;
            uint256 fromPendingActive = gAmount - fromActive;
            active = 0;
            pendingActive -= fromPendingActive;
        }

        // 移到pending_inactive状态
        pendingInactive += gAmount;

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
     * @dev 提取已解锁的资金
     * @param delegator 委托人地址
     * @param amount 要提取的具体金额（0表示提取全部可用）
     * @return withdrawnAmount 提取的G数量
     */
    function withdraw(
        address payable delegator,
        uint256 amount
    ) external onlyDelegationOrValidatorManager nonReentrant returns (uint256 withdrawnAmount) {
        // 只能从inactive状态提取
        if (inactive == 0) revert NoWithdrawableAmount();

        // 计算delegator的总价值
        uint256 delegatorTotalValue = getPooledGByShares(balanceOf(delegator));
        if (delegatorTotalValue == 0) revert NoWithdrawableAmount();

        // 计算delegator在inactive池中的份额比例对应的金额
        uint256 totalPooled = getTotalPooledG();
        uint256 delegatorInactiveAmount = (delegatorTotalValue * inactive) / totalPooled;
        if (delegatorInactiveAmount == 0) revert NoWithdrawableAmount();

        // 如果amount为0或大于可提取金额，则设置为最大可提取金额
        if (amount == 0 || amount > delegatorInactiveAmount) {
            amount = delegatorInactiveAmount;
        }
        withdrawnAmount = amount;

        // 计算要销毁的份额
        uint256 sharesToBurn = getSharesByPooledG(amount);
        if (sharesToBurn > balanceOf(delegator)) {
            sharesToBurn = balanceOf(delegator);
            withdrawnAmount = getPooledGByShares(sharesToBurn);
        }

        // 更新状态
        inactive -= withdrawnAmount;

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
    function unbond(
        address delegator,
        uint256 shares
    ) external onlyDelegationOrValidatorManager returns (uint256 gAmount) {
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
    ) external onlyDelegationOrValidatorManager returns (uint256 gAmount) {
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
        uint256 totalReward = msg.value;

        // 计算累积奖励（基于principal的增长）
        uint256 totalStake = getTotalPooledG();
        uint256 accumulatedRewards = totalStake > validatorPrincipal ? totalStake - validatorPrincipal : 0;

        // 计算本次奖励应得的佣金
        uint256 newRewards = totalReward;
        uint256 totalRewardsWithAccumulated = accumulatedRewards + newRewards;
        uint256 commission = (totalRewardsWithAccumulated * uint256(commissionRate)) / COMMISSION_RATE_BASE;

        // 限制佣金不超过新奖励
        if (commission > accumulatedRewards) {
            commission = commission - accumulatedRewards;
        } else {
            commission = 0;
        }

        // 更新principal（扣除佣金后的新本金）
        validatorPrincipal = totalStake + totalReward - commission;

        // 奖励直接加到active，让所有份额持有者受益
        active += totalReward;

        // 为佣金受益人铸造佣金份额（稀释其他人）
        if (commission > 0) {
            address beneficiary = commissionBeneficiary == address(0) ? validator : commissionBeneficiary;
            uint256 commissionShares = (commission * totalSupply()) / (totalStake + totalReward);
            _mint(beneficiary, commissionShares);
        }

        // 记录奖励
        uint256 index = ITimestamp(TIMESTAMP_ADDR).nowSeconds() / 86400;
        totalPooledGRecord[index] = getTotalPooledG();
        rewardRecord[index] += totalReward - commission;

        emit RewardReceived(totalReward - commission, commission);
    }

    /**
     * @dev 处理epoch转换 (对应Aptos on_new_epoch中的StakePool更新)
     */
    function onNewEpoch() external onlyValidatorManager {
        uint256 oldActive = active;
        uint256 oldInactive = inactive;
        uint256 oldPendingActive = pendingActive;
        uint256 oldPendingInactive = pendingInactive;

        // 1. pending_active -> active
        active += pendingActive;
        pendingActive = 0;

        // 2. 处理解锁请求
        if (hasUnlockRequest && pendingInactive > 0) {
            inactive += pendingInactive;
            pendingInactive = 0;
            hasUnlockRequest = false;
            unlockRequestedAt = 0;

            emit UnlockRequestProcessed(oldPendingInactive);
        }

        // 不需要遍历delegator或分配奖励
        // 奖励已经在distributeReward时通过增加active实现了

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
}
