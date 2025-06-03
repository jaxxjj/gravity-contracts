// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

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
 * @dev Manages blockchain epoch transitions using SystemV2 fixed address constants
 */
contract EpochManager is System, Protectable, IParamSubscriber, IEpochManager, Initializable {
    using Strings for string;

    // ======== State Variables ========
    uint256 public currentEpoch;

    /// @dev Epoch interval time in microseconds
    uint256 public epochIntervalMicrosecs;

    uint256 public lastEpochTransitionTime;

    modifier onlyAuthorizedCallers() {
        if (msg.sender != SYSTEM_CALLER && msg.sender != BLOCK_ADDR) {
            revert NotAuthorized();
        }
        _;
    }

    /**
     * @dev Disable initializers in constructor
     * @custom:oz-upgrades-unsafe-allow constructor
     */
    constructor() {
        _disableInitializers();
    }

    /// @inheritdoc IEpochManager
    function initialize() external initializer onlyGenesis {
        currentEpoch = 0;
        epochIntervalMicrosecs = 2 hours * MICRO_CONVERSION_FACTOR;
        lastEpochTransitionTime = ITimestamp(TIMESTAMP_ADDR).nowSeconds();
    }

    /**
     * @dev Unified parameter update function
     * @param key Parameter name
     * @param value Parameter value
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

    /// @inheritdoc IEpochManager
    function triggerEpochTransition() external onlyAuthorizedCallers {
        uint256 newEpoch = currentEpoch + 1;
        uint256 transitionTime = ITimestamp(TIMESTAMP_ADDR).nowSeconds();

        // Update epoch data
        currentEpoch = newEpoch;
        lastEpochTransitionTime = transitionTime;

        // Notify all system contracts using fixed addresses
        _notifySystemModules();

        // Emit event
        emit EpochTransitioned(newEpoch, transitionTime);
    }

    /// @inheritdoc IEpochManager
    function canTriggerEpochTransition() external view returns (bool) {
        uint256 currentTime = ITimestamp(TIMESTAMP_ADDR).nowSeconds();
        uint256 epoch_interval_seconds = epochIntervalMicrosecs / 1000000;
        return currentTime >= lastEpochTransitionTime + epoch_interval_seconds;
    }

    /// @inheritdoc IEpochManager
    function getCurrentEpochInfo()
        external
        view
        returns (uint256 epoch, uint256 lastTransitionTime, uint256 interval)
    {
        return (currentEpoch, lastEpochTransitionTime, epochIntervalMicrosecs);
    }

    /// @inheritdoc IEpochManager
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
     * @dev Notify all system contracts of epoch transition
     * Uses fixed address constants defined in SystemV2
     */
    function _notifySystemModules() internal {
        _safeNotifyModule(VALIDATOR_MANAGER_ADDR);
    }

    /**
     * @dev Safely notify a single module
     * @param moduleAddress Module address
     */
    function _safeNotifyModule(address moduleAddress) internal {
        if (moduleAddress != address(0)) {
            try IReconfigurableModule(moduleAddress).onNewEpoch() {}
            catch Error(string memory reason) {
                emit ModuleNotificationFailed(moduleAddress, bytes(reason));
            } catch (bytes memory lowLevelData) {
                emit ModuleNotificationFailed(moduleAddress, lowLevelData);
            }
        }
    }
}
