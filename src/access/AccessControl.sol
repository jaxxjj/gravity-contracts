// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@src/System.sol";
import "@src/interfaces/IAccessControl.sol";
/**
 * @title AccessControl
 * @dev 纯粹的权限注册表，只负责记录和查询权限映射
 * 简化的角色结构：owner, operator（包含agent功能）, delegatedVoter
 */

contract AccessControl is Ownable, System, IAccessControl {
    using EnumerableSet for EnumerableSet.AddressSet;

    // ======== 角色定义 ========

    /**
     * @dev 验证者角色结构（简化版）
     * 参考Aptos StakePool的角色分配，合并operator和agent
     */

    // ======== 存储映射 ========

    // 验证者地址 => 角色信息
    mapping(address => ValidatorRoles) private _validatorRoles;

    // 反向映射，用于快速查找
    mapping(address => address) public operatorToValidator; // 操作员 => 验证者
    mapping(address => address) public voterToValidator; // 投票者 => 验证者

    // 注册的验证者集合
    EnumerableSet.AddressSet private _registeredValidators;

    // 授权的模块合约（只有这些合约可以修改权限映射）
    mapping(address => bool) public authorizedModules;

    modifier validatorExists(address validator) {
        if (!_validatorRoles[validator].exists) {
            revert AccessControl__ValidatorNotRegistered(validator);
        }
        _;
    }

    /**
     * @dev 验证调用者是否为验证者的所有者
     * @param validator 验证者地址
     */
    modifier onlyValidatorOwner(address validator) {
        if (msg.sender != _validatorRoles[validator].owner) {
            revert AccessControl__NotOwner(msg.sender, validator);
        }
        _;
    }

    /**
     * @dev 验证提供的地址是否不为零地址
     * @param addr 要验证的地址
     */
    modifier validAddress(address addr) {
        if (addr == address(0)) {
            revert AccessControl__InvalidAddress(addr);
        }
        _;
    }

    // ======== 构造函数 ========

    constructor() Ownable(msg.sender) {
        // 构造函数中不设置任何授权模块，需要后续手动添加
    }

    // ======== 权限映射管理（只能由授权模块调用） ========

    /**
     * @dev 注册新的验证者角色映射
     * @param validator 验证者地址
     * @param owner 所有者地址
     * @param operator 操作员地址（
     * @param delegatedVoter 委托投票者地址
     * @param commissionBeneficiary 佣金受益人地址
     */
    function registerValidatorRoles(
        address validator,
        address owner,
        address operator,
        address delegatedVoter,
        address commissionBeneficiary
    ) external onlyValidatorManager {
        if (_validatorRoles[validator].exists) {
            revert AccessControl__ValidatorAlreadyRegistered(validator);
        }

        _validateAddresses(validator, owner, operator, delegatedVoter);
        _checkAddressConflicts(validator, operator);

        // 设置角色，默认佣金受益人为操作员
        _validatorRoles[validator] = ValidatorRoles({
            owner: owner,
            operator: operator,
            delegatedVoter: delegatedVoter,
            commissionBeneficiary: commissionBeneficiary != address(0) ? commissionBeneficiary : operator,
            exists: true
        });

        // 更新反向映射
        operatorToValidator[operator] = validator;
        voterToValidator[delegatedVoter] = validator;

        // 添加到注册集合
        _registeredValidators.add(validator);

        emit ValidatorRoleRegistered(validator, owner, operator);
    }

    /**
     * @dev 更新验证者所有者 - 只有当前owner可以转移所有权
     */
    function updateOwner(address validator, address newOwner)
        external
        validatorExists(validator)
        onlyValidatorOwner(validator)
        validAddress(newOwner)
    {
        address oldOwner = _validatorRoles[validator].owner;
        _validatorRoles[validator].owner = newOwner;

        emit OwnerUpdated(validator, oldOwner, newOwner);
    }

    /**
     * @dev 更新验证者操作员 - 只有owner可以更改operator
     */
    function updateOperator(address validator, address newOperator)
        external
        validatorExists(validator)
        onlyValidatorOwner(validator)
        validAddress(newOperator)
    {
        // 检查新操作员是否已被其他验证者使用
        if (operatorToValidator[newOperator] != address(0) && operatorToValidator[newOperator] != validator) {
            revert AccessControl__AddressAlreadyInUse(newOperator, operatorToValidator[newOperator]);
        }

        address oldOperator = _validatorRoles[validator].operator;

        // 更新反向映射
        if (oldOperator != address(0)) {
            delete operatorToValidator[oldOperator];
        }
        operatorToValidator[newOperator] = validator;

        _validatorRoles[validator].operator = newOperator;

        emit OperatorUpdated(validator, oldOperator, newOperator);
    }

    /**
     * @dev 更新委托投票者 - 只有owner可以更改voter
     */
    function updateDelegatedVoter(address validator, address newVoter)
        external
        validatorExists(validator)
        onlyValidatorOwner(validator)
        validAddress(newVoter)
    {
        address oldVoter = _validatorRoles[validator].delegatedVoter;
        _updateVoterMapping(validator, oldVoter, newVoter);
        _validatorRoles[validator].delegatedVoter = newVoter;

        emit DelegatedVoterUpdated(validator, oldVoter, newVoter);
    }

    /**
     * @dev 更新佣金受益人 - 只有owner可以更改佣金受益人
     */
    function updateCommissionBeneficiary(address validator, address newBeneficiary)
        external
        validatorExists(validator)
        onlyValidatorOwner(validator)
        validAddress(newBeneficiary)
    {
        address oldBeneficiary = _validatorRoles[validator].commissionBeneficiary;
        _validatorRoles[validator].commissionBeneficiary = newBeneficiary;

        emit CommissionBeneficiaryUpdated(validator, oldBeneficiary, newBeneficiary);
    }

    /**
     * @dev 检查是否为验证者所有者
     */
    function isOwner(address validator, address account) public view returns (bool) {
        return _validatorRoles[validator].exists && _validatorRoles[validator].owner == account;
    }

    /**
     * @dev 检查是否为验证者操作员
     */
    function isOperator(address validator, address account) public view returns (bool) {
        return _validatorRoles[validator].exists && _validatorRoles[validator].operator == account;
    }

    /**
     * @dev 检查是否为验证者的委托投票者
     */
    function isDelegatedVoter(address validator, address account) public view returns (bool) {
        return _validatorRoles[validator].exists && _validatorRoles[validator].delegatedVoter == account;
    }

    /**
     * @dev 综合权限检查：是否可以执行操作员权限操作
     * 包括：owner, operator（operator已包含原agent功能）
     */
    function hasOperatorPermission(address validator, address account) public view returns (bool) {
        if (!_validatorRoles[validator].exists) return false;

        ValidatorRoles storage roles = _validatorRoles[validator];
        return account == roles.owner || account == roles.operator;
    }

    /**
     * @dev 检查是否有所有者权限（只有owner）
     */
    function hasOwnerPermission(address validator, address account) public view returns (bool) {
        return isOwner(validator, account);
    }

    /**
     * @dev 检查是否有投票权限
     */
    function hasVotingPermission(address validator, address account) public view returns (bool) {
        return isDelegatedVoter(validator, account);
    }

    /**
     * @dev 获取验证者的所有角色信息
     */
    function getValidatorRoles(address validator)
        external
        view
        validatorExists(validator)
        returns (ValidatorRoles memory)
    {
        return _validatorRoles[validator];
    }

    /**
     * @dev 获取验证者所有者
     */
    function getOwner(address validator) external view validatorExists(validator) returns (address) {
        return _validatorRoles[validator].owner;
    }

    /**
     * @dev 获取验证者操作员
     */
    function getOperator(address validator) external view validatorExists(validator) returns (address) {
        return _validatorRoles[validator].operator;
    }

    /**
     * @dev 获取验证者委托投票者
     */
    function getDelegatedVoter(address validator) external view validatorExists(validator) returns (address) {
        return _validatorRoles[validator].delegatedVoter;
    }

    /**
     * @dev 获取佣金受益人
     */
    function getCommissionBeneficiary(address validator) external view validatorExists(validator) returns (address) {
        return _validatorRoles[validator].commissionBeneficiary;
    }

    /**
     * @dev 获取所有注册的验证者
     */
    function getAllValidators() external view returns (address[] memory) {
        return _registeredValidators.values();
    }

    /**
     * @dev 检查验证者是否已注册
     */
    function isValidatorRegistered(address validator) external view returns (bool) {
        return _validatorRoles[validator].exists;
    }

    /**
     * @dev 获取验证者数量
     */
    function getValidatorCount() external view returns (uint256) {
        return _registeredValidators.length();
    }

    // ======== 内部辅助函数 ========

    /**
     * @dev 验证地址有效性
     */
    function _validateAddresses(address validator, address owner, address operator, address delegatedVoter)
        private
        pure
    {
        if (validator == address(0) || owner == address(0) || operator == address(0) || delegatedVoter == address(0)) {
            revert AccessControl__InvalidAddress(address(0));
        }
    }

    /**
     * @dev 检查地址冲突
     */
    function _checkAddressConflicts(address validator, address operator) private view {
        // 检查操作员地址是否已被使用
        if (operatorToValidator[operator] != address(0)) {
            revert AccessControl__AddressAlreadyInUse(operator, operatorToValidator[operator]);
        }
    }

    /**
     * @dev 更新投票者映射
     */
    function _updateVoterMapping(address validator, address oldVoter, address newVoter) private {
        if (oldVoter != address(0) && voterToValidator[oldVoter] == validator) {
            delete voterToValidator[oldVoter];
        }
        voterToValidator[newVoter] = validator;
    }
}
