// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

/**
 * @title IReconfigurableModule
 * @dev 定义可重配置模块的接口，这些模块需要响应new epoch
 */
interface IReconfigurableModule {
    /**
     * @dev 在new epoch开始时被调用，允许模块更新其状态
     */
    function onNewEpoch() external;
}
