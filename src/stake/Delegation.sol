// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "../System.sol";
import "@src/interfaces/IStakeConfig.sol";
import "@src/interfaces/IValidatorManager.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@src/access/Protectable.sol";
import "@src/stake/StakeCredit.sol";
import "@src/interfaces/IDelegation.sol";
import "@src/interfaces/IEpochManager.sol";
import "@src/interfaces/IReconfigurableModule.sol";
import "@src/interfaces/IGovToken.sol";

/**
 * @title Delegation
 * @dev Contract for delegating tokens to validators and managing stake
 */
contract Delegation is System, ReentrancyGuard, Protectable, IDelegation {
    // ======== Errors ========
    error InvalidValidator();

    // ======== Modifiers ========
    modifier validatorExists(
        address validator
    ) {
        if (!IValidatorManager(VALIDATOR_MANAGER_ADDR).isValidatorExists(validator)) {
            revert Delegation__ValidatorNotRegistered(validator);
        }
        _;
    }

    /// @inheritdoc IDelegation
    function delegate(
        address validator
    ) external payable whenNotPaused validatorExists(validator) {
        uint256 amount = msg.value;
        if (amount < IStakeConfig(STAKE_CONFIG_ADDR).minDelegationChange()) {
            revert Delegation__LessThanMinDelegationChange();
        }

        address delegator = msg.sender;

        // Get StakeCredit address
        address stakeCreditAddress = IValidatorManager(VALIDATOR_MANAGER_ADDR).getValidatorStakeCredit(validator);

        uint256 shares = IStakeCredit(stakeCreditAddress).delegate{ value: amount }(delegator);

        // Check voting power increase limit
        IValidatorManager(VALIDATOR_MANAGER_ADDR).checkVotingPowerIncrease(msg.value);

        emit Delegated(validator, delegator, shares, amount);

        IGovToken(GOV_TOKEN_ADDR).sync(stakeCreditAddress, delegator);
    }

    /// @inheritdoc IDelegation
    function undelegate(
        address validator,
        uint256 shares
    ) external validatorExists(validator) whenNotPaused notInBlackList {
        if (shares == 0) {
            revert Delegation__ZeroShares();
        }

        address stakeCreditAddress = IValidatorManager(VALIDATOR_MANAGER_ADDR).getValidatorStakeCredit(validator);

        // Undelegate from StakeCredit contract
        uint256 amount = StakeCredit(payable(stakeCreditAddress)).unlock(msg.sender, shares);
        emit Undelegated(validator, msg.sender, shares, amount);

        // Check if validator still meets minimum stake requirement
        if (msg.sender == validator) {
            IValidatorManager(VALIDATOR_MANAGER_ADDR).checkValidatorMinStake(validator);
        }

        IGovToken(GOV_TOKEN_ADDR).sync(stakeCreditAddress, msg.sender);
    }

    /**
     * @dev Claim matured unlocked stake from a validator
     * Uses Pull model - delegator must actively claim after unbonding period
     * @param validator The validator to claim from
     * @return amount The amount claimed
     */
    function claim(
        address validator
    ) external nonReentrant returns (uint256 amount) {
        address stakeCreditAddress = IValidatorManager(VALIDATOR_MANAGER_ADDR).getValidatorStakeCredit(validator);
        if (stakeCreditAddress == address(0)) revert InvalidValidator();

        // Call claim on StakeCredit contract
        amount = IStakeCredit(stakeCreditAddress).claim(payable(msg.sender));

        if (amount > 0) {
            emit StakeClaimed(msg.sender, validator, amount);
        }

        return amount;
    }

    /**
     * @dev Batch claim from multiple validators
     * @param validators Array of validator addresses to claim from
     * @return totalClaimed Total amount claimed
     */
    function claimBatch(
        address[] calldata validators
    ) external nonReentrant returns (uint256 totalClaimed) {
        for (uint256 i = 0; i < validators.length; i++) {
            address stakeCreditAddress =
                IValidatorManager(VALIDATOR_MANAGER_ADDR).getValidatorStakeCredit(validators[i]);
            if (stakeCreditAddress != address(0)) {
                uint256 claimed = IStakeCredit(stakeCreditAddress).claim(payable(msg.sender));
                if (claimed > 0) {
                    totalClaimed += claimed;
                    emit StakeClaimed(msg.sender, validators[i], claimed);
                }
            }
        }
        return totalClaimed;
    }

    /**
     * @dev Calculate and charge fee for redelegation
     * @param dstStakeCredit Destination StakeCredit address
     * @param amount Amount to calculate fee on
     * @return Net amount after fee deduction
     */
    function _calculateAndChargeFee(address dstStakeCredit, uint256 amount) internal returns (uint256) {
        uint256 feeRate = IStakeConfig(STAKE_CONFIG_ADDR).redelegateFeeRate();
        uint256 feeCharge = (amount * feeRate) / IStakeConfig(STAKE_CONFIG_ADDR).PERCENTAGE_BASE();

        if (feeCharge > 0) {
            (bool success,) = dstStakeCredit.call{ value: feeCharge }("");
            if (!success) {
                revert Delegation__TransferFailed();
            }
        }

        return amount - feeCharge;
    }

    /// @inheritdoc IDelegation
    function redelegate(
        address srcValidator,
        address dstValidator,
        uint256 shares,
        bool delegateVotePower
    ) external whenNotPaused notInBlackList validatorExists(srcValidator) validatorExists(dstValidator) nonReentrant {
        // Basic checks
        if (shares == 0) revert Delegation__ZeroShares();
        if (srcValidator == dstValidator) revert Delegation__SameValidator();

        address delegator = msg.sender;

        // Get StakeCredit addresses
        address srcStakeCredit = IValidatorManager(VALIDATOR_MANAGER_ADDR).getValidatorStakeCredit(srcValidator);
        address dstStakeCredit = IValidatorManager(VALIDATOR_MANAGER_ADDR).getValidatorStakeCredit(dstValidator);

        // Check destination validator status
        _validateDstValidator(dstValidator, delegator);

        // Unbond from source validator
        uint256 amount = IStakeCredit(srcStakeCredit).unbond(delegator, shares);
        if (amount < IStakeConfig(STAKE_CONFIG_ADDR).minDelegationChange()) {
            revert Delegation__LessThanMinDelegationChange();
        }

        // If delegator is the validator itself, check source validator's stake requirement
        if (delegator == srcValidator) {
            IValidatorManager(VALIDATOR_MANAGER_ADDR).checkValidatorMinStake(srcValidator);
        }

        // Calculate and charge fee
        uint256 netAmount = _calculateAndChargeFee(dstStakeCredit, amount);

        // Delegate to destination validator
        uint256 newShares = IStakeCredit(dstStakeCredit).delegate{ value: netAmount }(delegator);

        // Check voting power increase limit
        IValidatorManager(VALIDATOR_MANAGER_ADDR).checkVotingPowerIncrease(netAmount);

        emit Redelegated(srcValidator, dstValidator, delegator, shares, newShares, netAmount, amount - netAmount);

        // Handle governance token synchronization
        address[] memory stakeCredits = new address[](2);
        stakeCredits[0] = srcStakeCredit;
        stakeCredits[1] = dstStakeCredit;
        IGovToken(GOV_TOKEN_ADDR).syncBatch(stakeCredits, delegator);

        if (delegateVotePower) {
            IGovToken(GOV_TOKEN_ADDR).delegateVote(delegator, dstValidator);
        }
    }

    /**
     * @dev Validate destination validator status
     * @param dstValidator Destination validator address
     * @param delegator Delegator address
     */
    function _validateDstValidator(address dstValidator, address delegator) internal view {
        IValidatorManager.ValidatorStatus dstStatus =
            IValidatorManager(VALIDATOR_MANAGER_ADDR).getValidatorStatus(dstValidator);
        if (
            dstStatus != IValidatorManager.ValidatorStatus.ACTIVE
                && dstStatus != IValidatorManager.ValidatorStatus.PENDING_ACTIVE && delegator != dstValidator
        ) {
            revert Delegation__OnlySelfDelegationToJailedValidator();
        }
    }

    /// @inheritdoc IDelegation
    function delegateVoteTo(
        address voter
    ) external whenNotPaused notInBlackList {
        IGovToken(GOV_TOKEN_ADDR).delegateVote(msg.sender, voter);
        emit VoteDelegated(msg.sender, voter);
    }
}
