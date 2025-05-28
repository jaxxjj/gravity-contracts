// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

import "@src/System.sol";
import "@src/interfaces/ITimestamp.sol";
/**
 * @title Timestamp
 * @dev 复刻Aptos timestamp.move模块，移除了timeStarted相关功能
 */

contract Timestamp is System, ITimestamp {
    /// 秒和微秒之间的转换因子
    uint64 public constant MICRO_CONVERSION_FACTOR = 1000000;

    /// 当前Unix时间（微秒）
    uint64 public microseconds;

    /**
     * @dev 通过共识更新全局时间，需要VM权限，在block prologue期间调用
     * 完全对应Aptos的update_global_time函数
     * @param proposer 提议者地址
     * @param timestamp 新的时间戳（微秒）
     */
    function updateGlobalTime(address proposer, uint64 timestamp) public onlySystemCaller {
        // 获取state里面存储的当前时间
        uint64 currentTime = microseconds;

        if (proposer == SYSTEM_CALLER) {
            // NIL block，提议者为SYSTEM_CALLER，时间戳必须相等
            if (currentTime != timestamp) {
                revert TimestampMustEqual(timestamp, currentTime);
            }
            emit GlobalTimeUpdated(proposer, currentTime, timestamp, true);
        } else {
            // 正常区块，时间必须前进
            if (!_isGreaterThanOrEqualCurrentTimestamp(timestamp)) {
                revert TimestampMustAdvance(timestamp, currentTime);
            }

            // 更新全局时间
            uint64 oldTimestamp = microseconds;
            microseconds = timestamp;

            emit GlobalTimeUpdated(proposer, oldTimestamp, timestamp, false);
        }
    }

    /**
     * @dev 获取当前时间（微秒）- 任何人都可以调用
     * 对应Aptos的now_microseconds函数
     */
    function nowMicroseconds() external view returns (uint64) {
        return microseconds;
    }

    /**
     * @dev 获取当前时间（秒）- 任何人都可以调用
     * 对应Aptos的now_seconds函数
     */
    function nowSeconds() external view returns (uint64) {
        return microseconds / MICRO_CONVERSION_FACTOR;
    }

    /**
     * @dev 获取详细的时间信息 - 任何人都可以调用
     */
    function getTimeInfo()
        external
        view
        returns (uint64 currentMicroseconds, uint64 currentSeconds, uint256 blockTimestamp)
    {
        return (microseconds, microseconds / MICRO_CONVERSION_FACTOR, block.timestamp);
    }

    /**
     * @dev 验证时间戳是否大于当前时间戳
     * @param timestamp 时间戳 微秒
     */
    function isGreaterThanOrEqualCurrentTimestamp(uint64 timestamp) external view returns (bool) {
        return _isGreaterThanOrEqualCurrentTimestamp(timestamp);
    }

    /**
     * @dev 验证时间戳是否大于当前时间戳
     * @param timestamp 时间戳 微秒
     */
    function _isGreaterThanOrEqualCurrentTimestamp(uint64 timestamp) private view returns (bool) {
        return timestamp >= microseconds;
    }
}
