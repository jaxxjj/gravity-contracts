// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "@src/System.sol";
import "@src/interfaces/IParamSubscriber.sol";
import "@src/interfaces/ISystemReward.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

contract SystemReward is System, IParamSubscriber, ISystemReward {
    uint256 public constant MAX_REWARDS = 5e18;

    uint256 public numOperator;
    mapping(address => bool) operators;

    modifier doInit() {
        if (!alreadyInit) {
            alreadyInit = true;
        }
        _;
    }

    modifier onlyOperator() {
        require(operators[msg.sender], "only operator is allowed to call the method");
        _;
    }

    event rewardTo(address indexed to, uint256 amount);
    event rewardEmpty();
    event receiveDeposit(address indexed from, uint256 amount);
    event addOperator(address indexed operator);
    event deleteOperator(address indexed operator);
    event paramChange(string key, bytes value);

    receive() external payable {
        if (msg.value > 0) {
            emit receiveDeposit(msg.sender, msg.value);
        }
    }

    function claimRewards(address payable to, uint256 amount)
        external
        override(ISystemReward)
        doInit
        onlyOperator
        returns (uint256)
    {
        uint256 actualAmount = amount < address(this).balance ? amount : address(this).balance;
        if (actualAmount > MAX_REWARDS) {
            actualAmount = MAX_REWARDS;
        }
        if (actualAmount != 0) {
            to.transfer(actualAmount);
            emit rewardTo(to, actualAmount);
        } else {
            emit rewardEmpty();
        }
        return actualAmount;
    }

    function isOperator(address addr) external view returns (bool) {
        return operators[addr];
    }

    function updateParam(string calldata key, bytes calldata value) external override onlyGov {
        if (Strings.equal(key, "addOperator")) {
            bytes memory valueLocal = value;
            require(valueLocal.length == 20, "length of value for addOperator should be 20");
            address operatorAddr = address(uint160(uint256(bytes32(valueLocal))));
            operators[operatorAddr] = true;
            emit addOperator(operatorAddr);
        } else if (Strings.equal(key, "deleteOperator")) {
            bytes memory valueLocal = value;
            require(valueLocal.length == 20, "length of value for deleteOperator should be 20");
            address operatorAddr = address(uint160(uint256(bytes32(valueLocal))));
            delete operators[operatorAddr];
            emit deleteOperator(operatorAddr);
        } else {
            require(false, "unknown param");
        }
        emit paramChange(key, value);
    }
}
