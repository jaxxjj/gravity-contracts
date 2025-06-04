// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

contract EpochManagerMock {
    bool public canTriggerEpochTransitionFlag;
    uint256 public triggerEpochTransitionCallCount;

    function setCanTriggerEpochTransition(bool canTrigger) external {
        canTriggerEpochTransitionFlag = canTrigger;
    }

    function canTriggerEpochTransition() external view returns (bool) {
        return canTriggerEpochTransitionFlag;
    }

    function triggerEpochTransition() external {
        triggerEpochTransitionCallCount++;
    }

    function reset() external {
        canTriggerEpochTransitionFlag = false;
        triggerEpochTransitionCallCount = 0;
    }
}
