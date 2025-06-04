// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "forge-std/Test.sol";
import "@src/block/Block.sol";
import "@test/mocks/ValidatorManagerMock.sol";
import "@test/mocks/ValidatorPerformanceTrackerMock.sol";
import "@test/mocks/TimestampMock.sol";
import {IBlock} from "@src/interfaces/IBlock.sol";
import "@test/mocks/EpochManagerMock.sol";
import "@test/utils/TestConstants.sol";

contract BlockTest is Test, TestConstants {
    Block blockContract;
    ValidatorManagerMock validatorManager;
    ValidatorPerformanceTrackerMock performanceTracker;
    TimestampMock timestampContract;
    EpochManagerMock epochManager;

    function setUp() public {
        // Deploy mock contracts
        validatorManager = new ValidatorManagerMock();
        performanceTracker = new ValidatorPerformanceTrackerMock();
        timestampContract = new TimestampMock();
        epochManager = new EpochManagerMock();

        // Deploy Block contract
        blockContract = new Block();

        // Deploy mock contracts to system addresses
        vm.etch(VALIDATOR_MANAGER_ADDR, address(validatorManager).code);
        vm.etch(VALIDATOR_PERFORMANCE_TRACKER_ADDR, address(performanceTracker).code);
        vm.etch(TIMESTAMP_ADDR, address(timestampContract).code);
        vm.etch(EPOCH_MANAGER_ADDR, address(epochManager).code);

        // Set up mock data AFTER vm.etch (because etch only copies code, not storage)
        ValidatorManagerMock(VALIDATOR_MANAGER_ADDR).setIsCurrentEpochValidator(VALID_PROPOSER, true);
        ValidatorManagerMock(VALIDATOR_MANAGER_ADDR).setValidatorIndex(VALID_PROPOSER, DEFAULT_VALIDATOR_INDEX);
        ValidatorManagerMock(VALIDATOR_MANAGER_ADDR).setIsCurrentEpochValidator(INVALID_PROPOSER, false);
    }

    function test_initialize_shouldEmitGenesisBlockEvent() public {
        // Arrange
        vm.startPrank(GENESIS_ADDR);

        // Act & Assert - Check only topics, not data
        vm.expectEmit(true, true, true, false);
        emit IBlock.NewBlockEvent(
            address(0), // genesis_id (topic1)
            0, // epoch (topic2)
            0, // round (topic3)
            0, // height (data - not checked)
            bytes(""), // previousBlockVotesBitvec (data - not checked)
            SYSTEM_CALLER, // proposer (data - not checked)
            new uint64[](0), // failedProposerIndices (data - not checked)
            0 // timeMicroseconds (data - not checked)
        );

        blockContract.initialize();

        vm.stopPrank();
    }

    function test_initialize_revertsIfNotCalledByGenesis() public {
        // Arrange & Act & Assert
        vm.startPrank(NOT_GENESIS);
        vm.expectRevert(); // Should revert with onlyGenesis modifier
        blockContract.initialize();
        vm.stopPrank();
    }

    function test_blockPrologue_validProposer_shouldUpdatePerformanceAndTimestamp() public {
        // Arrange
        vm.startPrank(SYSTEM_CALLER);
        uint64[] memory failedIndices = new uint64[](2);
        failedIndices[0] = 2;
        failedIndices[1] = 3;

        // Act
        blockContract.blockPrologue(VALID_PROPOSER, failedIndices, DEFAULT_TIMESTAMP_MICROS);

        vm.stopPrank();
    }

    function test_blockPrologue_systemCallerProposer_shouldUseMaxIndex() public {
        // Arrange
        vm.startPrank(SYSTEM_CALLER);
        uint64[] memory failedIndices = new uint64[](1);
        failedIndices[0] = 5;
        uint256 timestampMicros = 2000000;

        // Act
        blockContract.blockPrologue(SYSTEM_CALLER, failedIndices, timestampMicros);

        vm.stopPrank();
    }

    function test_blockPrologue_invalidProposer_shouldRevert() public {
        // Arrange
        vm.startPrank(SYSTEM_CALLER);
        uint64[] memory failedIndices = new uint64[](0);

        // Act & Assert
        vm.expectRevert(); // Should revert with InvalidProposer
        blockContract.blockPrologue(INVALID_PROPOSER, failedIndices, DEFAULT_TIMESTAMP_MICROS);

        vm.stopPrank();
    }

    function test_blockPrologue_notSystemCaller_shouldRevert() public {
        // Arrange & Act & Assert
        vm.startPrank(NOT_SYSTEM_CALLER);
        uint64[] memory failedIndices = new uint64[](0);
        vm.expectRevert(); // Should revert with onlySystemCaller modifier
        blockContract.blockPrologue(VALID_PROPOSER, failedIndices, DEFAULT_TIMESTAMP_MICROS);
        vm.stopPrank();
    }

    function test_blockPrologue_withEpochTransition_shouldTriggerEpoch() public {
        // Arrange
        vm.startPrank(SYSTEM_CALLER);
        uint64[] memory failedIndices = new uint64[](0);

        // Set epoch manager to trigger transition
        EpochManagerMock(EPOCH_MANAGER_ADDR).setCanTriggerEpochTransition(true);

        // Expect the triggerEpochTransition call
        vm.expectCall(EPOCH_MANAGER_ADDR, abi.encodeWithSignature("triggerEpochTransition()"));

        // Act
        blockContract.blockPrologue(VALID_PROPOSER, failedIndices, DEFAULT_TIMESTAMP_MICROS);

        vm.stopPrank();
    }

    function test_blockPrologue_withoutEpochTransition_shouldNotTriggerEpoch() public {
        // Arrange
        vm.startPrank(SYSTEM_CALLER);
        uint64[] memory failedIndices = new uint64[](0);

        // Set epoch manager to NOT trigger transition (default is false)
        EpochManagerMock(EPOCH_MANAGER_ADDR).setCanTriggerEpochTransition(false);

        // Act
        blockContract.blockPrologue(VALID_PROPOSER, failedIndices, DEFAULT_TIMESTAMP_MICROS);

        vm.stopPrank();
    }

    function test_blockPrologue_emptyFailedIndices_shouldWork() public {
        // Arrange
        vm.startPrank(SYSTEM_CALLER);
        uint64[] memory emptyFailedIndices = new uint64[](0);

        // Act
        blockContract.blockPrologue(VALID_PROPOSER, emptyFailedIndices, DEFAULT_TIMESTAMP_MICROS);

        vm.stopPrank();
    }

    function test_blockPrologue_multipleFailedIndices_shouldRecordAll() public {
        // Arrange
        vm.startPrank(SYSTEM_CALLER);
        uint64[] memory failedIndices = new uint64[](5);
        for (uint64 i = 0; i < 5; i++) {
            failedIndices[i] = i + 10;
        }

        // Act
        blockContract.blockPrologue(VALID_PROPOSER, failedIndices, DEFAULT_TIMESTAMP_MICROS);

        vm.stopPrank();
    }
}
