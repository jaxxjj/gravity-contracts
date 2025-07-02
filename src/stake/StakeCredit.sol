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
 * @dev Implements a shares-based staking mechanism with Aptos-style epoch transitions
 * Layer 1: State pools (active, inactive, pendingActive, pendingInactive)
 * Uses epoch-based state transitions where pendingInactive becomes claimable after epoch
 */
contract StakeCredit is Initializable, ERC20Upgradeable, ReentrancyGuardUpgradeable, System, IStakeCredit {

    uint256 private constant COMMISSION_RATE_BASE = 10_000; // 100%

    // State model - Layer 1: State Pools
    uint256 public active;
    uint256 public inactive;
    uint256 public pendingActive;
    uint256 public pendingInactive;

    // Removed UnlockRequest mechanism - using pure Aptos model

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

        // Move to pending_inactive state (Aptos model)
        pendingInactive += gAmount;

        emit StakeUnlocked(delegator, shares, gAmount);
        return gAmount;
    }

    /// @inheritdoc IStakeCredit
    function claim(
        address payable delegator
    ) external onlyDelegationOrValidatorManager nonReentrant returns (uint256 amount) {
        // In Aptos model, users can claim their inactive funds after epoch transition
        uint256 userPooledG = getPooledGByDelegator(delegator);
        
        // Calculate claimable amount from inactive pool
        if (userPooledG == 0) revert StakeCredit__NoClaimableRequest();
        
        // Check total pooled to get proportional share
        uint256 totalPooled = getTotalPooledG();
        if (totalPooled == 0) revert ZeroTotalPooledTokens();
        
        // Calculate user's share of inactive pool
        amount = (inactive * userPooledG) / totalPooled;
        
        if (amount == 0) revert StakeCredit__NoClaimableRequest();
        if (inactive < amount) revert InsufficientBalance();
        
        // Update state
        inactive -= amount;
        
        // Burn proportional shares
        uint256 sharesToBurn = (balanceOf(delegator) * amount) / userPooledG;
        _burn(delegator, sharesToBurn);
        
        // Transfer funds
        (bool success,) = delegator.call{ value: amount }("");
        if (!success) revert TransferFailed();

        emit StakeWithdrawn(delegator, amount);
        return amount;
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

        // In Aptos model, we can reactivate a portion of pendingInactive stake
        // Calculate proportional amount based on user's share of pendingInactive
        uint256 userPooledG = getPooledGByDelegator(delegator);
        if (userPooledG == 0) revert NoWithdrawableAmount();
        
        // Calculate user's share of pendingInactive
        uint256 totalPooled = getTotalPooledG();
        uint256 userPendingInactive = (pendingInactive * userPooledG) / totalPooled;
        
        // Calculate amount to reactivate based on shares
        gAmount = getPooledGByShares(shares);
        if (gAmount > userPendingInactive) {
            gAmount = userPendingInactive; // Cap at user's pendingInactive
        }

        // Move from pendingInactive back to active
        pendingInactive -= gAmount;
        active += gAmount;

        // Shares remain the same (no mint needed, just state change)

        emit StakeReactivated(delegator, shares, gAmount);
        
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
     * @dev Get user's claimable amount in Aptos model
     * Returns proportional share of inactive pool
     */
    function getClaimableAmount(
        address delegator
    ) external view returns (uint256) {
        if (inactive == 0) return 0;
        
        uint256 userPooledG = getPooledGByDelegator(delegator);
        if (userPooledG == 0) return 0;
        
        uint256 totalPooled = getTotalPooledG();
        if (totalPooled == 0) return 0;
        
        // User's proportional share of inactive pool
        return (inactive * userPooledG) / totalPooled;
    }

    /**
     * @dev Checks if validator is current epoch validator
     */
    function _isCurrentEpochValidator() internal view returns (bool) {
        return IValidatorManager(VALIDATOR_MANAGER_ADDR).isCurrentEpochValidator(validator);
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
            pendingInactive > 0 // In Aptos model, check if there's any pendingInactive
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

    /**
     * @dev Get pending unlock amount for a delegator
     * Returns user's proportional share of pendingInactive pool
     */
    function getPendingUnlockAmount(
        address delegator
    ) external view returns (uint256) {
        if (pendingInactive == 0) return 0;
        
        uint256 userPooledG = getPooledGByDelegator(delegator);
        if (userPooledG == 0) return 0;
        
        uint256 totalPooled = getTotalPooledG();
        if (totalPooled == 0) return 0;
        
        // User's proportional share of pendingInactive pool
        return (pendingInactive * userPooledG) / totalPooled;
    }

    /**
     * @dev Process matured unlocks for a specific user
     * In Aptos model, this is a no-op as processing happens automatically at epoch
     */
    function processUserUnlocks(
        address user
    ) external {
        // In Aptos model, unlock processing happens automatically during epoch transition
        // This function is kept for interface compatibility but does nothing
    }

    /// @inheritdoc IStakeCredit
    function getUnlockRequestStatus() external view returns (bool hasRequest, uint256 requestedAt) {
        // In Aptos model, check if user has any pendingInactive stake
        uint256 userPooledG = getPooledGByDelegator(msg.sender);
        if (userPooledG == 0) return (false, 0);
        
        uint256 totalPooled = getTotalPooledG();
        if (totalPooled == 0) return (false, 0);
        
        // Check if user has share of pendingInactive
        uint256 userPendingInactive = (pendingInactive * userPooledG) / totalPooled;
        hasRequest = userPendingInactive > 0;
        
        // In Aptos model, requestedAt is not applicable (epoch-based)
        requestedAt = 0;
        
        return (hasRequest, requestedAt);
    }
}
