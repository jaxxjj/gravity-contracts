// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

interface IParamSubscriber {
    function updateParam(string calldata key, bytes calldata value) external;
}
