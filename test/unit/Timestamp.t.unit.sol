// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "forge-std/Test.sol";
import "@src/timestamp/Timestamp.sol";
import "@src/interfaces/ITimestamp.sol";
import "@test/utils/TestConstants.sol";

contract TimestampTest is Test, TestConstants {
    Timestamp public timestamp;

    // Test constants
    uint64 private constant INITIAL_TIME = 1672531200000000; // 2023-01-01 00:00:00 UTC in microseconds
    uint64 private constant FUTURE_TIME = 1672531260000000; // 2023-01-01 00:01:00 UTC in microseconds
    uint64 private constant PAST_TIME = 1672531140000000; // 2023-01-01 23:59:00 UTC in microseconds
    uint64 private constant MICRO_CONVERSION_FACTOR = 1_000_000;

    address private constant TEST_PROPOSER = 0x1234567890123456789012345678901234567890;

    function setUp() public {
        // Deploy timestamp contract
        timestamp = new Timestamp();

        // Initialize the contract by setting initial time
        vm.prank(BLOCK_ADDR);
        timestamp.updateGlobalTime(TEST_PROPOSER, INITIAL_TIME);
    }

    // ============ UPDATE GLOBAL TIME TESTS ============

    function test_updateGlobalTime_normalBlock_shouldUpdateTime() public {
        // Arrange
        uint64 newTime = FUTURE_TIME;
        uint64 oldTime = timestamp.microseconds();

        // Act
        vm.prank(BLOCK_ADDR);
        vm.expectEmit(true, false, false, true);
        emit ITimestamp.GlobalTimeUpdated(TEST_PROPOSER, oldTime, newTime, false);
        timestamp.updateGlobalTime(TEST_PROPOSER, newTime);

        // Assert
        assertEq(timestamp.microseconds(), newTime);
    }

    function test_updateGlobalTime_nilBlock_shouldKeepSameTime() public {
        // Arrange
        uint64 currentTime = timestamp.microseconds();

        // Act
        vm.prank(BLOCK_ADDR);
        vm.expectEmit(true, false, false, true);
        emit ITimestamp.GlobalTimeUpdated(SYSTEM_CALLER, currentTime, currentTime, true);
        timestamp.updateGlobalTime(SYSTEM_CALLER, currentTime);

        // Assert
        assertEq(timestamp.microseconds(), currentTime);
    }

    function test_updateGlobalTime_normalBlock_timeEqual_shouldUpdate() public {
        // Arrange
        uint64 currentTime = timestamp.microseconds();

        // Act
        vm.prank(BLOCK_ADDR);
        timestamp.updateGlobalTime(TEST_PROPOSER, currentTime);

        // Assert
        assertEq(timestamp.microseconds(), currentTime);
    }

    function test_updateGlobalTime_unauthorizedCaller_shouldRevert() public {
        // Arrange
        address unauthorizedCaller = address(0xdead);

        // Act & Assert
        vm.prank(unauthorizedCaller);
        vm.expectRevert(abi.encodeWithSelector(System.OnlySystemContract.selector, BLOCK_ADDR));
        timestamp.updateGlobalTime(TEST_PROPOSER, FUTURE_TIME);
    }

    function test_updateGlobalTime_normalBlock_pastTime_shouldRevert() public {
        // Arrange
        uint64 pastTime = PAST_TIME;
        uint64 currentTime = timestamp.microseconds();

        // Act & Assert - Use BLOCK_ADDR (authorized) but with past time
        vm.prank(BLOCK_ADDR);
        vm.expectRevert(abi.encodeWithSelector(ITimestamp.TimestampMustAdvance.selector, pastTime, currentTime));
        timestamp.updateGlobalTime(TEST_PROPOSER, pastTime);
    }

    function test_updateGlobalTime_nilBlock_wrongTime_shouldRevert() public {
        // Arrange
        uint64 wrongTime = FUTURE_TIME;
        uint64 currentTime = timestamp.microseconds();

        // Act & Assert
        vm.prank(BLOCK_ADDR);
        vm.expectRevert(abi.encodeWithSelector(ITimestamp.TimestampMustEqual.selector, wrongTime, currentTime));
        timestamp.updateGlobalTime(SYSTEM_CALLER, wrongTime);
    }

    // ============ TIME QUERY TESTS ============

    function test_nowMicroseconds_shouldReturnCurrentTime() public view {
        // Act
        uint64 result = timestamp.nowMicroseconds();

        // Assert
        assertEq(result, INITIAL_TIME);
    }

    function test_nowSeconds_shouldReturnCurrentTimeInSeconds() public view {
        // Act
        uint64 result = timestamp.nowSeconds();

        // Assert
        uint64 expected = INITIAL_TIME / MICRO_CONVERSION_FACTOR;
        assertEq(result, expected);
    }

    function test_getTimeInfo_shouldReturnAllTimeData() public {
        // Act
        (uint64 currentMicroseconds, uint64 currentSeconds, uint256 blockTimestamp) = timestamp.getTimeInfo();

        // Assert
        assertEq(currentMicroseconds, INITIAL_TIME);
        assertEq(currentSeconds, INITIAL_TIME / MICRO_CONVERSION_FACTOR);
        assertEq(blockTimestamp, block.timestamp);
    }

    function test_isGreaterThanOrEqualCurrentTimestamp_futureTime_shouldReturnTrue() public view {
        // Act
        bool result = timestamp.isGreaterThanOrEqualCurrentTimestamp(FUTURE_TIME);

        // Assert
        assertTrue(result);
    }

    function test_isGreaterThanOrEqualCurrentTimestamp_equalTime_shouldReturnTrue() public view {
        // Act
        bool result = timestamp.isGreaterThanOrEqualCurrentTimestamp(INITIAL_TIME);

        // Assert
        assertTrue(result);
    }

    function test_isGreaterThanOrEqualCurrentTimestamp_pastTime_shouldReturnFalse() public view {
        // Act
        bool result = timestamp.isGreaterThanOrEqualCurrentTimestamp(PAST_TIME);

        // Assert
        assertFalse(result);
    }

    // ============ EDGE CASE TESTS ============

    function test_updateGlobalTime_maxUint64_shouldWork() public {
        // Arrange
        uint64 maxTime = type(uint64).max;

        // Act
        vm.prank(BLOCK_ADDR);
        timestamp.updateGlobalTime(TEST_PROPOSER, maxTime);

        // Assert
        assertEq(timestamp.microseconds(), maxTime);
    }

    function test_updateGlobalTime_incrementalTime_shouldWork() public {
        // Arrange
        uint64 currentTime = timestamp.microseconds();
        uint64 incrementTime = currentTime + 1;

        // Act
        vm.prank(BLOCK_ADDR);
        timestamp.updateGlobalTime(TEST_PROPOSER, incrementTime);

        // Assert
        assertEq(timestamp.microseconds(), incrementTime);
    }

    function test_nowSeconds_withRemainder_shouldTruncate() public {
        // Arrange - Set time with microseconds that don't divide evenly
        uint64 timeWithRemainder = 1672531200123456; // Has 123456 microseconds remainder
        vm.prank(BLOCK_ADDR);
        timestamp.updateGlobalTime(TEST_PROPOSER, timeWithRemainder);

        // Act
        uint64 result = timestamp.nowSeconds();

        // Assert
        uint64 expected = timeWithRemainder / MICRO_CONVERSION_FACTOR; // Should truncate
        assertEq(result, expected);
        assertEq(result, 1672531200); // Should be exactly this value
    }

    function test_timeProgression_multipleUpdates_shouldWork() public {
        // Arrange
        uint64[] memory times = new uint64[](5);
        times[0] = INITIAL_TIME + 1000000; // +1 second
        times[1] = INITIAL_TIME + 2000000; // +2 seconds
        times[2] = INITIAL_TIME + 3000000; // +3 seconds
        times[3] = INITIAL_TIME + 4000000; // +4 seconds
        times[4] = INITIAL_TIME + 5000000; // +5 seconds

        // Act & Assert
        for (uint256 i = 0; i < times.length; i++) {
            vm.prank(BLOCK_ADDR);
            timestamp.updateGlobalTime(TEST_PROPOSER, times[i]);
            assertEq(timestamp.microseconds(), times[i]);
        }
    }

    // ============ FUZZ TESTS ============

    function testFuzz_updateGlobalTime_normalBlock_validTime(
        uint64 newTime
    ) public {
        // Arrange
        uint64 currentTime = timestamp.microseconds();
        vm.assume(newTime >= currentTime);
        vm.assume(newTime > 0); // Avoid overflow issues

        // Act
        vm.prank(BLOCK_ADDR);
        timestamp.updateGlobalTime(TEST_PROPOSER, newTime);

        // Assert
        assertEq(timestamp.microseconds(), newTime);
    }

    function testFuzz_updateGlobalTime_normalBlock_invalidTime(
        uint64 newTime
    ) public {
        // Arrange
        uint64 currentTime = timestamp.microseconds();
        vm.assume(newTime < currentTime);

        // Act & Assert
        vm.prank(BLOCK_ADDR);
        vm.expectRevert(abi.encodeWithSelector(ITimestamp.TimestampMustAdvance.selector, newTime, currentTime));
        timestamp.updateGlobalTime(TEST_PROPOSER, newTime);
    }

    function testFuzz_isGreaterThanOrEqualCurrentTimestamp(
        uint64 testTime
    ) public view {
        // Arrange
        uint64 currentTime = timestamp.microseconds();

        // Act
        bool result = timestamp.isGreaterThanOrEqualCurrentTimestamp(testTime);

        // Assert
        if (testTime >= currentTime) {
            assertTrue(result);
        } else {
            assertFalse(result);
        }
    }

    function testFuzz_timeConversion_microsToSeconds(
        uint64 microTime
    ) public {
        // Arrange
        vm.assume(microTime >= timestamp.microseconds()); // Must be valid time
        vm.prank(BLOCK_ADDR);
        timestamp.updateGlobalTime(TEST_PROPOSER, microTime);

        // Act
        uint64 nowSeconds = timestamp.nowSeconds();
        uint64 microseconds = timestamp.nowMicroseconds();

        // Assert
        assertEq(nowSeconds, microTime / MICRO_CONVERSION_FACTOR);
        assertEq(microseconds, microTime);
    }

    // ============ INTEGRATION TESTS ============

    function test_completeWorkflow_realWorldScenario() public {
        // Arrange - Simulate a real blockchain scenario
        address[] memory proposers = new address[](3);
        proposers[0] = address(0x1111);
        proposers[1] = address(0x2222);
        proposers[2] = address(0x3333);

        uint64 baseTime = timestamp.microseconds();
        uint64[] memory blockTimes = new uint64[](5);
        blockTimes[0] = baseTime + 12000000; // +12 seconds (normal block)
        blockTimes[1] = baseTime + 24000000; // +12 seconds (normal block)
        blockTimes[2] = baseTime + 24000000; // Same time (NIL block)
        blockTimes[3] = baseTime + 36000000; // +12 seconds (normal block)
        blockTimes[4] = baseTime + 48000000; // +12 seconds (normal block)

        // Act & Assert - Simulate block sequence
        // Block 1: Normal block
        vm.prank(BLOCK_ADDR);
        timestamp.updateGlobalTime(proposers[0], blockTimes[0]);
        assertEq(timestamp.microseconds(), blockTimes[0]);

        // Block 2: Normal block
        vm.prank(BLOCK_ADDR);
        timestamp.updateGlobalTime(proposers[1], blockTimes[1]);
        assertEq(timestamp.microseconds(), blockTimes[1]);

        // Block 3: NIL block (same time)
        vm.prank(BLOCK_ADDR);
        timestamp.updateGlobalTime(SYSTEM_CALLER, blockTimes[2]);
        assertEq(timestamp.microseconds(), blockTimes[2]);

        // Block 4: Normal block (time advances)
        vm.prank(BLOCK_ADDR);
        timestamp.updateGlobalTime(proposers[2], blockTimes[3]);
        assertEq(timestamp.microseconds(), blockTimes[3]);

        // Block 5: Normal block
        vm.prank(BLOCK_ADDR);
        timestamp.updateGlobalTime(proposers[0], blockTimes[4]);
        assertEq(timestamp.microseconds(), blockTimes[4]);

        // Final verification
        (uint64 finalMicros, uint64 finalSeconds, uint256 blockTs) = timestamp.getTimeInfo();
        assertEq(finalMicros, blockTimes[4]);
        assertEq(finalSeconds, blockTimes[4] / MICRO_CONVERSION_FACTOR);
        assertEq(blockTs, block.timestamp);
    }

    function test_zeroTimestamp_initialization() public {
        // Arrange - Deploy fresh contract
        Timestamp freshTimestamp = new Timestamp();

        // Act & Assert - Should start with zero
        assertEq(freshTimestamp.microseconds(), 0);
        assertEq(freshTimestamp.nowMicroseconds(), 0);
        assertEq(freshTimestamp.nowSeconds(), 0);

        // Should be able to set initial time
        vm.prank(BLOCK_ADDR);
        freshTimestamp.updateGlobalTime(TEST_PROPOSER, INITIAL_TIME);
        assertEq(freshTimestamp.microseconds(), INITIAL_TIME);
    }
}
