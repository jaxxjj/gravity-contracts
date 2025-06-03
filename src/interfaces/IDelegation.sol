// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/**
 * @title IDelegation
 * @dev Interface for the Delegation contract
 */
interface IDelegation {
    // ======== Errors ========
    error Delegation__ValidatorNotRegistered(address validator);
    error Delegation__ZeroShares();
    error Delegation__LessThanMinDelegationChange();
    error Delegation__SameValidator();
    error Delegation__OnlySelfDelegationToJailedValidator();
    error Delegation__TransferFailed();

    // ======== Events ========
    event Delegated(address indexed validator, address indexed delegator, uint256 shares, uint256 amount);
    event Undelegated(address indexed validator, address indexed delegator, uint256 shares, uint256 amount);
    event UnbondedTokensWithdrawn(address indexed delegator, uint256 amount);
    event Redelegated(
        address indexed srcValidator,
        address indexed dstValidator,
        address indexed delegator,
        uint256 shares,
        uint256 newShares,
        uint256 amount,
        uint256 feeCharge
    );
    event VoteDelegated(address indexed delegator, address indexed voter);

    // ======== Core Functions ========
    /**
     * @dev Delegate tokens to a validator
     * @param validator The validator address to delegate to
     */
    function delegate(address validator) external payable;

    /**
     * @dev Undelegate tokens from a validator
     * @param validator The validator address to undelegate from
     * @param shares The amount of shares to undelegate
     */
    function undelegate(address validator, uint256 shares) external;

    /**
     * @dev Claim unbonded tokens
     * @param validator The validator address to claim from
     * @param requestCount The number of unbonding requests to process
     */
    function claim(address validator, uint256 requestCount) external;

    /**
     * @dev Redelegate tokens from one validator to another
     * @param srcValidator Source validator address
     * @param dstValidator Destination validator address
     * @param shares The amount of shares to redelegate
     * @param delegateVotePower Whether to also delegate voting power
     */
    function redelegate(address srcValidator, address dstValidator, uint256 shares, bool delegateVotePower) external;

    /**
     * @dev Delegate voting power to another address
     * @param voter The address to receive voting power
     */
    function delegateVoteTo(address voter) external;
}
