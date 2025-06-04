// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

contract ValidatorPerformanceTrackerMock {
    // Track calls made to updatePerformanceStatistics
    struct UpdateCall {
        uint64 proposerIndex;
        uint64[] failedProposerIndices;
        uint256 callCount;
    }

    UpdateCall public lastCall;
    uint256 public totalCalls;

    function updatePerformanceStatistics(uint64 proposerIndex, uint64[] calldata failedProposerIndices) external {
        lastCall.proposerIndex = proposerIndex;
        lastCall.failedProposerIndices = failedProposerIndices;
        lastCall.callCount++;
        totalCalls++;
    }

    function getLastCallData()
        external
        view
        returns (uint64 proposerIndex, uint64[] memory failedProposerIndices, uint256 callCount)
    {
        return (lastCall.proposerIndex, lastCall.failedProposerIndices, lastCall.callCount);
    }

    function reset() external {
        delete lastCall;
        totalCalls = 0;
    }
}
