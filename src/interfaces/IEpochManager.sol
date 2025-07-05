// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "@src/interfaces/IParamSubscriber.sol";
import "@src/interfaces/IValidatorManager.sol";

/**
 * @title IEpochManager
 * @dev Interface for EpochManager contract that manages blockchain epoch transitions
 */
interface IEpochManager is IParamSubscriber {
    event EpochTransitioned(uint256 indexed newEpoch, uint256 transitionTime);
    event EpochDurationUpdated(uint256 oldDuration, uint256 newDuration);
    event ModuleNotificationFailed(address indexed module, bytes reason);
    event ConfigParamUpdated(string indexed param, uint256 oldValue, uint256 newValue);

    error InvalidEpochDuration();
    error NotAuthorized();
    error EpochManager__ParameterNotFound(string param);
    /**
     * @dev Get current epoch number
     * @return Current epoch number
     */

    function currentEpoch() external view returns (uint256);

    /**
     * @dev Get epoch interval in microseconds
     * @return Epoch interval in microseconds
     */
    function epochIntervalMicrosecs() external view returns (uint256);

    /**
     * @dev Get last epoch transition time
     * @return Last epoch transition timestamp
     */
    function lastEpochTransitionTime() external view returns (uint256);

    /**
     * @dev Initialize the contract
     */
    function initialize() external;

    /**
     * @dev Trigger epoch transition and notify all system modules
     */
    function triggerEpochTransition() external;

    /**
     * @dev Check if epoch transition can be triggered
     * @return Whether epoch transition can be triggered
     */
    function canTriggerEpochTransition() external view returns (bool);

    /**
     * @dev Get current epoch information
     * @return epoch Current epoch number
     * @return lastTransitionTime Last epoch transition time
     * @return duration Epoch duration in microseconds
     */
    function getCurrentEpochInfo()
        external
        view
        returns (uint256 epoch, uint256 lastTransitionTime, uint256 duration);

    /**
     * @dev Get remaining time until next epoch transition
     * @return remainingTime Remaining time in seconds
     */
    function getRemainingTime() external view returns (uint256 remainingTime);
}
