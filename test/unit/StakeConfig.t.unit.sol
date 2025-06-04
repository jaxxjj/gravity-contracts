// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "forge-std/Test.sol";
import "@src/stake/StakeConfig.sol";
import "@src/System.sol";
import "@test/utils/TestConstants.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract StakeConfigTest is Test, TestConstants {
    StakeConfig public stakeConfig;
    StakeConfig public implementation;

    // Test users
    address public user1 = makeAddr("user1");
    address public user2 = makeAddr("user2");

    function setUp() public {
        // Deploy implementation
        implementation = new StakeConfig();

        // Deploy proxy
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), "");
        stakeConfig = StakeConfig(address(proxy));

        // Initialize from genesis
        vm.prank(GENESIS_ADDR);
        stakeConfig.initialize();
    }

    // ============ INITIALIZATION TESTS ============

    function test_initialize_shouldSetCorrectDefaults() public view {
        // Assert staking parameters
        assertEq(stakeConfig.minValidatorStake(), 1000 ether);
        assertEq(stakeConfig.maximumStake(), 1000000 ether);
        assertEq(stakeConfig.minDelegationStake(), 0.1 ether);
        assertEq(stakeConfig.minDelegationChange(), 0.1 ether);
        assertEq(stakeConfig.maxValidatorCount(), 100);
        assertEq(stakeConfig.recurringLockupDuration(), 14 days);
        assertTrue(stakeConfig.allowValidatorSetChange());
        assertEq(stakeConfig.redelegateFeeRate(), 2);

        // Assert reward parameters
        assertEq(stakeConfig.rewardsRate(), 100);
        assertEq(stakeConfig.rewardsRateDenominator(), 10000);

        // Assert voting power limit
        assertEq(stakeConfig.votingPowerIncreaseLimit(), 2000);

        // Assert commission parameters
        assertEq(stakeConfig.maxCommissionRate(), 5000);
        assertEq(stakeConfig.maxCommissionChangeRate(), 500);

        // Assert lock amount
        assertEq(stakeConfig.lockAmount(), 10000 ether);
    }

    function test_initialize_cannotBeCalledTwice() public {
        // Act & Assert
        vm.prank(GENESIS_ADDR);
        vm.expectRevert();
        stakeConfig.initialize();
    }

    function test_initialize_onlyGenesis() public {
        // Arrange
        StakeConfig newStakeConfig = new StakeConfig();

        // Act & Assert
        vm.prank(user1);
        vm.expectRevert();
        newStakeConfig.initialize();
    }

    // ============ UPDATE PARAM TESTS ============

    function test_updateParam_minValidatorStake_shouldWork() public {
        // Arrange
        uint256 newValue = 2000 ether;
        bytes memory encodedValue = abi.encode(newValue);

        // Act
        vm.prank(GOV_HUB_ADDR);
        stakeConfig.updateParam("minValidatorStake", encodedValue);

        // Assert
        assertEq(stakeConfig.minValidatorStake(), newValue);
    }

    function test_updateParam_minValidatorStake_shouldRevertIfZero() public {
        // Arrange
        uint256 newValue = 0;
        bytes memory encodedValue = abi.encode(newValue);

        // Act & Assert
        vm.prank(GOV_HUB_ADDR);
        vm.expectRevert(IStakeConfig.StakeConfig__StakeLimitsMustBePositive.selector);
        stakeConfig.updateParam("minValidatorStake", encodedValue);
    }

    function test_updateParam_minValidatorStake_shouldRevertIfExceedsMaximum() public {
        // Arrange
        uint256 newValue = 2000000 ether; // Exceeds maximumStake (1M)
        bytes memory encodedValue = abi.encode(newValue);

        // Act & Assert
        vm.startPrank(GOV_HUB_ADDR);
        vm.expectRevert(
            abi.encodeWithSelector(
                IStakeConfig.StakeConfig__InvalidStakeRange.selector, newValue, stakeConfig.maximumStake()
            )
        );
        stakeConfig.updateParam("minValidatorStake", encodedValue);
        vm.stopPrank();
    }

    function test_updateParam_maximumStake_shouldWork() public {
        // Arrange
        uint256 newValue = 2000000 ether;
        bytes memory encodedValue = abi.encode(newValue);

        // Act
        vm.prank(GOV_HUB_ADDR);
        stakeConfig.updateParam("maximumStake", encodedValue);

        // Assert
        assertEq(stakeConfig.maximumStake(), newValue);
    }

    function test_updateParam_maximumStake_shouldRevertIfBelowMinimum() public {
        // Arrange
        uint256 newValue = 500 ether; // Below minValidatorStake (1000)
        bytes memory encodedValue = abi.encode(newValue);

        // Act & Assert
        vm.startPrank(GOV_HUB_ADDR);
        vm.expectRevert(
            abi.encodeWithSelector(
                IStakeConfig.StakeConfig__InvalidStakeRange.selector, stakeConfig.minValidatorStake(), newValue
            )
        );
        stakeConfig.updateParam("maximumStake", encodedValue);
        vm.stopPrank();
    }

    function test_updateParam_minDelegationStake_shouldWork() public {
        // Arrange
        uint256 newValue = 1 ether;
        bytes memory encodedValue = abi.encode(newValue);

        // Act
        vm.prank(GOV_HUB_ADDR);
        stakeConfig.updateParam("minDelegationStake", encodedValue);

        // Assert
        assertEq(stakeConfig.minDelegationStake(), newValue);
    }

    function test_updateParam_allowValidatorSetChange_shouldWork() public {
        // Arrange
        bool newValue = false;
        bytes memory encodedValue = abi.encode(newValue);

        // Act
        vm.prank(GOV_HUB_ADDR);
        stakeConfig.updateParam("allowValidatorSetChange", encodedValue);

        // Assert
        assertEq(stakeConfig.allowValidatorSetChange(), newValue);
    }

    function test_updateParam_rewardsRate_shouldWork() public {
        // Arrange
        uint256 newValue = 200; // 2%
        bytes memory encodedValue = abi.encode(newValue);

        // Act
        vm.prank(GOV_HUB_ADDR);
        stakeConfig.updateParam("rewardsRate", encodedValue);

        // Assert
        assertEq(stakeConfig.rewardsRate(), newValue);
    }

    function test_updateParam_rewardsRate_shouldRevertIfExceedsDenominator() public {
        // Arrange
        uint256 newValue = 20000; // Exceeds denominator (10000)
        bytes memory encodedValue = abi.encode(newValue);

        // Act & Assert
        vm.startPrank(GOV_HUB_ADDR);
        vm.expectRevert(
            abi.encodeWithSelector(
                IStakeConfig.StakeConfig__RewardsRateCannotExceedLimit.selector,
                newValue,
                stakeConfig.rewardsRateDenominator()
            )
        );
        stakeConfig.updateParam("rewardsRate", encodedValue);
        vm.stopPrank();
    }

    function test_updateParam_votingPowerIncreaseLimit_shouldWork() public {
        // Arrange
        uint256 newValue = 3000; // 30%
        bytes memory encodedValue = abi.encode(newValue);

        // Act
        vm.prank(GOV_HUB_ADDR);
        stakeConfig.updateParam("votingPowerIncreaseLimit", encodedValue);

        // Assert
        assertEq(stakeConfig.votingPowerIncreaseLimit(), newValue);
    }

    function test_updateParam_votingPowerIncreaseLimit_shouldRevertIfInvalid() public {
        // Arrange - Exceeds 50%
        uint256 newValue = 6000;
        bytes memory encodedValue = abi.encode(newValue);

        // Act & Assert
        vm.prank(GOV_HUB_ADDR);
        vm.expectRevert(
            abi.encodeWithSelector(
                IStakeConfig.StakeConfig__InvalidVotingPowerIncreaseLimit.selector,
                newValue,
                5000 // PERCENTAGE_BASE / 2
            )
        );
        stakeConfig.updateParam("votingPowerIncreaseLimit", encodedValue);
    }

    function test_updateParam_lockAmount_shouldWork() public {
        // Arrange
        uint256 newValue = 20000 ether;
        bytes memory encodedValue = abi.encode(newValue);

        // Act
        vm.prank(GOV_HUB_ADDR);
        stakeConfig.updateParam("lockAmount", encodedValue);

        // Assert
        assertEq(stakeConfig.lockAmount(), newValue);
    }

    function test_updateParam_lockAmount_shouldRevertIfZero() public {
        // Arrange
        uint256 newValue = 0;
        bytes memory encodedValue = abi.encode(newValue);

        // Act & Assert
        vm.prank(GOV_HUB_ADDR);
        vm.expectRevert(abi.encodeWithSelector(IStakeConfig.StakeConfig__InvalidLockAmount.selector, newValue));
        stakeConfig.updateParam("lockAmount", encodedValue);
    }

    function test_updateParam_unknownParam_shouldRevert() public {
        // Arrange
        bytes memory encodedValue = abi.encode(uint256(100));

        // Act & Assert
        vm.prank(GOV_HUB_ADDR);
        vm.expectRevert(abi.encodeWithSelector(IStakeConfig.StakeConfig__ParameterNotFound.selector, "unknownParam"));
        stakeConfig.updateParam("unknownParam", encodedValue);
    }

    function test_updateParam_onlyGov() public {
        // Arrange
        bytes memory encodedValue = abi.encode(uint256(2000 ether));

        // Act & Assert
        vm.prank(user1);
        vm.expectRevert();
        stakeConfig.updateParam("minValidatorStake", encodedValue);
    }

    // ============ VIEW FUNCTION TESTS ============

    function test_getRequiredStake_shouldReturnCorrectValues() public view {
        // Act
        (uint256 minimum, uint256 maximum) = stakeConfig.getRequiredStake();

        // Assert
        assertEq(minimum, 1000 ether);
        assertEq(maximum, 1000000 ether);
    }

    function test_getRewardRate_shouldReturnCorrectValues() public view {
        // Act
        (uint256 rate, uint256 denominator) = stakeConfig.getRewardRate();

        // Assert
        assertEq(rate, 100);
        assertEq(denominator, 10000);
    }

    function test_getAllConfigParams_shouldReturnAllValues() public view {
        // Act
        IStakeConfig.ConfigParams memory params = stakeConfig.getAllConfigParams();

        // Assert
        assertEq(params.minValidatorStake, 1000 ether);
        assertEq(params.maximumStake, 1000000 ether);
        assertEq(params.minDelegationStake, 0.1 ether);
        assertEq(params.minDelegationChange, 0.1 ether);
        assertEq(params.maxValidatorCount, 100);
        assertEq(params.recurringLockupDuration, 14 days);
        assertTrue(params.allowValidatorSetChange);
        assertEq(params.rewardsRate, 100);
        assertEq(params.rewardsRateDenominator, 10000);
        assertEq(params.votingPowerIncreaseLimit, 2000);
        assertEq(params.maxCommissionRate, 5000);
        assertEq(params.maxCommissionChangeRate, 500);
        assertEq(params.redelegateFeeRate, 2);
        assertEq(params.lockAmount, 10000 ether);
    }

    function test_isValidStakeAmount_shouldReturnCorrectResults() public view {
        // Assert valid amounts
        assertTrue(stakeConfig.isValidStakeAmount(1000 ether)); // Min
        assertTrue(stakeConfig.isValidStakeAmount(500000 ether)); // Middle
        assertTrue(stakeConfig.isValidStakeAmount(1000000 ether)); // Max

        // Assert invalid amounts
        assertFalse(stakeConfig.isValidStakeAmount(999 ether)); // Below min
        assertFalse(stakeConfig.isValidStakeAmount(1000001 ether)); // Above max
    }

    function test_isValidDelegationAmount_shouldReturnCorrectResults() public view {
        // Assert valid amounts
        assertTrue(stakeConfig.isValidDelegationAmount(0.1 ether)); // Min
        assertTrue(stakeConfig.isValidDelegationAmount(1 ether)); // Above min

        // Assert invalid amounts
        assertFalse(stakeConfig.isValidDelegationAmount(0.05 ether)); // Below min
    }

    function test_isValidCommissionRate_shouldReturnCorrectResults() public view {
        // Assert valid rates
        assertTrue(stakeConfig.isValidCommissionRate(0)); // 0%
        assertTrue(stakeConfig.isValidCommissionRate(2500)); // 25%
        assertTrue(stakeConfig.isValidCommissionRate(5000)); // 50% (max)

        // Assert invalid rates
        assertFalse(stakeConfig.isValidCommissionRate(5001)); // Above max
        assertFalse(stakeConfig.isValidCommissionRate(10000)); // 100%
    }

    function test_isValidCommissionChange_shouldReturnCorrectResults() public view {
        // Assert valid changes (within 5% limit)
        assertTrue(stakeConfig.isValidCommissionChange(1000, 1500)); // 5% increase
        assertTrue(stakeConfig.isValidCommissionChange(1500, 1000)); // 5% decrease
        assertTrue(stakeConfig.isValidCommissionChange(2000, 2000)); // No change

        // Assert invalid changes (exceed 5% limit)
        assertFalse(stakeConfig.isValidCommissionChange(1000, 1600)); // 6% increase
        assertFalse(stakeConfig.isValidCommissionChange(1600, 1000)); // 6% decrease
    }

    // ============ CONSTANTS TESTS ============

    function test_constants_shouldHaveCorrectValues() public view {
        assertEq(stakeConfig.PERCENTAGE_BASE(), 10000);
        assertEq(stakeConfig.MAX_REWARDS_RATE(), 1000000);
        assertEq(stakeConfig.MAX_U64(), type(uint64).max);
        assertEq(stakeConfig.MAX_COMMISSION_RATE(), 5000);
    }

    // ============ EDGE CASE TESTS ============

    function test_updateParam_recurringLockupDuration_shouldRevertIfZero() public {
        // Arrange
        uint256 newValue = 0;
        bytes memory encodedValue = abi.encode(newValue);

        // Act & Assert
        vm.prank(GOV_HUB_ADDR);
        vm.expectRevert(IStakeConfig.StakeConfig__RecurringLockupDurationMustBePositive.selector);
        stakeConfig.updateParam("recurringLockupDuration", encodedValue);
    }

    function test_updateParam_rewardsRateDenominator_shouldRevertIfZero() public {
        // Arrange
        uint256 newValue = 0;
        bytes memory encodedValue = abi.encode(newValue);

        // Act & Assert
        vm.prank(GOV_HUB_ADDR);
        vm.expectRevert(IStakeConfig.StakeConfig__DenominatorMustBePositive.selector);
        stakeConfig.updateParam("rewardsRateDenominator", encodedValue);
    }

    function test_updateParam_maxCommissionRate_shouldRevertIfExceedsBase() public {
        // Arrange
        uint256 newValue = 20000; // Exceeds PERCENTAGE_BASE (10000)
        bytes memory encodedValue = abi.encode(newValue);

        // Act & Assert
        vm.prank(GOV_HUB_ADDR);
        vm.expectRevert(
            abi.encodeWithSelector(IStakeConfig.StakeConfig__InvalidCommissionRate.selector, newValue, 10000)
        );
        stakeConfig.updateParam("maxCommissionRate", encodedValue);
    }

    // ============ FUZZ TESTS ============

    function testFuzz_updateParam_minValidatorStake_validRange(
        uint256 newValue
    ) public {
        // Arrange
        vm.assume(newValue > 0 && newValue <= stakeConfig.maximumStake());
        bytes memory encodedValue = abi.encode(newValue);

        // Act
        vm.prank(GOV_HUB_ADDR);
        stakeConfig.updateParam("minValidatorStake", encodedValue);

        // Assert
        assertEq(stakeConfig.minValidatorStake(), newValue);
    }

    function testFuzz_isValidStakeAmount_edgeCases(
        uint256 amount
    ) public view {
        // Act
        bool isValid = stakeConfig.isValidStakeAmount(amount);

        // Assert
        if (amount >= stakeConfig.minValidatorStake() && amount <= stakeConfig.maximumStake()) {
            assertTrue(isValid);
        } else {
            assertFalse(isValid);
        }
    }

    function testFuzz_isValidCommissionChange_withinLimit(uint256 oldRate, uint256 newRate) public view {
        // Arrange
        vm.assume(oldRate <= 10000 && newRate <= 10000);
        uint256 change = oldRate > newRate ? oldRate - newRate : newRate - oldRate;

        // Act
        bool isValid = stakeConfig.isValidCommissionChange(oldRate, newRate);

        // Assert
        if (change <= stakeConfig.maxCommissionChangeRate()) {
            assertTrue(isValid);
        } else {
            assertFalse(isValid);
        }
    }
}
