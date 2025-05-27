// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@src/interfaces/IParamSubscriber.sol";

/**
 * @title IEpochManager
 * @dev 定义EpochManager合约的接口，用于管理区块链的纪元转换
 */
interface IEpochManager is IParamSubscriber {
    event EpochTransitioned(uint256 indexed newEpoch, uint256 transitionTime);
    event EpochDurationUpdated(uint256 oldDuration, uint256 newDuration);
    event ModuleNotificationFailed(address indexed module, bytes reason);
    event ConfigParamUpdated(string indexed param, uint256 oldValue, uint256 newValue);

    error EpochDurationNotPassed(uint256 currentTime, uint256 requiredTime);
    error InvalidEpochDuration();
    error NotAuthorized();
    error EpochManager__ParameterNotFound(string param);

    function currentEpoch() external view returns (uint256);
    function epochDuration() external view returns (uint256);
    function lastEpochTransitionTime() external view returns (uint256);

    /**
     * @dev 处理纪元转换，通知所有系统模块
     */
    function triggerEpochTransition() external;

    /**
     * @dev 检查是否可以进行纪元转换
     * @return 如果可以进行纪元转换，则返回 true
     */
    function canTriggerEpochTransition() external view returns (bool);

    /**
     * @dev 获取当前纪元信息
     * @return epoch 当前纪元
     * @return lastTransitionTime 上次纪元转换时间
     * @return duration 纪元持续时间
     */
    function getCurrentEpochInfo()
        external
        view
        returns (uint256 epoch, uint256 lastTransitionTime, uint256 duration);

    /**
     * @dev 获取距离下次epoch切换的剩余时间
     * @return remainingTime 剩余时间（秒）
     */
    function getRemainingTime() external view returns (uint256 remainingTime);
}
