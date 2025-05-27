// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@src/interfaces/IReconfigurableModule.sol";
import "@src/interfaces/IStakeConfig.sol";
import "@src/interfaces/IStakeCredit.sol";
import "@src/interfaces/IValidatorManager.sol";
import "@src/interfaces/IValidatorPerformanceTracker.sol";
import "@src/System.sol";

contract StakeHub is System, IReconfigurableModule {
    function onNewEpoch() external returns (bool) {
        IValidatorManager(VALIDATOR_MANAGER_ADDR).onNewEpoch();
        IValidatorPerformanceTracker(VALIDATOR_PERFORMANCE_TRACKER_ADDR).onNewEpoch();
        return true;
    }
}
