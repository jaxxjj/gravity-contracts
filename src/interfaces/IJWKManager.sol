// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

/**
 * @title IJWKManager
 * @dev JWK管理器接口定义
 */
interface IJWKManager {
    
    // ======== 结构体定义 ========
    
    struct OIDCProvider {
        string name;
        string configUrl;
        bool active;
    }

    struct RSA_JWK {
        string kid;
        string kty;
        string alg;
        string e;
        string n;
    }

    struct UnsupportedJWK {
        bytes id;
        bytes payload;
    }

    struct JWK {
        uint8 variant;      // 0: RSA_JWK, 1: UnsupportedJWK
        bytes data;
    }

    struct ProviderJWKs {
        string issuer;
        uint64 version;
        JWK[] jwks;
    }

    struct AllProvidersJWKs {
        ProviderJWKs[] entries;
    }

    enum PatchType {
        RemoveAll,
        RemoveIssuer,
        RemoveJWK,
        UpsertJWK
    }

    struct Patch {
        PatchType patchType;
        string issuer;
        bytes jwkId;
        JWK jwk;
    }

    // ======== 事件定义 ========
    
    event OIDCProviderAdded(string indexed name, string configUrl);
    event OIDCProviderRemoved(string indexed name);
    event OIDCProviderUpdated(string indexed name, string newConfigUrl);
    event ObservedJWKsUpdated(uint256 indexed epoch, bytes32 indexed dataHash);
    event PatchedJWKsRegenerated(bytes32 indexed dataHash);
    event PatchesUpdated(uint256 patchCount);
    event FederatedJWKsUpdated(address indexed dapp, string indexed issuer);

    // ======== 函数接口 ========

    // OIDC提供者管理
    function upsertOIDCProvider(string calldata name, string calldata configUrl) external;
    function removeOIDCProvider(string calldata name) external;
    function getActiveProviders() external view returns (OIDCProvider[] memory);

    // ObservedJWKs管理
    function upsertObservedJWKs(ProviderJWKs[] calldata providerJWKsArray) external;
    function removeIssuerFromObservedJWKs(string calldata issuer) external;

    // 补丁管理
    function setPatches(Patch[] calldata newPatches) external;
    function addPatch(Patch calldata patch) external;

    // 联邦JWKs管理
    function updateFederatedJWKSet(
        string calldata issuer,
        string[] calldata kidArray,
        string[] calldata algArray,
        string[] calldata eArray,
        string[] calldata nArray
    ) external;
    function patchFederatedJWKs(Patch[] calldata patchArray) external;

    // 查询函数
    function getPatchedJWK(string calldata issuer, bytes calldata jwkId) external view returns (JWK memory);
    function tryGetPatchedJWK(string calldata issuer, bytes calldata jwkId) external view returns (bool found, JWK memory jwk);
    function getFederatedJWK(address dapp, string calldata issuer, bytes calldata jwkId) external view returns (JWK memory);
    function getObservedJWKs() external view returns (AllProvidersJWKs memory);
    function getPatchedJWKs() external view returns (AllProvidersJWKs memory);
    function getFederatedJWKs(address dapp) external view returns (AllProvidersJWKs memory);
    function getPatches() external view returns (Patch[] memory);
}