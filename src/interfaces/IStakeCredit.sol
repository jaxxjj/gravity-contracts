// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/**
 * @title IStakeCredit
 * @dev Interface for StakeCredit contract which manages staking funds and shares
 * for validators and delegators using a shares-based staking model.
 */
interface IStakeCredit {
    // ======== Errors ========
    error ZeroTotalShares();
    error ZeroTotalPooledTokens();
    error TransferNotAllowed();
    error ApproveNotAllowed();
    error ZeroAmount();
    error ZeroShares();
    error InsufficientBalance();
    error TransferFailed();
    error NoWithdrawableAmount();
    error StakeCredit__WrongInitContext();
    error InsufficientActiveStake();
    error StakeCredit__UnauthorizedCaller();

    // ======== Events ========
    event RewardReceived(uint256 rewardToAll, uint256 commission);
    event StakeAdded(address indexed delegator, uint256 shares, uint256 gAmount);
    event StakeUnlocked(address indexed delegator, uint256 shares, uint256 gAmount);
    event StakeWithdrawn(address indexed delegator, uint256 amount);
    event EpochTransitioned(
        uint256 oldActive,
        uint256 oldInactive,
        uint256 oldPendingActive,
        uint256 oldPendingInactive,
        uint256 newActive,
        uint256 newInactive,
        uint256 newPendingActive,
        uint256 newPendingInactive
    );
    event Initialized(address validator, string moniker, address beneficiary);
    event StakeReactivated(address indexed delegator, uint256 shares, uint256 gAmount);
    event BeneficiaryUpdated(address indexed validator, address indexed oldBeneficiary, address indexed newBeneficiary);
    event UnlockRequestCreated(uint256 timestamp);
    event UnlockRequestProcessed(uint256 amount);

    // ======== Core Functions ========

    /**
     * @dev Initialize the StakeCredit contract
     * @param _validator Validator address
     * @param _moniker Validator name
     * @param _beneficiary Commission beneficiary address
     */
    function initialize(address _validator, string memory _moniker, address _beneficiary) external payable;

    /**
     * @dev Add stake to the pool
     * @param delegator The delegator address
     * @return shares The number of shares minted
     */
    function delegate(address delegator) external payable returns (uint256 shares);

    /**
     * @dev Unlock stake (moves from active to pending_inactive)
     * @param delegator The delegator address
     * @param shares The number of shares to unlock
     * @return gAmount The G amount unlocked
     */
    function unlock(address delegator, uint256 shares) external returns (uint256 gAmount);

    /**
     * @dev Withdraw unlocked stake
     * @param delegator The delegator address to receive the withdrawn funds
     * @param amount The amount to withdraw (0 for all available)
     * @return The withdrawn G amount
     */
    function withdraw(address payable delegator, uint256 amount) external returns (uint256);

    /**
     * @dev Unbond stake immediately (for redelegation)
     * @param delegator The delegator address
     * @param shares The number of shares to unbond
     * @return gAmount The G amount unbonded
     */
    function unbond(address delegator, uint256 shares) external returns (uint256 gAmount);

    /**
     * @dev Reactivate pending inactive stake
     * @param delegator The delegator address
     * @param shares The number of shares to reactivate
     * @return gAmount The G amount reactivated
     */
    function reactivateStake(address delegator, uint256 shares) external returns (uint256 gAmount);

    /**
     * @dev Distribute rewards to the stake pool
     * @param commissionRate The commission rate (base: 10000)
     */
    function distributeReward(uint64 commissionRate) external payable;

    /**
     * @dev Process epoch transition
     */
    function onNewEpoch() external;

    /**
     * @dev Update the beneficiary address
     * @param newBeneficiary The new beneficiary address
     */
    function updateBeneficiary(address newBeneficiary) external;

    // ======== View Functions ========

    /**
     * @dev Get the amount of active stake
     * @return Current active stake amount
     */
    function active() external view returns (uint256);

    /**
     * @dev Get the amount of inactive stake (withdrawable)
     * @return Current inactive stake amount
     */
    function inactive() external view returns (uint256);

    /**
     * @dev Get the amount of pending active stake
     * @return Current pending active stake amount
     */
    function pendingActive() external view returns (uint256);

    /**
     * @dev Get the amount of pending inactive stake
     * @return Current pending inactive stake amount
     */
    function pendingInactive() external view returns (uint256);

    /**
     * @dev Get the validator address
     * @return Validator address
     */
    function validator() external view returns (address);

    /**
     * @dev Get the commission beneficiary address
     * @return Commission beneficiary address
     */
    function commissionBeneficiary() external view returns (address);

    /**
     * @dev Check if there is an active unlock request
     * @return Whether there is an active unlock request
     */
    function hasUnlockRequest() external view returns (bool);

    /**
     * @dev Get the timestamp when the current unlock request was created
     * @return Timestamp of the current unlock request
     */
    function unlockRequestedAt() external view returns (uint256);

    /**
     * @dev Get the reward record for a specific day
     * @param day The day index (timestamp / 86400)
     * @return Reward amount for the specified day
     */
    function rewardRecord(uint256 day) external view returns (uint256);

    /**
     * @dev Get the total pooled G record for a specific day
     * @param day The day index (timestamp / 86400)
     * @return Total pooled G amount for the specified day
     */
    function totalPooledGRecord(uint256 day) external view returns (uint256);

    /**
     * @dev Get the current unlock request status
     * @return hasRequest Whether there is an active unlock request
     * @return requestedAt The timestamp when the request was created
     */
    function getUnlockRequestStatus() external view returns (bool hasRequest, uint256 requestedAt);

    /**
     * @dev Convert shares to G amount
     * @param shares The number of shares
     * @return The corresponding G amount
     */
    function getPooledGByShares(uint256 shares) external view returns (uint256);

    /**
     * @dev Get the G amount owned by a delegator
     * @param delegator The delegator address
     * @return The G amount owned by the delegator
     */
    function getPooledGByDelegator(address delegator) external view returns (uint256);

    /**
     * @dev Convert G amount to shares
     * @param gAmount The G amount
     * @return The corresponding number of shares
     */
    function getSharesByPooledG(uint256 gAmount) external view returns (uint256);

    /**
     * @dev Get the total pooled G amount
     * @return The total pooled G amount
     */
    function getTotalPooledG() external view returns (uint256);

    /**
     * @dev Get the four state balances
     * @return active The active stake amount
     * @return inactive The inactive stake amount
     * @return pendingActive The pending active stake amount
     * @return pendingInactive The pending inactive stake amount
     */
    function getStake()
        external
        view
        returns (uint256 active, uint256 inactive, uint256 pendingActive, uint256 pendingInactive);

    /**
     * @dev Get the voting power for the next epoch
     * @return The next epoch voting power
     */
    function getNextEpochVotingPower() external view returns (uint256);

    /**
     * @dev Get the voting power for the current epoch
     * @return The current epoch voting power
     */
    function getCurrentEpochVotingPower() external view returns (uint256);

    /**
     * @dev Validate that stake states are consistent with contract balance
     * @return Whether the stake states are valid
     */
    function validateStakeStates() external view returns (bool);

    /**
     * @dev Get detailed stake information
     * @return _active Active stake amount
     * @return _inactive Inactive stake amount
     * @return _pendingActive Pending active stake amount
     * @return _pendingInactive Pending inactive stake amount
     * @return _totalPooled Total pooled G amount
     * @return _contractBalance Contract balance
     * @return _totalShares Total shares supply
     * @return _hasUnlockRequest Whether there is an active unlock request
     */
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
        );
}
