// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

contract GovTokenMock {
    uint256 private _totalSupply;
    mapping(address => uint256) private _balances;
    mapping(address => address) private _delegates;
    mapping(address => uint256) private _votingPower;

    function setTotalSupply(
        uint256 _newTotalSupply
    ) external {
        _totalSupply = _newTotalSupply;
    }

    function totalSupply() external view returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(
        address account
    ) external view returns (uint256) {
        return _balances[account];
    }

    function setBalance(address account, uint256 balance) external {
        _balances[account] = balance;
    }

    function getVotes(
        address account
    ) external view returns (uint256) {
        return _votingPower[account];
    }

    function setVotes(address account, uint256 votes) external {
        _votingPower[account] = votes;
    }

    function getPastVotes(address account, uint256 /* timepoint */ ) external view returns (uint256) {
        return _votingPower[account];
    }

    function getPastTotalSupply(
        uint256 /* timepoint */
    ) external view returns (uint256) {
        return _totalSupply;
    }

    function delegates(
        address account
    ) external view returns (address) {
        return _delegates[account];
    }

    function delegate(
        address delegatee
    ) external {
        _delegates[msg.sender] = delegatee;
    }

    function delegateVote(address, /* delegator */ address /* delegatee */ ) external pure {
        // Mock implementation - do nothing
    }

    function sync(address, /* stakeCredit */ address /* user */ ) external pure {
        // Mock implementation - do nothing
    }

    function syncBatch(address[] calldata, /* stakeCredits */ address /* user */ ) external pure {
        // Mock implementation - do nothing
    }

    function clock() external view returns (uint48) {
        return uint48(block.number);
    }

    function CLOCK_MODE() external pure returns (string memory) {
        return "mode=blocknumber&from=default";
    }
}
