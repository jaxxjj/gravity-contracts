// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@src/interfaces/IReconfigurableModule.sol";
import "@src/interfaces/IValidatorManager.sol";
import "@src/interfaces/IValidatorPerformanceTracker.sol";
import "@src/System.sol";
import "@openzeppelin-upgrades/proxy/utils/Initializable.sol";

contract StakeHub is System, IReconfigurableModule, Initializable {
    /**
     * @dev 禁用构造函数中的初始化器
     * @custom:oz-upgrades-unsafe-allow constructor
     */
    constructor() {
        _disableInitializers();
    }
    
    /**
     * @dev 处理epoch转换
     */
    function onNewEpoch() external override returns (bool) {
        IValidatorManager(VALIDATOR_MANAGER_ADDR).onNewEpoch();
        IValidatorPerformanceTracker(VALIDATOR_PERFORMANCE_TRACKER_ADDR).onNewEpoch();
        return true;
    }
}
