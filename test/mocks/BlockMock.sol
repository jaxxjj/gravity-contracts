// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

contract BlockMock {
    bool public initialized;

    function initialize() external {
        initialized = true;
    }
}
