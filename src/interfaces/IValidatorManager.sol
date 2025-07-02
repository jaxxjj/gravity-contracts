// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "@src/interfaces/IReconfigurableModule.sol";

/**
 * @title IValidatorManager
 * @dev Interface for ValidatorManager
 */
interface IValidatorManager is IReconfigurableModule {
    // Validator status enum
    enum ValidatorStatus {
        PENDING_ACTIVE, // 0
        ACTIVE, // 1
        PENDING_INACTIVE, // 2
        INACTIVE // 3

    }

    // Commission structure
    struct Commission {
        uint64 rate; // the commission rate charged to delegators(10000 is 100%)
        uint64 maxRate; // maximum commission rate which validator can ever charge
        uint64 maxChangeRate; // maximum daily increase of the validator commission
    }

    /// Complete validator information (merged from multiple contracts)
    struct ValidatorInfo {
        // Basic information (from ValidatorManager)
        bytes consensusPublicKey;
        address payable feeAddress; // Fee receiving address
        bytes voteAddress; // BLS voting address
        Commission commission;
        string moniker;
        uint256 createdTime;
        bool registered;
        address stakeCreditAddress;
        ValidatorStatus status;
        uint256 votingPower; // Changed from uint64 to uint256 to prevent overflow
        uint256 validatorIndex;
        uint256 lastEpochActive;
        uint256 updateTime; // Last update time
        address operator;
    }

    // ValidatorSetData structure
    struct ValidatorSetData {
        uint256 totalVotingPower; // Total voting power - Changed from uint128 to uint256
        uint256 totalJoiningPower; // Total pending voting power - Changed from uint128 to uint256
    }

    // Validator registration parameters
    struct ValidatorRegistrationParams {
        bytes consensusPublicKey;
        address payable feeAddress; // Fee receiving address
        bytes voteAddress; // BLS voting address
        bytes blsProof; // BLS proof
        Commission commission; // Changed from uint64 commissionRate to Commission struct
        string moniker;
        address initialOperator;
        address initialVoter;
        address initialBeneficiary; // Passed directly to StakeCredit
    }

    /// Validator registration events
    event ValidatorRegistered(
        address indexed validator, address indexed operator, bytes consensusPublicKey, string moniker
    );

    event StakeCreditDeployed(address indexed validator, address stakeCreditAddress);
    event ValidatorInfoUpdated(address indexed validator, string field);
    event RewardsCollected(uint256 amount, uint256 totalIncoming);
    event CommissionRateEdited(address indexed operatorAddress, uint64 newCommissionRate);

    // Role management events
    event OperatorUpdated(address indexed validator, address indexed oldOperator, address indexed newOperator);

    /// Validator set management events (inspired by Aptos)
    event ValidatorJoinRequested(address indexed validator, uint256 votingPower, uint64 epoch);
    event ValidatorLeaveRequested(address indexed validator, uint64 epoch);
    event ValidatorStatusChanged(address indexed validator, uint8 oldStatus, uint8 newStatus, uint64 epoch);

    // StakeReward events
    event RewardsDistributed(address indexed validator, uint256 amount);
    event RewardDistributeFailed(address indexed validator, string reason);

    /// Epoch transition events
    event ValidatorSetUpdated(
        uint64 indexed epoch,
        uint256 activeCount,
        uint256 pendingActiveCount,
        uint256 pendingInactiveCount,
        uint256 totalVotingPower
    );

    // Registration related errors
    error ValidatorAlreadyExists(address validator);
    error ValidatorNotExists(address validator);
    error InvalidCommissionRate(uint64 rate, uint64 maxRate);
    error InvalidStakeAmount(uint256 provided, uint256 required);
    error StakeExceedsMaximum(uint256 provided, uint256 maximum);
    error UnauthorizedCaller(address caller, address validator);
    error InvalidCommission(); // Invalid commission settings
    error UpdateTooFrequently(); // Update too frequent error
    error InvalidAddress(address addr);
    error AddressAlreadyInUse(address addr, address currentValidator);
    error NotValidator(address caller, address validator);
    error ArrayLengthMismatch(); // Error for array length mismatch

    // BLS verification related errors
    error InvalidVoteAddress();
    error DuplicateVoteAddress(bytes voteAddress);
    error DuplicateConsensusAddress(bytes consensusAddress);
    error InvalidMoniker(string moniker);
    error DuplicateMoniker(string moniker);

    // Set management related errors (inspired by Aptos)
    error AlreadyInitialized();
    error ValidatorNotInactive(address validator);
    error ValidatorNotActive(address validator);
    error ValidatorSetReachedMax(uint256 current, uint256 max);
    error InvalidVotingPower(uint256 votingPower);
    error LastValidatorCannotLeave();
    error VotingPowerIncreaseExceedsLimit();
    error ValidatorSetChangeDisabled();
    error NewOperatorIsValidatorSelf();

    /**
     * @dev Initialize validator set
     */
    function initialize(
        address[] calldata validatorAddresses,
        address[] calldata consensusAddresses,
        address payable[] calldata feeAddresses,
        uint256[] calldata votingPowers,
        bytes[] calldata voteAddresses
    ) external;

    // ======== Validator Registration ========

    /**
     * @dev Register new validator
     */
    function registerValidator(
        ValidatorRegistrationParams calldata params
    ) external payable;

    /**
     * @dev Join validator set
     */
    function joinValidatorSet(
        address validator
    ) external;

    /**
     * @dev Leave validator set
     */
    function leaveValidatorSet(
        address validator
    ) external;

    /**
     * @dev Process new epoch event
     */
    function onNewEpoch() external;

    /**
     * @dev Check if validator meets minimum stake requirement
     */
    function checkValidatorMinStake(
        address validator
    ) external;

    // ======== Validator Information Updates ========

    /**
     * @dev Update consensus public key
     */
    function updateConsensusKey(address validator, bytes calldata newConsensusKey) external;

    /**
     * @dev Update commission rate
     * @param validator Validator address
     * @param newCommissionRate New commission rate
     */
    function updateCommissionRate(address validator, uint64 newCommissionRate) external;

    /**
     * @dev Update BLS voting address
     * @param validator Validator address
     * @param newVoteAddress New voting address
     * @param blsProof BLS proof
     */
    function updateVoteAddress(address validator, bytes calldata newVoteAddress, bytes calldata blsProof) external;

    // ======== Role Query Functions ========

    /**
     * @dev Check if account is validator itself
     */
    function isValidator(address validator, address account) external view returns (bool);

    /**
     * @dev Check if account is validator operator
     * @param validator The validator address
     * @param account The account to check
     * @return Whether the account is validator operator
     */
    function isOperator(address validator, address account) external view returns (bool);

    /**
     * @dev Check if account has operator permission for validator
     * @param validator The validator address
     * @param account The account to check
     * @return Whether the account has operator permission
     */
    function hasOperatorPermission(address validator, address account) external view returns (bool);

    /**
     * @dev Get validator information
     */
    function getValidatorInfo(
        address validator
    ) external view returns (ValidatorInfo memory);

    /**
     * @dev Get active validator list
     */
    function getActiveValidators() external view returns (address[] memory validators);

    /**
     * @dev Get pending validator list
     */
    function getPendingValidators() external view returns (address[] memory);

    /**
     * @dev Check if validator is current active validator
     */
    function isCurrentEpochValidator(
        address validator
    ) external view returns (bool);

    /**
     * @dev Check if validator is current active validator (alias for isCurrentEpochValidator)
     */
    function isCurrentValidator(
        address validator
    ) external view returns (bool);

    /**
     * @dev Get total voting power
     */
    function getTotalVotingPower() external view returns (uint256);

    /**
     * @dev Get validator set data
     */
    function getValidatorSetData() external view returns (ValidatorSetData memory);

    /**
     * @dev Get validator's StakeCredit address
     */
    function getValidatorStakeCredit(
        address validator
    ) external view returns (address);

    /**
     * @dev Check voting power increase limit
     */
    function checkVotingPowerIncrease(
        uint256 increaseAmount
    ) external view;

    /**
     * @dev Check if validator is registered
     */
    function isValidatorRegistered(
        address validator
    ) external view returns (bool);

    /**
     * @dev Check if validator exists
     */
    function isValidatorExists(
        address validator
    ) external view returns (bool);

    /**
     * @dev Get validator status
     */
    function getValidatorStatus(
        address validator
    ) external view returns (ValidatorStatus);

    /**
     * @dev Get validator's voting address
     */
    function getValidatorVoteAddress(
        address validator
    ) external view returns (bytes memory);

    /**
     * @dev Get validator index in current active validator set
     * @param validator Validator address
     * @return Validator index, may return 0 or revert if not active
     */
    function getValidatorIndex(
        address validator
    ) external view returns (uint64);

    /**
     * @dev Block producer deposits block rewards
     */
    function deposit() external payable;

    /**
     * @dev Update validator's operator address
     * @param validator Validator address
     * @param newOperator New operator address
     */
    function updateOperator(address validator, address newOperator) external;

    /**
     * @dev Get validator's operator address
     * @param validator The validator address
     * @return The operator address
     */
    function getOperator(
        address validator
    ) external view returns (address);
}
