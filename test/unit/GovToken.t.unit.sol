// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "forge-std/Test.sol";
import "@src/governance/GovToken.sol";
import "@src/interfaces/IGovToken.sol";
import "@test/utils/TestConstants.sol";
import "@test/mocks/StakeCreditMock.sol";
import "@test/mocks/ValidatorManagerMock.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

contract GovTokenTest is Test, TestConstants {
    GovToken public govToken;
    GovToken public implementation;
    StakeCreditMock public mockStakeCredit;
    ValidatorManagerMock public validatorManager;

    // Test addresses
    address public user1 = makeAddr("user1");
    address public user2 = makeAddr("user2");
    address public validator = makeAddr("validator");

    event Transfer(address indexed from, address indexed to, uint256 value);
    event DelegateChanged(address indexed delegator, address indexed fromDelegate, address indexed toDelegate);
    event DelegateVotesChanged(address indexed delegate, uint256 previousBalance, uint256 newBalance);

    function setUp() public {
        // Deploy mock contracts first
        validatorManager = new ValidatorManagerMock();
        mockStakeCredit = new StakeCreditMock();

        // Set up system contracts using vm.etch with actual deployed code
        // Note: Cannot etch GENESIS_ADDR (0x01) as it's a precompile
        vm.etch(VALIDATOR_MANAGER_ADDR, address(validatorManager).code);

        // Deploy implementation
        implementation = new GovToken();

        // Deploy proxy
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), "");
        govToken = GovToken(address(proxy));

        // Initialize the proxy from GENESIS_ADDR with vm.store to bypass onlyGenesis check
        // Store alreadyInit as false temporarily if needed
        vm.prank(GENESIS_ADDR);
        govToken.initialize();
    }

    // ============ INITIALIZATION TESTS ============

    function test_initialize_shouldSetCorrectValues() public view {
        // Assert
        assertEq(govToken.name(), "BSC Governance Token");
        assertEq(govToken.symbol(), "govG");
        assertEq(govToken.decimals(), 18);
        assertEq(govToken.totalSupply(), 0);
    }

    function test_initialize_cannotBeCalledTwice() public {
        // Act & Assert
        vm.expectRevert();
        govToken.initialize();
    }

    function test_initialize_onlyGenesis() public {
        // Arrange
        GovToken newToken = new GovToken();

        // Act & Assert
        vm.prank(user1);
        vm.expectRevert();
        newToken.initialize();
    }

    // ============ SYNC FUNCTION TESTS ============

    function test_sync_shouldMintTokensWhenStakeCreditIncreases() public {
        // Arrange
        uint256 stakeCreditAmount = 1000 ether;
        mockStakeCredit.setTotalPooledG(stakeCreditAmount);

        // Act
        vm.prank(VALIDATOR_MANAGER_ADDR);
        govToken.sync(address(mockStakeCredit), user1);

        // Assert
        assertEq(govToken.balanceOf(user1), stakeCreditAmount);
        assertEq(govToken.mintedMap(address(mockStakeCredit), user1), stakeCreditAmount);
        assertEq(govToken.totalSupply(), stakeCreditAmount);
    }

    function test_sync_shouldBurnTokensWhenStakeCreditDecreases() public {
        // Arrange - First mint some tokens
        uint256 initialAmount = 1000 ether;
        mockStakeCredit.setTotalPooledG(initialAmount);
        vm.prank(VALIDATOR_MANAGER_ADDR);
        govToken.sync(address(mockStakeCredit), user1);

        // Arrange - Decrease stake credit
        uint256 newAmount = 500 ether;
        mockStakeCredit.setTotalPooledG(newAmount);

        // Act
        vm.prank(VALIDATOR_MANAGER_ADDR);
        govToken.sync(address(mockStakeCredit), user1);

        // Assert
        assertEq(govToken.balanceOf(user1), newAmount);
        assertEq(govToken.mintedMap(address(mockStakeCredit), user1), newAmount);
        assertEq(govToken.totalSupply(), newAmount);
    }

    function test_sync_shouldDoNothingWhenAmountUnchanged() public {
        // Arrange
        uint256 stakeCreditAmount = 1000 ether;
        mockStakeCredit.setTotalPooledG(stakeCreditAmount);
        vm.prank(VALIDATOR_MANAGER_ADDR);
        govToken.sync(address(mockStakeCredit), user1);

        uint256 balanceBefore = govToken.balanceOf(user1);
        uint256 supplyBefore = govToken.totalSupply();

        // Act - Sync again with same amount
        vm.prank(VALIDATOR_MANAGER_ADDR);
        govToken.sync(address(mockStakeCredit), user1);

        // Assert
        assertEq(govToken.balanceOf(user1), balanceBefore);
        assertEq(govToken.totalSupply(), supplyBefore);
    }

    function test_sync_onlyValidatorManager() public {
        // Act & Assert
        vm.prank(user1);
        vm.expectRevert();
        govToken.sync(address(mockStakeCredit), user1);
    }

    function test_sync_shouldEmitTransferEvent() public {
        // Arrange
        uint256 stakeCreditAmount = 1000 ether;
        mockStakeCredit.setTotalPooledG(stakeCreditAmount);

        // Act & Assert
        vm.prank(VALIDATOR_MANAGER_ADDR);
        vm.expectEmit(true, true, true, true);
        emit Transfer(address(0), user1, stakeCreditAmount);
        govToken.sync(address(mockStakeCredit), user1);
    }

    // ============ SYNC BATCH TESTS ============

    function test_syncBatch_shouldSyncMultipleStakeCredits() public {
        // Arrange
        StakeCreditMock stakeCredit2 = new StakeCreditMock();
        address[] memory stakeCredits = new address[](2);
        stakeCredits[0] = address(mockStakeCredit);
        stakeCredits[1] = address(stakeCredit2);

        mockStakeCredit.setTotalPooledG(500 ether);
        stakeCredit2.setTotalPooledG(300 ether);

        // Act
        vm.prank(VALIDATOR_MANAGER_ADDR);
        govToken.syncBatch(stakeCredits, user1);

        // Assert
        assertEq(govToken.balanceOf(user1), 800 ether);
        assertEq(govToken.mintedMap(address(mockStakeCredit), user1), 500 ether);
        assertEq(govToken.mintedMap(address(stakeCredit2), user1), 300 ether);
    }

    function test_syncBatch_onlyValidatorManager() public {
        // Arrange
        address[] memory stakeCredits = new address[](1);
        stakeCredits[0] = address(mockStakeCredit);

        // Act & Assert
        vm.prank(user1);
        vm.expectRevert();
        govToken.syncBatch(stakeCredits, user1);
    }

    function test_syncBatch_emptyArray() public {
        // Arrange
        address[] memory stakeCredits = new address[](0);

        // Act
        vm.prank(VALIDATOR_MANAGER_ADDR);
        govToken.syncBatch(stakeCredits, user1);

        // Assert - Should not change anything
        assertEq(govToken.balanceOf(user1), 0);
    }

    // ============ DELEGATE VOTE TESTS ============

    function test_delegateVote_shouldDelegateVotes() public {
        // Arrange - Give user1 some tokens first
        mockStakeCredit.setTotalPooledG(1000 ether);
        vm.prank(VALIDATOR_MANAGER_ADDR);
        govToken.sync(address(mockStakeCredit), user1);

        // Act
        vm.prank(VALIDATOR_MANAGER_ADDR);
        vm.expectEmit(true, true, true, true);
        emit DelegateChanged(user1, address(0), user2);
        govToken.delegateVote(user1, user2);

        // Assert
        assertEq(govToken.delegates(user1), user2);
        assertEq(govToken.getVotes(user2), 1000 ether);
    }

    function test_delegateVote_onlyValidatorManager() public {
        // Act & Assert
        vm.prank(user1);
        vm.expectRevert();
        govToken.delegateVote(user1, user2);
    }

    function test_delegateVote_shouldUpdateVotingPower() public {
        // Arrange - Give user1 some tokens
        mockStakeCredit.setTotalPooledG(1000 ether);
        vm.prank(VALIDATOR_MANAGER_ADDR);
        govToken.sync(address(mockStakeCredit), user1);

        // Act - Delegate to user2
        vm.prank(VALIDATOR_MANAGER_ADDR);
        govToken.delegateVote(user1, user2);

        // Assert
        assertEq(govToken.getVotes(user1), 0);
        assertEq(govToken.getVotes(user2), 1000 ether);

        // Act - Change delegation to validator
        vm.prank(VALIDATOR_MANAGER_ADDR);
        govToken.delegateVote(user1, validator);

        // Assert
        assertEq(govToken.getVotes(user2), 0);
        assertEq(govToken.getVotes(validator), 1000 ether);
    }

    // ============ BURN FUNCTION TESTS ============

    function test_burn_shouldAlwaysRevert() public {
        // Act & Assert
        vm.expectRevert(IGovToken.BurnNotAllowed.selector);
        govToken.burn(100 ether);
    }

    function test_burnFrom_shouldAlwaysRevert() public {
        // Act & Assert
        vm.expectRevert(IGovToken.BurnNotAllowed.selector);
        govToken.burnFrom(user1, 100 ether);
    }

    // ============ TRANSFER RESTRICTION TESTS ============

    function test_transfer_shouldRevert() public {
        // Arrange - Give user1 some tokens
        mockStakeCredit.setTotalPooledG(1000 ether);
        vm.prank(VALIDATOR_MANAGER_ADDR);
        govToken.sync(address(mockStakeCredit), user1);

        // Act & Assert
        vm.prank(user1);
        vm.expectRevert(IGovToken.TransferNotAllowed.selector);
        govToken.transfer(user2, 100 ether);
    }

    function test_transferFrom_shouldRevert() public {
        // Arrange - Give user1 some tokens
        mockStakeCredit.setTotalPooledG(1000 ether);
        vm.prank(VALIDATOR_MANAGER_ADDR);
        govToken.sync(address(mockStakeCredit), user1);

        // First try to approve (this should fail with ApproveNotAllowed)
        vm.prank(user1);
        vm.expectRevert(IGovToken.ApproveNotAllowed.selector);
        govToken.approve(user2, 100 ether);

        // Since we can't approve, transferFrom will fail with ERC20InsufficientAllowance
        // because allowance check happens before the transfer logic
        vm.prank(user2);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, user2, 0, 100 ether));
        govToken.transferFrom(user1, user2, 100 ether);
    }

    // ============ APPROVAL RESTRICTION TESTS ============

    function test_approve_shouldRevert() public {
        // Act & Assert
        vm.prank(user1);
        vm.expectRevert(IGovToken.ApproveNotAllowed.selector);
        govToken.approve(user2, 100 ether);
    }

    // ============ VIEW FUNCTION TESTS ============

    function test_totalSupply_shouldReturnCorrectValue() public {
        // Arrange
        mockStakeCredit.setTotalPooledG(1000 ether);
        vm.prank(VALIDATOR_MANAGER_ADDR);
        govToken.sync(address(mockStakeCredit), user1);

        StakeCreditMock stakeCredit2 = new StakeCreditMock();
        stakeCredit2.setTotalPooledG(500 ether);
        vm.prank(VALIDATOR_MANAGER_ADDR);
        govToken.sync(address(stakeCredit2), user2);

        // Assert
        assertEq(govToken.totalSupply(), 1500 ether);
    }

    function test_nonces_shouldReturnCorrectValue() public view {
        // Assert
        assertEq(govToken.nonces(user1), 0);
    }

    // ============ MULTIPLE USER TESTS ============

    function test_multipleUsers_shouldMaintainSeparateBalances() public {
        // Arrange
        StakeCreditMock stakeCredit2 = new StakeCreditMock();

        mockStakeCredit.setTotalPooledG(1000 ether);
        stakeCredit2.setTotalPooledG(500 ether);

        // Act
        vm.prank(VALIDATOR_MANAGER_ADDR);
        govToken.sync(address(mockStakeCredit), user1);

        vm.prank(VALIDATOR_MANAGER_ADDR);
        govToken.sync(address(stakeCredit2), user2);

        // Assert
        assertEq(govToken.balanceOf(user1), 1000 ether);
        assertEq(govToken.balanceOf(user2), 500 ether);
        assertEq(govToken.totalSupply(), 1500 ether);
        assertEq(govToken.mintedMap(address(mockStakeCredit), user1), 1000 ether);
        assertEq(govToken.mintedMap(address(stakeCredit2), user2), 500 ether);
    }

    function test_multipleStakeCreditsPerUser_shouldAccumulate() public {
        // Arrange
        StakeCreditMock stakeCredit2 = new StakeCreditMock();

        mockStakeCredit.setTotalPooledG(600 ether);
        stakeCredit2.setTotalPooledG(400 ether);

        // Act
        vm.startPrank(VALIDATOR_MANAGER_ADDR);
        govToken.sync(address(mockStakeCredit), user1);
        govToken.sync(address(stakeCredit2), user1);
        vm.stopPrank();

        // Assert
        assertEq(govToken.balanceOf(user1), 1000 ether);
        assertEq(govToken.mintedMap(address(mockStakeCredit), user1), 600 ether);
        assertEq(govToken.mintedMap(address(stakeCredit2), user1), 400 ether);
    }

    // ============ EDGE CASE TESTS ============

    function test_sync_zeroAmount() public {
        // Arrange
        mockStakeCredit.setTotalPooledG(0);

        // Act
        vm.prank(VALIDATOR_MANAGER_ADDR);
        govToken.sync(address(mockStakeCredit), user1);

        // Assert
        assertEq(govToken.balanceOf(user1), 0);
        assertEq(govToken.mintedMap(address(mockStakeCredit), user1), 0);
    }

    function test_sync_largeAmount() public {
        // Arrange - Use a safer large amount that won't exceed ERC20 safe supply
        uint256 largeAmount = 1e30; // 1 billion tokens with 18 decimals, much safer
        mockStakeCredit.setTotalPooledG(largeAmount);

        // Act
        vm.prank(VALIDATOR_MANAGER_ADDR);
        govToken.sync(address(mockStakeCredit), user1);

        // Assert
        assertEq(govToken.balanceOf(user1), largeAmount);
        assertEq(govToken.mintedMap(address(mockStakeCredit), user1), largeAmount);
    }

    // ============ FUZZ TESTS ============

    function testFuzz_sync_validAmounts(
        uint256 amount
    ) public {
        // Arrange - Use much more conservative bounds to avoid ERC20 safe supply issues
        vm.assume(amount > 0 && amount <= 1e30); // Max 1 billion tokens with 18 decimals
        mockStakeCredit.setTotalPooledG(amount);

        // Act
        vm.prank(VALIDATOR_MANAGER_ADDR);
        govToken.sync(address(mockStakeCredit), user1);

        // Assert
        assertEq(govToken.balanceOf(user1), amount);
        assertEq(govToken.mintedMap(address(mockStakeCredit), user1), amount);
    }

    function testFuzz_delegateVote_validAddresses(
        address delegatee
    ) public {
        // Arrange
        vm.assume(delegatee != address(0));
        mockStakeCredit.setTotalPooledG(1000 ether);
        vm.prank(VALIDATOR_MANAGER_ADDR);
        govToken.sync(address(mockStakeCredit), user1);

        // Act
        vm.prank(VALIDATOR_MANAGER_ADDR);
        govToken.delegateVote(user1, delegatee);

        // Assert
        assertEq(govToken.delegates(user1), delegatee);
        assertEq(govToken.getVotes(delegatee), 1000 ether);
    }
}
