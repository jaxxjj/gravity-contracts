// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

import "@src/System.sol";
import "@src/interfaces/IValidatorPerformanceTracker.sol";
import "@src/interfaces/IEpochManager.sol";
import "@src/interfaces/ITimestamp.sol";

contract Block is System {
    /**
     * @dev 创世区块事件，记录区块链的起始
     */
    event NewBlockEvent(
        address indexed hash,
        uint256 epoch,
        uint256 round,
        uint256 height,
        bytes previousBlockVotesBitvec,
        address proposer,
        uint64[] failedProposerIndices,
        uint256 timeMicroseconds
    );

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

    /**
     * @dev 发射创世区块事件。这个函数将在创世时直接调用，以生成第一个重配置事件。
     * 对应Aptos emit_genesis_block_event函数
     */
    function emitGenesisBlockEvent() external onlySystemCaller {
        address genesisId = address(0);
        uint64[] memory emptyFailedProposerIndices = new uint64[](0);

        emit NewBlockEvent(
            genesisId, // hash: genesis_id
            0, // epoch: 0
            0, // round: 0
            0, // height: 0
            bytes(""), // previous_block_votes_bitvec: empty
            SYSTEM_CALLER, // proposer: @vm_reserved (对应SYSTEM_CALLER)
            emptyFailedProposerIndices, // failed_proposer_indices: empty
            0 // time_microseconds: 0
        );

        // 将全局时间戳初始化为0
        ITimestamp(TIMESTAMP_ADDR).updateGlobalTime(SYSTEM_CALLER, 0);

        // 触发初始epoch设置（可选，取决于系统设计）
        // 如果需要在创世时设置初始epoch，可以在这里添加相关逻辑
    }
}
