// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

/**
 * @title IBlock
 * @dev Interface for Block module that defines block-related operations and events
 */
interface IBlock {
    /**
     * @dev New block event that records key information for each block
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
     * @dev Error thrown when an invalid proposer is provided
     */
    error InvalidProposer(address proposer);

    /**
     * @dev Initialize the contract during genesis
     */
    function initialize() external;

    /**
     * @dev Called at the beginning of each block to execute necessary system logic
     * @param proposer Current block proposer address, SYSTEM_CALLER indicates VM reserved address
     * @param failedProposerIndices List of failed proposer indices
     * @param timestampMicros Current block timestamp in microseconds
     */
    function blockPrologue(address proposer, uint64[] calldata failedProposerIndices, uint256 timestampMicros)
        external;
}
