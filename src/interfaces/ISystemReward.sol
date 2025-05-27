// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

interface ISystemReward {
    function claimRewards(address payable to, uint256 amount) external returns (uint256 actualAmount);
}
