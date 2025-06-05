// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/**
 * @title IReconfigurableModule
 * @dev Interface for reconfigurable modules that need to respond to new epoch
 */
interface IReconfigurableModule {
    /**
     * @dev Called when new epoch starts, allowing module to update its state
     */
    function onNewEpoch() external;
}
