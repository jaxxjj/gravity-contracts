// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

import "@src/System.sol";
import "@src/interfaces/IValidatorPerformanceTracker.sol";
import "@src/interfaces/IEpochManager.sol";

contract Block is System {
    /**
     * @dev 区块开始时调用，执行必要的系统逻辑
     * 对应Aptos block_prologue_common的流程
     * @param proposerIndex 当前块的提议者索引，如果为类型最大值则表示无效
     * @param failedProposerIndices 失败的提议者索引列表
     * @param timestamp 当前块的时间戳
     */
    function blockPrologue(uint64 proposerIndex, uint64[] calldata failedProposerIndices, uint256 timestamp)
        external
        onlySystemCaller
    {
        // 1. 首先更新当前块的验证者性能统计
        // 对应Aptos中的update_performance_statistics调用
        IValidatorPerformanceTracker(VALIDATOR_PERFORMANCE_TRACKER_ADDR).updatePerformanceStatistics(
            proposerIndex, failedProposerIndices
        );

        // 2. 检查是否需要进行Epoch转换
        // 对应Aptos中的epoch interval检查和reconfigure调用
        if (IEpochManager(EPOCH_MANAGER_ADDR).canTriggerEpochTransition()) {
            IEpochManager(EPOCH_MANAGER_ADDR).triggerEpochTransition();
        }
    }
}
