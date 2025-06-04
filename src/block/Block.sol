// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

import "@src/System.sol";
import "@src/interfaces/IValidatorPerformanceTracker.sol";
import "@src/interfaces/IValidatorManager.sol";
import "@src/interfaces/IEpochManager.sol";
import "@src/interfaces/ITimestamp.sol";
import "@src/interfaces/IBlock.sol";
import "@openzeppelin-upgrades/proxy/utils/Initializable.sol";

contract Block is System, IBlock, Initializable {
    /// @inheritdoc IBlock
    function initialize() external initializer onlyGenesis {
        _emitGenesisBlockEvent();
    }

    /// @inheritdoc IBlock
    function blockPrologue(
        address proposer,
        uint64[] calldata failedProposerIndices,
        uint256 timestampMicros
    ) external onlySystemCaller {
        // 1. Validate proposer
        if (proposer != SYSTEM_CALLER && !IValidatorManager(VALIDATOR_MANAGER_ADDR).isCurrentEpochValidator(proposer)) {
            revert InvalidProposer(proposer);
        }

        // 2. Calculate proposer index
        uint64 proposerIndex;
        bool hasProposerIndex = false;

        if (proposer != SYSTEM_CALLER) {
            // Get proposer index from ValidatorManager
            proposerIndex = IValidatorManager(VALIDATOR_MANAGER_ADDR).getValidatorIndex(proposer);
            hasProposerIndex = true;
        }
        // If proposer == SYSTEM_CALLER, hasProposerIndex remains false

        // 3. Update global timestamp
        ITimestamp(TIMESTAMP_ADDR).updateGlobalTime(proposer, uint64(timestampMicros));

        // 4. Update validator performance statistics
        if (hasProposerIndex) {
            IValidatorPerformanceTracker(VALIDATOR_PERFORMANCE_TRACKER_ADDR).updatePerformanceStatistics(
                proposerIndex, failedProposerIndices
            );
        } else {
            // For VM reserved address, pass invalid index marker
            IValidatorPerformanceTracker(VALIDATOR_PERFORMANCE_TRACKER_ADDR).updatePerformanceStatistics(
                type(uint64).max, failedProposerIndices
            );
        }

        // 5. Check if epoch transition is needed
        if (IEpochManager(EPOCH_MANAGER_ADDR).canTriggerEpochTransition()) {
            IEpochManager(EPOCH_MANAGER_ADDR).triggerEpochTransition();
        }
    }

    /**
     * @dev Emit genesis block event. This function will be called directly during genesis
     * to generate the first reconfiguration event.
     */
    function _emitGenesisBlockEvent() private {
        address genesisId = address(0);
        uint64[] memory emptyFailedProposerIndices = new uint64[](0);

        emit NewBlockEvent(
            genesisId, // hash: genesis_id
            0, // epoch: 0
            0, // round: 0
            0, // height: 0
            bytes(""), // previous_block_votes_bitvec: empty
            SYSTEM_CALLER, // proposer: @vm_reserved
            emptyFailedProposerIndices, // failed_proposer_indices: empty
            0 // time_microseconds: 0
        );

        // Initialize global timestamp to 0
        ITimestamp(TIMESTAMP_ADDR).updateGlobalTime(SYSTEM_CALLER, 0);
    }
}
