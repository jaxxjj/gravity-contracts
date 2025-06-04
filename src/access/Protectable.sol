// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

import "@src/System.sol";

abstract contract Protectable is System {
    /*----------------- storage -----------------*/
    bool private _paused;
    mapping(address => bool) public blackList;

    /*----------------- errors -----------------*/
    // @notice signature: 0x1785c681
    error AlreadyPaused();
    error NotPaused();
    // @notice signature: 0xb1d02c3d
    error InBlackList();

    /*----------------- events -----------------*/
    event Paused();
    event Resumed();
    event BlackListed(address indexed target);
    event UnBlackListed(address indexed target);

    /*----------------- modifier -----------------*/
    modifier whenNotPaused() {
        if (_paused) revert AlreadyPaused();
        _;
    }

    modifier whenPaused() {
        if (!_paused) revert NotPaused();
        _;
    }

    modifier notInBlackList() {
        if (blackList[msg.sender]) revert InBlackList();
        _;
    }

    /*----------------- external functions -----------------*/
    /**
     * @return whether the system is paused
     */
    function isPaused() external view returns (bool) {
        return _paused;
    }

    /**
     * @dev Pause the whole system in emergency
     */
    function pause() external virtual onlyGov whenNotPaused {
        _paused = true;
        emit Paused();
    }

    /**
     * @dev Resume the whole system
     */
    function resume() external virtual onlyGov whenPaused {
        _paused = false;
        emit Resumed();
    }

    /**
     * @dev Add an address to the black list
     */
    function addToBlackList(
        address account
    ) external virtual onlyGov {
        blackList[account] = true;
        emit BlackListed(account);
    }

    /**
     * @dev Remove an address from the black list
     */
    function removeFromBlackList(
        address account
    ) external virtual onlyGov {
        delete blackList[account];
        emit UnBlackListed(account);
    }
}
