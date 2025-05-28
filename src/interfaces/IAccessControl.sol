// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

/**
 * @title IAccessControl
 * @dev 简化的访问控制接口
 * 角色结构：owner, operator（合并了agent功能）, delegatedVoter, commissionBeneficiary
 */
interface IAccessControl {
    struct ValidatorRoles {
        address owner; // 质押池所有者，拥有最高权限
        address operator; // 验证者操作员，负责日常操作）
        address delegatedVoter; // 委托投票者，负责治理投票
        address commissionBeneficiary; // 佣金受益人，接收验证者佣金
        bool exists; // 验证者是否存在
    }

    error AccessControl__ValidatorNotRegistered(address validator);
    error AccessControl__ValidatorAlreadyRegistered(address validator);
    error AccessControl__InvalidAddress(address addr);
    error AccessControl__AddressAlreadyInUse(address addr, address currentValidator);
    error AccessControl__OnlyAuthorizedModule();
    error AccessControl__NotOwner(address caller, address validator);

    function registerValidatorRoles(
        address validator,
        address owner,
        address operator,
        address delegatedVoter,
        address commissionBeneficiary
    ) external;

    function updateOwner(address validator, address newOwner) external;
    function updateOperator(address validator, address newOperator) external;
    function updateDelegatedVoter(address validator, address newVoter) external;
    function updateCommissionBeneficiary(address validator, address newBeneficiary) external;

    function isOwner(address validator, address account) external view returns (bool);
    function isOperator(address validator, address account) external view returns (bool);
    function isDelegatedVoter(address validator, address account) external view returns (bool);
    function hasOperatorPermission(address validator, address account) external view returns (bool);
    function hasOwnerPermission(address validator, address account) external view returns (bool);
    function hasVotingPermission(address validator, address account) external view returns (bool);

    function getValidatorRoles(address validator) external view returns (ValidatorRoles memory);
    function getOwner(address validator) external view returns (address);
    function getOperator(address validator) external view returns (address);
    function getDelegatedVoter(address validator) external view returns (address);
    function getCommissionBeneficiary(address validator) external view returns (address);
    function getAllValidators() external view returns (address[] memory);
    function isValidatorRegistered(address validator) external view returns (bool);
    function getValidatorCount() external view returns (uint256);

    function operatorToValidator(address operator) external view returns (address);
    function voterToValidator(address voter) external view returns (address);

    event ValidatorRoleRegistered(address indexed validator, address indexed owner, address indexed operator);
    event ValidatorRoleRemoved(address indexed validator);
    event OwnerUpdated(address indexed validator, address indexed oldOwner, address indexed newOwner);
    event OperatorUpdated(address indexed validator, address indexed oldOperator, address indexed newOperator);
    event DelegatedVoterUpdated(address indexed validator, address indexed oldVoter, address indexed newVoter);
    event CommissionBeneficiaryUpdated(
        address indexed validator, address indexed oldBeneficiary, address indexed newBeneficiary
    );
    event AuthorizedModuleUpdated(address indexed moduleAddr, bool authorized);
}
