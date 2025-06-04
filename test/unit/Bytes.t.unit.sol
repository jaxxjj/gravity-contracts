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
    function test_bytesToAddress_fuzzTest(address addr) public pure {
        // Arrange
        bytes memory data = abi.encodePacked(addr);

        // Act
        address result = Bytes.bytesToAddress(data, 0);

        // Assert
        assertEq(result, addr);
    }

    function test_bytesToUint256_fuzzTest(uint256 value) public pure {
        // Arrange
        bytes memory data = abi.encodePacked(value);

        // Act
        uint256 result = Bytes.bytesToUint256(data, 0);

        // Assert
        assertEq(result, value);
    }

    function test_bytesToUint64_fuzzTest(uint64 value) public pure {
        // Arrange
        bytes memory data = abi.encodePacked(value);

        // Act
        uint64 result = Bytes.bytesToUint64(data, 0);

        // Assert
        assertEq(result, value);
    }

    function test_bytesToBytes32_fuzzTest(bytes32 value) public pure {
        // Arrange
        bytes memory data = abi.encodePacked(value);

        // Act
        bytes32 result = Bytes.bytesToBytes32(data, 0);

        // Assert
        assertEq(result, value);
    }

    function test_bytesConcat_fuzzTest(uint8 len) public {
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
}
