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
    error StakeCredit__UnauthorizedCaller();

    // 所有事件定义
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
    event RewardDistributed(uint256 activeReward, uint256 pendingInactiveReward);
    event PendingInactiveProcessed(uint256 amount);
    event StakeReactivated(address indexed delegator, uint256 shares, uint256 gAmount);
    event BeneficiaryUpdated(address indexed validator, address indexed oldBeneficiary, address indexed newBeneficiary);

    // 遗漏的事件
    event LockupStarted(uint256 lockupTime);
    event LockupRenewed(uint256 newLockupTime);

    // 新增事件
    event UnlockRequestCreated(uint256 timestamp);
    event UnlockRequestProcessed(uint256 amount);
    event AllStakeUnlocked(uint256 amount);
    event UnlockRequestForcedProcessed(uint256 amount);
    event LockupDeprecated(string functionName, uint256 value);

    function initialize(address _validator, string memory _moniker, address _beneficiary) external payable;

    // 状态变量访问器
    function active() external view returns (uint256);
    function inactive() external view returns (uint256);
    function pendingActive() external view returns (uint256);
    function pendingInactive() external view returns (uint256);
    function lockedUntilSecs() external view returns (uint256);
    function validator() external view returns (address);
    function stakeHubAddress() external view returns (address);
    function commissionBeneficiary() external view returns (address);

    // 新增状态变量访问器
    function hasUnlockRequest() external view returns (bool);
    function unlockRequestedAt() external view returns (uint256);

    function rewardRecord(uint256 day) external view returns (uint256);
    function totalPooledGRecord(uint256 day) external view returns (uint256);

    // 核心功能
    function delegate(address delegator) external payable returns (uint256 shares);
    function unlock(address delegator, uint256 shares) external returns (uint256 gAmount);
    function withdraw(address payable delegator, uint256 shares) external returns (uint256);
    function distributeReward(uint64 commissionRate) external payable;
    function reactivateStake(address delegator, uint256 shares) external returns (uint256 gAmount);
    function unbond(address delegator, uint256 shares) external returns (uint256 gAmount);

    // 管理功能
    function onNewEpoch() external;
    function forceProcessPendingInactive() external;
    function updateBeneficiary(address newBeneficiary) external;

    function getUnlockRequestStatus() external view returns (bool hasRequest, uint256 requestedAt);

    // 查询功能
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
