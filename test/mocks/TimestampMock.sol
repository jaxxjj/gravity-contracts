// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

contract TimestampMock {
    struct UpdateCall {
        address proposer;
        uint64 timestampMicros;
        uint256 callCount;
    }

    UpdateCall public lastCall;
    uint256 public totalCalls;
    uint256 public mockCurrentTime; // Mock current time in seconds

    function updateGlobalTime(address proposer, uint64 timestampMicros) external {
        lastCall.proposer = proposer;
        lastCall.timestampMicros = timestampMicros;
        lastCall.callCount++;
        totalCalls++;
    }

    function getLastUpdateCall() external view returns (address proposer, uint64 timestampMicros, uint256 callCount) {
        return (lastCall.proposer, lastCall.timestampMicros, lastCall.callCount);
    }

    function setCurrentTime(uint256 timeInSeconds) external {
        mockCurrentTime = timeInSeconds;
    }

    function nowSeconds() external view returns (uint256) {
        return mockCurrentTime;
    }

    function reset() external {
        delete lastCall;
        totalCalls = 0;
        mockCurrentTime = 0;
    }
}
