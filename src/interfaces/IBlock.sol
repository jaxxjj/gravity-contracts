// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

/**
 * @title IBlock
 * @dev 区块模块接口，定义了区块相关操作和事件
 */
interface IBlock {
    /**
     * @dev 新区块事件，记录每个区块的关键信息
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
     * @dev genesis的时候初始化合约
     */
    function init() external;

    /**
     * @dev 区块开始时调用，执行必要的系统逻辑
     * 对应Aptos block_prologue_common的流程
     * @param proposer 当前块的提议者地址，如果为SYSTEM_CALLER则表示VM保留地址
     * @param failedProposerIndices 失败的提议者索引列表
     * @param timestampMicros 当前块的时间戳（微秒）
     */
    function blockPrologue(address proposer, uint64[] calldata failedProposerIndices, uint256 timestampMicros) external;
}
