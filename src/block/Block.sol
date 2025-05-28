// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

import "@src/System.sol";
import "@src/interfaces/IValidatorPerformanceTracker.sol";
import "@src/interfaces/IValidatorManager.sol";
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
     * @param proposer 当前块的提议者地址，如果为SYSTEM_CALLER则表示VM保留地址
     * @param failedProposerIndices 失败的提议者索引列表
     * @param timestampMicros 当前块的时间戳（微秒）
     */
    function blockPrologue(address proposer, uint64[] calldata failedProposerIndices, uint256 timestampMicros)
        external
        onlySystemCaller
    {
        // 1. 验证提议者是否有效（对应Aptos的assert检查）
        require(
            proposer == SYSTEM_CALLER || IValidatorManager(VALIDATOR_MANAGER_ADDR).isCurrentEpochValidator(proposer),
            "Invalid proposer"
        );

        // 2. 计算提议者索引（对应Aptos的proposer_index计算）
        uint64 proposerIndex;
        bool hasProposerIndex = false;

        if (proposer != SYSTEM_CALLER) {
            // 从ValidatorManager获取提议者索引
            proposerIndex = IValidatorManager(VALIDATOR_MANAGER_ADDR).getValidatorIndex(proposer);
            hasProposerIndex = true;
        }
        // 如果proposer == SYSTEM_CALLER，则hasProposerIndex保持false，对应Aptos的option::none()

        // 3. 更新全局时间戳
        ITimestamp(TIMESTAMP_ADDR).updateGlobalTime(proposer, uint64(timestampMicros));

        // 4. 更新验证者性能统计
        // 对应Aptos中的update_performance_statistics调用
        if (hasProposerIndex) {
            IValidatorPerformanceTracker(VALIDATOR_PERFORMANCE_TRACKER_ADDR).updatePerformanceStatistics(
                proposerIndex, failedProposerIndices
            );
        } else {
            // 对于VM保留地址，传入无效索引标记
            IValidatorPerformanceTracker(VALIDATOR_PERFORMANCE_TRACKER_ADDR).updatePerformanceStatistics(
                type(uint64).max, failedProposerIndices
            );
        }

        // 5. 检查是否需要进行Epoch转换
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
    }
}
