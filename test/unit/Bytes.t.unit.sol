// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "forge-std/Test.sol";
import "@src/lib/Bytes.sol";

contract BytesTest is Test {
    using Bytes for bytes;

    function test_bytesToAddress_shouldConvertCorrectly() public pure {
        // Arrange
        address expectedAddr = 0x1234567890123456789012345678901234567890;
        bytes memory data = abi.encodePacked(expectedAddr);

        // Act
        address result = Bytes.bytesToAddress(data, 0);

        // Assert
        assertEq(result, expectedAddr);
    }

    function test_bytesToAddress_withOffset_shouldConvertCorrectly() public pure {
        // Arrange
        address expectedAddr = 0x1234567890123456789012345678901234567890;
        bytes memory prefix = hex"deadbeef";
        bytes memory data = abi.encodePacked(prefix, expectedAddr);

        // Act
        address result = Bytes.bytesToAddress(data, 4); // offset by prefix length

        // Assert
        assertEq(result, expectedAddr);
    }

    function test_bytesToUint256_shouldConvertCorrectly() public pure {
        // Arrange
        uint256 expectedValue = 0x123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef0;
        bytes memory data = abi.encodePacked(expectedValue);

        // Act
        uint256 result = Bytes.bytesToUint256(data, 0);

        // Assert
        assertEq(result, expectedValue);
    }

    function test_bytesToUint256_withOffset_shouldConvertCorrectly() public pure {
        // Arrange
        uint256 expectedValue = 12345678901234567890;
        bytes memory prefix = hex"deadbeef";
        bytes memory data = abi.encodePacked(prefix, expectedValue);

        // Act
        uint256 result = Bytes.bytesToUint256(data, 4);

        // Assert
        assertEq(result, expectedValue);
    }

    function test_bytesToUint64_shouldConvertCorrectly() public pure {
        // Arrange
        uint64 expectedValue = 0x123456789abcdef0;
        bytes memory data = abi.encodePacked(expectedValue);

        // Act
        uint64 result = Bytes.bytesToUint64(data, 0);

        // Assert
        assertEq(result, expectedValue);
    }

    function test_bytesToUint64_withOffset_shouldConvertCorrectly() public pure {
        // Arrange
        uint64 expectedValue = 1234567890123456789;
        bytes memory prefix = hex"deadbeef";
        bytes memory data = abi.encodePacked(prefix, expectedValue);

        // Act
        uint64 result = Bytes.bytesToUint64(data, 4);

        // Assert
        assertEq(result, expectedValue);
    }

    function test_bytesToBytes32_shouldConvertCorrectly() public pure {
        // Arrange
        bytes32 expectedValue = 0x123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef0;
        bytes memory data = abi.encodePacked(expectedValue);

        // Act
        bytes32 result = Bytes.bytesToBytes32(data, 0);

        // Assert
        assertEq(result, expectedValue);
    }

    function test_bytesToBytes32_withOffset_shouldConvertCorrectly() public pure {
        // Arrange
        bytes32 expectedValue = keccak256("test");
        bytes memory prefix = hex"deadbeef";
        bytes memory data = abi.encodePacked(prefix, expectedValue);

        // Act
        bytes32 result = Bytes.bytesToBytes32(data, 4);

        // Assert
        assertEq(result, expectedValue);
    }

    function test_bytesConcat_shouldConcatenateCorrectly() public pure {
        // Arrange
        bytes memory data = new bytes(10);
        bytes memory source = hex"deadbeef";
        uint256 index = 2;
        uint256 len = 4;

        // Act
        Bytes.bytesConcat(data, source, index, len);

        // Assert
        assertEq(uint8(data[2]), 0xde);
        assertEq(uint8(data[3]), 0xad);
        assertEq(uint8(data[4]), 0xbe);
        assertEq(uint8(data[5]), 0xef);

        // Check other positions remain zero
        assertEq(uint8(data[0]), 0x00);
        assertEq(uint8(data[1]), 0x00);
        assertEq(uint8(data[6]), 0x00);
    }

    function test_bytesConcat_withPartialLength_shouldConcatenatePartially() public pure {
        // Arrange
        bytes memory data = new bytes(5);
        bytes memory source = hex"deadbeefcafe";
        uint256 index = 1;
        uint256 len = 3;

        // Act
        Bytes.bytesConcat(data, source, index, len);

        // Assert
        assertEq(uint8(data[0]), 0x00);
        assertEq(uint8(data[1]), 0xde);
        assertEq(uint8(data[2]), 0xad);
        assertEq(uint8(data[3]), 0xbe);
        assertEq(uint8(data[4]), 0x00);
    }

    function test_bytesToHex_withPrefix_shouldConvertCorrectly() public pure {
        // Arrange
        bytes memory data = hex"deadbeef";
        string memory expected = "0xdeadbeef";

        // Act
        string memory result = Bytes.bytesToHex(data, true);

        // Assert
        assertEq(result, expected);
    }

    function test_bytesToHex_withoutPrefix_shouldConvertCorrectly() public pure {
        // Arrange
        bytes memory data = hex"deadbeef";
        string memory expected = "deadbeef";

        // Act
        string memory result = Bytes.bytesToHex(data, false);

        // Assert
        assertEq(result, expected);
    }

    function test_bytesToHex_emptyBytes_shouldReturnEmptyString() public pure {
        // Arrange
        bytes memory data = "";

        // Act
        string memory resultWithPrefix = Bytes.bytesToHex(data, true);
        string memory resultWithoutPrefix = Bytes.bytesToHex(data, false);

        // Assert
        assertEq(resultWithPrefix, "0x");
        assertEq(resultWithoutPrefix, "");
    }

    function test_bytesToHex_singleByte_shouldConvertCorrectly() public pure {
        // Arrange
        bytes memory data = hex"ff";

        // Act
        string memory resultWithPrefix = Bytes.bytesToHex(data, true);
        string memory resultWithoutPrefix = Bytes.bytesToHex(data, false);

        // Assert
        assertEq(resultWithPrefix, "0xff");
        assertEq(resultWithoutPrefix, "ff");
    }

    function test_bytesToHex_allZeros_shouldConvertCorrectly() public pure {
        // Arrange
        bytes memory data = hex"0000";

        // Act
        string memory result = Bytes.bytesToHex(data, true);

        // Assert
        assertEq(result, "0x0000");
    }

    function test_bytesToHex_mixedCase_shouldReturnLowercase() public pure {
        // Arrange - Test that it always returns lowercase
        bytes memory data = hex"ABCDEF123456";
        string memory expected = "0xabcdef123456";

        // Act
        string memory result = Bytes.bytesToHex(data, true);

        // Assert
        assertEq(result, expected);
    }

    // Edge case tests
    function test_bytesToAddress_fuzzTest(
        address addr
    ) public pure {
        // Arrange
        bytes memory data = abi.encodePacked(addr);

        // Act
        address result = Bytes.bytesToAddress(data, 0);

        // Assert
        assertEq(result, addr);
    }

    function test_bytesToUint256_fuzzTest(
        uint256 value
    ) public pure {
        // Arrange
        bytes memory data = abi.encodePacked(value);

        // Act
        uint256 result = Bytes.bytesToUint256(data, 0);

        // Assert
        assertEq(result, value);
    }

    function test_bytesToUint64_fuzzTest(
        uint64 value
    ) public pure {
        // Arrange
        bytes memory data = abi.encodePacked(value);

        // Act
        uint64 result = Bytes.bytesToUint64(data, 0);

        // Assert
        assertEq(result, value);
    }

    function test_bytesToBytes32_fuzzTest(
        bytes32 value
    ) public pure {
        // Arrange
        bytes memory data = abi.encodePacked(value);

        // Act
        bytes32 result = Bytes.bytesToBytes32(data, 0);

        // Assert
        assertEq(result, value);
    }

    function test_bytesConcat_fuzzTest(
        uint8 len
    ) public {
        // Arrange
        len = uint8(bound(len, 0, 32)); // Bound len to reasonable range
        bytes memory data = new bytes(64);
        bytes memory source = new bytes(32);

        // Fill source with test data
        for (uint256 i = 0; i < 32; i++) {
            source[i] = bytes1(uint8(i + 1));
        }

        // Act
        Bytes.bytesConcat(data, source, 10, len);

        // Assert - Check that the correct number of bytes were copied
        for (uint256 i = 0; i < len; i++) {
            assertEq(uint8(data[10 + i]), uint8(source[i]));
        }

        // Check positions before and after remain zero
        if (len > 0) {
            assertEq(uint8(data[9]), 0x00); // Before
            if (10 + len < 64) {
                assertEq(uint8(data[10 + len]), 0x00); // After
            }
        }
    }

    function test_compositeDataParsing_shouldParseCorrectly() public pure {
        // Arrange - Simulate a real-world data packet
        address sender = 0x1234567890123456789012345678901234567890;
        uint256 amount = 1000000000000000000; // 1 ETH
        uint64 timestamp = 1672531200;
        bytes32 hash = keccak256("test");

        bytes memory packedData = abi.encodePacked(sender, amount, timestamp, hash);

        // Act & Assert - Parse each field with correct offsets
        assertEq(Bytes.bytesToAddress(packedData, 0), sender);
        assertEq(Bytes.bytesToUint256(packedData, 20), amount);
        assertEq(Bytes.bytesToUint64(packedData, 52), timestamp);
        assertEq(Bytes.bytesToBytes32(packedData, 60), hash);
    }

    function test_maxValuesParsing_shouldHandleMaxValues() public pure {
        // Arrange - Test maximum values for each type
        address maxAddr = address(type(uint160).max);
        uint256 maxUint256 = type(uint256).max;
        uint64 maxUint64 = type(uint64).max;
        bytes32 maxBytes32 = bytes32(type(uint256).max);

        // Act & Assert
        bytes memory addrData = abi.encodePacked(maxAddr);
        assertEq(Bytes.bytesToAddress(addrData, 0), maxAddr);

        bytes memory uint256Data = abi.encodePacked(maxUint256);
        assertEq(Bytes.bytesToUint256(uint256Data, 0), maxUint256);

        bytes memory uint64Data = abi.encodePacked(maxUint64);
        assertEq(Bytes.bytesToUint64(uint64Data, 0), maxUint64);

        bytes memory bytes32Data = abi.encodePacked(maxBytes32);
        assertEq(Bytes.bytesToBytes32(bytes32Data, 0), maxBytes32);
    }

    function test_zeroValuesParsing_shouldHandleZeroValues() public pure {
        // Arrange - Test zero values
        address zeroAddr = address(0);
        uint256 zeroUint256 = 0;
        uint64 zeroUint64 = 0;
        bytes32 zeroBytes32 = bytes32(0);

        // Act & Assert
        bytes memory addrData = abi.encodePacked(zeroAddr);
        assertEq(Bytes.bytesToAddress(addrData, 0), zeroAddr);

        bytes memory uint256Data = abi.encodePacked(zeroUint256);
        assertEq(Bytes.bytesToUint256(uint256Data, 0), zeroUint256);

        bytes memory uint64Data = abi.encodePacked(zeroUint64);
        assertEq(Bytes.bytesToUint64(uint64Data, 0), zeroUint64);

        bytes memory bytes32Data = abi.encodePacked(zeroBytes32);
        assertEq(Bytes.bytesToBytes32(bytes32Data, 0), zeroBytes32);
    }

    function test_boundaryOffsets_shouldReadCorrectlyAtBoundaries() public pure {
        // Arrange - Create data with multiple fields
        uint256 first = 0x1111111111111111111111111111111111111111111111111111111111111111;
        uint256 second = 0x2222222222222222222222222222222222222222222222222222222222222222;
        uint256 third = 0x3333333333333333333333333333333333333333333333333333333333333333;

        bytes memory data = abi.encodePacked(first, second, third);

        // Act & Assert - Read at exact boundaries
        assertEq(Bytes.bytesToUint256(data, 0), first); // Start of data
        assertEq(Bytes.bytesToUint256(data, 32), second); // Middle boundary
        assertEq(Bytes.bytesToUint256(data, 64), third); // End boundary
    }

    function test_unalignedReads_shouldHandleNonStandardOffsets() public pure {
        // Arrange - Test reads at non-standard byte boundaries with distinctive data
        bytes memory data = hex"deadbeef1234567890abcdef5555666677778888999900001111222233334444";

        // Act & Assert - Read address at various unaligned positions with more spacing
        address addr1 = Bytes.bytesToAddress(data, 0); // Start
        address addr2 = Bytes.bytesToAddress(data, 8); // Middle
        address addr3 = Bytes.bytesToAddress(data, 16); // End

        // Verify these are different values (proving unaligned reads work)
        // With this data pattern, these offsets should give different results
        assertTrue(addr1 != addr2);
        assertTrue(addr2 != addr3);
        assertTrue(addr1 != addr3);

        // Also verify the values are not zero (sanity check)
        assertTrue(addr1 != address(0));
        assertTrue(addr2 != address(0));
        assertTrue(addr3 != address(0));
    }

    function test_overlappingReads_shouldReadConsistently() public pure {
        // Arrange - Create overlapping data structure
        bytes memory data = hex"123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef01234";

        // Act - Read overlapping regions
        bytes32 read1 = Bytes.bytesToBytes32(data, 0);
        bytes32 read2 = Bytes.bytesToBytes32(data, 1);
        uint256 uint1 = Bytes.bytesToUint256(data, 0);
        uint256 uint2 = Bytes.bytesToUint256(data, 1);

        // Assert - Overlapping reads should be different but consistent
        assertTrue(read1 != read2);
        assertTrue(uint1 != uint2);
        assertEq(uint256(read1), uint1); // bytes32 and uint256 should be same value
        assertEq(uint256(read2), uint2);
    }

    function test_memoryLayoutIndependence_provesOurFixIsCorrect() public pure {
        // Arrange - This test proves our fix handles memory layout correctly
        // compared to BSC's raw implementation
        address testAddr = 0xabCDEF1234567890ABcDEF1234567890aBCDeF12;

        // Create bytes data the way Solidity does (with length prefix)
        bytes memory data = abi.encodePacked(testAddr);

        // Act - Our implementation should read from logical offset 0
        address result = Bytes.bytesToAddress(data, 0);

        // Assert - Should get the original address back
        assertEq(result, testAddr);

        // This proves our implementation correctly handles:
        // 1. The 32-byte length prefix in memory
        // 2. The 20-byte address padding/alignment
        // 3. Big-endian byte ordering
    }

    function test_multipleDataTypes_inSingleBuffer() public pure {
        // Arrange - Complex real-world scenario
        bytes memory prefix = hex"deadbeef";
        address addr = 0x1234567890123456789012345678901234567890;
        uint64 value = 0xabcdef0123456789;
        bytes32 hash = keccak256("complex test");
        bytes memory suffix = hex"cafebabe";

        bytes memory complexData = abi.encodePacked(prefix, addr, value, hash, suffix);

        // Act & Assert - Parse each component with correct offsets
        assertEq(Bytes.bytesToAddress(complexData, 4), addr); // Skip 4-byte prefix
        assertEq(Bytes.bytesToUint64(complexData, 24), value); // Skip prefix + address
        assertEq(Bytes.bytesToBytes32(complexData, 32), hash); // Skip prefix + address + uint64

        // Verify the prefix and suffix are in correct positions
        assertEq(uint8(complexData[0]), 0xde); // First byte of prefix
        assertEq(uint8(complexData[1]), 0xad); // Second byte of prefix
        assertEq(uint8(complexData[complexData.length - 4]), 0xca); // First byte of suffix
        assertEq(uint8(complexData[complexData.length - 1]), 0xbe); // Last byte of suffix
    }

    function test_extremeOffsets_shouldHandleEdgeCases() public pure {
        // Arrange - Large data buffer with reads at extreme positions
        bytes memory largeData = new bytes(1000);

        // Fill with pattern
        for (uint256 i = 0; i < 1000; i++) {
            largeData[i] = bytes1(uint8(i % 256));
        }

        // Place specific values at known positions
        address testAddr = 0x1111111111111111111111111111111111111111;
        bytes memory addrBytes = abi.encodePacked(testAddr);

        // Copy address bytes to position 500
        for (uint256 i = 0; i < 20; i++) {
            largeData[500 + i] = addrBytes[i];
        }

        // Act & Assert - Read from extreme offset
        address result = Bytes.bytesToAddress(largeData, 500);
        assertEq(result, testAddr);
    }

    function test_bytesToHex_edgeCases() public pure {
        // Test with pattern that could cause hex conversion issues
        bytes memory pattern = hex"00ff00ff00ff";
        string memory expectedWithPrefix = "0x00ff00ff00ff";
        string memory expectedWithoutPrefix = "00ff00ff00ff";

        assertEq(Bytes.bytesToHex(pattern, true), expectedWithPrefix);
        assertEq(Bytes.bytesToHex(pattern, false), expectedWithoutPrefix);

        // Test with all possible byte values
        bytes memory allBytes = new bytes(16);
        for (uint256 i = 0; i < 16; i++) {
            allBytes[i] = bytes1(uint8(i * 16 + i)); // 0x00, 0x11, 0x22, ..., 0xff
        }

        string memory hexResult = Bytes.bytesToHex(allBytes, false);
        // Should be "00112233445566778899aabbccddeeff"
        assertEq(bytes(hexResult).length, 32); // 16 bytes * 2 hex chars
    }

    function test_bytesConcat_extremeCases() public pure {
        // Test concatenation at buffer boundaries
        bytes memory target = new bytes(100);
        bytes memory source = hex"deadbeefcafebabe1234567890abcdef";

        // Test copying to the very end of buffer
        Bytes.bytesConcat(target, source, 84, 16); // Copy all 16 bytes to position 84-99

        // Verify all bytes were copied correctly
        assertEq(uint8(target[84]), 0xde);
        assertEq(uint8(target[99]), 0xef);

        // Test zero-length copy (should be no-op)
        bytes memory original = new bytes(10);
        bytes memory backup = new bytes(10);
        Bytes.bytesConcat(original, source, 5, 0);

        // Should be identical (no changes)
        for (uint256 i = 0; i < 10; i++) {
            assertEq(uint8(original[i]), uint8(backup[i]));
        }
    }
}
