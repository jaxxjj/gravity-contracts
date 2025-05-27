// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@src/System.sol";
import "@src/interfaces/IReconfigurableModule.sol";
import "@src/access/Protectable.sol";
import "@src/interfaces/IParamSubscriber.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@src/interfaces/IEpochManager.sol";
/**
 * @title EpochManager
 * @dev 管理区块链的epoch转换，使用SystemV2的固定地址常量
 * 不需要注册模块，直接调用已知的系统合约地址
 */

contract EpochManager is System, Protectable, IParamSubscriber, IEpochManager {
    using Strings for string;

    // Performance Tracker合约地址（假设部署在0xf0）

    // ======== 状态变量 ========
    uint256 public currentEpoch;
    uint256 public epochDuration;
    uint256 public lastEpochTransitionTime;

    modifier onlyAuthorizedCallers() {
        if (msg.sender != SYSTEM_CALLER && msg.sender != STAKE_HUB_ADDR && msg.sender != BLOCK_ADDR) {
            revert NotAuthorized();
        }
        _;
    }

    // ======== 构造函数 ========
    constructor(uint256 _epochDuration) {
        require(_epochDuration > 0, "EpochManager: epoch duration must be positive");
        currentEpoch = 0;
        epochDuration = _epochDuration;
        lastEpochTransitionTime = block.timestamp;
    }

    /**
     * @dev 统一参数更新函数
     * @param key 参数名称
     * @param value 参数值
     */
    function updateParam(string calldata key, bytes calldata value) external override onlyGov {
        if (Strings.equal(key, "epochDuration")) {
            uint256 newValue = abi.decode(value, (uint256));
            if (newValue == 0) revert InvalidEpochDuration();

            uint256 oldValue = epochDuration;
            epochDuration = newValue;

            emit ConfigParamUpdated("epochDuration", oldValue, newValue);
            emit EpochDurationUpdated(oldValue, newValue);
        } else {
            revert EpochManager__ParameterNotFound(key);
        }

        emit ParamChange(key, value);
    }

    /**
     * @dev 处理epoch转换，通知所有系统模块
     * 只能由系统账户（0x0）调用，通过系统交易触发
     */
    function triggerEpochTransition() external onlyAuthorizedCallers {
        // 检查是否已经过去足够的时间
        if (block.timestamp < lastEpochTransitionTime + epochDuration) {
            revert EpochDurationNotPassed(block.timestamp, lastEpochTransitionTime + epochDuration);
        }

        uint256 newEpoch = currentEpoch + 1;
        uint256 transitionTime = block.timestamp;

        // 更新epoch数据
        currentEpoch = newEpoch;
        lastEpochTransitionTime = transitionTime;

        // 通知所有系统合约（使用固定地址）
        _notifySystemModules(newEpoch, transitionTime);

        // 触发事件
        emit EpochTransitioned(newEpoch, transitionTime);
    }

    /**
     * @dev 检查是否可以进行epoch转换
     * @return 如果可以进行epoch转换，则返回 true
     */
    function canTriggerEpochTransition() external view returns (bool) {
        return block.timestamp >= lastEpochTransitionTime + epochDuration;
    }

    /**
     * @dev 获取当前epoch信息
     * @return epoch 当前epoch
     * @return lastTransitionTime 上次epoch转换时间
     * @return duration epoch持续时间
     */
    function getCurrentEpochInfo()
        external
        view
        returns (uint256 epoch, uint256 lastTransitionTime, uint256 duration)
    {
        return (currentEpoch, lastEpochTransitionTime, epochDuration);
    }

    /**
     * @dev 获取距离下次epoch切换的剩余时间
     * @return remainingTime 剩余时间（秒）
     */
    function getRemainingTime() external view returns (uint256 remainingTime) {
        uint256 nextTransitionTime = lastEpochTransitionTime + epochDuration;
        if (block.timestamp >= nextTransitionTime) {
            return 0;
        }
        return nextTransitionTime - block.timestamp;
    }


    /**
     * @dev 通知所有系统合约epoch切换
     * 使用SystemV2中定义的固定地址常量
     * @param newEpoch 新的epoch编号
     * @param transitionTime epoch切换时间
     */
    function _notifySystemModules(uint256 newEpoch, uint256 transitionTime) internal {
        _safeNotifyModule(STAKE_HUB_ADDR, newEpoch, transitionTime);

        _safeNotifyModule(GOVERNOR_ADDR, newEpoch, transitionTime);

    }

    /**
     * @dev 安全地通知单个模块
     * @param moduleAddress 模块地址
     * @param newEpoch 新epoch
     * @param transitionTime 切换时间
     */
    function _safeNotifyModule(address moduleAddress, uint256 newEpoch, uint256 transitionTime) internal {
        if (moduleAddress != address(0)) {
            try IReconfigurableModule(moduleAddress).onNewEpoch() returns (bool success) {
                if (!success) {
                    emit ModuleNotificationFailed(moduleAddress, "Module returned false");
                }
            } catch Error(string memory reason) {
                emit ModuleNotificationFailed(moduleAddress, bytes(reason));
            } catch (bytes memory lowLevelData) {
                emit ModuleNotificationFailed(moduleAddress, lowLevelData);
            }
        }
    }
}
