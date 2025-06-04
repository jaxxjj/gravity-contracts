// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

/**
 * @title ITimestamp
 * @dev Interface for the Timestamp contract - replicates Aptos timestamp.move module with timeStarted functionality removed
 */
interface ITimestamp {
    /**
     * @dev Emitted when global time is updated through consensus
     * @param proposer The address of the block proposer
     * @param oldTimestamp The previous timestamp in microseconds
     * @param newTimestamp The new timestamp in microseconds
     * @param isNilBlock Whether this is a NIL block (proposer is SYSTEM_CALLER)
     */
    event GlobalTimeUpdated(address indexed proposer, uint64 oldTimestamp, uint64 newTimestamp, bool isNilBlock);

    error TimestampMustEqual(uint64 providedTimestamp, uint64 currentTimestamp);

    error TimestampMustAdvance(uint64 providedTimestamp, uint64 currentTimestamp);

    /**
     * @dev Updates global time through consensus, requires VM permissions, called during block prologue
     * Corresponds exactly to Aptos's update_global_time function
     * @param proposer The proposer's address
     * @param timestamp The new timestamp in microseconds
     */
    function updateGlobalTime(address proposer, uint64 timestamp) external;

    /**
     * @dev Gets the current time in microseconds - callable by anyone
     * Corresponds to Aptos's now_microseconds function
     * @return The current Unix timestamp in microseconds
     */
    function nowMicroseconds() external view returns (uint64);

    /**
     * @dev Gets the current time in seconds - callable by anyone
     * Corresponds to Aptos's now_seconds function
     * @return The current Unix timestamp in seconds
     */
    function nowSeconds() external view returns (uint64);

    /**
     * @dev Gets detailed time information - callable by anyone
     * @return currentMicroseconds The current timestamp in microseconds
     * @return currentSeconds The current timestamp in seconds
     * @return blockTimestamp The current block.timestamp (for comparison)
     */
    function getTimeInfo()
        external
        view
        returns (uint64 currentMicroseconds, uint64 currentSeconds, uint256 blockTimestamp);

    /**
     * @dev Verifies if the timestamp is greater than or equal to the current timestamp
     * @param timestamp The timestamp to verify in microseconds
     * @return Whether the timestamp is greater than or equal to current timestamp
     */
    function isGreaterThanOrEqualCurrentTimestamp(uint64 timestamp) external view returns (bool);
}
