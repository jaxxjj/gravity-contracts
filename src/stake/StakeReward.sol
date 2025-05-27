// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "../System.sol";
import "@src/interfaces/IStakeConfig.sol";
import "@src/interfaces/IValidatorManager.sol";
import "@src/interfaces/IEpochManager.sol";
import "@src/stake/StakeCredit.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@src/access/Protectable.sol";
import "@src/interfaces/IValidatorManager.sol";
import "@src/stake/ValidatorPerformanceTracker.sol";

/**
 * @title StakeReward
 * @dev 负责验证者奖励的计算与分发
 */
contract StakeReward is System, ReentrancyGuard, Protectable {
    // 事件定义
    event RewardsDistributed(address indexed validator, uint256 amount);

    /**
     * @dev 分发奖励给所有活跃验证者
     * 只能被EpochManager调用
     */
    function distributeRewards() external onlyStakeHub nonReentrant whenNotPaused {
        _distributeRewards();
    }

    /**
     * @dev 分发奖励给活跃验证者 (对应Aptos distribute_rewards)
     */
    function _distributeRewards() internal {
        (address[] memory activeValidators,) = IValidatorManager(VALIDATOR_MANAGER_ADDR).getActiveValidators();
        ValidatorPerformanceTracker performanceTracker = ValidatorPerformanceTracker(PERFORMANCE_TRACKER_ADDR);

        for (uint256 i = 0; i < activeValidators.length; i++) {
            address validator = activeValidators[i];
            address stakeCreditAddress = IValidatorManager(VALIDATOR_MANAGER_ADDR).getValidatorStakeCredit(validator);

            if (stakeCreditAddress != address(0)) {
                uint256 stakeAmount = _getValidatorCurrentEpochVotingPower(validator);

                // 从ValidatorPerformanceTracker获取性能数据
                (uint64 successfulProposals, uint64 failedProposals,, bool exists) =
                    performanceTracker.getValidatorPerformance(validator);

                if (exists) {
                    uint64 totalProposals = successfulProposals + failedProposals;

                    // 计算奖励（如果没有提案，使用默认值）
                    uint256 rewardAmount;
                    if (totalProposals > 0) {
                        rewardAmount = IStakeConfig(STAKE_CONFIG_ADDR).calculateRewardsAmount(
                            stakeAmount, successfulProposals, totalProposals
                        );
                    } else {
                        // 如果没有提案记录，使用100%成功率
                        rewardAmount = IStakeConfig(STAKE_CONFIG_ADDR).calculateRewardsAmount(stakeAmount, 1, 1);
                    }

                    if (rewardAmount > 0) {
                        // 获取验证者的佣金率
                        IValidatorManager.ValidatorInfo memory info =
                            IValidatorManager(VALIDATOR_MANAGER_ADDR).getValidatorInfo(validator);
                        uint64 commissionRate = info.commissionRate;

                        // 发送奖励到StakeCredit合约
                        StakeCredit(payable(stakeCreditAddress)).distributeReward{value: rewardAmount}(commissionRate);
                        emit RewardsDistributed(validator, rewardAmount);
                    }
                }
            }
        }
    }

    /**
     * @dev 获取验证者的当前epoch投票权
     */
    function _getValidatorCurrentEpochVotingPower(address validator) internal view returns (uint256) {
        address stakeCreditAddress = IValidatorManager(VALIDATOR_MANAGER_ADDR).getValidatorStakeCredit(validator);
        if (stakeCreditAddress == address(0)) {
            return 0;
        }
        return StakeCredit(payable(stakeCreditAddress)).getCurrentEpochVotingPower();
    }

    // 接收奖励资金的回退函数
    receive() external payable {}
}
