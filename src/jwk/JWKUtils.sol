// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "@src/interfaces/IJWKManager.sol";

/**
 * @title JWKUtils
 * @dev Utility library for JWK operations
 */
library JWKUtils {
    using JWKUtils for IJWKManager.JWK;

    // ======== Error Definitions ========
    error InvalidJWKType();
    error InvalidRSAJWK();
    error EmptyKid();
    error EmptyModulus();
    error EmptyExponent();

    // ======== JWK Creation Functions ========

    /**
     * @dev Create RSA JWK
     * @param kid Key ID
     * @param alg Algorithm (e.g., "RS256")
     * @param e Public exponent (usually "AQAB")
     * @param n Modulus (Base64URL encoded)
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

        IJWKManager.RSA_JWK memory rsaJWK = IJWKManager.RSA_JWK({ kid: kid, kty: "RSA", alg: alg, e: e, n: n });

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
    function newUnsupportedJWK(bytes memory id, bytes memory payload) internal pure returns (IJWKManager.JWK memory) {
        IJWKManager.UnsupportedJWK memory unsupportedJWK = IJWKManager.UnsupportedJWK({ id: id, payload: payload });

        return IJWKManager.JWK({
            variant: 1, // UnsupportedJWK
            data: abi.encode(unsupportedJWK)
        });
    }

    // ======== Patch Creation Functions ========

    /**
     * @dev 创建"移除所有"补丁
     */
    function newPatchRemoveAll() internal pure returns (IJWKManager.Patch memory) {
        return IJWKManager.Patch({
            patchType: IJWKManager.PatchType.RemoveAll,
            issuer: "",
            jwkId: "",
            jwk: IJWKManager.JWK({ variant: 0, data: "" })
        });
    }

    /**
     * @dev Create "Remove Issuer" patch
     * @param issuer Issuer to remove
     */
    function newPatchRemoveIssuer(string memory issuer) internal pure returns (IJWKManager.Patch memory) {
        return IJWKManager.Patch({
            patchType: IJWKManager.PatchType.RemoveIssuer,
            issuer: issuer,
            jwkId: "",
            jwk: IJWKManager.JWK({ variant: 0, data: "" })
        });
    }

    /**
     * @dev Create "Remove JWK" patch
     * @param issuer Issuer
     * @param jwkId JWK ID to remove
     */
    function newPatchRemoveJWK(
        string memory issuer,
        bytes memory jwkId
    ) internal pure returns (IJWKManager.Patch memory) {
        return IJWKManager.Patch({
            patchType: IJWKManager.PatchType.RemoveJWK,
            issuer: issuer,
            jwkId: jwkId,
            jwk: IJWKManager.JWK({ variant: 0, data: "" })
        });
    }

    /**
     * @dev Create "Insert or Update JWK" patch
     * @param issuer Issuer
     * @param jwk JWK to insert or update
     */
    function newPatchUpsertJWK(
        string memory issuer,
        IJWKManager.JWK memory jwk
    ) internal pure returns (IJWKManager.Patch memory) {
        return IJWKManager.Patch({ patchType: IJWKManager.PatchType.UpsertJWK, issuer: issuer, jwkId: "", jwk: jwk });
    }

    // ======== JWK Operation Functions ========

    /**
     * @dev Get JWK ID
     * @param jwk JWK structure
     * @return JWK ID
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
     * @dev Decode RSA JWK
     * @param jwk JWK structure
     * @return RSA JWK structure
     */
    function toRSAJWK(IJWKManager.JWK memory jwk) internal pure returns (IJWKManager.RSA_JWK memory) {
        if (jwk.variant != 0) revert InvalidJWKType();
        return abi.decode(jwk.data, (IJWKManager.RSA_JWK));
    }

    /**
     * @dev Decode unsupported JWK
     * @param jwk JWK structure
     * @return Unsupported JWK structure
     */
    function toUnsupportedJWK(IJWKManager.JWK memory jwk) internal pure returns (IJWKManager.UnsupportedJWK memory) {
        if (jwk.variant != 1) revert InvalidJWKType();
        return abi.decode(jwk.data, (IJWKManager.UnsupportedJWK));
    }

    /**
     * @dev Check if JWK is RSA type
     * @param jwk JWK structure
     * @return true if RSA type
     */
    function isRSAJWK(IJWKManager.JWK memory jwk) internal pure returns (bool) {
        return jwk.variant == 0;
    }

    /**
     * @dev Check if JWK is unsupported type
     * @param jwk JWK structure
     * @return true if unsupported type
     */
    function isUnsupportedJWK(IJWKManager.JWK memory jwk) internal pure returns (bool) {
        return jwk.variant == 1;
    }

    // ======== Validation Functions ========

    /**
     * @dev Validate RSA JWK basic format
     * @param rsaJWK RSA JWK structure
     * @return true if validation passes
     */
    function validateRSAJWK(IJWKManager.RSA_JWK memory rsaJWK) internal pure returns (bool) {
        // Check required fields
        if (bytes(rsaJWK.kid).length == 0) return false;
        if (bytes(rsaJWK.e).length == 0) return false;
        if (bytes(rsaJWK.n).length == 0) return false;

        // Check if kty is RSA
        if (!_stringsEqual(rsaJWK.kty, "RSA")) return false;

        return true;
    }

    /**
     * @dev Validate OIDC provider format
     * @param provider OIDC provider structure
     * @return true if validation passes
     */
    function validateOIDCProvider(IJWKManager.OIDCProvider memory provider) internal pure returns (bool) {
        if (bytes(provider.name).length == 0) return false;
        if (bytes(provider.configUrl).length == 0) return false;

        // 检查name是否以https://开头
        bytes memory nameBytes = bytes(provider.name);
        if (nameBytes.length < 8) return false;

        bytes8 httpsPrefix = bytes8(nameBytes[0]) | (bytes8(nameBytes[1]) << 8) | (bytes8(nameBytes[2]) << 16)
            | (bytes8(nameBytes[3]) << 24) | (bytes8(nameBytes[4]) << 32) | (bytes8(nameBytes[5]) << 40)
            | (bytes8(nameBytes[6]) << 48) | (bytes8(nameBytes[7]) << 56);

        if (httpsPrefix != "https://") return false;

        return true;
    }

    // ======== Utility Functions ========

    /**
     * @dev Compare two strings for equality
     * @param a String A
     * @param b String B
     * @return true if strings are equal
     */
    function _stringsEqual(string memory a, string memory b) internal pure returns (bool) {
        return keccak256(abi.encodePacked(a)) == keccak256(abi.encodePacked(b));
    }

    /**
     * @dev Compare two strings for sorting
     * @param a String A
     * @param b String B
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
     * @dev Calculate hash of AllProvidersJWKs
     * @param allJWKs AllProvidersJWKs structure
     * @return hash value
     */
    function hashAllProvidersJWKs(IJWKManager.AllProvidersJWKs memory allJWKs) internal pure returns (bytes32) {
        return keccak256(abi.encode(allJWKs));
    }

    /**
     * @dev Calculate hash of ProviderJWKs
     * @param providerJWKs ProviderJWKs structure
     * @return hash value
     */
    function hashProviderJWKs(IJWKManager.ProviderJWKs memory providerJWKs) internal pure returns (bytes32) {
        return keccak256(abi.encode(providerJWKs));
    }
}

/**
 * @title JWKManagerFactory
 * @dev Factory contract for JWK management operations
 */
contract JWKManagerFactory {
    using JWKUtils for IJWKManager.JWK;

    // ======== Events ========
    event JWKCreated(bytes32 indexed jwkHash, uint8 variant, bytes data);
    event PatchCreated(bytes32 indexed patchHash, IJWKManager.PatchType patchType);

    // ======== RSA JWK Creation ========

    /**
     * @dev Batch create RSA JWKs
     * @param kids Key IDs array
     * @param algs Algorithms array
     * @param es Public exponents array
     * @param ns Modulus array
     * @return Created JWK array
     */
    function createRSAJWKs(
        string[] memory kids,
        string[] memory algs,
        string[] memory es,
        string[] memory ns
    ) external pure returns (IJWKManager.JWK[] memory) {
        require(
            kids.length == algs.length && kids.length == es.length && kids.length == ns.length, "Array length mismatch"
        );

        IJWKManager.JWK[] memory jwks = new IJWKManager.JWK[](kids.length);
        for (uint256 i = 0; i < kids.length; i++) {
            jwks[i] = JWKUtils.newRSAJWK(kids[i], algs[i], es[i], ns[i]);
        }
        return jwks;
    }

    /**
     * @dev Create standard Google RSA JWK
     * @param kid Key ID
     * @param n Modulus
     * @return Google-formatted RSA JWK
     */
    function createGoogleRSAJWK(string memory kid, string memory n) external pure returns (IJWKManager.JWK memory) {
        return JWKUtils.newRSAJWK(kid, "RS256", "AQAB", n);
    }

    // ======== Batch Patch Creation ========

    /**
     * @dev Create batch remove issuer patches
     * @param issuers Issuers to remove
     * @return Patches array
     */
    function createRemoveIssuerPatches(string[] memory issuers) external pure returns (IJWKManager.Patch[] memory) {
        IJWKManager.Patch[] memory patches = new IJWKManager.Patch[](issuers.length);
        for (uint256 i = 0; i < issuers.length; i++) {
            patches[i] = JWKUtils.newPatchRemoveIssuer(issuers[i]);
        }
        return patches;
    }

    /**
     * @dev Create patch sequence for replacing all JWKs for a single issuer
     * @param issuer Issuer
     * @param jwks New JWK array
     * @return Patches array (first remove issuer, then add each JWK)
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

    // ======== Validation and Query ========

    /**
     * @dev Batch validate RSA JWKs
     * @param jwks JWK array
     * @return Validation results array
     */
    function validateRSAJWKs(IJWKManager.JWK[] memory jwks) external pure returns (bool[] memory) {
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
     * @dev Extract all JWK IDs from array
     * @param jwks JWK array
     * @return JWK ID array
     */
    function extractJWKIds(IJWKManager.JWK[] memory jwks) external pure returns (bytes[] memory) {
        bytes[] memory ids = new bytes[](jwks.length);
        for (uint256 i = 0; i < jwks.length; i++) {
            ids[i] = jwks[i].getJWKId();
        }
        return ids;
    }
}
