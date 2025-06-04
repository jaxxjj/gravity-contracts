// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "forge-std/Test.sol";
import "@src/governance/Timelock.sol";
import "@src/System.sol";
import "@test/utils/TestConstants.sol";
import "@test/mocks/ValidatorManagerMock.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "@openzeppelin-upgrades/governance/TimelockControllerUpgradeable.sol";

contract TimelockTest is Test, TestConstants {
    Timelock public timelock;
    Timelock public implementation;
    ValidatorManagerMock public validatorManager;

    // Test addresses
    address public user1 = makeAddr("user1");
    address public user2 = makeAddr("user2");

    event ParamChange(string key, bytes value);
    event MinDelayChange(uint256 oldDuration, uint256 newDuration);

    function setUp() public {
        // Deploy mock contracts
        validatorManager = new ValidatorManagerMock();

        // Set up system contracts using vm.etch with actual deployed code
        vm.etch(VALIDATOR_MANAGER_ADDR, address(validatorManager).code);

        // Deploy implementation
        implementation = new Timelock();

        // Deploy proxy
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), "");
        timelock = Timelock(payable(address(proxy)));

        // Initialize the proxy from GENESIS_ADDR
        vm.prank(GENESIS_ADDR);
        timelock.initialize();
    }

    // ============ INITIALIZATION TESTS ============

    function test_initialize_shouldSetCorrectValues() public view {
        // Assert - Check if timelock was initialized with correct delay
        assertEq(timelock.getMinDelay(), 24 hours);

        // Check if GOVERNOR_ADDR has PROPOSER_ROLE
        bytes32 proposerRole = timelock.PROPOSER_ROLE();
        assertTrue(timelock.hasRole(proposerRole, GOVERNOR_ADDR));

        // Check if GOVERNOR_ADDR has EXECUTOR_ROLE
        bytes32 executorRole = timelock.EXECUTOR_ROLE();
        assertTrue(timelock.hasRole(executorRole, GOVERNOR_ADDR));
    }

    function test_initialize_cannotBeCalledTwice() public {
        // Act & Assert
        vm.expectRevert();
        timelock.initialize();
    }

    function test_initialize_onlyGenesis() public {
        // Arrange
        Timelock newTimelock = new Timelock();

        // Act & Assert
        vm.prank(user1);
        vm.expectRevert();
        newTimelock.initialize();
    }

    // ============ UPDATE PARAM TESTS ============

    function test_updateParam_minDelay_shouldUpdateCorrectly() public {
        // Arrange
        uint256 newMinDelay = 48 hours;
        bytes memory encodedValue = abi.encode(newMinDelay);

        // Act & Assert
        vm.prank(GOV_HUB_ADDR);
        vm.expectEmit(true, true, true, true);
        emit ParamChange("minDelay", encodedValue);
        timelock.updateParam("minDelay", encodedValue);

        // Assert
        assertEq(timelock.getMinDelay(), newMinDelay);
    }

    function test_updateParam_minDelay_minimumValue() public {
        // Arrange
        uint256 newMinDelay = 1 seconds;
        bytes memory encodedValue = abi.encode(newMinDelay);

        // Act
        vm.prank(GOV_HUB_ADDR);
        timelock.updateParam("minDelay", encodedValue);

        // Assert
        assertEq(timelock.getMinDelay(), newMinDelay);
    }

    function test_updateParam_minDelay_maximumValue() public {
        // Arrange
        uint256 newMinDelay = 14 days;
        bytes memory encodedValue = abi.encode(newMinDelay);

        // Act
        vm.prank(GOV_HUB_ADDR);
        timelock.updateParam("minDelay", encodedValue);

        // Assert
        assertEq(timelock.getMinDelay(), newMinDelay);
    }

    function test_updateParam_minDelay_shouldRevertForZero() public {
        // Arrange
        uint256 newMinDelay = 0;
        bytes memory encodedValue = abi.encode(newMinDelay);

        // Act & Assert
        vm.prank(GOV_HUB_ADDR);
        vm.expectRevert(abi.encodeWithSelector(System.InvalidValue.selector, "minDelay", encodedValue));
        timelock.updateParam("minDelay", encodedValue);
    }

    function test_updateParam_minDelay_shouldRevertForTooLarge() public {
        // Arrange
        uint256 newMinDelay = 15 days;
        bytes memory encodedValue = abi.encode(newMinDelay);

        // Act & Assert
        vm.prank(GOV_HUB_ADDR);
        vm.expectRevert(abi.encodeWithSelector(System.InvalidValue.selector, "minDelay", encodedValue));
        timelock.updateParam("minDelay", encodedValue);
    }

    function test_updateParam_minDelay_shouldRevertForInvalidLength() public {
        // Arrange - Use a byte array that's not 32 bytes long
        bytes memory encodedValue = abi.encodePacked(uint64(24 hours)); // This creates 8 bytes

        // Act & Assert
        vm.prank(GOV_HUB_ADDR);
        vm.expectRevert(abi.encodeWithSelector(System.InvalidValue.selector, "minDelay", encodedValue));
        timelock.updateParam("minDelay", encodedValue);
    }

    function test_updateParam_unknownParam_shouldRevert() public {
        // Arrange
        bytes memory encodedValue = abi.encode(uint256(100));

        // Act & Assert
        vm.prank(GOV_HUB_ADDR);
        vm.expectRevert(abi.encodeWithSelector(System.UnknownParam.selector, "unknownParam", encodedValue));
        timelock.updateParam("unknownParam", encodedValue);
    }

    function test_updateParam_onlyGov() public {
        // Arrange
        bytes memory encodedValue = abi.encode(uint256(48 hours));

        // Act & Assert
        vm.prank(user1);
        vm.expectRevert();
        timelock.updateParam("minDelay", encodedValue);
    }

    // ============ ACCESS CONTROL TESTS ============

    function test_hasRole_proposer() public view {
        // Assert
        bytes32 proposerRole = timelock.PROPOSER_ROLE();
        assertTrue(timelock.hasRole(proposerRole, GOVERNOR_ADDR));
        assertFalse(timelock.hasRole(proposerRole, user1));
    }

    function test_hasRole_executor() public view {
        // Assert
        bytes32 executorRole = timelock.EXECUTOR_ROLE();
        assertTrue(timelock.hasRole(executorRole, GOVERNOR_ADDR));
        assertFalse(timelock.hasRole(executorRole, user1));
    }

    function test_hasRole_admin() public view {
        // Assert
        bytes32 adminRole = timelock.DEFAULT_ADMIN_ROLE();
        assertTrue(timelock.hasRole(adminRole, GOVERNOR_ADDR));
        assertFalse(timelock.hasRole(adminRole, user1));
    }

    // ============ TIMELOCK FUNCTIONALITY TESTS ============

    function test_getMinDelay_returnsCorrectValue() public view {
        // Assert
        assertEq(timelock.getMinDelay(), 24 hours);
    }

    // ============ FUZZ TESTS ============

    function testFuzz_updateParam_minDelay_validValues(
        uint256 newMinDelay
    ) public {
        // Arrange
        vm.assume(newMinDelay > 0 && newMinDelay <= 14 days);
        bytes memory encodedValue = abi.encode(newMinDelay);

        // Act
        vm.prank(GOV_HUB_ADDR);
        timelock.updateParam("minDelay", encodedValue);

        // Assert
        assertEq(timelock.getMinDelay(), newMinDelay);
    }

    function testFuzz_updateParam_minDelay_invalidValues(
        uint256 newMinDelay
    ) public {
        // Arrange
        vm.assume(newMinDelay == 0 || newMinDelay > 14 days);
        bytes memory encodedValue = abi.encode(newMinDelay);

        // Act & Assert
        vm.prank(GOV_HUB_ADDR);
        vm.expectRevert(abi.encodeWithSelector(System.InvalidValue.selector, "minDelay", encodedValue));
        timelock.updateParam("minDelay", encodedValue);
    }
}
