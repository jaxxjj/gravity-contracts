// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "../System.sol";
import "@src/interfaces/IStakeConfig.sol";
import "@src/interfaces/IValidatorManager.sol"; // 替换IValidatorRegistry
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@src/access/Protectable.sol";
import "@src/stake/StakeCredit.sol";
import "@src/interfaces/IDelegation.sol";
import "@src/interfaces/IEpochManager.sol";
import "@src/interfaces/IReconfigurableModule.sol";
import "@src/interfaces/IGovToken.sol";

/**
 * @title StakeHub
 * @dev 完全复刻Aptos stake.move的核心逻辑
 *
 * 对应Aptos stake.move的主要功能：
 * - initialize_validator: registerValidator
 * - add_stake: delegate
 * - unlock: undelegate
 * - withdraw: claim
 * - join_validator_set: joinValidatorSet
 * - leave_validator_set: leaveValidatorSet
 * - on_new_epoch: 完整的epoch转换逻辑
 * - distribute_rewards: 奖励分发机制
 *
 * 每个验证者拥有独立的StakeCredit合约(对应Aptos StakePool)
 */
contract Delegation is System, ReentrancyGuard, Protectable, IDelegation {
    // ======== 修改器 ========
    modifier validatorExists(address validator) {
        if (!IValidatorManager(VALIDATOR_MANAGER_ADDR).isValidatorExists(validator)) {
            revert Delegation__ValidatorNotRegistered(validator);
        }
        _;
    }

    /**
     * @dev 向验证者质押 (对应Aptos add_stake)
     * @param validator 验证者地址
     */
    function delegate(address validator) external payable whenNotPaused validatorExists(validator) {
        uint256 gAmount = msg.value;
        if (gAmount < IStakeConfig(STAKE_CONFIG_ADDR).minDelegationChange()) {
            revert Delegation__LessThanMinDelegationChange();
        }

        address delegator = msg.sender;

        // 获取StakeCredit地址
        address stakeCreditAddress = IValidatorManager(VALIDATOR_MANAGER_ADDR).getValidatorStakeCredit(validator);

        uint256 shares = IStakeCredit(stakeCreditAddress).delegate{value: gAmount}(delegator);

        // 检查投票权增长限制 (对应Aptos EVOTING_POWER_INCREASE_EXCEEDS_LIMIT)
        IValidatorManager(VALIDATOR_MANAGER_ADDR).checkVotingPowerIncrease(validator, msg.value);

        emit Delegated(validator, delegator, shares, gAmount);

        IGovToken(GOV_TOKEN_ADDR).sync(stakeCreditAddress, delegator);
    }

    /**
     * @dev 解除质押 (对应Aptos unlock)
     * @param validator 验证者地址
     * @param shares 要解除的份额
     */
    function undelegate(address validator, uint256 shares)
        external
        validatorExists(validator)
        whenNotPaused
        notInBlackList
    {
        if (shares == 0) {
            revert Delegation__ZeroShares();
        }

        address stakeCreditAddress = IValidatorManager(VALIDATOR_MANAGER_ADDR).getValidatorStakeCredit(validator);

        // 从StakeCredit合约解除质押
        uint256 gAmount = StakeCredit(payable(stakeCreditAddress)).unlock(msg.sender, shares);
        emit Undelegated(validator, msg.sender, shares, gAmount);

        // 检查验证者是否还满足最小质押要求
        if (msg.sender == validator) {
            IValidatorManager(VALIDATOR_MANAGER_ADDR).checkValidatorMinStake(validator);
        }

        IGovToken(GOV_TOKEN_ADDR).sync(stakeCreditAddress, msg.sender);
    }

    /**
     * @dev 提取解绑的资金 (对应Aptos withdraw)
     * @param validator 验证者地址
     * @param requestCount 要处理的请求数量
     */
    function claim(address validator, uint256 requestCount) external validatorExists(validator) whenNotPaused {
        address stakeCreditAddress = IValidatorManager(VALIDATOR_MANAGER_ADDR).getValidatorStakeCredit(validator);
        require(stakeCreditAddress != address(0), "StakeHub: StakeCredit not found");

        uint256 claimedAmount = StakeCredit(payable(stakeCreditAddress)).withdraw(payable(msg.sender), requestCount);

        emit UnbondedTokensWithdrawn(msg.sender, claimedAmount);
    }

    // 将手续费计算和处理逻辑拆分成独立函数
    function _calculateAndChargeFee(address dstStakeCredit, uint256 amount) internal returns (uint256) {
        uint256 feeRate = IStakeConfig(STAKE_CONFIG_ADDR).redelegateFeeRate();
        uint256 feeCharge = (amount * feeRate) / IStakeConfig(STAKE_CONFIG_ADDR).PERCENTAGE_BASE();

        if (feeCharge > 0) {
            (bool success,) = dstStakeCredit.call{value: feeCharge}("");
            if (!success) {
                revert Delegation__TransferFailed();
            }
        }

        return amount - feeCharge;
    }

    // 重构后的 redelegate 函数
    function redelegate(address srcValidator, address dstValidator, uint256 shares, bool delegateVotePower)
        external
        whenNotPaused
        notInBlackList
        validatorExists(srcValidator)
        validatorExists(dstValidator)
        nonReentrant
    {
        // 基本检查
        if (shares == 0) revert Delegation__ZeroShares();
        if (srcValidator == dstValidator) revert Delegation__SameValidator();

        address delegator = msg.sender;

        // 获取StakeCredit地址
        address srcStakeCredit = IValidatorManager(VALIDATOR_MANAGER_ADDR).getValidatorStakeCredit(srcValidator);
        address dstStakeCredit = IValidatorManager(VALIDATOR_MANAGER_ADDR).getValidatorStakeCredit(dstValidator);

        // 检查目标验证者状态
        _validateDstValidator(dstValidator, delegator);

        // 从源验证者解绑
        uint256 gAmount = IStakeCredit(srcStakeCredit).unbond(delegator, shares);
        if (gAmount < IStakeConfig(STAKE_CONFIG_ADDR).minDelegationChange()) {
            revert Delegation__LessThanMinDelegationChange();
        }

        // 如果委托人是验证者自己，检查源验证者的质押要求
        if (delegator == srcValidator) {
            IValidatorManager(VALIDATOR_MANAGER_ADDR).checkValidatorMinStake(srcValidator);
        }

        // 计算并收取手续费
        uint256 netAmount = _calculateAndChargeFee(dstStakeCredit, gAmount);

        // 委托到目标验证者
        uint256 newShares = IStakeCredit(dstStakeCredit).delegate{value: netAmount}(delegator);

        // 检查投票权增长限制
        IValidatorManager(VALIDATOR_MANAGER_ADDR).checkVotingPowerIncrease(dstValidator, netAmount);

        emit Redelegated(srcValidator, dstValidator, delegator, shares, newShares, netAmount, gAmount - netAmount);

        // 处理治理同步
        address[] memory stakeCredits = new address[](2);
        stakeCredits[0] = srcStakeCredit;
        stakeCredits[1] = dstStakeCredit;
        IGovToken(GOV_TOKEN_ADDR).syncBatch(stakeCredits, delegator);

        if (delegateVotePower) {
            IGovToken(GOV_TOKEN_ADDR).delegateVote(delegator, dstValidator);
        }
    }

    // 验证目标验证者状态
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

    // 添加独立的投票委托函数
    function delegateVoteTo(address voter) external whenNotPaused notInBlackList {
        IGovToken(GOV_TOKEN_ADDR).delegateVote(msg.sender, voter);
        emit VoteDelegated(msg.sender, voter);
    }
}
