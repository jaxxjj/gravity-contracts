// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "@src/System.sol";
import "@src/interfaces/IStakeConfig.sol";
import "@src/interfaces/IParamSubscriber.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin-upgrades/proxy/utils/Initializable.sol";

/**
 * @title StakeConfig
 * @dev Contract that manages staking configuration parameters
 */
contract StakeConfig is System, IStakeConfig, IParamSubscriber, Initializable {
    // Constants
    uint256 public constant PERCENTAGE_BASE = 10000; // 100.00%
    uint256 public constant MAX_REWARDS_RATE = 1000000;
    uint128 public constant MAX_U64 = type(uint64).max;
    uint256 public constant MAX_COMMISSION_RATE = 5_000;

    // Validator lock amount (security deposit)
    uint256 public lockAmount;

    // Staking configuration parameters
    uint256 public minValidatorStake;
    uint256 public maximumStake;
    uint256 public minDelegationStake;
    uint256 public minDelegationChange;
    uint256 public redelegateFeeRate;
    uint256 public maxValidatorCount;
    uint256 public recurringLockupDuration;
    bool public allowValidatorSetChange;
    uint256 public votingPowerIncreaseLimit;

    // Reward parameters
    uint256 public rewardsRate;
    uint256 public rewardsRateDenominator;

    // Commission parameters
    uint256 public maxCommissionRate;
    uint256 public maxCommissionChangeRate;

    constructor() {
        _disableInitializers();
    }

    /// @inheritdoc IStakeConfig
    function initialize() public initializer onlyGenesis {
        // Staking parameters
        minValidatorStake = 1000 ether;
        maximumStake = 1000000 ether;
        minDelegationStake = 0.1 ether;
        minDelegationChange = 0.1 ether;
        maxValidatorCount = 100;
        recurringLockupDuration = 2 hours; // Aligned with epoch interval for Aptos model
        allowValidatorSetChange = true;
        redelegateFeeRate = 2; // 0.02%

        // Reward parameters
        rewardsRate = 100; // 1.00%
        rewardsRateDenominator = PERCENTAGE_BASE;

        // Voting power limit
        votingPowerIncreaseLimit = 2000; // 20.00% per epoch

        // Commission parameters
        maxCommissionRate = 5000; // 50% maximum commission rate
        maxCommissionChangeRate = 500; // 5% maximum change rate

        // Lock amount initial value
        lockAmount = 10000 ether;
    }

    /// @inheritdoc IStakeConfig
    function updateParam(
        string calldata key,
        bytes calldata value
    ) external override(IStakeConfig, IParamSubscriber) onlyGov {
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
        } else if (Strings.equal(key, "lockAmount")) {
            uint256 newValue = abi.decode(value, (uint256));
            if (newValue == 0) revert StakeConfig__InvalidLockAmount(newValue);

            uint256 oldValue = lockAmount;
            lockAmount = newValue;
            emit ConfigParamUpdated("lockAmount", oldValue, newValue);
        } else {
            revert StakeConfig__ParameterNotFound(key);
        }

        emit ParamChange(key, value);
    }

    /// @inheritdoc IStakeConfig
    function getRequiredStake() external view returns (uint256 minimum, uint256 maximum) {
        return (minValidatorStake, maximumStake);
    }

    /// @inheritdoc IStakeConfig
    function getRewardRate() external view returns (uint256 rate, uint256 denominator) {
        return (rewardsRate, rewardsRateDenominator);
    }

    /// @inheritdoc IStakeConfig
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
            redelegateFeeRate: redelegateFeeRate,
            lockAmount: lockAmount
        });
    }

    /// @inheritdoc IStakeConfig
    function isValidStakeAmount(
        uint256 amount
    ) external view returns (bool) {
        return amount >= minValidatorStake && amount <= maximumStake;
    }

    /// @inheritdoc IStakeConfig
    function isValidDelegationAmount(
        uint256 amount
    ) external view returns (bool) {
        return amount >= minDelegationStake;
    }

    /// @inheritdoc IStakeConfig
    function isValidCommissionRate(
        uint256 rate
    ) external view returns (bool) {
        return rate <= maxCommissionRate;
    }

    /// @inheritdoc IStakeConfig
    function isValidCommissionChange(uint256 oldRate, uint256 newRate) external view returns (bool) {
        uint256 change = oldRate > newRate ? oldRate - newRate : newRate - oldRate;
        return change <= maxCommissionChangeRate;
    }
}
