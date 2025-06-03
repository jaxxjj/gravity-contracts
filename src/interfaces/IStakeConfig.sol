// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/**
 * @title IStakeConfig
 * @dev Interface for the StakeConfig contract that defines the staking system configuration
 */
interface IStakeConfig {
    // Errors
    error StakeConfig__StakeLimitsMustBePositive();
    error StakeConfig__InvalidStakeRange(uint256 minStake, uint256 maxStake);
    error StakeConfig__RecurringLockupDurationMustBePositive();
    error StakeConfig__DenominatorMustBePositive();
    error StakeConfig__RewardsRateCannotExceedLimit(uint256 rewardsRate, uint256 denominator);
    error StakeConfig__InvalidVotingPowerIncreaseLimit(uint256 actualValue, uint256 maxValue);
    error StakeConfig__ParameterNotFound(string paramName);
    error StakeConfig__InvalidCommissionRate(uint256 rate, uint256 maxRate);
    error StakeConfig__InvalidLockAmount(uint256 providedAmount);

    // Events
    event ConfigParamUpdated(string parameter, uint256 oldValue, uint256 newValue);
    event ConfigBoolParamUpdated(string parameter, bool oldValue, bool newValue);

    /**
     * @dev Returns the minimum stake required for validators
     * @return Minimum validator stake amount
     */
    function minValidatorStake() external view returns (uint256);

    /**
     * @dev Returns the maximum stake allowed for validators
     * @return Maximum validator stake amount
     */
    function maximumStake() external view returns (uint256);

    /**
     * @dev Returns the minimum stake required for delegators
     * @return Minimum delegation stake amount
     */
    function minDelegationStake() external view returns (uint256);

    /**
     * @dev Returns the maximum number of validators allowed in the network
     * @return Maximum validator count
     */
    function maxValidatorCount() external view returns (uint256);

    /**
     * @dev Returns the duration in seconds that tokens remain locked after unbonding request
     * @return Lockup duration in seconds
     */
    function recurringLockupDuration() external view returns (uint256);

    /**
     * @dev Returns the minimum amount for delegation changes
     * @return Minimum delegation change amount
     */
    function minDelegationChange() external view returns (uint256);

    /**
     * @dev Returns the fee rate applied when redelegating stake
     * @return Redelegate fee rate (basis points)
     */
    function redelegateFeeRate() external view returns (uint256);

    /**
     * @dev Returns whether validator set changes are allowed
     * @return True if validator set changes are allowed, false otherwise
     */
    function allowValidatorSetChange() external view returns (bool);

    /**
     * @dev Returns the current rewards rate
     * @return Rewards rate
     */
    function rewardsRate() external view returns (uint256);

    /**
     * @dev Returns the rewards rate denominator
     * @return Rewards rate denominator
     */
    function rewardsRateDenominator() external view returns (uint256);

    /**
     * @dev Returns the maximum voting power increase limit per epoch
     * @return Voting power increase limit (basis points)
     */
    function votingPowerIncreaseLimit() external view returns (uint256);

    /**
     * @dev Returns the maximum commission rate allowed for validators
     * @return Maximum commission rate (basis points)
     */
    function maxCommissionRate() external view returns (uint256);

    /**
     * @dev Returns the maximum commission change rate allowed per change
     * @return Maximum commission change rate (basis points)
     */
    function maxCommissionChangeRate() external view returns (uint256);

    /**
     * @dev Returns the amount that must be locked when creating a validator
     * @return Lock amount
     */
    function lockAmount() external view returns (uint256);

    /**
     * @dev Returns the percentage base used for calculations (100% representation)
     * @return Percentage base value
     */
    function PERCENTAGE_BASE() external view returns (uint256);

    /**
     * @dev Returns the maximum rewards rate allowed
     * @return Maximum rewards rate
     */
    function MAX_REWARDS_RATE() external view returns (uint256);

    /**
     * @dev Returns the maximum uint64 value
     * @return Maximum uint64 value
     */
    function MAX_U64() external view returns (uint128);

    /**
     * @dev Returns the maximum commission rate constant
     * @return Maximum commission rate
     */
    function MAX_COMMISSION_RATE() external view returns (uint256);

    /**
     * @dev Initializes the contract with default values
     */
    function initialize() external;

    /**
     * @dev Updates a parameter value
     * @param key The parameter name
     * @param value The new value encoded as bytes
     */
    function updateParam(string calldata key, bytes calldata value) external;

    /**
     * @dev Returns the required stake limits
     * @return minimum The minimum stake required
     * @return maximum The maximum stake allowed
     */
    function getRequiredStake() external view returns (uint256 minimum, uint256 maximum);

    /**
     * @dev Returns the current reward rate
     * @return rate The reward rate
     * @return denominator The rate denominator
     */
    function getRewardRate() external view returns (uint256 rate, uint256 denominator);

    /**
     * @dev Structure containing all configuration parameters
     */
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

    /**
     * @dev Returns all configuration parameters
     * @return ConfigParams struct containing all parameters
     */
    function getAllConfigParams() external view returns (ConfigParams memory);

    /**
     * @dev Checks if a stake amount is valid for a validator
     * @param amount The amount to check
     * @return True if valid, false otherwise
     */
    function isValidStakeAmount(uint256 amount) external view returns (bool);

    /**
     * @dev Checks if a delegation amount is valid
     * @param amount The amount to check
     * @return True if valid, false otherwise
     */
    function isValidDelegationAmount(uint256 amount) external view returns (bool);

    /**
     * @dev Checks if a commission rate is valid
     * @param rate The rate to check
     * @return True if valid, false otherwise
     */
    function isValidCommissionRate(uint256 rate) external view returns (bool);

    /**
     * @dev Checks if a commission rate change is valid
     * @param oldRate The previous rate
     * @param newRate The new rate
     * @return True if valid, false otherwise
     */
    function isValidCommissionChange(uint256 oldRate, uint256 newRate) external view returns (bool);
}
