// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

contract ValidatorManagerMock {
    mapping(address => bool) public isCurrentEpochValidatorMap;
    mapping(address => uint64) public validatorIndexMap;
    bool public initialized;

    function initialize(
        address[] calldata validatorAddresses,
        address[] calldata consensusAddresses,
        address payable[] calldata feeAddresses,
        uint64[] calldata votingPowers,
        bytes[] calldata voteAddresses
    ) external {
        initialized = true;
        // Store the validators for testing
        for (uint256 i = 0; i < validatorAddresses.length; i++) {
            isCurrentEpochValidatorMap[validatorAddresses[i]] = true;
            validatorIndexMap[validatorAddresses[i]] = uint64(i);
        }
    }

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
