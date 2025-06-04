// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

contract ValidatorManagerMock {
    mapping(address => bool) public isCurrentEpochValidatorMap;
    mapping(address => uint64) public validatorIndexMap;

    function setIsCurrentEpochValidator(address validator, bool isValidator) external {
        isCurrentEpochValidatorMap[validator] = isValidator;
    }

    function setValidatorIndex(address validator, uint64 index) external {
        validatorIndexMap[validator] = index;
    }

    function isCurrentEpochValidator(address validator) external view returns (bool) {
        return isCurrentEpochValidatorMap[validator];
    }

    function getValidatorIndex(address validator) external view returns (uint64) {
        require(isCurrentEpochValidatorMap[validator], "ValidatorNotActive");
        return validatorIndexMap[validator];
    }
}
