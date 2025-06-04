// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

contract TimelockMock {
    bool public initialized;

    function initialize() external {
        initialized = true;
    }
}
