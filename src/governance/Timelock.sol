// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

import "@openzeppelin-upgrades/governance/TimelockControllerUpgradeable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@src/System.sol";
import "@src/lib/Bytes.sol";

contract Timelock is System, Initializable, TimelockControllerUpgradeable {
    using Bytes for bytes;

    /*----------------- constants -----------------*/
    /*
     * @dev caution: minDelay using second as unit
     */
    uint256 private constant INIT_MINIMAL_DELAY = 24 hours;

    /*----------------- init -----------------*/
    function initialize() external initializer onlyCoinbase onlyZeroGasPrice {
        address[] memory _governor = new address[](1);
        _governor[0] = GOVERNOR_ADDR;
        __TimelockController_init(INIT_MINIMAL_DELAY, _governor, _governor, GOVERNOR_ADDR);
    }

    /*----------------- system functions -----------------*/
    /**
     * @param key the key of the param
     * @param value the value of the param
     */
    function updateParam(string calldata key, bytes calldata value) external onlyGov {
        if (Strings.equal(key, "minDelay")) {
            if (value.length != 32) revert InvalidValue(key, value);
            uint256 newMinDelay = value.bytesToUint256(32);
            if (newMinDelay == 0 || newMinDelay > 14 days) revert InvalidValue(key, value);
            this.updateDelay(newMinDelay);
        } else {
            revert UnknownParam(key, value);
        }
        emit ParamChange(key, value);
    }
}
