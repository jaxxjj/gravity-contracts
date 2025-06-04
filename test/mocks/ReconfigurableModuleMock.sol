// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

contract ReconfigurableModuleMock {
    uint256 public onNewEpochCallCount;
    bool public shouldRevert;
    string public revertMessage;

    function setRevertBehavior(bool _shouldRevert, string memory _message) external {
        shouldRevert = _shouldRevert;
        revertMessage = _message;
    }

    function onNewEpoch() external {
        if (shouldRevert) {
            revert(revertMessage);
        }
        onNewEpochCallCount++;
    }

    function reset() external {
        onNewEpochCallCount = 0;
        shouldRevert = false;
        revertMessage = "";
    }
}
