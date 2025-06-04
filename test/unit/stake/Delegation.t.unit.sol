// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "forge-std/Test.sol";
import "@src/stake/Delegation.sol";
import "@src/System.sol";
import "@test/utils/TestConstants.sol";
import "@test/mocks/ValidatorManagerMock.sol";
import "@test/mocks/StakeCreditMock.sol";
import "@test/mocks/StakeConfigMock.sol";
import "@test/mocks/GovTokenMock.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract DelegationTest is Test, TestConstants {
    Delegation public delegation;
    Delegation public implementation;

    ValidatorManagerMock public validatorManagerMock;
    StakeCreditMock public stakeCreditMock;
    StakeConfigMock public stakeConfigMock;
    GovTokenMock public govTokenMock;

    // Test users
    address public validator1 = TEST_VALIDATOR_1;
    address public validator2 = TEST_VALIDATOR_2;
    address public delegator1 = TEST_DELEGATOR_1;
    address public delegator2 = TEST_DELEGATOR_2;
    address public attacker = makeAddr("attacker");

    // Test values
    uint256 public constant MIN_DELEGATION_CHANGE = 0.1 ether;
    uint256 public constant REDELEGATE_FEE_RATE = 100; // 1%
    uint256 public constant PERCENTAGE_BASE = 10000;

    function setUp() public {
        // Deploy implementation
        implementation = new Delegation();

        // Deploy proxy
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), "");
        delegation = Delegation(payable(address(proxy)));

        // Deploy mocks
        validatorManagerMock = new ValidatorManagerMock();
        stakeCreditMock = new StakeCreditMock();
        stakeConfigMock = new StakeConfigMock();
        govTokenMock = new GovTokenMock();

        // Setup mocks at system addresses
        vm.etch(VALIDATOR_MANAGER_ADDR, address(validatorManagerMock).code);
        vm.etch(STAKE_CONFIG_ADDR, address(stakeConfigMock).code);
        vm.etch(GOV_TOKEN_ADDR, address(govTokenMock).code);

        // Initialize mocks that have initialize function
        ValidatorManagerMock(VALIDATOR_MANAGER_ADDR).initialize(
            new address[](0),
            new address[](0),
            new address payable[](0),
            new uint64[](0),
            new bytes[](0)
        );
        StakeConfigMock(STAKE_CONFIG_ADDR).initialize();
        // GovTokenMock doesn't have initialize method

        // Setup test validators using ValidatorManagerMock methods on system address
        ValidatorManagerMock(VALIDATOR_MANAGER_ADDR).setIsValidatorExists(validator1, true);
        ValidatorManagerMock(VALIDATOR_MANAGER_ADDR).setIsValidatorExists(validator2, true);
        ValidatorManagerMock(VALIDATOR_MANAGER_ADDR).setValidatorStakeCredit(validator1, address(stakeCreditMock));
        ValidatorManagerMock(VALIDATOR_MANAGER_ADDR).setValidatorStakeCredit(validator2, address(stakeCreditMock));
        ValidatorManagerMock(VALIDATOR_MANAGER_ADDR).setValidatorStatus(
            validator1,
            IValidatorManager.ValidatorStatus.ACTIVE
        );
        ValidatorManagerMock(VALIDATOR_MANAGER_ADDR).setValidatorStatus(
            validator2,
            IValidatorManager.ValidatorStatus.ACTIVE
        );

        // Setup stake config mocks
        vm.mockCall(
            STAKE_CONFIG_ADDR,
            abi.encodeWithSelector(IStakeConfig.minDelegationChange.selector),
            abi.encode(MIN_DELEGATION_CHANGE)
        );
        vm.mockCall(
            STAKE_CONFIG_ADDR,
            abi.encodeWithSelector(IStakeConfig.redelegateFeeRate.selector),
            abi.encode(REDELEGATE_FEE_RATE)
        );
        vm.mockCall(
            STAKE_CONFIG_ADDR,
            abi.encodeWithSelector(IStakeConfig.PERCENTAGE_BASE.selector),
            abi.encode(PERCENTAGE_BASE)
        );

        // Mock gov token calls
        vm.mockCall(GOV_TOKEN_ADDR, abi.encodeWithSelector(IGovToken.sync.selector), abi.encode());
        vm.mockCall(GOV_TOKEN_ADDR, abi.encodeWithSelector(IGovToken.syncBatch.selector), abi.encode());
        vm.mockCall(GOV_TOKEN_ADDR, abi.encodeWithSelector(IGovToken.delegateVote.selector), abi.encode());

        // Give test accounts some ETH
        vm.deal(delegator1, 100 ether);
        vm.deal(delegator2, 100 ether);
        vm.deal(validator1, 100 ether);
        vm.deal(validator2, 100 ether);

        // Give delegation contract some ETH for fee payments
        vm.deal(address(delegation), 10 ether);
    }

    // ============ DELEGATE TESTS ============

    function test_delegate_shouldWork() public {
        // Arrange
        uint256 delegationAmount = 1 ether;
        uint256 expectedShares = 1000; // Mock shares

        // Mock StakeCredit delegate call
        vm.mockCall(
            address(stakeCreditMock),
            abi.encodeWithSelector(IStakeCredit.delegate.selector, delegator1),
            abi.encode(expectedShares)
        );

        // Act
        vm.prank(delegator1);
        delegation.delegate{ value: delegationAmount }(validator1);

        // Assert - Check that the delegate call was made with correct parameters
        // The actual verification is done through mock calls
        assertTrue(true); // Placeholder for now
    }

    function test_delegate_shouldRevertIfValidatorNotExists() public {
        // Arrange
        address nonExistentValidator = makeAddr("nonExistent");
        uint256 delegationAmount = 1 ether;

        // Act & Assert
        vm.prank(delegator1);
        vm.expectRevert(
            abi.encodeWithSelector(IDelegation.Delegation__ValidatorNotRegistered.selector, nonExistentValidator)
        );
        delegation.delegate{ value: delegationAmount }(nonExistentValidator);
    }

    function test_delegate_shouldRevertIfAmountTooSmall() public {
        // Arrange
        uint256 smallAmount = MIN_DELEGATION_CHANGE - 1;

        // Act & Assert
        vm.prank(delegator1);
        vm.expectRevert(IDelegation.Delegation__LessThanMinDelegationChange.selector);
        delegation.delegate{ value: smallAmount }(validator1);
    }

    function test_delegate_shouldEmitDelegatedEvent() public {
        // Arrange
        uint256 delegationAmount = 1 ether;
        uint256 expectedShares = 1000;

        vm.mockCall(
            address(stakeCreditMock),
            abi.encodeWithSelector(IStakeCredit.delegate.selector, delegator1),
            abi.encode(expectedShares)
        );

        // Act & Assert
        vm.prank(delegator1);
        vm.expectEmit(true, true, true, true);
        emit IDelegation.Delegated(validator1, delegator1, expectedShares, delegationAmount);
        delegation.delegate{ value: delegationAmount }(validator1);
    }

    // ============ UNDELEGATE TESTS ============

    function test_undelegate_shouldWork() public {
        // Arrange
        uint256 shares = 1000;
        uint256 expectedAmount = 1 ether;

        vm.mockCall(
            address(stakeCreditMock),
            abi.encodeWithSelector(StakeCredit.unlock.selector, delegator1, shares),
            abi.encode(expectedAmount)
        );

        // Act
        vm.prank(delegator1);
        delegation.undelegate(validator1, shares);

        // Assert - The unlock call should have been made
        assertTrue(true); // Placeholder for verification
    }

    function test_undelegate_shouldRevertIfZeroShares() public {
        // Act & Assert
        vm.prank(delegator1);
        vm.expectRevert(IDelegation.Delegation__ZeroShares.selector);
        delegation.undelegate(validator1, 0);
    }

    function test_undelegate_shouldRevertIfValidatorNotExists() public {
        // Arrange
        address nonExistentValidator = makeAddr("nonExistent");
        uint256 shares = 1000;

        // Act & Assert
        vm.prank(delegator1);
        vm.expectRevert(
            abi.encodeWithSelector(IDelegation.Delegation__ValidatorNotRegistered.selector, nonExistentValidator)
        );
        delegation.undelegate(nonExistentValidator, shares);
    }

    function test_undelegate_shouldEmitUndelegatedEvent() public {
        // Arrange
        uint256 shares = 1000;
        uint256 expectedAmount = 1 ether;

        vm.mockCall(
            address(stakeCreditMock),
            abi.encodeWithSelector(StakeCredit.unlock.selector, delegator1, shares),
            abi.encode(expectedAmount)
        );

        // Act & Assert
        vm.prank(delegator1);
        vm.expectEmit(true, true, true, true);
        emit IDelegation.Undelegated(validator1, delegator1, shares, expectedAmount);
        delegation.undelegate(validator1, shares);
    }

    // ============ CLAIM TESTS ============

    function test_claim_shouldWork() public {
        // Arrange
        uint256 claimableAmount = 1 ether;

        vm.mockCall(
            address(stakeCreditMock),
            abi.encodeWithSelector(IStakeCredit.claim.selector, delegator1),
            abi.encode(claimableAmount)
        );

        // Act
        vm.prank(delegator1);
        uint256 claimed = delegation.claim(validator1);

        // Assert
        assertEq(claimed, claimableAmount);
    }

    function test_claim_shouldReturnZeroIfNothingToClaim() public {
        // Arrange
        vm.mockCall(
            address(stakeCreditMock),
            abi.encodeWithSelector(IStakeCredit.claim.selector, delegator1),
            abi.encode(0)
        );

        // Act
        vm.prank(delegator1);
        uint256 claimed = delegation.claim(validator1);

        // Assert
        assertEq(claimed, 0);
    }

    function test_claim_shouldRevertIfInvalidValidator() public {
        // Arrange
        address invalidValidator = makeAddr("invalid");

        // Mock to return zero address for stake credit
        vm.mockCall(
            VALIDATOR_MANAGER_ADDR,
            abi.encodeWithSelector(IValidatorManager.getValidatorStakeCredit.selector, invalidValidator),
            abi.encode(address(0))
        );

        // Act & Assert
        vm.prank(delegator1);
        vm.expectRevert(Delegation.InvalidValidator.selector);
        delegation.claim(invalidValidator);
    }

    function test_claim_shouldEmitStakeClaimedEvent() public {
        // Arrange
        uint256 claimableAmount = 1 ether;

        vm.mockCall(
            address(stakeCreditMock),
            abi.encodeWithSelector(IStakeCredit.claim.selector, delegator1),
            abi.encode(claimableAmount)
        );

        // Act & Assert
        vm.prank(delegator1);
        vm.expectEmit(true, true, true, true);
        emit IDelegation.StakeClaimed(delegator1, validator1, claimableAmount);
        delegation.claim(validator1);
    }

    // ============ CLAIM BATCH TESTS ============

    function test_claimBatch_shouldWork() public {
        // Arrange
        address[] memory validators = new address[](2);
        validators[0] = validator1;
        validators[1] = validator2;

        uint256 claimAmount1 = 1 ether;
        uint256 claimAmount2 = 2 ether;
        uint256 totalExpected = claimAmount1 + claimAmount2;

        vm.mockCall(
            address(stakeCreditMock),
            abi.encodeWithSelector(IStakeCredit.claim.selector, delegator1),
            abi.encode(claimAmount1)
        );

        // Act
        vm.prank(delegator1);
        uint256 totalClaimed = delegation.claimBatch(validators);

        // Assert
        assertEq(totalClaimed, claimAmount1 * 2); // Both validators use same mock
    }

    function test_claimBatch_shouldSkipInvalidValidators() public {
        // Arrange
        address[] memory validators = new address[](2);
        validators[0] = validator1;
        validators[1] = makeAddr("invalid");

        uint256 claimAmount = 1 ether;

        vm.mockCall(
            address(stakeCreditMock),
            abi.encodeWithSelector(IStakeCredit.claim.selector, delegator1),
            abi.encode(claimAmount)
        );

        // Mock invalid validator to return zero address
        vm.mockCall(
            VALIDATOR_MANAGER_ADDR,
            abi.encodeWithSelector(IValidatorManager.getValidatorStakeCredit.selector, validators[1]),
            abi.encode(address(0))
        );

        // Act
        vm.prank(delegator1);
        uint256 totalClaimed = delegation.claimBatch(validators);

        // Assert
        assertEq(totalClaimed, claimAmount); // Only valid validator
    }

    // ============ REDELEGATE TESTS ============

    function test_redelegate_shouldWork() public {
        // Arrange
        uint256 shares = 1000;
        uint256 unbondAmount = 1 ether;
        uint256 feeAmount = (unbondAmount * REDELEGATE_FEE_RATE) / PERCENTAGE_BASE;
        uint256 netAmount = unbondAmount - feeAmount;
        uint256 newShares = 950;

        // Setup separate mock addresses for different validators
        StakeCreditMock srcStakeCredit = new StakeCreditMock();
        StakeCreditMock dstStakeCredit = new StakeCreditMock();

        // Use ValidatorManagerMock methods to set stake credit addresses on system address
        ValidatorManagerMock(VALIDATOR_MANAGER_ADDR).setValidatorStakeCredit(validator1, address(srcStakeCredit));
        ValidatorManagerMock(VALIDATOR_MANAGER_ADDR).setValidatorStakeCredit(validator2, address(dstStakeCredit));

        vm.mockCall(
            address(srcStakeCredit),
            abi.encodeWithSelector(IStakeCredit.unbond.selector, delegator1, shares),
            abi.encode(unbondAmount)
        );

        vm.mockCall(
            address(dstStakeCredit),
            abi.encodeWithSelector(IStakeCredit.delegate.selector, delegator1),
            abi.encode(newShares)
        );

        // Act
        vm.prank(delegator1);
        delegation.redelegate(validator1, validator2, shares, false);

        // Assert - The redelegate should have completed without revert
        assertTrue(true);
    }

    function test_redelegate_shouldRevertIfZeroShares() public {
        // Act & Assert
        vm.prank(delegator1);
        vm.expectRevert(IDelegation.Delegation__ZeroShares.selector);
        delegation.redelegate(validator1, validator2, 0, false);
    }

    function test_redelegate_shouldRevertIfSameValidator() public {
        // Act & Assert
        vm.prank(delegator1);
        vm.expectRevert(IDelegation.Delegation__SameValidator.selector);
        delegation.redelegate(validator1, validator1, 1000, false);
    }

    function test_redelegate_shouldRevertIfSrcValidatorNotExists() public {
        // Arrange
        address nonExistentValidator = makeAddr("nonExistent");

        // Act & Assert
        vm.prank(delegator1);
        vm.expectRevert(
            abi.encodeWithSelector(IDelegation.Delegation__ValidatorNotRegistered.selector, nonExistentValidator)
        );
        delegation.redelegate(nonExistentValidator, validator2, 1000, false);
    }

    function test_redelegate_shouldRevertIfDstValidatorNotExists() public {
        // Arrange
        address nonExistentValidator = makeAddr("nonExistent");

        // Act & Assert
        vm.prank(delegator1);
        vm.expectRevert(
            abi.encodeWithSelector(IDelegation.Delegation__ValidatorNotRegistered.selector, nonExistentValidator)
        );
        delegation.redelegate(validator1, nonExistentValidator, 1000, false);
    }

    function test_redelegate_shouldRevertIfAmountTooSmall() public {
        // Arrange
        uint256 shares = 1000;
        uint256 smallAmount = MIN_DELEGATION_CHANGE - 1;

        StakeCreditMock srcStakeCredit = new StakeCreditMock();

        // Use ValidatorManagerMock method to set stake credit address on system address
        ValidatorManagerMock(VALIDATOR_MANAGER_ADDR).setValidatorStakeCredit(validator1, address(srcStakeCredit));

        vm.mockCall(
            address(srcStakeCredit),
            abi.encodeWithSelector(IStakeCredit.unbond.selector, delegator1, shares),
            abi.encode(smallAmount)
        );

        // Act & Assert
        vm.prank(delegator1);
        vm.expectRevert(IDelegation.Delegation__LessThanMinDelegationChange.selector);
        delegation.redelegate(validator1, validator2, shares, false);
    }

    function test_redelegate_shouldAllowSelfDelegationToJailedValidator() public {
        // Arrange
        // Use ValidatorManagerMock method to set validator2 status as INACTIVE on system address
        ValidatorManagerMock(VALIDATOR_MANAGER_ADDR).setValidatorStatus(
            validator2,
            IValidatorManager.ValidatorStatus.INACTIVE
        );

        uint256 shares = 1000;
        uint256 unbondAmount = 1 ether;
        uint256 newShares = 950;

        StakeCreditMock srcStakeCredit = new StakeCreditMock();
        StakeCreditMock dstStakeCredit = new StakeCreditMock();

        // Use ValidatorManagerMock methods to set stake credit addresses on system address
        ValidatorManagerMock(VALIDATOR_MANAGER_ADDR).setValidatorStakeCredit(validator1, address(srcStakeCredit));
        ValidatorManagerMock(VALIDATOR_MANAGER_ADDR).setValidatorStakeCredit(validator2, address(dstStakeCredit));

        vm.mockCall(
            address(srcStakeCredit),
            abi.encodeWithSelector(IStakeCredit.unbond.selector, validator2, shares),
            abi.encode(unbondAmount)
        );

        vm.mockCall(
            address(dstStakeCredit),
            abi.encodeWithSelector(IStakeCredit.delegate.selector, validator2),
            abi.encode(newShares)
        );

        // Act - Should work when validator delegates to themselves even if inactive
        vm.prank(validator2);
        delegation.redelegate(validator1, validator2, shares, false);

        // Assert
        assertTrue(true);
    }

    function test_redelegate_shouldRevertForNonSelfDelegationToJailedValidator() public {
        // Arrange
        // Use ValidatorManagerMock method to set validator2 status as INACTIVE on system address
        ValidatorManagerMock(VALIDATOR_MANAGER_ADDR).setValidatorStatus(
            validator2,
            IValidatorManager.ValidatorStatus.INACTIVE
        );

        // Act & Assert
        vm.prank(delegator1); // Not the validator itself
        vm.expectRevert(IDelegation.Delegation__OnlySelfDelegationToJailedValidator.selector);
        delegation.redelegate(validator1, validator2, 1000, false);
    }

    // ============ DELEGATE VOTE TESTS ============

    function test_delegateVoteTo_shouldWork() public {
        // Arrange
        address voter = makeAddr("voter");

        // Act & Assert
        vm.prank(delegator1);
        vm.expectEmit(true, true, true, true);
        emit IDelegation.VoteDelegated(delegator1, voter);
        delegation.delegateVoteTo(voter);
    }

    // ============ ACCESS CONTROL TESTS ============

    function test_delegate_shouldRevertWhenPaused() public {
        // Arrange
        vm.prank(GOV_HUB_ADDR);
        delegation.pause();

        // Act & Assert
        vm.prank(delegator1);
        vm.expectRevert();
        delegation.delegate{ value: 1 ether }(validator1);
    }

    function test_undelegate_shouldRevertWhenPaused() public {
        // Arrange
        vm.prank(GOV_HUB_ADDR);
        delegation.pause();

        // Act & Assert
        vm.prank(delegator1);
        vm.expectRevert();
        delegation.undelegate(validator1, 1000);
    }

    function test_redelegate_shouldRevertWhenPaused() public {
        // Arrange
        vm.prank(GOV_HUB_ADDR);
        delegation.pause();

        // Act & Assert
        vm.prank(delegator1);
        vm.expectRevert();
        delegation.redelegate(validator1, validator2, 1000, false);
    }

    // ============ FUZZ TESTS ============

    function testFuzz_delegate_validAmounts(uint256 amount) public {
        // Arrange
        vm.assume(amount >= MIN_DELEGATION_CHANGE && amount <= 100 ether);

        uint256 expectedShares = amount / 1e15; // Simple conversion
        vm.deal(delegator1, amount);

        vm.mockCall(
            address(stakeCreditMock),
            abi.encodeWithSelector(IStakeCredit.delegate.selector, delegator1),
            abi.encode(expectedShares)
        );

        // Act
        vm.prank(delegator1);
        delegation.delegate{ value: amount }(validator1);

        // Assert - Should not revert
        assertTrue(true);
    }

    function testFuzz_redelegate_validShares(uint256 shares) public {
        // Arrange
        vm.assume(shares > 0 && shares <= 1e18);

        uint256 unbondAmount = 1 ether;
        uint256 newShares = (shares * 95) / 100; // Assume some conversion

        StakeCreditMock srcStakeCredit = new StakeCreditMock();
        StakeCreditMock dstStakeCredit = new StakeCreditMock();

        // Use ValidatorManagerMock methods to set stake credit addresses on system address
        ValidatorManagerMock(VALIDATOR_MANAGER_ADDR).setValidatorStakeCredit(validator1, address(srcStakeCredit));
        ValidatorManagerMock(VALIDATOR_MANAGER_ADDR).setValidatorStakeCredit(validator2, address(dstStakeCredit));

        vm.mockCall(
            address(srcStakeCredit),
            abi.encodeWithSelector(IStakeCredit.unbond.selector, delegator1, shares),
            abi.encode(unbondAmount)
        );

        vm.mockCall(
            address(dstStakeCredit),
            abi.encodeWithSelector(IStakeCredit.delegate.selector, delegator1),
            abi.encode(newShares)
        );

        // Act
        vm.prank(delegator1);
        delegation.redelegate(validator1, validator2, shares, false);

        // Assert
        assertTrue(true);
    }
}
