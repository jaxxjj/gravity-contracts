// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "@openzeppelin-upgrades/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin-upgrades/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin-upgrades/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/utils/structs/DoubleEndedQueue.sol";
import "@src/interfaces/IStakeConfig.sol";
import "@src/System.sol";
import "@src/interfaces/IValidatorManager.sol";
import "@src/interfaces/IStakeCredit.sol";
import "@src/interfaces/ITimestamp.sol";

/**
 * @title StakeCredit
 * @dev Implements a shares-based staking mechanism with BSC-style unlock mechanism
 * Layer 1: State pools (active, inactive, pendingActive, pendingInactive)
 * Uses Pull model for withdrawals with unbonding period
 */
contract StakeCredit is Initializable, ERC20Upgradeable, ReentrancyGuardUpgradeable, System, IStakeCredit {
    using DoubleEndedQueue for DoubleEndedQueue.Bytes32Deque;

    uint256 private constant COMMISSION_RATE_BASE = 10_000; // 100%

    // State model - Layer 1: State Pools
    uint256 public active;
    uint256 public inactive;
    uint256 public pendingActive;
    uint256 public pendingInactive;

    // Unlock request tracking (BSC style)
    struct UnlockRequest {
        uint256 amount; // Amount to unlock (not shares)
        uint256 unlockTime; // When it becomes claimable
    }

    // Hash of unlock request => UnlockRequest
    mapping(bytes32 => UnlockRequest) private _unlockRequests;
    // User address => unlock request queue (hash of requests)
    mapping(address => DoubleEndedQueue.Bytes32Deque) private _unlockRequestsQueue;
    // User address => personal unlock sequence
    mapping(address => uint256) private _unlockSequence;

    // Validator information
    address public validator;

    // Reward history records
    mapping(uint256 => uint256) public rewardRecord;
    mapping(uint256 => uint256) public totalPooledGRecord;

    // Commission beneficiary
    address public commissionBeneficiary;

    // Principal tracking
    uint256 public validatorPrincipal;

    constructor() {
        _disableInitializers();
    }

    /**
     * @dev Receives G as reward
     */
    receive() external payable onlyValidatorManager {
        uint256 index = ITimestamp(TIMESTAMP_ADDR).nowSeconds() / 86400; // Daily index
        totalPooledGRecord[index] = getTotalPooledG();
        rewardRecord[index] += msg.value;
    }

    /// @inheritdoc IStakeCredit
    function initialize(
        address _validator,
        string memory _moniker,
        address _beneficiary
    ) external payable initializer {
        // Initialize ERC20 base
        _initializeERC20(_moniker);

        // Set validator address
        validator = _validator;

        // Initialize state balances to zero
        _initializeStakeStates();

        // Handle initial stake
        _bootstrapInitialStake(msg.value);

        // Set commission beneficiary
        commissionBeneficiary = _beneficiary;

        emit Initialized(_validator, _moniker, _beneficiary);
    }

    /**
     * @dev Initializes ERC20 component
     */
    function _initializeERC20(
        string memory _moniker
    ) private {
        string memory name_ = string.concat("Stake ", _moniker, " Credit");
        string memory symbol_ = string.concat("st", _moniker);
        __ERC20_init(name_, symbol_);
        __ReentrancyGuard_init();
    }

    /**
     * @dev Initializes stake states
     */
    function _initializeStakeStates() private {
        active = 0;
        inactive = 0;
        pendingActive = 0;
        pendingInactive = 0;
    }

    /**
     * @dev Initializes initial stake
     */
    function _bootstrapInitialStake(
        uint256 _initialAmount
    ) private {
        _bootstrapInitialHolder(_initialAmount);
    }

    /**
     * @dev Bootstraps initial holder
     */
    function _bootstrapInitialHolder(
        uint256 initialAmount
    ) private {
        uint256 toLock = IStakeConfig(STAKE_CONFIG_ADDR).lockAmount();
        if (initialAmount <= toLock || validator == address(0)) {
            revert StakeCredit__WrongInitContext();
        }

        // Mint initial shares
        _mint(DEAD_ADDRESS, toLock);
        uint256 initShares = initialAmount - toLock;
        _mint(validator, initShares);

        // Update balances
        active = initialAmount; // All initial stake goes to active state

        // Initialize principal
        validatorPrincipal = initialAmount;
    }

    /// @inheritdoc IStakeCredit
    function delegate(
        address delegator
    ) external payable onlyDelegationOrValidatorManager returns (uint256 shares) {
        if (msg.value == 0) revert ZeroAmount();

        // Calculate shares based on current pool value
        uint256 totalPooled = getTotalPooledG();
        if (totalSupply() == 0 || totalPooled == 0) {
            shares = msg.value;
        } else {
            shares = (msg.value * totalSupply()) / totalPooled;
        }

        // Update state
        if (_isCurrentEpochValidator()) {
            pendingActive += msg.value;
        } else {
            active += msg.value;
        }

        // Mint shares
        _mint(delegator, shares);

        emit StakeAdded(delegator, shares, msg.value);
        return shares;
    }

    /// @inheritdoc IStakeCredit
    function unlock(
        address delegator,
        uint256 shares
    ) external onlyDelegationOrValidatorManager returns (uint256 gAmount) {
        // Basic validation
        if (shares == 0) revert ZeroShares();
        if (shares > balanceOf(delegator)) revert InsufficientBalance();

        // Calculate G amount and burn shares immediately
        gAmount = getPooledGByShares(shares);
        _burn(delegator, shares);

        // Deduct from active pools (managing totals only)
        uint256 totalActive = active + pendingActive;
        if (gAmount > totalActive) revert InsufficientActiveStake();

        if (active >= gAmount) {
            active -= gAmount;
        } else {
            uint256 fromActive = active;
            uint256 fromPendingActive = gAmount - fromActive;
            active = 0;
            pendingActive -= fromPendingActive;
        }

        // Move to pending_inactive state
        pendingInactive += gAmount;

        // Create unlock request (BSC style)
        uint256 unlockTime = ITimestamp(TIMESTAMP_ADDR).nowSeconds() + _getUnbondPeriod();
        bytes32 requestHash = keccak256(abi.encodePacked(delegator, _unlockSequence[delegator]++));

        // Check for hash collision (should not happen in normal cases)
        if (_unlockRequests[requestHash].amount != 0) revert StakeCredit__RequestExists();

        _unlockRequests[requestHash] = UnlockRequest({ amount: gAmount, unlockTime: unlockTime });

        _unlockRequestsQueue[delegator].pushBack(requestHash);

        emit StakeUnlocked(delegator, shares, gAmount);
        return gAmount;
    }

    /// @inheritdoc IStakeCredit
    function claim(
        address payable delegator
    ) external onlyDelegationOrValidatorManager nonReentrant returns (uint256 totalClaimed) {
        DoubleEndedQueue.Bytes32Deque storage queue = _unlockRequestsQueue[delegator];

        if (queue.length() == 0) revert StakeCredit__NoUnlockRequest();

        uint256 currentTime = ITimestamp(TIMESTAMP_ADDR).nowSeconds();

        // Process all claimable requests from the front of the queue
        while (queue.length() > 0) {
            bytes32 requestHash = queue.front();
            UnlockRequest memory request = _unlockRequests[requestHash];

            // Check if request is claimable
            if (currentTime < request.unlockTime) {
                break; // Requests are in chronological order, so we can stop here
            }

            // Check if we have enough inactive funds
            if (inactive < request.amount) {
                break; // Not enough funds available
            }

            // Remove from queue
            queue.popFront();
            delete _unlockRequests[requestHash];

            // Update state
            inactive -= request.amount;
            totalClaimed += request.amount;
        }

        // Transfer all claimed amount at once
        if (totalClaimed == 0) revert StakeCredit__NoClaimableRequest();

        (bool success,) = delegator.call{ value: totalClaimed }("");
        if (!success) revert TransferFailed();

        emit StakeWithdrawn(delegator, totalClaimed);
        return totalClaimed;
    }

    /// @inheritdoc IStakeCredit
    function unbond(
        address delegator,
        uint256 shares
    ) external onlyDelegationOrValidatorManager returns (uint256 gAmount) {
        if (shares == 0) revert ZeroShares();
        if (shares > balanceOf(delegator)) revert InsufficientBalance();

        // Calculate G amount
        gAmount = getPooledGByShares(shares);

        // Burn shares
        _burn(delegator, shares);

        // Deduct from active state
        if (active >= gAmount) {
            active -= gAmount;
        } else {
            uint256 fromActive = active;
            uint256 fromPendingActive = gAmount - fromActive;
            active = 0;
            if (pendingActive >= fromPendingActive) {
                pendingActive -= fromPendingActive;
            } else {
                revert InsufficientBalance();
            }
        }

        // Transfer directly to caller (Delegation contract)
        (bool success,) = msg.sender.call{ value: gAmount }("");
        if (!success) revert TransferFailed();

        return gAmount;
    }

    /// @inheritdoc IStakeCredit
    function reactivateStake(
        address delegator,
        uint256 shares
    ) external onlyDelegationOrValidatorManager returns (uint256 gAmount) {
        if (shares == 0) revert ZeroShares();
        if (pendingInactive == 0) revert NoWithdrawableAmount();

        // For reactivation, we need to cancel pending unlock requests
        // This is a simplified implementation - in production you might want more sophisticated logic
        DoubleEndedQueue.Bytes32Deque storage queue = _unlockRequestsQueue[delegator];
        uint256 totalReactivated = 0;
        uint256 currentTime = ITimestamp(TIMESTAMP_ADDR).nowSeconds();

        // Find and cancel unlock requests that haven't been moved to distribution pool yet
        while (queue.length() > 0) {
            bytes32 requestHash = queue.front();
            UnlockRequest memory request = _unlockRequests[requestHash];

            // Check if request is claimable
            if (currentTime < request.unlockTime) {
                break; // Requests are in chronological order, so we can stop here
            }

            // Remove from queue
            queue.popFront();
            delete _unlockRequests[requestHash];

            // Move from pendingInactive back to active
            if (pendingInactive >= request.amount) {
                pendingInactive -= request.amount;
                active += request.amount;
                totalReactivated += request.amount;
            } else {
                revert InsufficientBalance();
            }
        }

        gAmount = totalReactivated;

        // Mint shares back
        if (gAmount > 0) {
            uint256 sharesToMint = getSharesByPooledG(gAmount);
            _mint(delegator, sharesToMint);

            emit StakeReactivated(delegator, sharesToMint, gAmount);
        }

        return gAmount;
    }

    /// @inheritdoc IStakeCredit
    function distributeReward(
        uint64 commissionRate
    ) external payable onlyValidatorManager {
        uint256 totalReward = msg.value;

        // Calculate accumulated rewards (growth based on principal)
        uint256 totalStake = getTotalPooledG();
        uint256 accumulatedRewards = totalStake > validatorPrincipal ? totalStake - validatorPrincipal : 0;

        // Calculate commission for this reward
        uint256 newRewards = totalReward;
        uint256 totalRewardsWithAccumulated = accumulatedRewards + newRewards;
        uint256 commission = (totalRewardsWithAccumulated * uint256(commissionRate)) / COMMISSION_RATE_BASE;

        // Limit commission to not exceed new rewards
        if (commission > accumulatedRewards) {
            commission = commission - accumulatedRewards;
        } else {
            commission = 0;
        }

        // Update principal (new principal after commission)
        validatorPrincipal = totalStake + totalReward - commission;

        // Rewards go directly to active, benefiting all share holders
        active += totalReward;

        // Mint commission shares for beneficiary (dilutes others)
        if (commission > 0) {
            address beneficiary = commissionBeneficiary == address(0) ? validator : commissionBeneficiary;
            uint256 commissionShares = (commission * totalSupply()) / (totalStake + totalReward);
            _mint(beneficiary, commissionShares);
        }

        // Record reward
        uint256 index = ITimestamp(TIMESTAMP_ADDR).nowSeconds() / 86400;
        totalPooledGRecord[index] = getTotalPooledG();
        rewardRecord[index] += totalReward - commission;

        emit RewardReceived(totalReward - commission, commission);
    }

    /// @inheritdoc IStakeCredit
    function onNewEpoch() external onlyValidatorManager {
        uint256 oldActive = active;
        uint256 oldInactive = inactive;
        uint256 oldPendingActive = pendingActive;
        uint256 oldPendingInactive = pendingInactive;

        // 1. pending_active -> active
        active += pendingActive;
        pendingActive = 0;

        // 2. Process unlock requests and update distribution pool
        if (pendingInactive > 0) {
            // Move funds to inactive
            inactive += pendingInactive;
            pendingInactive = 0;
        }

        emit EpochTransitioned(
            oldActive,
            oldInactive,
            oldPendingActive,
            oldPendingInactive,
            active,
            inactive,
            pendingActive,
            pendingInactive
        );
    }

    /// @inheritdoc IStakeCredit
    function getPooledGByShares(
        uint256 shares
    ) public view returns (uint256) {
        uint256 totalPooled = getTotalPooledG();
        if (totalSupply() == 0) revert ZeroTotalShares();
        return (shares * totalPooled) / totalSupply();
    }

    /// @inheritdoc IStakeCredit
    function getSharesByPooledG(
        uint256 gAmount
    ) public view returns (uint256) {
        uint256 totalPooled = getTotalPooledG();
        if (totalPooled == 0) revert ZeroTotalPooledTokens();
        return (gAmount * totalSupply()) / totalPooled;
    }

    /// @inheritdoc IStakeCredit
    function getTotalPooledG() public view returns (uint256) {
        return active + inactive + pendingActive + pendingInactive;
    }

    /// @inheritdoc IStakeCredit
    function getStake() external view returns (uint256, uint256, uint256, uint256) {
        return (active, inactive, pendingActive, pendingInactive);
    }

    /// @inheritdoc IStakeCredit
    function getNextEpochVotingPower() external view returns (uint256) {
        return active + pendingActive;
    }

    /// @inheritdoc IStakeCredit
    function getCurrentEpochVotingPower() external view returns (uint256) {
        return active + pendingInactive;
    }

    /// @inheritdoc IStakeCredit
    function getPooledGByDelegator(
        address delegator
    ) public view returns (uint256) {
        return getPooledGByShares(balanceOf(delegator));
    }

    /**
     * @dev Get user's claimable amount
     */
    function getClaimableAmount(
        address delegator
    ) external view returns (uint256 claimable) {
        DoubleEndedQueue.Bytes32Deque storage queue = _unlockRequestsQueue[delegator];

        if (queue.length() == 0) return 0;

        uint256 currentTime = ITimestamp(TIMESTAMP_ADDR).nowSeconds();
        uint256 index = 0;
        bytes32[] memory hashes = new bytes32[](queue.length());

        // Get all request hashes from the queue
        for (uint256 i = 0; i < queue.length(); i++) {
            hashes[i] = queue.at(i);
        }

        // Process all claimable requests from the front of the queue
        while (index < hashes.length) {
            bytes32 requestHash = hashes[index];
            UnlockRequest memory request = _unlockRequests[requestHash];

            // Check if request is claimable
            if (currentTime < request.unlockTime) {
                break; // Requests are in chronological order, so we can stop here
            }

            claimable += request.amount;
            index++;
        }

        return claimable;
    }

    /**
     * @dev Get user's pending unlock amount
     */
    function getPendingUnlockAmount(
        address delegator
    ) external view returns (uint256) {
        return _unlockRequestsQueue[delegator].length();
    }

    /**
     * @dev Process matured unlocks for a specific user
     * In BSC-style implementation, this checks and processes unlock requests
     * that have completed their unbonding period but haven't been claimed yet
     */
    function processUserUnlocks(
        address user
    ) external {
        DoubleEndedQueue.Bytes32Deque storage queue = _unlockRequestsQueue[user];
        uint256 currentTime = ITimestamp(TIMESTAMP_ADDR).nowSeconds();

        // Process all claimable requests from the front of the queue
        while (queue.length() > 0) {
            bytes32 requestHash = queue.front();
            UnlockRequest memory request = _unlockRequests[requestHash];

            // Check if request is claimable
            if (currentTime < request.unlockTime) {
                break; // Requests are in chronological order, so we can stop here
            }

            // Remove from queue
            queue.popFront();
            delete _unlockRequests[requestHash];

            // Note: Funds stay in inactive pool until user claims them
            // This is part of the BSC-style pull model
        }
    }

    /**
     * @dev Checks if validator is current epoch validator
     */
    function _isCurrentEpochValidator() internal view returns (bool) {
        return IValidatorManager(VALIDATOR_MANAGER_ADDR).isCurrentEpochValidator(validator);
    }

    /**
     * @dev Gets unbond period from StakeConfig
     */
    function _getUnbondPeriod() internal view returns (uint256) {
        return IStakeConfig(STAKE_CONFIG_ADDR).recurringLockupDuration();
    }

    // ERC20 overrides (disable transfers)

    /**
     * @dev Override _update to disable direct transfers between accounts
     */
    function _update(address from, address to, uint256 value) internal virtual override {
        if (from != address(0) && to != address(0)) {
            revert TransferNotAllowed();
        }
        super._update(from, to, value);
    }

    /**
     * @dev Override _approve to disable approvals
     */
    function _approve(address, address, uint256, bool) internal virtual override {
        revert ApproveNotAllowed();
    }

    /// @inheritdoc IStakeCredit
    function validateStakeStates() external view returns (bool) {
        // Verify total of four states equals contract balance
        uint256 totalStates = active + inactive + pendingActive + pendingInactive;
        return totalStates == address(this).balance;
    }

    /// @inheritdoc IStakeCredit
    function getDetailedStakeInfo()
        external
        view
        returns (
            uint256 _active,
            uint256 _inactive,
            uint256 _pendingActive,
            uint256 _pendingInactive,
            uint256 _totalPooled,
            uint256 _contractBalance,
            uint256 _totalShares,
            bool _hasUnlockRequest
        )
    {
        return (
            active,
            inactive,
            pendingActive,
            pendingInactive,
            getTotalPooledG(),
            address(this).balance,
            totalSupply(),
            _unlockRequestsQueue[msg.sender].length() > 0
        );
    }

    /// @inheritdoc IStakeCredit
    function updateBeneficiary(
        address newBeneficiary
    ) external {
        // Only validator can call
        if (msg.sender != validator) {
            revert StakeCredit__UnauthorizedCaller();
        }

        address oldBeneficiary = commissionBeneficiary;
        commissionBeneficiary = newBeneficiary;

        emit BeneficiaryUpdated(validator, oldBeneficiary, newBeneficiary);
    }

    /// @inheritdoc IStakeCredit
    function getUnlockRequestStatus() external view returns (bool hasRequest, uint256 requestedAt) {
        address user = msg.sender;
        DoubleEndedQueue.Bytes32Deque storage queue = _unlockRequestsQueue[user];

        if (queue.length() > 0) {
            hasRequest = true;
            // Return the oldest unlock request time
            bytes32 requestHash = queue.front();
            UnlockRequest memory request = _unlockRequests[requestHash];
            requestedAt = request.unlockTime - _getUnbondPeriod();
        }

        return (hasRequest, requestedAt);
    }
}
