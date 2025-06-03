// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "@openzeppelin-upgrades/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin-upgrades/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin-upgrades/proxy/utils/Initializable.sol";
import "@src/interfaces/IStakeConfig.sol";
import "@src/System.sol";
import "@src/interfaces/IValidatorManager.sol";
import "@src/interfaces/IStakeCredit.sol";
import "@src/interfaces/ITimestamp.sol";

/**
 * @title StakeCredit
 * @dev Implements a shares-based staking mechanism for validators and delegators
 * Stakes are tracked in four states:
 * - active: currently participating in consensus
 * - inactive: withdrawable funds
 * - pending_active: will become active in next epoch
 * - pending_inactive: will become inactive in next epoch
 */
contract StakeCredit is Initializable, ERC20Upgradeable, ReentrancyGuardUpgradeable, System, IStakeCredit {
    uint256 private constant COMMISSION_RATE_BASE = 10_000; // 100%

    // State model
    uint256 public active;
    uint256 public inactive;
    uint256 public pendingActive;
    uint256 public pendingInactive;

    // Validator information
    address public validator;

    // Reward history records
    mapping(uint256 => uint256) public rewardRecord;
    mapping(uint256 => uint256) public totalPooledGRecord;

    // Commission beneficiary
    address public commissionBeneficiary;

    // Principal tracking
    uint256 public validatorPrincipal;

    // Unlock request tracking
    bool public hasUnlockRequest;
    uint256 public unlockRequestedAt;

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
    function initialize(address _validator, string memory _moniker, address _beneficiary)
        external
        payable
        initializer
    {
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
    function _initializeERC20(string memory _moniker) private {
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
    function _bootstrapInitialStake(uint256 _initialAmount) private {
        _bootstrapInitialHolder(_initialAmount);
    }

    /**
     * @dev Bootstraps initial holder
     */
    function _bootstrapInitialHolder(uint256 initialAmount) private {
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
    function delegate(address delegator) external payable onlyDelegationOrValidatorManager returns (uint256 shares) {
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

    /**
     * @dev Updates stake state
     * @param amount Stake amount
     */
    function _updateStakeState(uint256 amount) private {
        // Determine funds destination based on validator status
        bool isCurrentValidator = _isCurrentEpochValidator();

        // If validator is current epoch validator, new stake goes to pending_active
        // Otherwise goes directly to active (validator not in current epoch)
        if (isCurrentValidator) {
            pendingActive += amount;
        } else {
            active += amount;
        }
    }

    /// @inheritdoc IStakeCredit
    function unlock(address delegator, uint256 shares)
        external
        onlyDelegationOrValidatorManager
        returns (uint256 gAmount)
    {
        // Basic validation
        if (shares == 0) revert ZeroShares();
        if (shares > balanceOf(delegator)) revert InsufficientBalance();

        // Calculate G amount
        gAmount = getPooledGByShares(shares);

        // Simple state transition logic: deduct from active first
        uint256 totalActive = active + pendingActive;
        if (gAmount > totalActive) revert InsufficientActiveStake();

        if (active >= gAmount) {
            active -= gAmount;
        } else {
            // Need to deduct from both active and pendingActive
            uint256 fromActive = active;
            uint256 fromPendingActive = gAmount - fromActive;
            active = 0;
            pendingActive -= fromPendingActive;
        }

        // Move to pending_inactive state
        pendingInactive += gAmount;

        // Burn shares
        _burn(delegator, shares);

        // Mark unlock request
        if (!hasUnlockRequest) {
            hasUnlockRequest = true;
            unlockRequestedAt = ITimestamp(TIMESTAMP_ADDR).nowSeconds();
            emit UnlockRequestCreated(unlockRequestedAt);
        }

        emit StakeUnlocked(delegator, shares, gAmount);
        return gAmount;
    }

    /// @inheritdoc IStakeCredit
    function withdraw(address payable delegator, uint256 amount)
        external
        onlyDelegationOrValidatorManager
        nonReentrant
        returns (uint256 withdrawnAmount)
    {
        // Can only withdraw from inactive state
        if (inactive == 0) revert NoWithdrawableAmount();

        // Calculate delegator's total value
        uint256 delegatorTotalValue = getPooledGByShares(balanceOf(delegator));
        if (delegatorTotalValue == 0) revert NoWithdrawableAmount();

        // Calculate delegator's share of inactive pool
        uint256 totalPooled = getTotalPooledG();
        uint256 delegatorInactiveAmount = (delegatorTotalValue * inactive) / totalPooled;
        if (delegatorInactiveAmount == 0) revert NoWithdrawableAmount();

        // If amount is 0 or greater than withdrawable, set to max withdrawable
        if (amount == 0 || amount > delegatorInactiveAmount) {
            amount = delegatorInactiveAmount;
        }
        withdrawnAmount = amount;

        // Calculate shares to burn
        uint256 sharesToBurn = getSharesByPooledG(amount);
        if (sharesToBurn > balanceOf(delegator)) {
            sharesToBurn = balanceOf(delegator);
            withdrawnAmount = getPooledGByShares(sharesToBurn);
        }

        // Update state
        inactive -= withdrawnAmount;

        // Burn shares
        _burn(delegator, sharesToBurn);

        // Transfer
        (bool success,) = delegator.call{value: withdrawnAmount}("");
        if (!success) revert TransferFailed();

        emit StakeWithdrawn(delegator, withdrawnAmount);
        return withdrawnAmount;
    }

    /// @inheritdoc IStakeCredit
    function unbond(address delegator, uint256 shares)
        external
        onlyDelegationOrValidatorManager
        returns (uint256 gAmount)
    {
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
        (bool success,) = msg.sender.call{value: gAmount}("");
        if (!success) revert TransferFailed();

        return gAmount;
    }

    /// @inheritdoc IStakeCredit
    function reactivateStake(address delegator, uint256 shares)
        external
        onlyDelegationOrValidatorManager
        returns (uint256 gAmount)
    {
        if (shares == 0) revert ZeroShares();
        if (pendingInactive == 0) revert NoWithdrawableAmount();

        // Calculate delegator's reactivatable amount in pendingInactive pool
        uint256 delegatorShares = balanceOf(delegator);
        if (delegatorShares == 0) revert InsufficientBalance();

        uint256 delegatorPendingInactiveAmount = (delegatorShares * pendingInactive) / totalSupply();
        if (delegatorPendingInactiveAmount == 0) revert NoWithdrawableAmount();

        // Calculate G amount, ensure it doesn't exceed user's share in pendingInactive
        gAmount = getPooledGByShares(shares);
        if (gAmount > delegatorPendingInactiveAmount) {
            gAmount = delegatorPendingInactiveAmount;
        }

        // Move from pendingInactive to active
        if (pendingInactive >= gAmount) {
            pendingInactive -= gAmount;
            active += gAmount;

            emit StakeReactivated(delegator, shares, gAmount);
            return gAmount;
        } else {
            revert InsufficientBalance();
        }
    }

    /// @inheritdoc IStakeCredit
    function distributeReward(uint64 commissionRate) external payable onlyValidatorManager {
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

        // 2. Process unlock request
        if (hasUnlockRequest && pendingInactive > 0) {
            inactive += pendingInactive;
            pendingInactive = 0;
            hasUnlockRequest = false;
            unlockRequestedAt = 0;

            emit UnlockRequestProcessed(oldPendingInactive);
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
    function getPooledGByShares(uint256 shares) public view returns (uint256) {
        uint256 totalPooled = getTotalPooledG();
        if (totalSupply() == 0) revert ZeroTotalShares();
        return (shares * totalPooled) / totalSupply();
    }

    /// @inheritdoc IStakeCredit
    function getSharesByPooledG(uint256 gAmount) public view returns (uint256) {
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
    function getPooledGByDelegator(address delegator) public view returns (uint256) {
        return getPooledGByShares(balanceOf(delegator));
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
            hasUnlockRequest
        );
    }

    /// @inheritdoc IStakeCredit
    function updateBeneficiary(address newBeneficiary) external {
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
        return (hasUnlockRequest, unlockRequestedAt);
    }
}
