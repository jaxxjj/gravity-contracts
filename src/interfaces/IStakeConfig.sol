// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

/**
 * @title IStakeConfig
 * @dev StakeConfig 合约的接口，定义了质押系统配置的访问方法
 */
interface IStakeConfig {
    function minValidatorStake() external view returns (uint256);
    function maximumStake() external view returns (uint256);
    function minDelegationStake() external view returns (uint256);
    function maxValidatorCount() external view returns (uint256);
    function recurringLockupDuration() external view returns (uint256);
    function minDelegationChange() external view returns (uint256);
    function redelegateFeeRate() external view returns (uint256);
    function allowValidatorSetChange() external view returns (bool);
    function rewardsRate() external view returns (uint256);
    function rewardsRateDenominator() external view returns (uint256);
    function votingPowerIncreaseLimit() external view returns (uint256);
    function maxCommissionRate() external view returns (uint256);
    function maxCommissionChangeRate() external view returns (uint256);
    function lockAmount() external view returns (uint256);

    function PERCENTAGE_BASE() external view returns (uint256);
    function MAX_REWARDS_RATE() external view returns (uint256);
    function MAX_U64() external view returns (uint128);
    function MAX_COMMISSION_RATE() external view returns (uint256);

    event ConfigParamUpdated(string parameter, uint256 oldValue, uint256 newValue);
    event ConfigBoolParamUpdated(string parameter, bool oldValue, bool newValue);

    error StakeConfig__StakeLimitsMustBePositive();
    error StakeConfig__InvalidStakeRange(uint256 minStake, uint256 maxStake);
    error StakeConfig__RecurringLockupDurationMustBePositive();
    error StakeConfig__DenominatorMustBePositive();
    error StakeConfig__RewardsRateCannotExceedLimit(uint256 rewardsRate, uint256 denominator);
    error StakeConfig__InvalidVotingPowerIncreaseLimit(uint256 actualValue, uint256 maxValue);
    error StakeConfig__ParameterNotFound(string paramName);
    error StakeConfig__InvalidCommissionRate(uint256 rate, uint256 maxRate);
    error StakeConfig__WrongInitContext();
    error StakeConfig__InvalidParameter();
    error StakeConfig__InvalidLockAmount(uint256 providedAmount);

    function initialize() external;

    function getRequiredStake() external view returns (uint256 minimum, uint256 maximum);
    function getRewardRate() external view returns (uint256 rate, uint256 denominator);

    function calculateRewardsAmount(uint256 stakeAmount, uint256 successfulProposals, uint256 totalProposals)
        external
        view
        returns (uint256);

    struct ConfigParams {
        uint256 minValidatorStake;
        uint256 maximumStake;
        uint256 minDelegationStake;
        uint256 minDelegationChange;
        uint256 maxValidatorCount;
        uint256 recurringLockupDuration;
        bool allowValidatorSetChange;
        uint256 rewardsRate;
        uint256 rewardsRateDenominator;
        uint256 votingPowerIncreaseLimit;
        uint256 maxCommissionRate;
        uint256 maxCommissionChangeRate;
        uint256 redelegateFeeRate;
        uint256 lockAmount;
    }

    function getAllConfigParams() external view returns (ConfigParams memory);

    function isValidStakeAmount(uint256 amount) external view returns (bool);
    function isValidDelegationAmount(uint256 amount) external view returns (bool);
    function isValidCommissionRate(uint256 rate) external view returns (bool);
    function isValidCommissionChange(uint256 oldRate, uint256 newRate) external view returns (bool);
}
