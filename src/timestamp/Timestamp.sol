// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

import "@src/System.sol";

/**
 * @title Timestamp
 * @dev 复刻Aptos timestamp.move模块
 */
contract Timestamp is System {

    /// 秒和微秒之间的转换因子
    uint64 public constant MICRO_CONVERSION_FACTOR = 1000000;

    /// 当前Unix时间（微秒）
    uint64 public microseconds;

    /// 时间是否已经开始
    bool public timeStarted;


    error InvalidTimestamp(uint64 provided, uint64 current);
    error TimestampMustAdvance(uint64 provided, uint64 current);
    error TimestampMustEqual(uint64 provided, uint64 expected);
    error TimeNotStarted();
    error TimeAlreadyStarted();
    error onlyGovAccount();
    error NotTestEnvironment();

    event TimeStarted(uint64 initialTimestamp);
    event GlobalTimeUpdated(address indexed proposer, uint64 oldTimestamp, uint64 newTimestamp, bool isNilBlock);


    /// 检查时间是否已开始
    modifier requireTimeStarted() {
        if (!timeStarted) revert TimeNotStarted();
        _;
    }

    /// 检查时间未开始
    modifier requireTimeNotStarted() {
        if (timeStarted) revert TimeAlreadyStarted();
        _;
    }

    /**
     * @dev 使用当前区块时间戳初始化（SystemCaller专用）
     */
    function setTimeHasStartedWithCurrentTime() external onlySystemCaller requireTimeNotStarted {
        uint64 currentTimeMicros = uint64(block.timestamp * MICRO_CONVERSION_FACTOR);
        setTimeHasStarted(currentTimeMicros);
    }

    /**
     * @dev 标记时间已开始，只能从genesis调用且需要SystemCaller权限
     * 对应Aptos的set_time_has_started函数
     * @param initialTimestamp 初始时间戳（微秒）
     */
    function setTimeHasStarted(uint64 initialTimestamp) public onlySystemCaller requireTimeNotStarted {
        timeStarted = true;
        microseconds = initialTimestamp;

        emit TimeStarted(initialTimestamp);
    }

    /**
     * @dev 通过共识更新全局时间，需要VM权限，在block prologue期间调用
     * 完全对应Aptos的update_global_time函数
     * @param proposer 提议者地址
     * @param timestamp 新的时间戳（微秒）
     */
    function updateGlobalTime(address proposer, uint64 timestamp) public onlyGov requireTimeStarted {
        uint64 now = microseconds;
        bool isNilBlock = (proposer == DEAD_ADDRESS);

        if (isNilBlock) {
            // NIL block，提议者为null地址，时间戳必须相等
            if (now != timestamp) {
                revert TimestampMustEqual(timestamp, now);
            }
            emit GlobalTimeUpdated(proposer, now, timestamp, true);
        } else {
            // 正常区块，时间必须前进
            if (now >= timestamp) {
                revert TimestampMustAdvance(timestamp, now);
            }

            // 更新全局时间
            uint64 oldTimestamp = microseconds;
            microseconds = timestamp;

            emit GlobalTimeUpdated(proposer, oldTimestamp, timestamp, false);
        }
    }

    /**
     * @dev 便利函数：使用秒为单位更新时间（VM专用）
     */
    function updateGlobalTimeSeconds(address proposer, uint64 timestampSeconds) external onlyGov requireTimeStarted {
        updateGlobalTime(proposer, timestampSeconds * MICRO_CONVERSION_FACTOR);
    }

    /**
     * @dev 获取当前时间（微秒）- 任何人都可以调用
     * 对应Aptos的now_microseconds函数
     */
    function nowMicroseconds() external view requireTimeStarted returns (uint64) {
        return microseconds;
    }

    /**
     * @dev 获取当前时间（秒）- 任何人都可以调用
     * 对应Aptos的now_seconds函数
     */
    function nowSeconds() external view requireTimeStarted returns (uint64) {
        return microseconds / MICRO_CONVERSION_FACTOR;
    }

    /**
     * @dev 检查时间是否已初始化 - 任何人都可以调用
     */
    function isTimeStarted() external view returns (bool) {
        return timeStarted;
    }

    /**
     * @dev 获取详细的时间信息 - 任何人都可以调用
     */
    function getTimeInfo()
        external
        view
        returns (bool started, uint64 currentMicroseconds, uint64 currentSeconds, uint256 blockTimestamp)
    {
        return (
            timeStarted,
            timeStarted ? microseconds : 0,
            timeStarted ? microseconds / MICRO_CONVERSION_FACTOR : 0,
            block.timestamp
        );
    }

    /**
     * @dev 验证时间戳是否有效
     */
    function isValidTimestamp(uint64 timestamp) external view requireTimeStarted returns (bool) {
        return timestamp > microseconds;
    }

    /**
     * @dev 秒转微秒
     */
    function secondsToMicroseconds(uint64 secondsValue) external pure returns (uint64) {
        return secondsValue * MICRO_CONVERSION_FACTOR;
    }

    /**
     * @dev 微秒转秒
     */
    function microsecondsToSeconds(uint64 micros) external pure returns (uint64) {
        return micros / MICRO_CONVERSION_FACTOR;
    }

    /**
     * @dev 将Solidity的block.timestamp转换为微秒
     */
    function blockTimestampMicros() external view returns (uint64) {
        return uint64(block.timestamp * MICRO_CONVERSION_FACTOR);
    }
}
