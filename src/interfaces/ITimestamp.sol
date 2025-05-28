// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

/**
 * @title ITimestamp
 * @dev Interface for the Timestamp contract that manages global time
 */
interface ITimestamp {
    /// Custom errors
    error InvalidTimestamp(uint64 provided, uint64 current);
    error TimestampMustAdvance(uint64 provided, uint64 current);
    error TimestampMustEqual(uint64 provided, uint64 expected);
    error onlyGovAccount();
    error NotTestEnvironment();

    /// Events
    event GlobalTimeUpdated(address indexed proposer, uint64 oldTimestamp, uint64 newTimestamp, bool isNilBlock);

    /// @dev 秒和微秒之间的转换因子
    function MICRO_CONVERSION_FACTOR() external view returns (uint64);

    /// @dev 当前Unix时间（微秒）
    function microseconds() external view returns (uint64);

    /**
     * @dev 通过共识更新全局时间，需要VM权限，在block prologue期间调用
     * @param proposer 提议者地址
     * @param timestamp 新的时间戳（微秒）
     */
    function updateGlobalTime(address proposer, uint64 timestamp) external;

    /**
     * @dev 获取当前时间（微秒）- 任何人都可以调用
     * @return 当前时间，以微秒为单位
     */
    function nowMicroseconds() external view returns (uint64);

    /**
     * @dev 获取当前时间（秒）- 任何人都可以调用
     * @return 当前时间，以秒为单位
     */
    function nowSeconds() external view returns (uint64);

    /**
     * @dev 获取详细的时间信息 - 任何人都可以调用
     * @return currentMicroseconds 当前时间（微秒）
     * @return currentSeconds 当前时间（秒）
     * @return blockTimestamp 当前区块时间戳
     */
    function getTimeInfo()
        external
        view
        returns (uint64 currentMicroseconds, uint64 currentSeconds, uint256 blockTimestamp);

    /**
     * @dev 验证时间戳是否大于当前时间戳
     * @param timestamp 时间戳（微秒）
     * @return 如果时间戳大于当前时间戳，则返回true
     */
    function isGreaterThanOrEqualCurrentTimestamp(uint64 timestamp) external view returns (bool);
}
