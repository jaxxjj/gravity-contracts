// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

import "@openzeppelin-upgrades/governance/extensions/GovernorSettingsUpgradeable.sol";
import "@openzeppelin-upgrades/governance/GovernorUpgradeable.sol";
import "@openzeppelin-upgrades/governance/extensions/GovernorVotesUpgradeable.sol";
import "@openzeppelin-upgrades/governance/extensions/GovernorTimelockControlUpgradeable.sol";
import "@openzeppelin-upgrades/governance/extensions/GovernorVotesQuorumFractionUpgradeable.sol";
import "@openzeppelin-upgrades/governance/extensions/GovernorPreventLateQuorumUpgradeable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

import "@src/System.sol";
import "@src/access/Protectable.sol";
import "@src/lib/Bytes.sol";
import "@src/interfaces/IGovToken.sol";
import "@src/lib/Bytes.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { IVotes } from "@openzeppelin/contracts/governance/utils/IVotes.sol";
import "@src/interfaces/IEpochManager.sol";

contract GravityGovernor is
    System,
    Initializable,
    Protectable,
    GovernorUpgradeable,
    GovernorSettingsUpgradeable,
    GovernorVotesUpgradeable,
    GovernorTimelockControlUpgradeable,
    GovernorVotesQuorumFractionUpgradeable,
    GovernorPreventLateQuorumUpgradeable
{
    using Bytes for bytes;
    using Strings for string;

    /*----------------- constants -----------------*/
    /**
     * @dev caution:
     * INIT_VOTING_DELAY, INIT_VOTING_PERIOD and INIT_MIN_PERIOD_AFTER_QUORUM are default in number of blocks, not seconds
     */
    uint256 private constant BLOCK_INTERVAL = 3 seconds;
    uint48 private constant INIT_VOTING_DELAY = uint48(0 hours / BLOCK_INTERVAL);
    uint32 private constant INIT_VOTING_PERIOD = uint32(7 days / BLOCK_INTERVAL);
    uint256 private constant INIT_PROPOSAL_THRESHOLD = 2_000_000 ether; //  = 2_000_000 G
    uint256 private constant INIT_QUORUM_NUMERATOR = 10; // for >= 10%

    // starting propose requires totalSupply of GovG >= 1_000_000_000 * 1e18
    uint256 private constant PROPOSE_START_GOVG_SUPPLY_THRESHOLD = 1_000_000_000 ether;
    // ensures there is a minimum voting period (1 days) after quorum is reached
    uint48 private constant INIT_MIN_PERIOD_AFTER_QUORUM = uint48(1 days / BLOCK_INTERVAL);

    /*----------------- errors -----------------*/
    // @notice signature: 0x584a7938
    error NotWhitelisted();
    // @notice signature: 0x11b6707f
    error TotalSupplyNotEnough();
    // @notice signature: 0x867f3ee5
    error OneLiveProposalPerProposer();

    /*----------------- storage -----------------*/
    // target contract => is whitelisted for governance
    mapping(address => bool) public whitelistTargets;

    bool public proposeStarted;

    // @notice The latest proposal for each proposer
    mapping(address => uint256) public latestProposalIds;

    /*----------------- init -----------------*/
    function initialize() external initializer onlySystemCaller {
        __Governor_init("GravityGovernor");
        __GovernorSettings_init(INIT_VOTING_DELAY, INIT_VOTING_PERIOD, INIT_PROPOSAL_THRESHOLD);
        __GovernorVotes_init(IVotes(GOV_TOKEN_ADDR));
        __GovernorTimelockControl_init(TimelockControllerUpgradeable(payable(TIMELOCK_ADDR)));
        __GovernorVotesQuorumFraction_init(INIT_QUORUM_NUMERATOR);
        __GovernorPreventLateQuorum_init(INIT_MIN_PERIOD_AFTER_QUORUM);

        // GravityGovernor => Timelock => GovHub => system contracts
        whitelistTargets[GOV_HUB_ADDR] = true;
    }

    /*----------------- external functions -----------------*/
    /**
     * @dev Create a new proposal. Vote start after a delay specified by {IGovernor-votingDelay} and lasts for a
     * duration specified by {IGovernor-votingPeriod}.
     *
     * Emits a {ProposalCreated} event.
     */
    function propose(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description
    ) public override(GovernorUpgradeable) whenNotPaused notInBlackList returns (uint256) {
        _checkAndStartPropose();

        uint256 latestProposalId = latestProposalIds[msg.sender];
        if (latestProposalId != 0) {
            ProposalState proposersLatestProposalState = state(latestProposalId);
            if (
                proposersLatestProposalState == ProposalState.Active ||
                proposersLatestProposalState == ProposalState.Pending
            ) {
                revert OneLiveProposalPerProposer();
            }
        }

        bytes32 descriptionHash = keccak256(bytes(description));
        uint256 proposalId = hashProposal(targets, values, calldatas, descriptionHash);
        latestProposalIds[msg.sender] = proposalId;

        return super.propose(targets, values, calldatas, description);
    }

    /**
     * @dev Function to queue a proposal to the timelock.
     * @param targets target contracts to call
     * @param values msg.value for each contract call
     * @param calldatas calldata for each contract call
     * @param descriptionHash the description hash
     */
    function queue(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) public override whenNotPaused notInBlackList returns (uint256 proposalId) {
        for (uint256 i = 0; i < targets.length; i++) {
            if (!whitelistTargets[targets[i]]) revert NotWhitelisted();
        }

        return super.queue(targets, values, calldatas, descriptionHash);
    }

    /*----------------- system functions -----------------*/
    /**
     * @param key the key of the param
     * @param value the value of the param
     */
    function updateParam(string calldata key, bytes calldata value) external onlyGov {
        if (Strings.equal(key, "votingDelay")) {
            if (value.length != 32) revert InvalidValue(key, value);
            uint256 newVotingDelay = value.bytesToUint256(32);
            if (newVotingDelay == 0 || newVotingDelay > 24 hours) revert InvalidValue(key, value);
            _setVotingDelay(SafeCast.toUint48(newVotingDelay));
        } else if (Strings.equal(key, "votingPeriod")) {
            if (value.length != 32) revert InvalidValue(key, value);
            uint256 newVotingPeriod = value.bytesToUint256(32);
            if (newVotingPeriod == 0 || newVotingPeriod > 30 days) revert InvalidValue(key, value);
            _setVotingPeriod(SafeCast.toUint32(newVotingPeriod));
        } else if (Strings.equal(key, "proposalThreshold")) {
            if (value.length != 32) revert InvalidValue(key, value);
            uint256 newProposalThreshold = value.bytesToUint256(32);
            if (newProposalThreshold == 0 || newProposalThreshold > 10_000 ether) revert InvalidValue(key, value);
            _setProposalThreshold(newProposalThreshold);
        } else if (Strings.equal(key, "quorumNumerator")) {
            if (value.length != 32) revert InvalidValue(key, value);
            uint256 newQuorumNumerator = value.bytesToUint256(32);
            if (newQuorumNumerator < 5 || newQuorumNumerator > 20) revert InvalidValue(key, value);
            _updateQuorumNumerator(newQuorumNumerator);
        } else if (Strings.equal(key, "minPeriodAfterQuorum")) {
            if (value.length != 8) revert InvalidValue(key, value);
            uint64 newMinPeriodAfterQuorum = value.bytesToUint64(8);
            if (newMinPeriodAfterQuorum == 0 || newMinPeriodAfterQuorum > 2 days) revert InvalidValue(key, value);
            _setLateQuorumVoteExtension(SafeCast.toUint48(newMinPeriodAfterQuorum));
        } else {
            revert UnknownParam(key, value);
        }
        emit ParamChange(key, value);
    }

    /*----------------- view functions -----------------*/
    function supportsInterface(bytes4 interfaceId) public view override(GovernorUpgradeable) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    /**
     * @notice module:core
     * @dev Current state of a proposal, following Compound's convention
     */
    function state(
        uint256 proposalId
    ) public view override(GovernorUpgradeable, GovernorTimelockControlUpgradeable) returns (ProposalState) {
        return GovernorTimelockControlUpgradeable.state(proposalId);
    }

    /**
     * @dev Part of the Governor Bravo's interface: _"The number of votes required in order for a voter to become a proposer"_.
     */
    function proposalThreshold()
        public
        view
        override(GovernorSettingsUpgradeable, GovernorUpgradeable)
        returns (uint256)
    {
        return GovernorSettingsUpgradeable.proposalThreshold();
    }

    /**
     * @notice module:core
     * @dev Timepoint at which votes close. If using block number, votes close at the end of this block, so it is
     * possible to cast a vote during this block.
     */
    function proposalDeadline(
        uint256 proposalId
    ) public view override(GovernorUpgradeable, GovernorPreventLateQuorumUpgradeable) returns (uint256) {
        return GovernorPreventLateQuorumUpgradeable.proposalDeadline(proposalId);
    }

    /*----------------- internal functions -----------------*/
    function _checkAndStartPropose() internal {
        if (!proposeStarted) {
            if (IGovToken(GOV_TOKEN_ADDR).totalSupply() < PROPOSE_START_GOVG_SUPPLY_THRESHOLD) {
                revert TotalSupplyNotEnough();
            }
            proposeStarted = true;
        }
    }

    function _executeOperations(
        uint256 proposalId,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal override(GovernorUpgradeable, GovernorTimelockControlUpgradeable) whenNotPaused notInBlackList {
        for (uint256 i = 0; i < targets.length; i++) {
            if (!whitelistTargets[targets[i]]) revert NotWhitelisted();
        }

        GovernorTimelockControlUpgradeable._executeOperations(proposalId, targets, values, calldatas, descriptionHash);

        // 所有治理操作执行完成后，尝试触发epoch转换
        IEpochManager(EPOCH_MANAGER_ADDR).triggerEpochTransition();
    }

    function _cancel(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal override(GovernorUpgradeable, GovernorTimelockControlUpgradeable) returns (uint256) {
        return GovernorTimelockControlUpgradeable._cancel(targets, values, calldatas, descriptionHash);
    }

    function _castVote(
        uint256 proposalId,
        address account,
        uint8 support,
        string memory reason,
        bytes memory params
    ) internal override(GovernorUpgradeable) whenNotPaused notInBlackList returns (uint256) {
        return super._castVote(proposalId, account, support, reason, params);
    }

    function _executor()
        internal
        view
        override(GovernorUpgradeable, GovernorTimelockControlUpgradeable)
        returns (address)
    {
        return GovernorTimelockControlUpgradeable._executor();
    }

    /*----------------- additional override functions -----------------*/

    /**
     * @dev Override _queueOperations to resolve conflict between GovernorUpgradeable and GovernorTimelockControlUpgradeable
     */
    function _queueOperations(
        uint256 proposalId,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal override(GovernorUpgradeable, GovernorTimelockControlUpgradeable) returns (uint48) {
        return
            GovernorTimelockControlUpgradeable._queueOperations(
                proposalId,
                targets,
                values,
                calldatas,
                descriptionHash
            );
    }

    /**
     * @dev Override _tallyUpdated to resolve conflict between GovernorUpgradeable and GovernorPreventLateQuorumUpgradeable
     */
    function _tallyUpdated(
        uint256 proposalId
    ) internal override(GovernorUpgradeable, GovernorPreventLateQuorumUpgradeable) {
        GovernorPreventLateQuorumUpgradeable._tallyUpdated(proposalId);
    }

    /**
     * @dev Override proposalNeedsQueuing to resolve conflict between GovernorUpgradeable and GovernorTimelockControlUpgradeable
     */
    function proposalNeedsQueuing(
        uint256 proposalId
    ) public view override(GovernorUpgradeable, GovernorTimelockControlUpgradeable) returns (bool) {
        return GovernorTimelockControlUpgradeable.proposalNeedsQueuing(proposalId);
    }

    /*----------------- Voting Logic Implementation -----------------*/

    /**
     * @dev Voting power tracking for proposals
     */
    struct ProposalVote {
        uint256 againstVotes;
        uint256 forVotes;
        uint256 abstainVotes;
        mapping(address => bool) hasVoted;
    }

    mapping(uint256 => ProposalVote) private _proposalVotes;

    /**
     * @dev See {Governor-_quorumReached}.
     */
    function _quorumReached(uint256 proposalId) internal view override returns (bool) {
        ProposalVote storage proposalVote = _proposalVotes[proposalId];
        return quorum(proposalSnapshot(proposalId)) <= proposalVote.forVotes + proposalVote.abstainVotes;
    }

    /**
     * @dev See {Governor-_voteSucceeded}. In this module, the forVotes must be strictly over the againstVotes.
     */
    function _voteSucceeded(uint256 proposalId) internal view override returns (bool) {
        ProposalVote storage proposalVote = _proposalVotes[proposalId];
        return proposalVote.forVotes > proposalVote.againstVotes;
    }

    /**
     * @dev See {Governor-_countVote}. In this module, the support follows the `VoteType` enum (from Governor Bravo).
     */
    function _countVote(
        uint256 proposalId,
        address account,
        uint8 support,
        uint256 totalWeight,
        bytes memory // params
    ) internal override returns (uint256) {
        ProposalVote storage proposalVote = _proposalVotes[proposalId];

        require(!proposalVote.hasVoted[account], "GravityGovernor: vote already cast");
        proposalVote.hasVoted[account] = true;

        if (support == 0) {
            proposalVote.againstVotes += totalWeight;
        } else if (support == 1) {
            proposalVote.forVotes += totalWeight;
        } else if (support == 2) {
            proposalVote.abstainVotes += totalWeight;
        } else {
            revert("GravityGovernor: invalid value for enum VoteType");
        }

        return totalWeight;
    }

    /**
     * @dev See {IGovernor-hasVoted}.
     */
    function hasVoted(uint256 proposalId, address account) public view returns (bool) {
        return _proposalVotes[proposalId].hasVoted[account];
    }

    /**
     * @dev Accessor to the internal vote counts.
     */
    function proposalVotes(
        uint256 proposalId
    ) public view returns (uint256 againstVotes, uint256 forVotes, uint256 abstainVotes) {
        ProposalVote storage proposalVote = _proposalVotes[proposalId];
        return (proposalVote.againstVotes, proposalVote.forVotes, proposalVote.abstainVotes);
    }
    /*----------------- view functions -----------------*/

    /**
     * @dev See {IGovernor-COUNTING_MODE}.
     */
    // solhint-disable-next-line func-name-mixedcase
    function COUNTING_MODE() public pure override returns (string memory) {
        return "support=bravo&quorum=for,abstain";
    }
}
