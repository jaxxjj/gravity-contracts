// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "@src/interfaces/IStakeCredit.sol";

contract StakeCreditMock is IStakeCredit {
    uint256 private _totalPooledG;

    // Allow receiving ETH for fee payments
    receive() external payable { }

    function setTotalPooledG(
        uint256 amount
    ) external {
        _totalPooledG = amount;
    }

    function getTotalPooledG() external view returns (uint256) {
        return _totalPooledG;
    }

    // ======== Required Interface Implementation ========
    // Most functions are not used in testing, so they revert or return defaults

    function initialize(address, string memory, address) external payable {
        revert("StakeCreditMock: not implemented");
    }

    function delegate(
        address
    ) external payable returns (uint256) {
        revert("StakeCreditMock: not implemented");
    }

    function unlock(address, uint256) external pure returns (uint256) {
        revert("StakeCreditMock: not implemented");
    }

    function unbond(address, uint256) external pure returns (uint256) {
        revert("StakeCreditMock: not implemented");
    }

    function reactivateStake(address, uint256) external pure returns (uint256) {
        revert("StakeCreditMock: not implemented");
    }

    function distributeReward(
        uint64
    ) external payable {
        revert("StakeCreditMock: not implemented");
    }

    function onNewEpoch() external pure {
        revert("StakeCreditMock: not implemented");
    }

    function updateBeneficiary(
        address
    ) external pure {
        revert("StakeCreditMock: not implemented");
    }

    function claim(
        address payable
    ) external pure returns (uint256) {
        revert("StakeCreditMock: not implemented");
    }

    function getClaimableAmount(
        address
    ) external pure returns (uint256) {
        return 0;
    }

    function getPendingUnlockAmount(
        address
    ) external pure returns (uint256) {
        return 0;
    }

    function processUserUnlocks(
        address
    ) external pure {
        revert("StakeCreditMock: not implemented");
    }

    function active() external pure returns (uint256) {
        return 0;
    }

    function inactive() external pure returns (uint256) {
        return 0;
    }

    function pendingActive() external pure returns (uint256) {
        return 0;
    }

    function pendingInactive() external pure returns (uint256) {
        return 0;
    }

    function validator() external pure returns (address) {
        return address(0);
    }

    function commissionBeneficiary() external pure returns (address) {
        return address(0);
    }

    function rewardRecord(
        uint256
    ) external pure returns (uint256) {
        return 0;
    }

    function totalPooledGRecord(
        uint256
    ) external pure returns (uint256) {
        return 0;
    }

    function getUnlockRequestStatus() external pure returns (bool, uint256) {
        return (false, 0);
    }

    function getPooledGByShares(
        uint256
    ) external pure returns (uint256) {
        return 0;
    }

    function getPooledGByDelegator(
        address
    ) external pure returns (uint256) {
        return 0;
    }

    function getSharesByDelegator(
        address
    ) external pure returns (uint256) {
        return 0;
    }

    function getSharesByPooledG(
        uint256
    ) external pure returns (uint256) {
        return 0;
    }

    function getStake() external pure returns (uint256, uint256, uint256, uint256) {
        return (0, 0, 0, 0);
    }

    function getNextEpochVotingPower() external pure returns (uint256) {
        return 0;
    }

    function getCurrentEpochVotingPower() external pure returns (uint256) {
        return 0;
    }

    function validateStakeStates() external pure returns (bool) {
        return true;
    }

    function getDetailedStakeInfo()
        external
        view
        returns (uint256, uint256, uint256, uint256, uint256, uint256, uint256, bool)
    {
        return (0, 0, 0, 0, _totalPooledG, 0, 0, false);
    }

    function balanceOf(
        address
    ) external pure returns (uint256) {
        return 0;
    }

    function totalSupply() external pure returns (uint256) {
        return 0;
    }

    function totalShares() external pure returns (uint256) {
        return 0;
    }

    function claimedEpoch() external pure returns (uint256) {
        return 0;
    }

    function lockedShares() external pure returns (uint256) {
        return 0;
    }

    function name() external pure returns (string memory) {
        return "StakeCreditMock";
    }

    function symbol() external pure returns (string memory) {
        return "SCM";
    }

    function decimals() external pure returns (uint8) {
        return 18;
    }

    function transfer(address, uint256) external pure returns (bool) {
        revert("StakeCreditMock: transfer not allowed");
    }

    function allowance(address, address) external pure returns (uint256) {
        return 0;
    }

    function approve(address, uint256) external pure returns (bool) {
        revert("StakeCreditMock: approve not allowed");
    }

    function transferFrom(address, address, uint256) external pure returns (bool) {
        revert("StakeCreditMock: transferFrom not allowed");
    }
}
