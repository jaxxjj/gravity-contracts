// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./interfaces/IJWKManager.sol";

/**
 * @title JWKUtils
 * @dev JWK操作的实用工具库
 */
library JWKUtils {
    using JWKUtils for IJWKManager.JWK;

    // ======== 错误定义 ========
    error InvalidJWKType();
    error InvalidRSAJWK();
    error EmptyKid();
    error EmptyModulus();
    error EmptyExponent();

    // ======== JWK创建函数 ========

    /**
     * @dev 创建RSA JWK
     * @param kid Key ID
     * @param alg 算法 (如 "RS256")
     * @param e 公共指数 (通常是 "AQAB")
     * @param n 模数 (Base64URL编码)
     */
    function newRSAJWK(
        string memory kid,
        string memory alg,
        string memory e,
        string memory n
    ) internal pure returns (IJWKManager.JWK memory) {
        if (bytes(kid).length == 0) revert EmptyKid();
        if (bytes(e).length == 0) revert EmptyExponent();
        if (bytes(n).length == 0) revert EmptyModulus();

        IJWKManager.RSA_JWK memory rsaJWK = IJWKManager.RSA_JWK({
            kid: kid,
            kty: "RSA",
            alg: alg,
            e: e,
            n: n
        });

        return IJWKManager.JWK({
            variant: 0, // RSA_JWK
            data: abi.encode(rsaJWK)
        });
    }

    /**
     * @dev 创建不支持的JWK
     * @param id JWK标识符
     * @param payload JWK原始数据
     */
    function newUnsupportedJWK(
        bytes memory id,
        bytes memory payload
    ) internal pure returns (IJWKManager.JWK memory) {
        IJWKManager.UnsupportedJWK memory unsupportedJWK = IJWKManager.UnsupportedJWK({
            id: id,
            payload: payload
        });

        return IJWKManager.JWK({
            variant: 1, // UnsupportedJWK
            data: abi.encode(unsupportedJWK)
        });
    }

    // ======== 补丁创建函数 ========

    /**
     * @dev 创建"移除所有"补丁
     */
    function newPatchRemoveAll() internal pure returns (IJWKManager.Patch memory) {
        return IJWKManager.Patch({
            patchType: IJWKManager.PatchType.RemoveAll,
            issuer: "",
            jwkId: "",
            jwk: IJWKManager.JWK({variant: 0, data: ""})
        });
    }

    /**
     * @dev 创建"移除发行者"补丁
     * @param issuer 要移除的发行者
     */
    function newPatchRemoveIssuer(
        string memory issuer
    ) internal pure returns (IJWKManager.Patch memory) {
        return IJWKManager.Patch({
            patchType: IJWKManager.PatchType.RemoveIssuer,
            issuer: issuer,
            jwkId: "",
            jwk: IJWKManager.JWK({variant: 0, data: ""})
        });
    }

    /**
     * @dev 创建"移除JWK"补丁
     * @param issuer 发行者
     * @param jwkId 要移除的JWK ID
     */
    function newPatchRemoveJWK(
        string memory issuer,
        bytes memory jwkId
    ) internal pure returns (IJWKManager.Patch memory) {
        return IJWKManager.Patch({
            patchType: IJWKManager.PatchType.RemoveJWK,
            issuer: issuer,
            jwkId: jwkId,
            jwk: IJWKManager.JWK({variant: 0, data: ""})
        });
    }

    /**
     * @dev 创建"插入或更新JWK"补丁
     * @param issuer 发行者
     * @param jwk 要插入或更新的JWK
     */
    function newPatchUpsertJWK(
        string memory issuer,
        IJWKManager.JWK memory jwk
    ) internal pure returns (IJWKManager.Patch memory) {
        return IJWKManager.Patch({
            patchType: IJWKManager.PatchType.UpsertJWK,
            issuer: issuer,
            jwkId: "",
            jwk: jwk
        });
    }

    // ======== JWK操作函数 ========

    /**
     * @dev 获取JWK的ID
     * @param jwk JWK结构体
     * @return JWK的ID
     */
    function getJWKId(IJWKManager.JWK memory jwk) internal pure returns (bytes memory) {
        if (jwk.variant == 0) {
            // RSA_JWK
            IJWKManager.RSA_JWK memory rsaJWK = abi.decode(jwk.data, (IJWKManager.RSA_JWK));
            return bytes(rsaJWK.kid);
        } else if (jwk.variant == 1) {
            // UnsupportedJWK
            IJWKManager.UnsupportedJWK memory unsupportedJWK = abi.decode(jwk.data, (IJWKManager.UnsupportedJWK));
            return unsupportedJWK.id;
        } else {
            revert InvalidJWKType();
        }
    }

    /**
     * @dev 解码RSA JWK
     * @param jwk JWK结构体
     * @return RSA JWK结构体
     */
    function toRSAJWK(IJWKManager.JWK memory jwk) internal pure returns (IJWKManager.RSA_JWK memory) {
        if (jwk.variant != 0) revert InvalidJWKType();
        return abi.decode(jwk.data, (IJWKManager.RSA_JWK));
    }

    /**
     * @dev 解码不支持的JWK
     * @param jwk JWK结构体
     * @return 不支持的JWK结构体
     */
    function toUnsupportedJWK(IJWKManager.JWK memory jwk) internal pure returns (IJWKManager.UnsupportedJWK memory) {
        if (jwk.variant != 1) revert InvalidJWKType();
        return abi.decode(jwk.data, (IJWKManager.UnsupportedJWK));
    }

    /**
     * @dev 检查JWK是否为RSA类型
     * @param jwk JWK结构体
     * @return 如果是RSA类型返回true
     */
    function isRSAJWK(IJWKManager.JWK memory jwk) internal pure returns (bool) {
        return jwk.variant == 0;
    }

    /**
     * @dev 检查JWK是否为不支持类型
     * @param jwk JWK结构体
     * @return 如果是不支持类型返回true
     */
    function isUnsupportedJWK(IJWKManager.JWK memory jwk) internal pure returns (bool) {
        return jwk.variant == 1;
    }

    // ======== 验证函数 ========

    /**
     * @dev 验证RSA JWK的基本格式
     * @param rsaJWK RSA JWK结构体
     * @return 验证是否通过
     */
    function validateRSAJWK(IJWKManager.RSA_JWK memory rsaJWK) internal pure returns (bool) {
        // 检查必要字段
        if (bytes(rsaJWK.kid).length == 0) return false;
        if (bytes(rsaJWK.e).length == 0) return false;
        if (bytes(rsaJWK.n).length == 0) return false;
        
        // 检查kty是否为RSA
        if (!_stringsEqual(rsaJWK.kty, "RSA")) return false;
        
        return true;
    }

    /**
     * @dev 验证OIDC提供者格式
     * @param provider OIDC提供者结构体
     * @return 验证是否通过
     */
    function validateOIDCProvider(IJWKManager.OIDCProvider memory provider) internal pure returns (bool) {
        if (bytes(provider.name).length == 0) return false;
        if (bytes(provider.configUrl).length == 0) return false;
        
        // 检查name是否以https://开头
        bytes memory nameBytes = bytes(provider.name);
        if (nameBytes.length < 8) return false;
        
        bytes8 httpsPrefix = bytes8(nameBytes[0]) | 
                           (bytes8(nameBytes[1]) << 8) |
                           (bytes8(nameBytes[2]) << 16) |
                           (bytes8(nameBytes[3]) << 24) |
                           (bytes8(nameBytes[4]) << 32) |
                           (bytes8(nameBytes[5]) << 40) |
                           (bytes8(nameBytes[6]) << 48) |
                           (bytes8(nameBytes[7]) << 56);
        
        if (httpsPrefix != "https://") return false;
        
        return true;
    }

    // ======== 实用工具函数 ========

    /**
     * @dev 比较两个字符串是否相等
     * @param a 字符串A
     * @param b 字符串B
     * @return 是否相等
     */
    function _stringsEqual(string memory a, string memory b) internal pure returns (bool) {
        return keccak256(abi.encodePacked(a)) == keccak256(abi.encodePacked(b));
    }

    /**
     * @dev 字符串比较（用于排序）
     * @param a 字符串A
     * @param b 字符串B
     * @return -1 if a < b, 0 if a == b, 1 if a > b
     */
    function compareStrings(string memory a, string memory b) internal pure returns (int256) {
        bytes memory aBytes = bytes(a);
        bytes memory bBytes = bytes(b);
        
        uint256 minLength = aBytes.length < bBytes.length ? aBytes.length : bBytes.length;
        
        for (uint256 i = 0; i < minLength; i++) {
            if (uint8(aBytes[i]) < uint8(bBytes[i])) {
                return -1;
            } else if (uint8(aBytes[i]) > uint8(bBytes[i])) {
                return 1;
            }
        }
        
        if (aBytes.length < bBytes.length) {
            return -1;
        } else if (aBytes.length > bBytes.length) {
            return 1;
        } else {
            return 0;
        }
    }

    /**
     * @dev 计算AllProvidersJWKs的哈希
     * @param allJWKs AllProvidersJWKs结构体
     * @return 哈希值
     */
    function hashAllProvidersJWKs(IJWKManager.AllProvidersJWKs memory allJWKs) internal pure returns (bytes32) {
        return keccak256(abi.encode(allJWKs));
    }

    /**
     * @dev 计算ProviderJWKs的哈希
     * @param providerJWKs ProviderJWKs结构体
     * @return 哈希值
     */
    function hashProviderJWKs(IJWKManager.ProviderJWKs memory providerJWKs) internal pure returns (bytes32) {
        return keccak256(abi.encode(providerJWKs));
    }
}

/**
 * @title JWKManagerFactory
 * @dev JWK管理相关的工厂合约
 */
contract JWKManagerFactory {
    using JWKUtils for IJWKManager.JWK;

    // ======== 事件 ========
    event JWKCreated(bytes32 indexed jwkHash, uint8 variant, bytes data);
    event PatchCreated(bytes32 indexed patchHash, IJWKManager.PatchType patchType);

    // ======== RSA JWK创建 ========

    /**
     * @dev 批量创建RSA JWKs
     * @param kids Key IDs数组
     * @param algs 算法数组
     * @param es 公共指数数组
     * @param ns 模数数组
     * @return 创建的JWK数组
     */
    function createRSAJWKs(
        string[] memory kids,
        string[] memory algs,
        string[] memory es,
        string[] memory ns
    ) external pure returns (IJWKManager.JWK[] memory) {
        require(kids.length == algs.length && 
                kids.length == es.length && 
                kids.length == ns.length, 
                "Array length mismatch");

        IJWKManager.JWK[] memory jwks = new IJWKManager.JWK[](kids.length);
        for (uint256 i = 0; i < kids.length; i++) {
            jwks[i] = JWKUtils.newRSAJWK(kids[i], algs[i], es[i], ns[i]);
        }
        return jwks;
    }

    /**
     * @dev 创建标准的Google RSA JWK
     * @param kid Key ID
     * @param n 模数
     * @return Google格式的RSA JWK
     */
    function createGoogleRSAJWK(
        string memory kid,
        string memory n
    ) external pure returns (IJWKManager.JWK memory) {
        return JWKUtils.newRSAJWK(kid, "RS256", "AQAB", n);
    }

    // ======== 补丁批量创建 ========

    /**
     * @dev 创建批量移除发行者的补丁
     * @param issuers 要移除的发行者数组
     * @return 补丁数组
     */
    function createRemoveIssuerPatches(
        string[] memory issuers
    ) external pure returns (IJWKManager.Patch[] memory) {
        IJWKManager.Patch[] memory patches = new IJWKManager.Patch[](issuers.length);
        for (uint256 i = 0; i < issuers.length; i++) {
            patches[i] = JWKUtils.newPatchRemoveIssuer(issuers[i]);
        }
        return patches;
    }

    /**
     * @dev 为单个发行者创建替换所有JWK的补丁序列
     * @param issuer 发行者
     * @param jwks 新的JWK数组
     * @return 补丁数组（先移除发行者，再逐个添加JWK）
     */
    function createReplaceIssuerJWKsPatches(
        string memory issuer,
        IJWKManager.JWK[] memory jwks
    ) external pure returns (IJWKManager.Patch[] memory) {
        IJWKManager.Patch[] memory patches = new IJWKManager.Patch[](jwks.length + 1);
        
        // 第一个补丁：移除现有发行者
        patches[0] = JWKUtils.newPatchRemoveIssuer(issuer);
        
        // 后续补丁：添加所有新JWK
        for (uint256 i = 0; i < jwks.length; i++) {
            patches[i + 1] = JWKUtils.newPatchUpsertJWK(issuer, jwks[i]);
        }
        
        return patches;
    }

    // ======== 验证和查询 ========

    /**
     * @dev 批量验证RSA JWKs
     * @param jwks JWK数组
     * @return 验证结果数组
     */
    function validateRSAJWKs(
        IJWKManager.JWK[] memory jwks
    ) external pure returns (bool[] memory) {
        bool[] memory results = new bool[](jwks.length);
        for (uint256 i = 0; i < jwks.length; i++) {
            if (jwks[i].isRSAJWK()) {
                IJWKManager.RSA_JWK memory rsaJWK = jwks[i].toRSAJWK();
                results[i] = JWKUtils.validateRSAJWK(rsaJWK);
            } else {
                results[i] = false;
            }
        }
        return results;
    }

    /**
     * @dev 提取JWK数组的所有ID
     * @param jwks JWK数组
     * @return JWK ID数组
     */
    function extractJWKIds(
        IJWKManager.JWK[] memory jwks
    ) external pure returns (bytes[] memory) {
        bytes[] memory ids = new bytes[](jwks.length);
        for (uint256 i = 0; i < jwks.length; i++) {
            ids[i] = jwks[i].getJWKId();
        }
        return ids;
    }
}