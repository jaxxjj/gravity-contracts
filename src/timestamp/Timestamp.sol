// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

import "@src/System.sol";
import "@src/interfaces/ITimestamp.sol";

/**
 * @title Timestamp
 * @dev Replicates Aptos timestamp.move module, with timeStarted functionality removed
 */
contract Timestamp is System, ITimestamp {
    /// @dev Conversion factor between seconds and microseconds
    uint64 public constant MICRO_CONVERSION_FACTOR = 1_000_000;
    uint64 public microseconds;

    /**
     * @dev Updates global time through consensus, requires VM permission, called during block prologue
     * Corresponds exactly to Aptos's update_global_time function
     * @param proposer Proposer address
     * @param timestamp New timestamp in microseconds
     */
    function updateGlobalTime(address proposer, uint64 timestamp) public onlyBlock {
        // Get current time stored in state
        uint64 currentTime = microseconds;

        if (proposer == SYSTEM_CALLER) {
            // NIL block, proposer is SYSTEM_CALLER, timestamp must be equal
            if (currentTime != timestamp) {
                revert TimestampMustEqual(timestamp, currentTime);
            }
            emit GlobalTimeUpdated(proposer, currentTime, timestamp, true);
        } else {
            // Normal block, time must advance
            if (!_isGreaterThanOrEqualCurrentTimestamp(timestamp)) {
                revert TimestampMustAdvance(timestamp, currentTime);
            }

            // Update global time
            uint64 oldTimestamp = microseconds;
            microseconds = timestamp;

            emit GlobalTimeUpdated(proposer, oldTimestamp, timestamp, false);
        }
    }

    /**
     * @dev Get current time in microseconds - callable by anyone
     * Corresponds to Aptos's now_microseconds function
     */
    function nowMicroseconds() external view returns (uint64) {
        return microseconds;
    }

    /**
     * @dev Get current time in seconds - callable by anyone
     * Corresponds to Aptos's now_seconds function
     */
    function nowSeconds() external view returns (uint64) {
        return microseconds / MICRO_CONVERSION_FACTOR;
    }

    /**
     * @dev Get detailed time information - callable by anyone
     */
    function getTimeInfo()
        external
        view
        returns (uint64 currentMicroseconds, uint64 currentSeconds, uint256 blockTimestamp)
    {
        return (microseconds, microseconds / MICRO_CONVERSION_FACTOR, block.timestamp);
    }

    /**
     * @dev Verify if timestamp is greater than or equal to current timestamp
     * @param timestamp Timestamp in microseconds
     */
    function isGreaterThanOrEqualCurrentTimestamp(
        uint64 timestamp
    ) external view returns (bool) {
        return _isGreaterThanOrEqualCurrentTimestamp(timestamp);
    }

    /**
     * @dev Internal function to verify if timestamp is greater than or equal to current timestamp
     * @param timestamp Timestamp in microseconds
     */
    function _isGreaterThanOrEqualCurrentTimestamp(
        uint64 timestamp
    ) private view returns (bool) {
        return timestamp >= microseconds;
    }
}
