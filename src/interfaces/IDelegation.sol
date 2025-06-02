// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

/**
 * @title IDelegation
 * @dev Interface for the Delegation contract
 */
interface IDelegation {
    // ======== 错误定义 ========
    error Delegation__ValidatorNotRegistered(address validator);
    error Delegation__NotOperator(address caller, address validator);
    error Delegation__NotValidatorOwner(address caller, address validator);
    error Delegation__ZeroShares();
    error Delegation__LessThanMinDelegationChange();
    error Delegation__SameValidator();
    error Delegation__OnlySelfDelegationToJailedValidator();
    error Delegation__TransferFailed();
    // ======== 事件 ========

    event Delegated(address indexed validator, address indexed delegator, uint256 shares, uint256 bnbAmount);
    event Undelegated(address indexed validator, address indexed delegator, uint256 shares, uint256 gAmount);
    event UnbondedTokensWithdrawn(address indexed delegator, uint256 amount);
    event NewEpoch(uint256 indexed epoch, uint256 epochTransitionTime);
    event Redelegated(
        address indexed srcValidator,
        address indexed dstValidator,
        address indexed delegator,
        uint256 shares,
        uint256 newShares,
        uint256 bnbAmount,
        uint256 feeCharge
    );
    event VoteDelegated(address indexed delegator, address indexed voter);

    // ======== 核心功能 ========
    /**
     * @dev 向验证者质押
     * @param validator 验证者地址
     */
    function delegate(address validator) external payable;

    /**
     * @dev 解除质押
     * @param validator 验证者地址
     * @param shares 要解除的份额
     */
    function undelegate(address validator, uint256 shares) external;

    /**
     * @dev 提取解绑的资金
     * @param validator 验证者地址
     * @param requestCount 要处理的请求数量
     */
    function claim(address validator, uint256 requestCount) external;

    /**
     * @dev 重新委托质押从一个验证者到另一个
     * @param srcValidator 源验证者地址
     * @param dstValidator 目标验证者地址
     * @param shares 要重新委托的份额
     * @param delegateVotePower 是否同时委托投票权
     */
    function redelegate(address srcValidator, address dstValidator, uint256 shares, bool delegateVotePower) external;

    /**
     * @dev 委托投票权给指定地址
     * @param voter 接收投票权的地址
     */
    function delegateVoteTo(address voter) external;
}
