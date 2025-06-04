// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "forge-std/Test.sol";
import "@src/epoch/EpochManager.sol";
import "@test/mocks/TimestampMock.sol";
import "@test/mocks/ReconfigurableModuleMock.sol";
import "@test/utils/TestConstants.sol";
import { IEpochManager } from "@src/interfaces/IEpochManager.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { System } from "@src/System.sol";

contract EpochManagerTest is Test, TestConstants {
    EpochManager epochManager;
    EpochManager implementation;
    TimestampMock timestampContract;
    ReconfigurableModuleMock validatorManager;

    uint256 constant INITIAL_TIME = 1000000; // Initial timestamp
    uint256 constant DEFAULT_EPOCH_INTERVAL = 2 hours * 1000000; // 2 hours in microseconds

    function setUp() public {
        // Deploy mock contracts
        timestampContract = new TimestampMock();
        validatorManager = new ReconfigurableModuleMock();

        // Deploy implementation contract
        implementation = new EpochManager();

        // Deploy proxy with empty initialization data (we'll call initialize separately)
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), "");
        epochManager = EpochManager(address(proxy));

        // Deploy mock contracts to system addresses
        vm.etch(TIMESTAMP_ADDR, address(timestampContract).code);
        vm.etch(VALIDATOR_MANAGER_ADDR, address(validatorManager).code);

        // Set up mock data AFTER vm.etch
        TimestampMock(TIMESTAMP_ADDR).setCurrentTime(INITIAL_TIME);
    }

    function test_initialize_shouldSetInitialValues() public {
        // Arrange
        vm.startPrank(GENESIS_ADDR);

        // Act
        epochManager.initialize();

        // Assert
        assertEq(epochManager.currentEpoch(), 0);
        assertEq(epochManager.epochIntervalMicrosecs(), DEFAULT_EPOCH_INTERVAL);
        assertEq(epochManager.lastEpochTransitionTime(), INITIAL_TIME);

        vm.stopPrank();
    }

    function test_initialize_revertsIfNotCalledByGenesis() public {
        // Arrange & Act & Assert
        vm.startPrank(NOT_GENESIS);
        vm.expectRevert(); // Should revert with onlyGenesis modifier
        epochManager.initialize();
        vm.stopPrank();
    }

    function test_updateParam_epochIntervalMicrosecs_shouldUpdateValue() public {
        // Arrange
        vm.startPrank(GENESIS_ADDR);
        epochManager.initialize();
        vm.stopPrank();

        vm.startPrank(GOV_HUB_ADDR); // Use GOV_HUB_ADDR for governance calls
        uint256 newInterval = 3 hours * 1000000;
        bytes memory encodedValue = abi.encode(newInterval);

        // Act & Assert
        vm.expectEmit(true, false, false, true);
        emit IEpochManager.ConfigParamUpdated("epochIntervalMicrosecs", DEFAULT_EPOCH_INTERVAL, newInterval);
        vm.expectEmit(true, false, false, true);
        emit IEpochManager.EpochDurationUpdated(DEFAULT_EPOCH_INTERVAL, newInterval);
        vm.expectEmit(true, false, false, true);
        emit System.ParamChange("epochIntervalMicrosecs", encodedValue);

        epochManager.updateParam("epochIntervalMicrosecs", encodedValue);

        // Assert
        assertEq(epochManager.epochIntervalMicrosecs(), newInterval);

        vm.stopPrank();
    }

    function test_updateParam_invalidKey_shouldRevert() public {
        // Arrange
        vm.startPrank(GENESIS_ADDR);
        epochManager.initialize();
        vm.stopPrank();

        vm.startPrank(GOV_HUB_ADDR);
        bytes memory encodedValue = abi.encode(uint256(123));

        // Act & Assert
        vm.expectRevert();
        epochManager.updateParam("invalidKey", encodedValue);

        vm.stopPrank();
    }

    function test_updateParam_zeroValue_shouldRevert() public {
        // Arrange
        vm.startPrank(GENESIS_ADDR);
        epochManager.initialize();
        vm.stopPrank();

        vm.startPrank(GOV_HUB_ADDR);
        bytes memory encodedValue = abi.encode(uint256(0));

        // Act & Assert
        vm.expectRevert(); // Should revert with InvalidEpochDuration
        epochManager.updateParam("epochIntervalMicrosecs", encodedValue);

        vm.stopPrank();
    }

    function test_triggerEpochTransition_shouldIncrementEpoch() public {
        // Arrange
        vm.startPrank(GENESIS_ADDR);
        epochManager.initialize();
        vm.stopPrank();

        uint256 newTime = INITIAL_TIME + 1000;
        TimestampMock(TIMESTAMP_ADDR).setCurrentTime(newTime);

        vm.startPrank(SYSTEM_CALLER);

        // Act & Assert
        vm.expectEmit(true, false, false, true);
        emit IEpochManager.EpochTransitioned(1, newTime);

        epochManager.triggerEpochTransition();

        // Assert
        assertEq(epochManager.currentEpoch(), 1);
        assertEq(epochManager.lastEpochTransitionTime(), newTime);
        assertEq(ReconfigurableModuleMock(VALIDATOR_MANAGER_ADDR).onNewEpochCallCount(), 1);

        vm.stopPrank();
    }

    function test_triggerEpochTransition_fromBlockContract_shouldWork() public {
        // Arrange
        vm.startPrank(GENESIS_ADDR);
        epochManager.initialize();
        vm.stopPrank();

        vm.startPrank(BLOCK_ADDR);

        // Act
        epochManager.triggerEpochTransition();

        // Assert
        assertEq(epochManager.currentEpoch(), 1);

        vm.stopPrank();
    }

    function test_triggerEpochTransition_notAuthorized_shouldRevert() public {
        // Arrange
        vm.startPrank(GENESIS_ADDR);
        epochManager.initialize();
        vm.stopPrank();

        vm.startPrank(NOT_SYSTEM_CALLER);

        // Act & Assert
        vm.expectRevert(); // Should revert with NotAuthorized
        epochManager.triggerEpochTransition();

        vm.stopPrank();
    }

    function test_canTriggerEpochTransition_beforeInterval_shouldReturnFalse() public {
        // Arrange
        vm.startPrank(GENESIS_ADDR);
        epochManager.initialize();
        vm.stopPrank();

        // Set current time to 1 hour after initialization (less than 2 hour interval)
        uint256 currentTime = INITIAL_TIME + 1 hours;
        TimestampMock(TIMESTAMP_ADDR).setCurrentTime(currentTime);

        // Act
        bool canTrigger = epochManager.canTriggerEpochTransition();

        // Assert
        assertFalse(canTrigger);
    }

    function test_canTriggerEpochTransition_afterInterval_shouldReturnTrue() public {
        // Arrange
        vm.startPrank(GENESIS_ADDR);
        epochManager.initialize();
        vm.stopPrank();

        // Set current time to 3 hours after initialization (more than 2 hour interval)
        uint256 currentTime = INITIAL_TIME + 3 hours;
        TimestampMock(TIMESTAMP_ADDR).setCurrentTime(currentTime);

        // Act
        bool canTrigger = epochManager.canTriggerEpochTransition();

        // Assert
        assertTrue(canTrigger);
    }

    function test_canTriggerEpochTransition_exactInterval_shouldReturnTrue() public {
        // Arrange
        vm.startPrank(GENESIS_ADDR);
        epochManager.initialize();
        vm.stopPrank();

        // Set current time to exactly 2 hours after initialization
        uint256 currentTime = INITIAL_TIME + 2 hours;
        TimestampMock(TIMESTAMP_ADDR).setCurrentTime(currentTime);

        // Act
        bool canTrigger = epochManager.canTriggerEpochTransition();

        // Assert
        assertTrue(canTrigger);
    }

    function test_getCurrentEpochInfo_shouldReturnCorrectValues() public {
        // Arrange
        vm.startPrank(GENESIS_ADDR);
        epochManager.initialize();
        vm.stopPrank();

        // Act
        (uint256 epoch, uint256 lastTransitionTime, uint256 interval) = epochManager.getCurrentEpochInfo();

        // Assert
        assertEq(epoch, 0);
        assertEq(lastTransitionTime, INITIAL_TIME);
        assertEq(interval, DEFAULT_EPOCH_INTERVAL);
    }

    function test_getRemainingTime_beforeInterval_shouldReturnCorrectTime() public {
        // Arrange
        vm.startPrank(GENESIS_ADDR);
        epochManager.initialize();
        vm.stopPrank();

        // Set current time to 1 hour after initialization
        uint256 currentTime = INITIAL_TIME + 1 hours;
        TimestampMock(TIMESTAMP_ADDR).setCurrentTime(currentTime);

        // Act
        uint256 remainingTime = epochManager.getRemainingTime();

        // Assert
        assertEq(remainingTime, 1 hours); // Should have 1 hour remaining
    }

    function test_getRemainingTime_afterInterval_shouldReturnZero() public {
        // Arrange
        vm.startPrank(GENESIS_ADDR);
        epochManager.initialize();
        vm.stopPrank();

        // Set current time to 3 hours after initialization
        uint256 currentTime = INITIAL_TIME + 3 hours;
        TimestampMock(TIMESTAMP_ADDR).setCurrentTime(currentTime);

        // Act
        uint256 remainingTime = epochManager.getRemainingTime();

        // Assert
        assertEq(remainingTime, 0);
    }

    function test_notifySystemModules_shouldCallOnNewEpoch() public {
        // Arrange
        vm.startPrank(GENESIS_ADDR);
        epochManager.initialize();
        vm.stopPrank();

        vm.startPrank(SYSTEM_CALLER);

        // Act
        epochManager.triggerEpochTransition();

        // Assert
        assertEq(ReconfigurableModuleMock(VALIDATOR_MANAGER_ADDR).onNewEpochCallCount(), 1);

        vm.stopPrank();
    }

    function test_notifySystemModules_shouldHandleFailures() public {
        // Arrange
        vm.startPrank(GENESIS_ADDR);
        epochManager.initialize();
        vm.stopPrank();

        // Set validator manager to revert
        ReconfigurableModuleMock(VALIDATOR_MANAGER_ADDR).setRevertBehavior(true, "Test revert");

        vm.startPrank(SYSTEM_CALLER);

        // Act & Assert - Should emit ModuleNotificationFailed event
        vm.expectEmit(true, false, false, false);
        emit IEpochManager.ModuleNotificationFailed(VALIDATOR_MANAGER_ADDR, bytes("Test revert"));

        epochManager.triggerEpochTransition();

        // Should still increment epoch despite notification failure
        assertEq(epochManager.currentEpoch(), 1);

        vm.stopPrank();
    }

    function test_multipleEpochTransitions_shouldIncrementCorrectly() public {
        // Arrange
        vm.startPrank(GENESIS_ADDR);
        epochManager.initialize();
        vm.stopPrank();

        vm.startPrank(SYSTEM_CALLER);

        // Act - Trigger multiple transitions
        for (uint256 i = 1; i <= 5; i++) {
            uint256 newTime = INITIAL_TIME + (i * 1000);
            TimestampMock(TIMESTAMP_ADDR).setCurrentTime(newTime);

            epochManager.triggerEpochTransition();

            // Assert
            assertEq(epochManager.currentEpoch(), i);
            assertEq(epochManager.lastEpochTransitionTime(), newTime);
        }

        vm.stopPrank();
    }

    function test_updateParam_afterEpochTransition_shouldWork() public {
        // Arrange
        vm.startPrank(GENESIS_ADDR);
        epochManager.initialize();
        vm.stopPrank();

        // Trigger epoch transition first
        vm.startPrank(SYSTEM_CALLER);
        epochManager.triggerEpochTransition();
        vm.stopPrank();

        // Update parameter
        vm.startPrank(GOV_HUB_ADDR);
        uint256 newInterval = 4 hours * 1000000;
        bytes memory encodedValue = abi.encode(newInterval);
        epochManager.updateParam("epochIntervalMicrosecs", encodedValue);

        // Assert
        assertEq(epochManager.epochIntervalMicrosecs(), newInterval);
        assertEq(epochManager.currentEpoch(), 1);

        vm.stopPrank();
    }
}
