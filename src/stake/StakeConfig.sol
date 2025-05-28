// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@src/System.sol";
import "@src/interfaces/IStakeConfig.sol";
import "@src/interfaces/IParamSubscriber.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin-upgrades/proxy/utils/Initializable.sol";

/**
 * @title StakeConfig
 * @dev 完全对应Aptos staking_config.move的StakingConfig和StakingRewardsConfig
 *
 * 对应Aptos的主要结构：
 * - StakingConfig: 基础质押配置
 * - StakingRewardsConfig: 奖励配置
 * - get_required_stake: 获取质押要求
 * - get_reward_rate: 获取奖励率
 * - calculate_rewards_amount: 计算奖励数量
 */
contract StakeConfig is System, IStakeConfig, IParamSubscriber, Initializable {
    // ======== 常量定义 (对应Aptos常量) ========

    // 验证者状态常量 (对应Aptos stake.move)
    uint256 public constant VALIDATOR_STATUS_PENDING_ACTIVE = 1;
    uint256 public constant VALIDATOR_STATUS_ACTIVE = 2;
    uint256 public constant VALIDATOR_STATUS_PENDING_INACTIVE = 3;
    uint256 public constant VALIDATOR_STATUS_INACTIVE = 4;

    // 百分比基数
    uint256 public constant PERCENTAGE_BASE = 10000; // 100.00%

    // 对应Aptos MAX_REWARDS_RATE
    uint256 public constant MAX_REWARDS_RATE = 1000000;

    // 对应Aptos MAX_U64
    uint128 public constant MAX_U64 = type(uint64).max;

    // 验证者锁定金额 (类似于保证金)
    uint256 public constant LOCK_AMOUNT = 1 ether;

    // 验证者集合最大大小 (最多45个验证者)
    uint64 public constant MAX_VALIDATOR_COUNT_LIMIT = 45;

    // ======== 质押配置参数 (对应Aptos StakingConfig) ========

    // 对应Aptos minimum_stake, maximum_stake
    uint256 public minValidatorStake; // 验证人最低质押量
    uint256 public maximumStake; // 验证人最大质押量
    uint256 public minDelegationStake; // 委托人最低质押量
    uint256 public minDelegationChange; // 委托人最小变更量
    uint256 public redelegateFeeRate; // 重新委托手续费率

    // 对应Aptos max_validator_count
    uint256 public maxValidatorCount; // 验证人集合的最大大小

    // 对应Aptos recurring_lockup_duration_secs
    uint256 public recurringLockupDuration; // 解绑等待期（秒）

    // 对应Aptos allow_validator_set_change
    bool public allowValidatorSetChange; // 是否允许验证人加入/离开集合

    // 对应Aptos voting_power_increase_limit
    uint256 public votingPowerIncreaseLimit; // 每个纪元最大投票权增长百分比

    // 对应Aptos rewards_rate, rewards_rate_denominator
    uint256 public rewardsRate; // 基础奖励率
    uint256 public rewardsRateDenominator; // 奖励率分母

    // 佣金相关 (对应Aptos中的commission逻辑)
    uint256 public maxCommissionRate; // 最大佣金率
    uint256 public maxCommissionChangeRate; // 最大佣金变更率

    /**
     * @dev 禁用构造函数
     * @custom:oz-upgrades-unsafe-allow constructor
     */
    constructor() {
        _disableInitializers();
    }

    /**
     * @dev 初始化函数，替代构造函数用于代理模式，设置默认配置值 (对应Aptos初始化参数)
     */
    function initialize() public initializer onlySystemCaller {
        // 质押参数 (对应Aptos StakingConfig默认值)
        minValidatorStake = 1000 ether; // 对应Aptos minimum_stake
        maximumStake = 1000000 ether; // 对应Aptos maximum_stake
        minDelegationStake = 0.1 ether; // 最小委托质押
        minDelegationChange = 0.1 ether; // 最小委托变更量
        maxValidatorCount = 100; // 对应Aptos max_validator_count
        recurringLockupDuration = 14 days; // 对应Aptos recurring_lockup_duration_secs
        allowValidatorSetChange = true; // 对应Aptos allow_validator_set_change
        redelegateFeeRate = 2; // 重新委托手续费率(%)

        // 奖励参数 (对应Aptos StakingRewardsConfig)
        rewardsRate = 100; // 1.00%
        rewardsRateDenominator = PERCENTAGE_BASE;

        // 投票权限制 (对应Aptos voting_power_increase_limit)
        votingPowerIncreaseLimit = 2000; // 20.00%每个纪元

        // 佣金参数
        maxCommissionRate = 5000; // 50%最大佣金率
        maxCommissionChangeRate = 500; // 5%最大变更率
    }

    /**
     * @dev 统一参数更新函数
     * @param key 参数名称
     * @param value 参数值
     */
    function updateParam(string calldata key, bytes calldata value) external override onlyGov {
        if (Strings.equal(key, "minValidatorStake")) {
            uint256 newValue = abi.decode(value, (uint256));
            if (newValue == 0) revert StakeConfig__StakeLimitsMustBePositive();
            if (newValue > maximumStake) revert StakeConfig__InvalidStakeRange(newValue, maximumStake);

            uint256 oldValue = minValidatorStake;
            minValidatorStake = newValue;
            emit ConfigParamUpdated("minValidatorStake", oldValue, newValue);
        } else if (Strings.equal(key, "maximumStake")) {
            uint256 newValue = abi.decode(value, (uint256));
            if (newValue == 0) revert StakeConfig__StakeLimitsMustBePositive();
            if (minValidatorStake > newValue) revert StakeConfig__InvalidStakeRange(minValidatorStake, newValue);

            uint256 oldValue = maximumStake;
            maximumStake = newValue;
            emit ConfigParamUpdated("maximumStake", oldValue, newValue);
        } else if (Strings.equal(key, "minDelegationStake")) {
            uint256 newValue = abi.decode(value, (uint256));
            uint256 oldValue = minDelegationStake;
            minDelegationStake = newValue;
            emit ConfigParamUpdated("minDelegationStake", oldValue, newValue);
        } else if (Strings.equal(key, "minDelegationChange")) {
            uint256 newValue = abi.decode(value, (uint256));
            uint256 oldValue = minDelegationChange;
            minDelegationChange = newValue;
            emit ConfigParamUpdated("minDelegationChange", oldValue, newValue);
        } else if (Strings.equal(key, "maxValidatorCount")) {
            uint256 newValue = abi.decode(value, (uint256));
            uint256 oldValue = maxValidatorCount;
            maxValidatorCount = newValue;
            emit ConfigParamUpdated("maxValidatorCount", oldValue, newValue);
        } else if (Strings.equal(key, "recurringLockupDuration")) {
            uint256 newValue = abi.decode(value, (uint256));
            if (newValue == 0) revert StakeConfig__RecurringLockupDurationMustBePositive();

            uint256 oldValue = recurringLockupDuration;
            recurringLockupDuration = newValue;
            emit ConfigParamUpdated("recurringLockupDuration", oldValue, newValue);
        } else if (Strings.equal(key, "allowValidatorSetChange")) {
            bool newValue = abi.decode(value, (bool));
            bool oldValue = allowValidatorSetChange;
            allowValidatorSetChange = newValue;
            emit ConfigBoolParamUpdated("allowValidatorSetChange", oldValue, newValue);
        } else if (Strings.equal(key, "rewardsRate")) {
            uint256 newValue = abi.decode(value, (uint256));
            if (newValue > rewardsRateDenominator) {
                revert StakeConfig__RewardsRateCannotExceedLimit(newValue, rewardsRateDenominator);
            }
            if (newValue > MAX_REWARDS_RATE) {
                revert StakeConfig__RewardsRateCannotExceedLimit(newValue, MAX_REWARDS_RATE);
            }

            uint256 oldValue = rewardsRate;
            rewardsRate = newValue;
            emit ConfigParamUpdated("rewardsRate", oldValue, newValue);
        } else if (Strings.equal(key, "rewardsRateDenominator")) {
            uint256 newValue = abi.decode(value, (uint256));
            if (newValue == 0) revert StakeConfig__DenominatorMustBePositive();
            if (rewardsRate > newValue) {
                revert StakeConfig__RewardsRateCannotExceedLimit(rewardsRate, newValue);
            }

            uint256 oldValue = rewardsRateDenominator;
            rewardsRateDenominator = newValue;
            emit ConfigParamUpdated("rewardsRateDenominator", oldValue, newValue);
        } else if (Strings.equal(key, "votingPowerIncreaseLimit")) {
            uint256 newValue = abi.decode(value, (uint256));
            if (newValue == 0 || newValue > PERCENTAGE_BASE / 2) {
                revert StakeConfig__InvalidVotingPowerIncreaseLimit(newValue, PERCENTAGE_BASE / 2);
            }

            uint256 oldValue = votingPowerIncreaseLimit;
            votingPowerIncreaseLimit = newValue;
            emit ConfigParamUpdated("votingPowerIncreaseLimit", oldValue, newValue);
        } else if (Strings.equal(key, "maxCommissionRate")) {
            uint256 newValue = abi.decode(value, (uint256));
            if (newValue > PERCENTAGE_BASE) {
                revert StakeConfig__InvalidCommissionRate(newValue, PERCENTAGE_BASE);
            }

            uint256 oldValue = maxCommissionRate;
            maxCommissionRate = newValue;
            emit ConfigParamUpdated("maxCommissionRate", oldValue, newValue);
        } else if (Strings.equal(key, "maxCommissionChangeRate")) {
            uint256 newValue = abi.decode(value, (uint256));
            if (newValue > maxCommissionRate) {
                revert StakeConfig__InvalidCommissionRate(newValue, maxCommissionRate);
            }

            uint256 oldValue = maxCommissionChangeRate;
            maxCommissionChangeRate = newValue;
            emit ConfigParamUpdated("maxCommissionChangeRate", oldValue, newValue);
        } else if (Strings.equal(key, "redelegateFeeRate")) {
            uint256 newValue = abi.decode(value, (uint256));
            if (newValue > PERCENTAGE_BASE) {
                revert StakeConfig__InvalidCommissionRate(newValue, PERCENTAGE_BASE);
            }

            uint256 oldValue = redelegateFeeRate;
            redelegateFeeRate = newValue;
            emit ConfigParamUpdated("redelegateFeeRate", oldValue, newValue);
        } else {
            revert StakeConfig__ParameterNotFound(key);
        }

        emit ParamChange(key, value);
    }

    /**
     * @dev 获取质押要求 (对应Aptos get_required_stake)
     * @return minimum 最小质押要求
     * @return maximum 最大质押要求
     */
    function getRequiredStake() external view returns (uint256 minimum, uint256 maximum) {
        return (minValidatorStake, maximumStake);
    }

    /**
     * @dev 获取奖励率 (对应Aptos get_reward_rate)
     * @return rate 奖励率
     * @return denominator 奖励率分母
     */
    function getRewardRate() external view returns (uint256 rate, uint256 denominator) {
        return (rewardsRate, rewardsRateDenominator);
    }

    /**
     * @dev 计算基于性能的奖励金额 (对应Aptos calculate_rewards_amount)
     * @param stakeAmount 质押金额
     * @param successfulProposals 成功提案数
     * @param totalProposals 总提案数
     * @return 奖励金额
     */
    function calculateRewardsAmount(uint256 stakeAmount, uint256 successfulProposals, uint256 totalProposals)
        public
        view
        returns (uint256)
    {
        if (totalProposals == 0 || stakeAmount == 0) {
            return 0;
        }

        // 对应Aptos中的性能乘数计算
        // rewards_numerator = stake_amount * rewards_rate * num_successful_proposals
        // rewards_denominator = rewards_rate_denominator * num_total_proposals
        uint256 rewardsNumerator = stakeAmount * rewardsRate * successfulProposals;
        uint256 rewardsDenominator = rewardsRateDenominator * totalProposals;

        return rewardsNumerator / rewardsDenominator;
    }

    /**
     * @dev 获取当前所有配置参数
     */
    function getAllConfigParams() external view returns (ConfigParams memory) {
        return ConfigParams({
            minValidatorStake: minValidatorStake,
            maximumStake: maximumStake,
            minDelegationStake: minDelegationStake,
            minDelegationChange: minDelegationChange,
            maxValidatorCount: maxValidatorCount,
            recurringLockupDuration: recurringLockupDuration,
            allowValidatorSetChange: allowValidatorSetChange,
            rewardsRate: rewardsRate,
            rewardsRateDenominator: rewardsRateDenominator,
            votingPowerIncreaseLimit: votingPowerIncreaseLimit,
            maxCommissionRate: maxCommissionRate,
            maxCommissionChangeRate: maxCommissionChangeRate,
            redelegateFeeRate: redelegateFeeRate
        });
    }

    /**
     * @dev 检查质押金额是否有效
     */
    function isValidStakeAmount(uint256 amount) external view returns (bool) {
        return amount >= minValidatorStake && amount <= maximumStake;
    }

    /**
     * @dev 检查委托金额是否有效
     */
    function isValidDelegationAmount(uint256 amount) external view returns (bool) {
        return amount >= minDelegationStake;
    }

    /**
     * @dev 检查佣金率是否有效
     */
    function isValidCommissionRate(uint256 rate) external view returns (bool) {
        return rate <= maxCommissionRate;
    }

    /**
     * @dev 检查佣金变更是否有效
     */
    function isValidCommissionChange(uint256 oldRate, uint256 newRate) external view returns (bool) {
        uint256 change = oldRate > newRate ? oldRate - newRate : newRate - oldRate;
        return change <= maxCommissionChangeRate;
    }
}
