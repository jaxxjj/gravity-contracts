// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

/**
 * @title IValidatorPerformanceTracker
 * @dev Interface for tracking validator proposal performance
 */
interface IValidatorPerformanceTracker {
    /// Individual validator performance data
    struct IndividualValidatorPerformance {
        uint64 successfulProposals; // Number of successful proposals
        uint64 failedProposals; // Number of failed proposals
    }

    /// Performance update event
    event PerformanceUpdated(
        address indexed validator,
        uint256 indexed validatorIndex,
        uint64 successfulProposals,
        uint64 failedProposals,
        uint256 epoch
    );

    /// Single proposal result event
    event ProposalResult(address indexed validator, uint256 indexed validatorIndex, bool success, uint256 epoch);

    /// Epoch performance data finalization event
    event EpochPerformanceFinalized(
        uint256 indexed epoch,
        uint256 totalValidators,
        uint256 totalSuccessfulProposals,
        uint256 totalFailedProposals
    );

    /// Active validator set update event
    event ActiveValidatorSetUpdated(uint256 indexed epoch, address[] validators);

    /// Validator performance reset event
    event PerformanceReset(uint256 indexed newEpoch, uint256 validatorCount);

    error AlreadyInitialized();
    error InvalidValidatorIndex(uint256 index, uint256 maxIndex);
    error EmptyActiveValidatorSet();
    error DuplicateValidator(address validator);

    /**
     * @dev Initialize the contract with initial validators
     * @param initialValidators List of initial validator addresses
     */
    function initialize(address[] calldata initialValidators) external;

    /**
     * @dev Update validator performance statistics
     * @param proposerIndex Current proposer index (use type(uint256).max for None)
     * @param failedProposerIndices Array of failed proposer indices
     */
    function updatePerformanceStatistics(uint64 proposerIndex, uint64[] calldata failedProposerIndices) external;

    /**
     * @dev Handle new epoch transition, reset performance statistics
     */
    function onNewEpoch() external;

    /**
     * @dev Get current epoch proposal statistics
     * @param validatorIndex Validator index
     * @return successful Number of successful proposals
     * @return failed Number of failed proposals
     */
    function getCurrentEpochProposalCounts(
        uint256 validatorIndex
    ) external view returns (uint64 successful, uint64 failed);

    /**
     * @dev Get validator performance by address
     * @param validator Validator address
     * @return successful Number of successful proposals
     * @return failed Number of failed proposals
     * @return index Validator index
     * @return exists Whether validator exists
     */
    function getValidatorPerformance(
        address validator
    ) external view returns (uint64 successful, uint64 failed, uint256 index, bool exists);

    /**
     * @dev Get historical epoch performance data
     * @param epoch Epoch number
     * @param validatorIndex Validator index
     * @return successful Number of successful proposals
     * @return failed Number of failed proposals
     */
    function getHistoricalPerformance(
        uint256 epoch,
        uint256 validatorIndex
    ) external view returns (uint64 successful, uint64 failed);

    /**
     * @dev Get all current validator addresses
     * @return Array of validator addresses
     */
    function getCurrentValidators() external view returns (address[] memory);

    /**
     * @dev Get current validator count
     * @return Number of validators
     */
    function getCurrentValidatorCount() external view returns (uint256);

    /**
     * @dev Check if address is an active validator
     * @param validator Validator address
     * @return Whether the address is an active validator
     */
    function isValidator(address validator) external view returns (bool);

    /**
     * @dev Get complete performance data for current validators
     * @return validators Array of validator addresses
     * @return performances Array of corresponding performance data
     */
    function getCurrentPerformanceData()
        external
        view
        returns (address[] memory validators, IndividualValidatorPerformance[] memory performances);

    /**
     * @dev Calculate validator success rate
     * @param validator Validator address
     * @return successRate Success rate in basis points (10000 = 100%)
     */
    function getValidatorSuccessRate(address validator) external view returns (uint256 successRate);

    /**
     * @dev Get epoch summary statistics
     * @param epoch Epoch number (use type(uint256).max for current epoch)
     * @return totalValidators Total number of validators
     * @return totalSuccessful Total successful proposals
     * @return totalFailed Total failed proposals
     * @return averageSuccessRate Average success rate in basis points
     */
    function getEpochSummary(
        uint256 epoch
    )
        external
        view
        returns (uint256 totalValidators, uint256 totalSuccessful, uint256 totalFailed, uint256 averageSuccessRate);

    /**
     * @dev Get active validator address by index
     * @param index Validator index
     * @return Validator address
     */
    function activeValidators(uint256 index) external view returns (address);

    /**
     * @dev Get validator index by address
     * @param validator Validator address
     * @return Validator index
     */
    function validatorIndex(address validator) external view returns (uint256);

    /**
     * @dev Check if address is an active validator
     * @param validator Validator address
     * @return Whether the address is an active validator
     */
    function isActiveValidator(address validator) external view returns (bool);
}
