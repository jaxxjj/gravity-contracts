// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "@src/System.sol";
import "@src/interfaces/IParamSubscriber.sol";
import "@src/interfaces/ISystemReward.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

contract SystemReward is System, IParamSubscriber, ISystemReward {
    uint256 public constant MAX_REWARDS = 10000 ether;

    uint256 public numAuthorizedCaller;
    mapping(address => bool) authorizedCallers;

    modifier doInit() {
        if (!alreadyInit) {
            authorizedCallers[VALIDATOR_MANAGER_ADDR] = true;
            numAuthorizedCaller = 1;
            alreadyInit = true;
        }
        _;
    }

    modifier onlyAuthorizedCaller() {
        require(authorizedCallers[msg.sender], "only authorized caller is allowed to call the method");
        _;
    }

    event rewardTo(address indexed to, uint256 amount);
    event rewardEmpty();
    event receiveDeposit(address indexed from, uint256 amount);
    event addAuthorizedCaller(address indexed authorizedCaller);
    event deleteAuthorizedCaller(address indexed authorizedCaller);
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
        onlyAuthorizedCaller
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

    function isAuthorizedCaller(address addr) external view returns (bool) {
        return authorizedCallers[addr];
    }

    function updateParam(string calldata key, bytes calldata value) external override onlyGov {
        if (Strings.equal(key, "addAuthorizedCaller")) {
            bytes memory valueLocal = value;
            require(valueLocal.length == 20, "length of value for addAuthorizedCaller should be 20");
            address authorizedCallerAddr = address(uint160(uint256(bytes32(valueLocal))));
            authorizedCallers[authorizedCallerAddr] = true;
            emit addAuthorizedCaller(authorizedCallerAddr);
        } else if (Strings.equal(key, "deleteAuthorizedCaller")) {
            bytes memory valueLocal = value;
            require(valueLocal.length == 20, "length of value for deleteAuthorizedCaller should be 20");
            address authorizedCallerAddr = address(uint160(uint256(bytes32(valueLocal))));
            delete authorizedCallers[authorizedCallerAddr];
            emit deleteAuthorizedCaller(authorizedCallerAddr);
        } else {
            require(false, "unknown param");
        }
        emit paramChange(key, value);
    }
}
