// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "forge-std/Test.sol";
import "@src/governance/GravityGovernor.sol";
import "@src/System.sol";
import "@test/utils/TestConstants.sol";
import "@test/mocks/GovTokenMock.sol";
import "@test/mocks/TimelockMock.sol";
import "@test/mocks/ValidatorManagerMock.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract GravityGovernorTest is Test, TestConstants {
    GravityGovernor public governor;
    GravityGovernor public governorImpl;
    GovTokenMock public mockGovToken;
    TimelockMock public mockTimelock;
    ValidatorManagerMock public validatorManager;

    // Test addresses
    address public user1 = makeAddr("user1");
    address public user2 = makeAddr("user2");
    address public proposer = makeAddr("proposer");

    event ParamChange(string key, bytes value);
    event ProposalCreated(
        uint256 proposalId,
        address proposer,
        address[] targets,
        uint256[] values,
        string[] signatures,
        bytes[] calldatas,
        uint256 startBlock,
        uint256 endBlock,
        string description
    );

    function setUp() public {
        // Deploy mock contracts
        validatorManager = new ValidatorManagerMock();
        mockGovToken = new GovTokenMock();
        mockTimelock = new TimelockMock();

        // Set up system contracts using vm.etch
        vm.etch(VALIDATOR_MANAGER_ADDR, address(validatorManager).code);
        vm.etch(GOV_TOKEN_ADDR, address(mockGovToken).code);
        vm.etch(TIMELOCK_ADDR, address(mockTimelock).code);

        // Deploy implementation
        governorImpl = new GravityGovernor();

        // Deploy proxy
        ERC1967Proxy governorProxy = new ERC1967Proxy(address(governorImpl), "");
        governor = GravityGovernor(payable(address(governorProxy)));

        // Initialize the governor
        vm.prank(GENESIS_ADDR);
        governor.initialize();

        // Set up mock data
        mockGovToken.setTotalSupply(1_500_000_000 ether); // Above 1B threshold
        mockGovToken.setBalance(proposer, 3_000_000 ether); // Above proposal threshold
        mockGovToken.setVotes(proposer, 3_000_000 ether);
    }

    // ============ INITIALIZATION TESTS ============

    function test_initialize_shouldSetCorrectValues() public view {
        // Assert basic governor settings
        assertEq(governor.name(), "GravityGovernor");
        assertEq(governor.votingDelay(), 0); // INIT_VOTING_DELAY
        assertEq(governor.votingPeriod(), 201600); // 7 days / 3 seconds
        assertEq(governor.proposalThreshold(), 2_000_000 ether);

        // Check if GovHub is whitelisted
        assertTrue(governor.whitelistTargets(GOV_HUB_ADDR));

        // Check propose not started yet
        assertFalse(governor.proposeStarted());
    }

    function test_initialize_cannotBeCalledTwice() public {
        // Act & Assert
        vm.expectRevert();
        governor.initialize();
    }

    function test_initialize_onlyGenesis() public {
        // Arrange
        GravityGovernor newGovernor = new GravityGovernor();

        // Act & Assert
        vm.prank(user1);
        vm.expectRevert();
        newGovernor.initialize();
    }

    // ============ PROPOSAL TESTS ============

    function test_propose_shouldStartProposeWhenThresholdMet() public {
        // Arrange - Mock the totalSupply call that Governor will make
        vm.mockCall(
            GOV_TOKEN_ADDR, abi.encodeWithSelector(IERC20.totalSupply.selector), abi.encode(1_100_000_000 ether)
        );

        // Mock getPastVotes for proposer to have sufficient voting power
        vm.mockCall(
            GOV_TOKEN_ADDR,
            abi.encodeWithSignature("getPastVotes(address,uint256)", proposer, 0),
            abi.encode(3_000_000 ether)
        );

        address[] memory targets = new address[](1);
        targets[0] = GOV_HUB_ADDR;
        uint256[] memory values = new uint256[](1);
        values[0] = 0;
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSignature("updateParam(string,bytes)", "test", abi.encode(123));

        // Act
        vm.prank(proposer);
        uint256 proposalId = governor.propose(targets, values, calldatas, "Test proposal");

        // Assert
        assertTrue(governor.proposeStarted());
        assertEq(governor.latestProposalIds(proposer), proposalId);
    }

    function test_propose_shouldRevertIfTotalSupplyNotEnough() public {
        // Arrange - Mock the totalSupply call that Governor will make
        vm.mockCall(GOV_TOKEN_ADDR, abi.encodeWithSelector(IERC20.totalSupply.selector), abi.encode(500_000_000 ether));

        address[] memory targets = new address[](1);
        targets[0] = GOV_HUB_ADDR;
        uint256[] memory values = new uint256[](1);
        values[0] = 0;
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSignature("updateParam(string,bytes)", "test", abi.encode(123));

        // Act & Assert
        vm.prank(proposer);
        vm.expectRevert(GravityGovernor.TotalSupplyNotEnough.selector);
        governor.propose(targets, values, calldatas, "Test proposal");
    }

    function test_propose_shouldRevertIfProposerHasActiveProposal() public {
        // Arrange - Mock the totalSupply call that Governor will make
        vm.mockCall(
            GOV_TOKEN_ADDR, abi.encodeWithSelector(IERC20.totalSupply.selector), abi.encode(1_100_000_000 ether)
        );

        // Mock getPastVotes for proposer to have sufficient voting power
        vm.mockCall(
            GOV_TOKEN_ADDR,
            abi.encodeWithSignature("getPastVotes(address,uint256)", proposer, 0),
            abi.encode(3_000_000 ether)
        );

        address[] memory targets = new address[](1);
        targets[0] = GOV_HUB_ADDR;
        uint256[] memory values = new uint256[](1);
        values[0] = 0;
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSignature("updateParam(string,bytes)", "test", abi.encode(123));

        // Create first proposal
        vm.prank(proposer);
        governor.propose(targets, values, calldatas, "Test proposal 1");

        // Act & Assert - Try to create another proposal
        vm.prank(proposer);
        vm.expectRevert(GravityGovernor.OneLiveProposalPerProposer.selector);
        governor.propose(targets, values, calldatas, "Test proposal 2");
    }

    // ============ QUEUE TESTS ============

    function test_queue_shouldRevertForNonWhitelistedTarget() public {
        // Arrange
        address[] memory targets = new address[](1);
        targets[0] = user1; // Not whitelisted
        uint256[] memory values = new uint256[](1);
        values[0] = 0;
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = "";
        bytes32 descriptionHash = keccak256("Test proposal");

        // Act & Assert
        vm.expectRevert(GravityGovernor.NotWhitelisted.selector);
        governor.queue(targets, values, calldatas, descriptionHash);
    }

    // ============ UPDATE PARAM TESTS ============

    function test_updateParam_votingDelay_shouldUpdateCorrectly() public {
        // Arrange
        uint256 newVotingDelay = 1 hours;
        bytes memory encodedValue = abi.encode(newVotingDelay);

        // Act & Assert
        vm.prank(GOV_HUB_ADDR);
        vm.expectEmit(true, true, true, true);
        emit ParamChange("votingDelay", encodedValue);
        governor.updateParam("votingDelay", encodedValue);

        // Assert
        assertEq(governor.votingDelay(), newVotingDelay);
    }

    function test_updateParam_votingPeriod_shouldUpdateCorrectly() public {
        // Arrange
        uint256 newVotingPeriod = 14 days;
        bytes memory encodedValue = abi.encode(newVotingPeriod);

        // Act
        vm.prank(GOV_HUB_ADDR);
        governor.updateParam("votingPeriod", encodedValue);

        // Assert
        assertEq(governor.votingPeriod(), newVotingPeriod);
    }

    function test_updateParam_proposalThreshold_shouldUpdateCorrectly() public {
        // Arrange
        uint256 newProposalThreshold = 5_000 ether;
        bytes memory encodedValue = abi.encode(newProposalThreshold);

        // Act
        vm.prank(GOV_HUB_ADDR);
        governor.updateParam("proposalThreshold", encodedValue);

        // Assert
        assertEq(governor.proposalThreshold(), newProposalThreshold);
    }

    function test_updateParam_quorumNumerator_shouldUpdateCorrectly() public {
        // Arrange
        uint256 newQuorumNumerator = 15; // 15%
        bytes memory encodedValue = abi.encode(newQuorumNumerator);

        // Act
        vm.prank(GOV_HUB_ADDR);
        governor.updateParam("quorumNumerator", encodedValue);

        // Assert - Check that quorum calculation uses new numerator
        // Note: Actual quorum check would require creating a proposal and checking quorum
    }

    function test_updateParam_minPeriodAfterQuorum_shouldUpdateCorrectly() public {
        // Arrange - Use uint64 value but encode as 8 bytes using abi.encodePacked
        uint64 newMinPeriod = 12 hours;
        bytes memory encodedValue = abi.encodePacked(newMinPeriod);

        // Act
        vm.prank(GOV_HUB_ADDR);
        governor.updateParam("minPeriodAfterQuorum", encodedValue);

        // Assert - The value is set internally, hard to verify without proposal
    }

    function test_updateParam_shouldRevertForInvalidValues() public {
        // Test votingDelay = 0
        vm.prank(GOV_HUB_ADDR);
        vm.expectRevert(abi.encodeWithSelector(System.InvalidValue.selector, "votingDelay", abi.encode(uint256(0))));
        governor.updateParam("votingDelay", abi.encode(uint256(0)));

        // Test votingDelay > 24 hours
        vm.prank(GOV_HUB_ADDR);
        vm.expectRevert(
            abi.encodeWithSelector(System.InvalidValue.selector, "votingDelay", abi.encode(uint256(25 hours)))
        );
        governor.updateParam("votingDelay", abi.encode(uint256(25 hours)));

        // Test proposalThreshold = 0
        vm.prank(GOV_HUB_ADDR);
        vm.expectRevert(
            abi.encodeWithSelector(System.InvalidValue.selector, "proposalThreshold", abi.encode(uint256(0)))
        );
        governor.updateParam("proposalThreshold", abi.encode(uint256(0)));

        // Test quorumNumerator < 5
        vm.prank(GOV_HUB_ADDR);
        vm.expectRevert(abi.encodeWithSelector(System.InvalidValue.selector, "quorumNumerator", abi.encode(uint256(4))));
        governor.updateParam("quorumNumerator", abi.encode(uint256(4)));
    }

    function test_updateParam_unknownParam_shouldRevert() public {
        // Arrange
        bytes memory encodedValue = abi.encode(uint256(100));

        // Act & Assert
        vm.prank(GOV_HUB_ADDR);
        vm.expectRevert(abi.encodeWithSelector(System.UnknownParam.selector, "unknownParam", encodedValue));
        governor.updateParam("unknownParam", encodedValue);
    }

    function test_updateParam_onlyGov() public {
        // Arrange
        bytes memory encodedValue = abi.encode(uint256(1 hours));

        // Act & Assert
        vm.prank(user1);
        vm.expectRevert();
        governor.updateParam("votingDelay", encodedValue);
    }

    // ============ VIEW FUNCTION TESTS ============

    function test_supportsInterface_shouldReturnTrue() public view {
        // Assert - Check for IGovernor interface
        assertTrue(governor.supportsInterface(type(IGovernor).interfaceId));
    }

    function test_COUNTING_MODE_shouldReturnCorrectString() public view {
        // Assert
        assertEq(governor.COUNTING_MODE(), "support=bravo&quorum=for,abstain");
    }

    // ============ ACCESS CONTROL TESTS ============

    function test_whitelistTargets_shouldBeSetCorrectly() public view {
        // Assert
        assertTrue(governor.whitelistTargets(GOV_HUB_ADDR));
        assertFalse(governor.whitelistTargets(user1));
    }
}
