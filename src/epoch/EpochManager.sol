// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@src/System.sol";
import "@src/interfaces/IReconfigurableModule.sol";
import "@src/access/Protectable.sol";
import "@src/interfaces/IParamSubscriber.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@src/interfaces/IEpochManager.sol";
import "@src/interfaces/ITimestamp.sol";
import "@openzeppelin-upgrades/proxy/utils/Initializable.sol";
/**
 * @title EpochManager
 * @dev 管理区块链的epoch转换，使用SystemV2的固定地址常量
 * 不需要注册模块，直接调用已知的系统合约地址
 */

contract EpochManager is System, Protectable, IParamSubscriber, IEpochManager, Initializable {
    using Strings for string;

    // Performance Tracker合约地址（假设部署在0xf0）

    // ======== 状态变量 ========
    uint256 public currentEpoch;

    /// @dev Epoch间隔时间（微秒）
    uint256 public epochIntervalMicrosecs;

    uint256 public lastEpochTransitionTime;

    modifier onlyAuthorizedCallers() {
        if (msg.sender != SYSTEM_CALLER && msg.sender != BLOCK_ADDR) {
            revert NotAuthorized();
        }
        _;
    }

    /**
     * @dev 禁用构造函数中的初始化器
     * @custom:oz-upgrades-unsafe-allow constructor
     */
    constructor() {
        _disableInitializers();
    }

    /**
     * @dev 初始化函数，替代构造函数用于代理模式
     */
    function initialize() external initializer {
        currentEpoch = 0;
        epochIntervalMicrosecs = 2 hours * MICRO_CONVERSION_FACTOR;
        lastEpochTransitionTime = ITimestamp(TIMESTAMP_ADDR).nowSeconds();
    }

    /**
     * @dev 统一参数更新函数
     * @param key 参数名称
     * @param value 参数值
     */
    function updateParam(string calldata key, bytes calldata value) external override onlyGov {
        if (Strings.equal(key, "epochIntervalMicrosecs")) {
            uint256 newValue = abi.decode(value, (uint256));
            if (newValue == 0) revert InvalidEpochDuration();

            uint256 oldValue = epochIntervalMicrosecs;
            epochIntervalMicrosecs = newValue;

            emit ConfigParamUpdated("epochIntervalMicrosecs", oldValue, newValue);
            emit EpochDurationUpdated(oldValue, newValue);
        } else {
            revert EpochManager__ParameterNotFound(key);
        }

        emit ParamChange(key, value);
    }

    /**
     * @dev 处理epoch转换，通知所有系统模块
     * 只能由系统账户（0x0）或者block模块调用
     */
    function triggerEpochTransition() external onlyAuthorizedCallers {
        uint256 newEpoch = currentEpoch + 1;
        uint256 transitionTime = ITimestamp(TIMESTAMP_ADDR).nowSeconds();

        // 更新epoch数据
        currentEpoch = newEpoch;
        lastEpochTransitionTime = transitionTime;

        // 通知所有系统合约（使用固定地址）
        _notifySystemModules();

        // 触发事件
        emit EpochTransitioned(newEpoch, transitionTime);
    }

    /**
     * @dev 检查是否可以进行epoch转换
     * @return 如果可以进行epoch转换，则返回 true
     */
    function canTriggerEpochTransition() external view returns (bool) {
        uint256 currentTime = ITimestamp(TIMESTAMP_ADDR).nowSeconds();
        uint256 epoch_interval_seconds = epochIntervalMicrosecs / 1000000;
        return currentTime >= lastEpochTransitionTime + epoch_interval_seconds;
    }

    /**
     * @dev 获取当前epoch信息
     * @return epoch 当前epoch
     * @return lastTransitionTime 上次epoch转换时间
     * @return interval epoch持续时间（微秒）
     */
    function getCurrentEpochInfo() external view returns (uint256 epoch, uint256 lastTransitionTime, uint256 interval) {
        return (currentEpoch, lastEpochTransitionTime, epochIntervalMicrosecs);
    }

    /**
     * @dev 获取距离下次epoch切换的剩余时间
     * @return remainingTime 剩余时间（秒）
     */
    function getRemainingTime() external view returns (uint256 remainingTime) {
        uint256 currentTime = ITimestamp(TIMESTAMP_ADDR).nowSeconds();
        uint256 epoch_interval_seconds = epochIntervalMicrosecs / 1000000;
        uint256 nextTransitionTime = lastEpochTransitionTime + epoch_interval_seconds;

        if (currentTime >= nextTransitionTime) {
            return 0;
        }
        return nextTransitionTime - currentTime;
    }

    /**
     * @dev 通知所有系统合约epoch切换
     * 使用SystemV2中定义的固定地址常量
     */
    function _notifySystemModules() internal {
        _safeNotifyModule(VALIDATOR_MANAGER_ADDR);
    }

    /**
     * @dev 安全地通知单个模块
     * @param moduleAddress 模块地址
     */
    function _safeNotifyModule(address moduleAddress) internal {
        if (moduleAddress != address(0)) {
            try IReconfigurableModule(moduleAddress).onNewEpoch() {} catch Error(string memory reason) {
                emit ModuleNotificationFailed(moduleAddress, bytes(reason));
            } catch (bytes memory lowLevelData) {
                emit ModuleNotificationFailed(moduleAddress, lowLevelData);
            }
        }
    }
}
