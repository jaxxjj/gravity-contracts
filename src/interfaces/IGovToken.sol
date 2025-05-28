// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import "@openzeppelin/contracts/governance/utils/IVotes.sol";

/**
 * @title IGovToken
 * @dev Interface for BSC Governance Token (govBNB)
 * @notice This interface defines the governance token functionality for BSC staking
 */
interface IGovToken {
    /*----------------- errors -----------------*/
    /// @notice Thrown when attempting to transfer tokens (transfers are not allowed)
    error TransferNotAllowed();

    /// @notice Thrown when attempting to approve tokens (approvals are not allowed)
    error ApproveNotAllowed();

    /// @notice Thrown when attempting to burn tokens (burning is not allowed)
    error BurnNotAllowed();

    /*----------------- view functions -----------------*/
    /**
     * @dev Returns the amount of tokens minted for a specific stake credit and account
     * @param stakeCredit The stake credit contract address
     * @param account The user account address
     * @return The amount of tokens minted for this combination
     */
    function mintedMap(address stakeCredit, address account) external view returns (uint256);

    /*----------------- external functions -----------------*/
    /**
     * @dev Initialize the contract (can only be called once)
     * @notice Must be called by coinbase with zero gas price
     */
    function initialize() external;

    /**
     * @dev Sync the account's govBNB amount to the actual BNB value of the StakingCredit
     * @param stakeCredit The stakeCredit Token contract address
     * @param account The account to sync gov tokens to
     * @notice Can only be called by StakeHub
     */
    function sync(address stakeCredit, address account) external;

    /**
     * @dev Batch sync accounts' govBNB amounts to actual BNB values of StakingCredits
     * @param stakeCredits Array of stakeCredit Token contract addresses
     * @param account The account to sync gov tokens to
     * @notice Can only be called by StakeHub
     */
    function syncBatch(address[] calldata stakeCredits, address account) external;

    /**
     * @dev Delegate govBNB votes from delegator to delegatee
     * @param delegator The address delegating votes
     * @param delegatee The address receiving delegated votes
     * @notice Can only be called by StakeHub
     */
    function delegateVote(address delegator, address delegatee) external;

    /**
     * @dev Burn tokens (disabled - will always revert)
     * @param amount Amount to burn (ignored)
     * @notice This function is disabled and will always revert
     */
    function burn(uint256 amount) external;

    /**
     * @dev Burn tokens from account (disabled - will always revert)
     * @param account Account to burn from (ignored)
     * @param amount Amount to burn (ignored)
     * @notice This function is disabled and will always revert
     */
    function burnFrom(address account, uint256 amount) external pure;

    function totalSupply() external view returns (uint256);
}

/**
 * @title IGovTokenEvents
 * @dev Additional events that may be emitted by GovToken
 * @notice These events are inherited from OpenZeppelin contracts but listed for completeness
 */
interface IGovTokenEvents {
    /// @notice Emitted when tokens are transferred (including mint/burn)
    /// @dev Inherited from IERC20
    event Transfer(address indexed from, address indexed to, uint256 value);

    /// @notice Emitted when allowance is set (though approvals are disabled)
    /// @dev Inherited from IERC20
    event Approval(address indexed owner, address indexed spender, uint256 value);

    /// @notice Emitted when votes are delegated
    /// @dev Inherited from IVotes
    event DelegateChanged(address indexed delegator, address indexed fromDelegate, address indexed toDelegate);

    /// @notice Emitted when delegate vote weight changes
    /// @dev Inherited from IVotes
    event DelegateVotesChanged(address indexed delegate, uint256 previousBalance, uint256 newBalance);
}

/**
 * @title IGovTokenErrors
 * @dev Additional errors that may be thrown by GovToken
 * @notice These errors are inherited from OpenZeppelin contracts but listed for completeness
 */
interface IGovTokenErrors {
    /// @notice Insufficient balance for transfer
    error ERC20InsufficientBalance(address sender, uint256 balance, uint256 needed);

    /// @notice Invalid sender address
    error ERC20InvalidSender(address sender);

    /// @notice Invalid receiver address
    error ERC20InvalidReceiver(address receiver);

    /// @notice Insufficient allowance
    error ERC20InsufficientAllowance(address spender, uint256 allowance, uint256 needed);

    /// @notice Invalid approver address
    error ERC20InvalidApprover(address approver);

    /// @notice Invalid spender address
    error ERC20InvalidSpender(address spender);
}
