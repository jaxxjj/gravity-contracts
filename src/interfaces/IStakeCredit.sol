// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

/**
 * @title IStakeCredit
 * @dev Interface for StakeCredit contract
 */
interface IStakeCredit {
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
    error StateTransitionError();
    error LockupNotExpired();
    error AlreadyInitialized();

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
    event LockupIncreased(uint256 oldLockup, uint256 newLockup);
    event LockupRenewed(uint256 newLockupTime);
    event LockupStarted(uint256 lockupTime);
    event Initialized(address validator, string moniker);
    event RewardDistributed(uint256 activeReward, uint256 pendingInactiveReward);
    event PendingInactiveProcessed(uint256 amount);
    event StakeReactivated(address indexed delegator, uint256 shares, uint256 gAmount);

    function initialize(address _validator, string memory _moniker) external payable;

    function active() external view returns (uint256);
    function inactive() external view returns (uint256);
    function pendingActive() external view returns (uint256);
    function pendingInactive() external view returns (uint256);
    function lockedUntilSecs() external view returns (uint256);
    function validator() external view returns (address);
    function stakeHubAddress() external view returns (address);

    function rewardRecord(uint256 day) external view returns (uint256);
    function totalPooledGRecord(uint256 day) external view returns (uint256);

    function delegate(address delegator) external payable returns (uint256 shares);
    function unlock(address delegator, uint256 shares) external returns (uint256 gAmount);
    function withdraw(address payable delegator, uint256 shares) external returns (uint256);
    function distributeReward(uint64 commissionRate) external payable;
    function reactivateStake(address delegator, uint256 shares) external returns (uint256 gAmount);

    function onNewEpoch() external;
    function forceProcessPendingInactive() external;
    function increaseLockup(uint256 newLockUntil) external;
    function renewLockup() external;
    function unbond(address delegator, uint256 shares) external returns (uint256 gAmount);

    function getPooledGByShares(uint256 shares) external view returns (uint256);
    function getPooledGByDelegator(address delegator) external view returns (uint256);
    function getSharesByPooledG(uint256 gAmount) external view returns (uint256);
    function getTotalPooledG() external view returns (uint256);
    function getStake() external view returns (uint256, uint256, uint256, uint256);
    function getNextEpochVotingPower() external view returns (uint256);
    function getCurrentEpochVotingPower() external view returns (uint256);
    function getRemainingLockupSecs() external view returns (uint256);
    function validateStakeStates() external view returns (bool);
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
            bool _isLocked
        );
}
