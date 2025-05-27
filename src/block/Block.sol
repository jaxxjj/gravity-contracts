// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

import "@src/System.sol";
import "@src/interfaces/IValidatorPerformanceTracker.sol";
import "@src/interfaces/IEpochManager.sol";
import "@src/interfaces/ITimestamp.sol";

contract Block is System {
    /**
     * @dev 区块开始时调用，执行必要的系统逻辑
     * 对应Aptos block_prologue_common的流程
     * @param proposerIndex 当前块的提议者索引，如果为类型最大值则表示无效
     * @param failedProposerIndices 失败的提议者索引列表
     * @param timestamp 当前块的时间戳（秒）
     */
    function blockPrologue(uint64 proposerIndex, uint64[] calldata failedProposerIndices, uint256 timestamp)
        external
        onlySystemCaller
    {
        // 0. 更新全局时间戳
        // 将传入的秒级时间戳转换为微秒级时间戳
        address proposerAddr;
        
        // 如果proposerIndex是无效值（在这里我们假设是uint64的最大值），使用SYSTEM_CALLER作为提议者
        // 对应Move代码中的 proposer == @vm_reserved
        if (proposerIndex == type(uint64).max) {
            proposerAddr = SYSTEM_CALLER;
        } else {
            // 这里需要从验证者管理器获取提议者地址，但我们没有看到相关实现
            // 暂时使用coinbase作为提议者地址
            proposerAddr = block.coinbase;
        }
        
        // 将时间戳转换为微秒并调用时间戳合约更新全局时间
        uint64 timestampMicros = uint64(timestamp * ITimestamp(TIMESTAMP_ADDR).MICRO_CONVERSION_FACTOR());
        ITimestamp(TIMESTAMP_ADDR).updateGlobalTime(proposerAddr, timestampMicros);

        // 1. 更新当前块的验证者性能统计
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
