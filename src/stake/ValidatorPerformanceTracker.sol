// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

import "@src/System.sol";
import "@src/interfaces/IEpochManager.sol";
import "@src/interfaces/IValidatorManager.sol";
import "@src/interfaces/IValidatorPerformanceTracker.sol";

contract ValidatorPerformanceTracker is System, IValidatorPerformanceTracker {
    /// Current performance data - store dynamic arrays separately
    IndividualValidatorPerformance[] private currentValidators;

    /// Historical epoch performance records - use mapping for storage
    mapping(uint256 => mapping(uint256 => IndividualValidatorPerformance)) private epochValidatorPerformance;
    mapping(uint256 => uint256) private epochValidatorCount;

    /// Current active validator list (sorted by index)
    address[] public activeValidators;

    /// Validator address to index mapping (for quick lookup)
    mapping(address => uint256) public validatorIndex;

    /// Validator existence flag
    mapping(address => bool) public isActiveValidator;

    /// Initialization flag
    bool private initialized;

    modifier validValidatorIndex(uint256 index) {
        if (index >= currentValidators.length) {
            revert InvalidValidatorIndex(index, currentValidators.length);
        }
        _;
    }

    /// @inheritdoc IValidatorPerformanceTracker
    function initialize(address[] calldata initialValidators) external onlyGenesis {
        if (initialized) revert AlreadyInitialized();

        initialized = true;

        if (initialValidators.length > 0) {
            _initializeValidatorSet(initialValidators);
        }
    }

    /// @inheritdoc IValidatorPerformanceTracker
    function updatePerformanceStatistics(
        uint64 proposerIndex,
        uint64[] calldata failedProposerIndices
    ) external onlyBlock {
        // Get current epoch directly from EpochManager
        uint256 epoch = IEpochManager(EPOCH_MANAGER_ADDR).currentEpoch();

        uint256 validatorCount = currentValidators.length;

        // Handle successful proposer
        if (proposerIndex != type(uint256).max) {
            if (proposerIndex < validatorCount) {
                // Increment successful proposals
                currentValidators[proposerIndex].successfulProposals += 1;

                // Emit events
                emit ProposalResult(activeValidators[proposerIndex], proposerIndex, true, epoch);

                emit PerformanceUpdated(
                    activeValidators[proposerIndex],
                    proposerIndex,
                    currentValidators[proposerIndex].successfulProposals,
                    currentValidators[proposerIndex].failedProposals,
                    epoch
                );
            }
        }

        // Handle failed proposers
        for (uint256 i = 0; i < failedProposerIndices.length; i++) {
            uint256 failedIndex = failedProposerIndices[i];
            if (failedIndex < validatorCount) {
                // Increment failed proposals
                currentValidators[failedIndex].failedProposals += 1;

                // Emit events
                emit ProposalResult(activeValidators[failedIndex], failedIndex, false, epoch);

                emit PerformanceUpdated(
                    activeValidators[failedIndex],
                    failedIndex,
                    currentValidators[failedIndex].successfulProposals,
                    currentValidators[failedIndex].failedProposals,
                    epoch
                );
            }
        }
    }

    /// @inheritdoc IValidatorPerformanceTracker
    function onNewEpoch() external onlyValidatorManager {
        // Verify epoch order
        uint256 currentEpoch = IEpochManager(EPOCH_MANAGER_ADDR).currentEpoch();

        // Save current epoch performance data to historical records
        _finalizeCurrentEpochPerformance(currentEpoch);

        // Get new validator set from ValidatorManager
        _updateActiveValidatorSetFromSystem();

        // Reset all validator performance statistics
        _resetPerformanceStatistics();

        emit PerformanceReset(currentEpoch, activeValidators.length);
    }

    /// @inheritdoc IValidatorPerformanceTracker
    function getCurrentEpochProposalCounts(
        uint256 validatorIdx
    ) external view validValidatorIndex(validatorIdx) returns (uint64 successful, uint64 failed) {
        IndividualValidatorPerformance memory perf = currentValidators[validatorIdx];
        return (perf.successfulProposals, perf.failedProposals);
    }

    /// @inheritdoc IValidatorPerformanceTracker
    function getValidatorPerformance(
        address validator
    ) external view returns (uint64 successful, uint64 failed, uint256 index, bool exists) {
        if (!isActiveValidator[validator]) {
            return (0, 0, 0, false);
        }

        index = validatorIndex[validator];
        IndividualValidatorPerformance memory perf = currentValidators[index];
        return (perf.successfulProposals, perf.failedProposals, index, true);
    }

    /// @inheritdoc IValidatorPerformanceTracker
    function getHistoricalPerformance(
        uint256 epoch,
        uint256 validatorIdx
    ) external view returns (uint64 successful, uint64 failed) {
        uint256 currentEpoch = IEpochManager(EPOCH_MANAGER_ADDR).currentEpoch();
        require(epoch <= currentEpoch, "Future epoch not accessible");

        if (epoch == currentEpoch) {
            if (validatorIdx >= currentValidators.length) {
                revert InvalidValidatorIndex(validatorIdx, currentValidators.length);
            }
            IndividualValidatorPerformance memory perf = currentValidators[validatorIdx];
            return (perf.successfulProposals, perf.failedProposals);
        } else {
            require(validatorIdx < epochValidatorCount[epoch], "Invalid historical validator index");
            IndividualValidatorPerformance memory perf = epochValidatorPerformance[epoch][validatorIdx];
            return (perf.successfulProposals, perf.failedProposals);
        }
    }

    /// @inheritdoc IValidatorPerformanceTracker
    function getCurrentValidators() external view returns (address[] memory) {
        return activeValidators;
    }

    /// @inheritdoc IValidatorPerformanceTracker
    function getCurrentValidatorCount() external view returns (uint256) {
        return activeValidators.length;
    }

    /// @inheritdoc IValidatorPerformanceTracker
    function isValidator(address validator) external view returns (bool) {
        return isActiveValidator[validator];
    }

    /// @inheritdoc IValidatorPerformanceTracker
    function getCurrentPerformanceData()
        external
        view
        returns (address[] memory validators, IndividualValidatorPerformance[] memory performances)
    {
        validators = activeValidators;
        performances = new IndividualValidatorPerformance[](currentValidators.length);

        for (uint256 i = 0; i < currentValidators.length; i++) {
            performances[i] = currentValidators[i];
        }

        return (validators, performances);
    }

    /// @inheritdoc IValidatorPerformanceTracker
    function getValidatorSuccessRate(address validator) external view returns (uint256 successRate) {
        if (!isActiveValidator[validator]) {
            return 0;
        }

        uint256 index = validatorIndex[validator];
        IndividualValidatorPerformance memory perf = currentValidators[index];
        uint64 total = perf.successfulProposals + perf.failedProposals;

        if (total == 0) {
            return 0;
        }

        return (uint256(perf.successfulProposals) * 10000) / uint256(total);
    }

    /// @inheritdoc IValidatorPerformanceTracker
    function getEpochSummary(
        uint256 epoch
    )
        external
        view
        returns (uint256 totalValidators, uint256 totalSuccessful, uint256 totalFailed, uint256 averageSuccessRate)
    {
        if (epoch == type(uint256).max || epoch == IEpochManager(EPOCH_MANAGER_ADDR).currentEpoch()) {
            totalValidators = currentValidators.length;

            for (uint256 i = 0; i < currentValidators.length; i++) {
                totalSuccessful += currentValidators[i].successfulProposals;
                totalFailed += currentValidators[i].failedProposals;
            }
        } else {
            require(epoch < IEpochManager(EPOCH_MANAGER_ADDR).currentEpoch(), "Future epoch not accessible");
            totalValidators = epochValidatorCount[epoch];

            for (uint256 i = 0; i < totalValidators; i++) {
                IndividualValidatorPerformance memory perf = epochValidatorPerformance[epoch][i];
                totalSuccessful += perf.successfulProposals;
                totalFailed += perf.failedProposals;
            }
        }

        uint256 grandTotal = totalSuccessful + totalFailed;
        if (grandTotal > 0) {
            averageSuccessRate = (totalSuccessful * 10000) / grandTotal;
        } else {
            averageSuccessRate = 0;
        }

        return (totalValidators, totalSuccessful, totalFailed, averageSuccessRate);
    }

    /**
     * @dev Initialize validator set
     * @param validators Initial validator addresses
     */
    function _initializeValidatorSet(address[] calldata validators) internal {
        if (validators.length == 0) revert EmptyActiveValidatorSet();

        // Check for duplicate validators
        for (uint256 i = 0; i < validators.length; i++) {
            for (uint256 j = i + 1; j < validators.length; j++) {
                if (validators[i] == validators[j]) {
                    revert DuplicateValidator(validators[i]);
                }
            }
        }

        _updateActiveValidatorSet(validators, 0);
    }

    /**
     * @dev Save current epoch performance data to historical records
     * @param epoch Current epoch number
     */
    function _finalizeCurrentEpochPerformance(uint256 epoch) internal {
        if (currentValidators.length > 0) {
            uint256 totalSuccessful = 0;
            uint256 totalFailed = 0;

            // Save to historical mapping
            epochValidatorCount[epoch] = currentValidators.length;
            for (uint256 i = 0; i < currentValidators.length; i++) {
                epochValidatorPerformance[epoch][i] = currentValidators[i];
                totalSuccessful += currentValidators[i].successfulProposals;
                totalFailed += currentValidators[i].failedProposals;
            }

            emit EpochPerformanceFinalized(epoch, currentValidators.length, totalSuccessful, totalFailed);
        }
    }

    /**
     * @dev Reset current epoch performance statistics
     */
    function _resetPerformanceStatistics() internal {
        for (uint256 i = 0; i < currentValidators.length; i++) {
            currentValidators[i].successfulProposals = 0;
            currentValidators[i].failedProposals = 0;
        }
    }

    /**
     * @dev Get validator set from ValidatorManager
     */
    function _updateActiveValidatorSetFromSystem() internal {
        address[] memory validators = IValidatorManager(VALIDATOR_MANAGER_ADDR).getActiveValidators();
        if (validators.length > 0) {
            _updateActiveValidatorSet(validators, IEpochManager(EPOCH_MANAGER_ADDR).currentEpoch());
        }
    }

    /**
     * @dev Update active validator set and performance data structure
     * @param validators New validator addresses
     * @param epoch Current epoch number
     */
    function _updateActiveValidatorSet(address[] memory validators, uint256 epoch) internal {
        if (validators.length == 0) revert EmptyActiveValidatorSet();

        // Clear old validator mappings
        for (uint256 i = 0; i < activeValidators.length; i++) {
            isActiveValidator[activeValidators[i]] = false;
            delete validatorIndex[activeValidators[i]];
        }

        // Clear arrays
        delete activeValidators;
        delete currentValidators;

        // Set new validator set
        for (uint256 i = 0; i < validators.length; i++) {
            // Check address validity
            require(validators[i] != address(0), "Invalid validator address");

            // Check for duplicates
            require(!isActiveValidator[validators[i]], "Duplicate validator");

            activeValidators.push(validators[i]);
            validatorIndex[validators[i]] = i;
            isActiveValidator[validators[i]] = true;

            // Initialize performance data
            currentValidators.push(IndividualValidatorPerformance({ successfulProposals: 0, failedProposals: 0 }));
        }

        emit ActiveValidatorSetUpdated(epoch, validators);
    }
}
