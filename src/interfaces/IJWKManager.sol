// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@src/interfaces/IParamSubscriber.sol";

/**
 * @title IJWKManager
 * @dev 管理JSON Web Keys (JWKs)接口，支持OIDC提供者和联邦JWK
 * 基于Aptos JWK系统设计，适配Gravity链架构
 */
interface IJWKManager is IParamSubscriber {
    // ======== 错误定义 ========
    error JWKManager__ParameterNotFound(string key);
    error InvalidOIDCProvider();
    error DuplicateProvider();
    error JWKNotFound();
    error IssuerNotFound();
    error FederatedJWKsTooLarge();
    error InvalidJWKFormat();
    error UnknownJWKVariant();
    error UnknownPatchVariant();
    error NotAuthorized();

    // ======== 结构体定义 ========

    /// @dev OIDC提供者信息
    struct OIDCProvider {
        string name; // 提供者名称，如 "https://accounts.google.com"
        string configUrl; // OpenID配置URL
        bool active; // 是否激活
    }

    /// @dev RSA JWK结构
    struct RSA_JWK {
        string kid; // Key ID
        string kty; // Key Type (RSA)
        string alg; // Algorithm (RS256等)
        string e; // Public exponent
        string n; // Modulus
    }

    /// @dev 不支持的JWK类型
    struct UnsupportedJWK {
        bytes id;
        bytes payload;
    }

    /// @dev JWK联合体
    struct JWK {
        uint8 variant; // 0: RSA_JWK, 1: UnsupportedJWK
        bytes data; // 编码后的JWK数据
    }

    /// @dev 提供者的JWK集合
    struct ProviderJWKs {
        string issuer; // 发行者
        uint64 version; // 版本号
        JWK[] jwks; // JWK数组，按kid排序
    }

    /// @dev 所有提供者的JWK集合
    struct AllProvidersJWKs {
        ProviderJWKs[] entries; // 按issuer排序的提供者数组
    }

    /// @dev 补丁操作类型
    enum PatchType {
        RemoveAll, // 移除所有
        RemoveIssuer, // 移除特定发行者
        RemoveJWK, // 移除特定JWK
        UpsertJWK // 插入或更新JWK
    }

    /// @dev 补丁操作
    struct Patch {
        PatchType patchType;
        string issuer; // 对于RemoveIssuer, RemoveJWK, UpsertJWK
        bytes jwkId; // 对于RemoveJWK
        JWK jwk; // 对于UpsertJWK
    }

    // ======== 事件定义 ========
    event OIDCProviderAdded(string indexed name, string configUrl);
    event OIDCProviderRemoved(string indexed name);
    event OIDCProviderUpdated(string indexed name, string newConfigUrl);
    event ObservedJWKsUpdated(uint256 indexed epoch, bytes32 indexed dataHash);
    event PatchedJWKsRegenerated(bytes32 indexed dataHash);
    event PatchesUpdated(uint256 patchCount);
    event FederatedJWKsUpdated(address indexed dapp, string indexed issuer);
    event ConfigParamUpdated(string indexed key, uint256 oldValue, uint256 newValue);

    // ======== 函数声明 ========

    /**
     * @dev 初始化函数
     */
    function initialize() external;

    /**
     * @dev 添加或更新OIDC提供者
     */
    function upsertOIDCProvider(string calldata name, string calldata configUrl) external;

    /**
     * @dev 移除OIDC提供者
     */
    function removeOIDCProvider(string calldata name) external;

    /**
     * @dev 获取所有活跃的OIDC提供者
     */
    function getActiveProviders() external view returns (OIDCProvider[] memory);

    /**
     * @dev 更新观察到的JWKs（仅由共识层调用）
     */
    function upsertObservedJWKs(ProviderJWKs[] calldata providerJWKsArray) external;

    /**
     * @dev 从观察到的JWKs中移除发行者
     */
    function removeIssuerFromObservedJWKs(string calldata issuer) external;

    /**
     * @dev 设置补丁
     */
    function setPatches(Patch[] calldata newPatches) external;

    /**
     * @dev 添加单个补丁
     */
    function addPatch(Patch calldata patch) external;

    /**
     * @dev 更新联邦JWK集合（dApp调用）
     */
    function updateFederatedJWKSet(
        string calldata issuer,
        string[] calldata kidArray,
        string[] calldata algArray,
        string[] calldata eArray,
        string[] calldata nArray
    ) external;

    /**
     * @dev 应用补丁到联邦JWKs
     */
    function patchFederatedJWKs(Patch[] calldata patchArray) external;

    /**
     * @dev 获取补丁后的JWK
     */
    function getPatchedJWK(string calldata issuer, bytes calldata jwkId) external view returns (JWK memory);

    /**
     * @dev 尝试获取补丁后的JWK（不会revert）
     */
    function tryGetPatchedJWK(
        string calldata issuer,
        bytes calldata jwkId
    ) external view returns (bool found, JWK memory jwk);

    /**
     * @dev 获取联邦JWK
     */
    function getFederatedJWK(
        address dapp,
        string calldata issuer,
        bytes calldata jwkId
    ) external view returns (JWK memory);

    /**
     * @dev 获取观察到的JWKs
     */
    function getObservedJWKs() external view returns (AllProvidersJWKs memory);

    /**
     * @dev 获取补丁后的JWKs
     */
    function getPatchedJWKs() external view returns (AllProvidersJWKs memory);

    /**
     * @dev 获取联邦JWKs
     */
    function getFederatedJWKs(address dapp) external view returns (AllProvidersJWKs memory);

    /**
     * @dev 获取所有补丁
     */
    function getPatches() external view returns (Patch[] memory);

    /**
     * @dev 获取常量值
     */
    function MAX_FEDERATED_JWKS_SIZE_BYTES() external view returns (uint256);
    function MAX_PROVIDERS_PER_REQUEST() external view returns (uint256);
    function MAX_JWKS_PER_PROVIDER() external view returns (uint256);

    /**
     * @dev 获取配置参数
     */
    function maxSignaturesPerTxn() external view returns (uint256);
    function maxExpHorizonSecs() external view returns (uint256);
    function maxCommittedEpkBytes() external view returns (uint256);
    function maxIssValBytes() external view returns (uint256);
    function maxExtraFieldBytes() external view returns (uint256);
    function maxJwtHeaderB64Bytes() external view returns (uint256);

    /**
     * @dev 获取提供者信息
     */
    function supportedProviders(
        uint256 index
    ) external view returns (string memory name, string memory configUrl, bool active);
    function providerIndex(string calldata name) external view returns (uint256);
}
