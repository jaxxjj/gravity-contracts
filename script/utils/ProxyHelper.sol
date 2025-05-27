// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

/**
 * @title ProxyHelper
 * @notice 用于简化代理合约存储槽访问的工具库
 * @dev 适用于OpenZeppelin ERC1967代理合约
 */
library ProxyHelper {
    // ERC1967实现槽的位置
    bytes32 internal constant IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    // ERC1967管理员槽的位置
    bytes32 internal constant ADMIN_SLOT = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;

    /**
     * @notice 获取代理合约的实现地址
     * @param proxy 代理合约地址
     * @return implementationAddress 实现合约地址
     */
    function getProxyImplementation(address proxy) internal view returns (address implementationAddress) {
        // 从指定的代理合约地址读取存储槽
        // 注意：我们需要使用低级调用来读取存储槽
        bool success;
        bytes memory returnData;

        // 尝试调用EIP-1967兼容的实现获取方法
        bytes memory data = abi.encodeWithSignature("implementation()");
        (success, returnData) = proxy.staticcall(data);

        if (success && returnData.length == 32) {
            // 如果函数调用成功，解码返回值
            implementationAddress = abi.decode(returnData, (address));
        } else {
            // 否则直接从存储槽读取
            bytes32 slot = IMPLEMENTATION_SLOT;
            assembly {
                implementationAddress := sload(slot)
            }
        }
    }

    /**
     * @notice 获取代理合约的管理员地址
     * @param proxy 代理合约地址
     * @return adminAddress 管理员地址
     */
    function getProxyAdmin(address proxy) internal view returns (address adminAddress) {
        // 从指定的代理合约地址读取存储槽
        // 注意：我们需要使用低级调用来读取存储槽
        bool success;
        bytes memory returnData;

        // 尝试调用EIP-1967兼容的管理员获取方法
        bytes memory data = abi.encodeWithSignature("admin()");
        (success, returnData) = proxy.staticcall(data);

        if (success && returnData.length == 32) {
            // 如果函数调用成功，解码返回值
            adminAddress = abi.decode(returnData, (address));
        } else {
            // 否则直接从存储槽读取
            bytes32 slot = ADMIN_SLOT;
            assembly {
                adminAddress := sload(slot)
            }
        }
    }
}
