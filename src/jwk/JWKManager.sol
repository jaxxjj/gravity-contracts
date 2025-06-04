// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "@src/System.sol";
import "@src/access/Protectable.sol";
import "@src/interfaces/IParamSubscriber.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin-upgrades/proxy/utils/Initializable.sol";
import "@src/interfaces/IJWKManager.sol";
/**
 * @title JWKManager
 * @dev 管理JSON Web Keys (JWKs)，支持OIDC提供者和联邦JWK
 * 基于Aptos JWK系统设计，适配Gravity链架构
 */

contract JWKManager is System, Protectable, IParamSubscriber, IJWKManager, Initializable {
    using Strings for string;

    // ======== 常量 ========
    uint256 public constant MAX_FEDERATED_JWKS_SIZE_BYTES = 2 * 1024; // 2 KiB
    uint256 public constant MAX_PROVIDERS_PER_REQUEST = 50;
    uint256 public constant MAX_JWKS_PER_PROVIDER = 100;

    // ======== 状态变量 ========

    /// @dev 支持的OIDC提供者
    OIDCProvider[] public supportedProviders;
    mapping(string => uint256) public providerIndex; // name => index (index + 1, 0表示不存在)

    /// @dev 验证者观察到的JWKs（由共识写入）
    AllProvidersJWKs private observedJWKs;

    /// @dev 应用补丁后的JWKs（最终使用的）
    AllProvidersJWKs private patchedJWKs;

    /// @dev 治理设置的补丁
    Patch[] public patches;

    /// @dev 联邦JWKs：dapp地址 => AllProvidersJWKs
    mapping(address => AllProvidersJWKs) private federatedJWKs;

    /// @dev 配置参数
    uint256 public maxSignaturesPerTxn;
    uint256 public maxExpHorizonSecs;
    uint256 public maxCommittedEpkBytes;
    uint256 public maxIssValBytes;
    uint256 public maxExtraFieldBytes;
    uint256 public maxJwtHeaderB64Bytes;

    modifier validIssuer(string memory issuer) {
        if (bytes(issuer).length == 0) revert InvalidOIDCProvider();
        _;
    }

    // ======== 初始化 ========

    /**
     * @dev 禁用构造函数中的初始化器
     * @custom:oz-upgrades-unsafe-allow constructor
     */
    constructor() {
        _disableInitializers();
    }

    /**
     * @dev 初始化函数
     */
    function initialize() external initializer onlyGenesis {
        maxSignaturesPerTxn = 10;
        maxExpHorizonSecs = 3600; // 1 hour
        maxCommittedEpkBytes = 93;
        maxIssValBytes = 256;
        maxExtraFieldBytes = 256;
        maxJwtHeaderB64Bytes = 1024;
    }

    // ======== 参数管理 ========

    /**
     * @dev 统一参数更新函数
     */
    function updateParam(string calldata key, bytes calldata value) external override onlyGov {
        if (Strings.equal(key, "maxSignaturesPerTxn")) {
            uint256 newValue = abi.decode(value, (uint256));
            uint256 oldValue = maxSignaturesPerTxn;
            maxSignaturesPerTxn = newValue;
            emit ConfigParamUpdated("maxSignaturesPerTxn", oldValue, newValue);
        } else if (Strings.equal(key, "maxExpHorizonSecs")) {
            uint256 newValue = abi.decode(value, (uint256));
            uint256 oldValue = maxExpHorizonSecs;
            maxExpHorizonSecs = newValue;
            emit ConfigParamUpdated("maxExpHorizonSecs", oldValue, newValue);
        } else if (Strings.equal(key, "maxCommittedEpkBytes")) {
            uint256 newValue = abi.decode(value, (uint256));
            uint256 oldValue = maxCommittedEpkBytes;
            maxCommittedEpkBytes = newValue;
            emit ConfigParamUpdated("maxCommittedEpkBytes", oldValue, newValue);
        } else if (Strings.equal(key, "maxIssValBytes")) {
            uint256 newValue = abi.decode(value, (uint256));
            uint256 oldValue = maxIssValBytes;
            maxIssValBytes = newValue;
            emit ConfigParamUpdated("maxIssValBytes", oldValue, newValue);
        } else if (Strings.equal(key, "maxExtraFieldBytes")) {
            uint256 newValue = abi.decode(value, (uint256));
            uint256 oldValue = maxExtraFieldBytes;
            maxExtraFieldBytes = newValue;
            emit ConfigParamUpdated("maxExtraFieldBytes", oldValue, newValue);
        } else if (Strings.equal(key, "maxJwtHeaderB64Bytes")) {
            uint256 newValue = abi.decode(value, (uint256));
            uint256 oldValue = maxJwtHeaderB64Bytes;
            maxJwtHeaderB64Bytes = newValue;
            emit ConfigParamUpdated("maxJwtHeaderB64Bytes", oldValue, newValue);
        } else {
            revert JWKManager__ParameterNotFound(key);
        }

        emit ParamChange(key, value);
    }

    // ======== OIDC提供者管理 ========

    /**
     * @dev 添加OIDC提供者
     */
    function upsertOIDCProvider(string calldata name, string calldata configUrl) external onlyGov validIssuer(name) {
        uint256 index = providerIndex[name];

        if (index == 0) {
            // 新增提供者
            supportedProviders.push(OIDCProvider({ name: name, configUrl: configUrl, active: true }));
            providerIndex[name] = supportedProviders.length;
            emit OIDCProviderAdded(name, configUrl);
        } else {
            // 更新现有提供者
            OIDCProvider storage provider = supportedProviders[index - 1];
            provider.configUrl = configUrl;
            provider.active = true;
            emit OIDCProviderUpdated(name, configUrl);
        }
    }

    /**
     * @dev 移除OIDC提供者
     */
    function removeOIDCProvider(string calldata name) external onlyGov {
        uint256 index = providerIndex[name];
        if (index == 0) revert IssuerNotFound();

        // 标记为不活跃而不是删除，保持索引一致性
        supportedProviders[index - 1].active = false;
        emit OIDCProviderRemoved(name);
    }

    /**
     * @dev 获取所有活跃的OIDC提供者
     */
    function getActiveProviders() external view returns (OIDCProvider[] memory) {
        uint256 activeCount = 0;
        for (uint256 i = 0; i < supportedProviders.length; i++) {
            if (supportedProviders[i].active) {
                activeCount++;
            }
        }

        OIDCProvider[] memory activeProviders = new OIDCProvider[](activeCount);
        uint256 index = 0;
        for (uint256 i = 0; i < supportedProviders.length; i++) {
            if (supportedProviders[i].active) {
                activeProviders[index] = supportedProviders[i];
                index++;
            }
        }
        return activeProviders;
    }

    // ======== ObservedJWKs管理（由共识层调用）========

    /**
     * @dev 更新观察到的JWKs（仅由共识层调用）
     * 对应Aptos的upsert_into_observed_jwks函数
     */
    function upsertObservedJWKs(ProviderJWKs[] calldata providerJWKsArray) external onlySystemCaller {
        // 更新observedJWKs
        for (uint256 i = 0; i < providerJWKsArray.length; i++) {
            _upsertProviderJWKs(observedJWKs, providerJWKsArray[i]);
        }

        // 重新生成patchedJWKs
        _regeneratePatchedJWKs();

        emit ObservedJWKsUpdated(block.number, keccak256(abi.encode(observedJWKs)));
    }

    /**
     * @dev 从观察到的JWKs中移除发行者（仅由治理调用）
     */
    function removeIssuerFromObservedJWKs(string calldata issuer) external onlyGov validIssuer(issuer) {
        _removeIssuer(observedJWKs, issuer);
        _regeneratePatchedJWKs();
        emit ObservedJWKsUpdated(block.number, keccak256(abi.encode(observedJWKs)));
    }

    // ======== 补丁管理 ========

    /**
     * @dev 设置补丁（仅由治理调用）
     */
    function setPatches(Patch[] calldata newPatches) external onlyGov {
        delete patches;
        for (uint256 i = 0; i < newPatches.length; i++) {
            patches.push(newPatches[i]);
        }

        _regeneratePatchedJWKs();
        emit PatchesUpdated(newPatches.length);
    }

    /**
     * @dev 添加单个补丁
     */
    function addPatch(Patch calldata patch) external onlyGov {
        patches.push(patch);
        _regeneratePatchedJWKs();
        emit PatchesUpdated(patches.length);
    }

    // ======== 联邦JWKs管理 ========

    /**
     * @dev 更新联邦JWK集合（dApp调用）
     * 对应Aptos的update_federated_jwk_set函数
     */
    function updateFederatedJWKSet(
        string calldata issuer,
        string[] calldata kidArray,
        string[] calldata algArray,
        string[] calldata eArray,
        string[] calldata nArray
    ) external validIssuer(issuer) {
        if (kidArray.length == 0) revert InvalidJWKFormat();
        if (
            kidArray.length != algArray.length || kidArray.length != eArray.length || kidArray.length != nArray.length
        ) {
            revert InvalidJWKFormat();
        }

        // 获取或创建dapp的联邦JWKs
        AllProvidersJWKs storage dappJWKs = federatedJWKs[msg.sender];

        // 先移除该issuer的所有现有JWKs
        _removeIssuer(dappJWKs, issuer);

        // 创建新的ProviderJWKs
        ProviderJWKs memory newProviderJWKs = ProviderJWKs({
            issuer: issuer,
            version: 1, // 简化版本管理
            jwks: new JWK[](kidArray.length)
        });

        // 添加所有JWKs
        for (uint256 i = 0; i < kidArray.length; i++) {
            RSA_JWK memory rsaJWK = RSA_JWK({
                kid: kidArray[i],
                kty: "RSA",
                alg: algArray[i],
                e: eArray[i],
                n: nArray[i]
            });

            newProviderJWKs.jwks[i] = JWK({
                variant: 0, // RSA_JWK
                data: abi.encode(rsaJWK)
            });
        }

        // 插入新的ProviderJWKs
        _upsertProviderJWKs(dappJWKs, newProviderJWKs);

        // 检查大小限制
        bytes memory encoded = abi.encode(dappJWKs);
        if (encoded.length > MAX_FEDERATED_JWKS_SIZE_BYTES) {
            revert FederatedJWKsTooLarge();
        }

        emit FederatedJWKsUpdated(msg.sender, issuer);
    }

    /**
     * @dev 应用补丁到联邦JWKs
     */
    function patchFederatedJWKs(Patch[] calldata patchArray) external {
        AllProvidersJWKs storage dappJWKs = federatedJWKs[msg.sender];

        for (uint256 i = 0; i < patchArray.length; i++) {
            _applyPatch(dappJWKs, patchArray[i]);
        }

        // 检查大小限制
        bytes memory encoded = abi.encode(dappJWKs);
        if (encoded.length > MAX_FEDERATED_JWKS_SIZE_BYTES) {
            revert FederatedJWKsTooLarge();
        }

        emit FederatedJWKsUpdated(msg.sender, "");
    }

    // ======== 查询函数 ========

    /**
     * @dev 获取补丁后的JWK
     */
    function getPatchedJWK(string calldata issuer, bytes calldata jwkId) external view returns (JWK memory) {
        return _getJWKByIssuer(patchedJWKs, issuer, jwkId);
    }

    /**
     * @dev 尝试获取补丁后的JWK（不会revert）
     */
    function tryGetPatchedJWK(
        string calldata issuer,
        bytes calldata jwkId
    ) external view returns (bool found, JWK memory jwk) {
        try this.getPatchedJWK(issuer, jwkId) returns (JWK memory result) {
            return (true, result);
        } catch {
            return (false, JWK({ variant: 0, data: "" }));
        }
    }

    /**
     * @dev 获取联邦JWK
     */
    function getFederatedJWK(
        address dapp,
        string calldata issuer,
        bytes calldata jwkId
    ) external view returns (JWK memory) {
        return _getJWKByIssuer(federatedJWKs[dapp], issuer, jwkId);
    }

    /**
     * @dev 获取观察到的JWKs
     */
    function getObservedJWKs() external view returns (AllProvidersJWKs memory) {
        return observedJWKs;
    }

    /**
     * @dev 获取补丁后的JWKs
     */
    function getPatchedJWKs() external view returns (AllProvidersJWKs memory) {
        return patchedJWKs;
    }

    /**
     * @dev 获取联邦JWKs
     */
    function getFederatedJWKs(address dapp) external view returns (AllProvidersJWKs memory) {
        return federatedJWKs[dapp];
    }

    /**
     * @dev 获取所有补丁
     */
    function getPatches() external view returns (Patch[] memory) {
        return patches;
    }

    // ======== 内部函数 ========

    /**
     * @dev 重新生成补丁后的JWKs
     */
    function _regeneratePatchedJWKs() internal {
        // 复制observedJWKs到patchedJWKs
        _copyAllProvidersJWKs(patchedJWKs, observedJWKs);

        // 应用所有补丁
        for (uint256 i = 0; i < patches.length; i++) {
            _applyPatch(patchedJWKs, patches[i]);
        }

        emit PatchedJWKsRegenerated(keccak256(abi.encode(patchedJWKs)));
    }

    /**
     * @dev 复制AllProvidersJWKs
     */
    function _copyAllProvidersJWKs(AllProvidersJWKs storage dest, AllProvidersJWKs storage src) internal {
        // 清空目标
        delete dest.entries;

        // 复制所有entries
        for (uint256 i = 0; i < src.entries.length; i++) {
            dest.entries.push();
            ProviderJWKs storage destEntry = dest.entries[dest.entries.length - 1];
            ProviderJWKs storage srcEntry = src.entries[i];

            // 逐个字段拷贝而不是直接赋值结构体
            destEntry.issuer = srcEntry.issuer;
            destEntry.version = srcEntry.version;

            delete destEntry.jwks;
            for (uint256 j = 0; j < srcEntry.jwks.length; j++) {
                destEntry.jwks.push(srcEntry.jwks[j]);
            }
        }
    }

    /**
     * @dev 应用补丁
     */
    function _applyPatch(AllProvidersJWKs storage jwks, Patch memory patch) internal {
        if (patch.patchType == PatchType.RemoveAll) {
            delete jwks.entries;
        } else if (patch.patchType == PatchType.RemoveIssuer) {
            _removeIssuer(jwks, patch.issuer);
        } else if (patch.patchType == PatchType.RemoveJWK) {
            _removeJWK(jwks, patch.issuer, patch.jwkId);
        } else if (patch.patchType == PatchType.UpsertJWK) {
            _upsertJWK(jwks, patch.issuer, patch.jwk);
        } else {
            revert UnknownPatchVariant();
        }
    }

    /**
     * @dev 插入或更新ProviderJWKs
     */
    function _upsertProviderJWKs(AllProvidersJWKs storage jwks, ProviderJWKs memory providerJWKs) internal {
        // 查找是否已存在
        for (uint256 i = 0; i < jwks.entries.length; i++) {
            if (Strings.equal(jwks.entries[i].issuer, providerJWKs.issuer)) {
                // 更新现有entry - 避免直接赋值，逐个字段拷贝
                jwks.entries[i].issuer = providerJWKs.issuer;
                jwks.entries[i].version = providerJWKs.version;

                // 清空并重新添加jwks数组
                delete jwks.entries[i].jwks;
                for (uint256 j = 0; j < providerJWKs.jwks.length; j++) {
                    jwks.entries[i].jwks.push(providerJWKs.jwks[j]);
                }
                return;
            }
        }

        // 插入新entry（保持按issuer排序）
        uint256 insertIndex = 0;
        for (uint256 i = 0; i < jwks.entries.length; i++) {
            if (_compareStrings(providerJWKs.issuer, jwks.entries[i].issuer) < 0) {
                insertIndex = i;
                break;
            }
            insertIndex = i + 1;
        }

        // 插入到指定位置 - 避免直接赋值，逐个字段拷贝
        jwks.entries.push();
        for (uint256 i = jwks.entries.length - 1; i > insertIndex; i--) {
            // 逐个字段拷贝
            jwks.entries[i].issuer = jwks.entries[i - 1].issuer;
            jwks.entries[i].version = jwks.entries[i - 1].version;
            delete jwks.entries[i].jwks;
            for (uint256 j = 0; j < jwks.entries[i - 1].jwks.length; j++) {
                jwks.entries[i].jwks.push(jwks.entries[i - 1].jwks[j]);
            }
        }

        // 设置新entry
        jwks.entries[insertIndex].issuer = providerJWKs.issuer;
        jwks.entries[insertIndex].version = providerJWKs.version;
        delete jwks.entries[insertIndex].jwks;
        for (uint256 j = 0; j < providerJWKs.jwks.length; j++) {
            jwks.entries[insertIndex].jwks.push(providerJWKs.jwks[j]);
        }
    }

    /**
     * @dev 移除发行者
     */
    function _removeIssuer(AllProvidersJWKs storage jwks, string memory issuer) internal {
        for (uint256 i = 0; i < jwks.entries.length; i++) {
            if (Strings.equal(jwks.entries[i].issuer, issuer)) {
                // 移除该entry - 逐个字段拷贝而不是直接赋值
                for (uint256 j = i; j < jwks.entries.length - 1; j++) {
                    jwks.entries[j].issuer = jwks.entries[j + 1].issuer;
                    jwks.entries[j].version = jwks.entries[j + 1].version;

                    delete jwks.entries[j].jwks;
                    for (uint256 k = 0; k < jwks.entries[j + 1].jwks.length; k++) {
                        jwks.entries[j].jwks.push(jwks.entries[j + 1].jwks[k]);
                    }
                }
                jwks.entries.pop();
                return;
            }
        }
    }

    /**
     * @dev 插入或更新JWK
     */
    function _upsertJWK(AllProvidersJWKs storage jwks, string memory issuer, JWK memory jwk) internal {
        // 查找或创建ProviderJWKs
        int256 _providerIndex = -1;
        for (uint256 i = 0; i < jwks.entries.length; i++) {
            if (Strings.equal(jwks.entries[i].issuer, issuer)) {
                _providerIndex = int256(i);
                break;
            }
        }

        if (_providerIndex == -1) {
            // 创建新的ProviderJWKs
            ProviderJWKs memory newProvider = ProviderJWKs({ issuer: issuer, version: 1, jwks: new JWK[](1) });
            newProvider.jwks[0] = jwk;
            _upsertProviderJWKs(jwks, newProvider);
        } else {
            // 更新现有ProviderJWKs中的JWK
            ProviderJWKs storage provider = jwks.entries[uint256(_providerIndex)];
            bytes memory jwkId = _getJWKId(jwk);

            // 查找JWK是否已存在
            bool found = false;
            for (uint256 i = 0; i < provider.jwks.length; i++) {
                if (keccak256(_getJWKId(provider.jwks[i])) == keccak256(jwkId)) {
                    provider.jwks[i] = jwk;
                    found = true;
                    break;
                }
            }

            if (!found) {
                // 添加新JWK（保持按kid排序）
                JWK[] memory newJWKs = new JWK[](provider.jwks.length + 1);
                uint256 insertIndex = 0;
                for (uint256 i = 0; i < provider.jwks.length; i++) {
                    bytes memory existingId = _getJWKId(provider.jwks[i]);
                    if (keccak256(jwkId) < keccak256(existingId)) {
                        insertIndex = i;
                        break;
                    }
                    insertIndex = i + 1;
                }

                for (uint256 i = 0; i < insertIndex; i++) {
                    newJWKs[i] = provider.jwks[i];
                }
                newJWKs[insertIndex] = jwk;
                for (uint256 i = insertIndex; i < provider.jwks.length; i++) {
                    newJWKs[i + 1] = provider.jwks[i];
                }

                delete provider.jwks;
                for (uint256 i = 0; i < newJWKs.length; i++) {
                    provider.jwks.push(newJWKs[i]);
                }
            }
        }
    }

    /**
     * @dev 移除特定JWK
     */
    function _removeJWK(AllProvidersJWKs storage jwks, string memory issuer, bytes memory jwkId) internal {
        for (uint256 i = 0; i < jwks.entries.length; i++) {
            if (Strings.equal(jwks.entries[i].issuer, issuer)) {
                ProviderJWKs storage provider = jwks.entries[i];
                for (uint256 j = 0; j < provider.jwks.length; j++) {
                    if (keccak256(_getJWKId(provider.jwks[j])) == keccak256(jwkId)) {
                        // 移除该JWK
                        for (uint256 k = j; k < provider.jwks.length - 1; k++) {
                            provider.jwks[k] = provider.jwks[k + 1];
                        }
                        provider.jwks.pop();
                        return;
                    }
                }
                return;
            }
        }
    }

    /**
     * @dev 根据发行者和JWK ID获取JWK
     */
    function _getJWKByIssuer(
        AllProvidersJWKs storage jwks,
        string memory issuer,
        bytes memory jwkId
    ) internal view returns (JWK memory) {
        for (uint256 i = 0; i < jwks.entries.length; i++) {
            if (Strings.equal(jwks.entries[i].issuer, issuer)) {
                ProviderJWKs storage provider = jwks.entries[i];
                for (uint256 j = 0; j < provider.jwks.length; j++) {
                    if (keccak256(_getJWKId(provider.jwks[j])) == keccak256(jwkId)) {
                        return provider.jwks[j];
                    }
                }
                break;
            }
        }
        revert JWKNotFound();
    }

    /**
     * @dev 获取JWK的ID
     */
    function _getJWKId(JWK memory jwk) internal pure returns (bytes memory) {
        if (jwk.variant == 0) {
            // RSA_JWK
            RSA_JWK memory rsaJWK = abi.decode(jwk.data, (RSA_JWK));
            return bytes(rsaJWK.kid);
        } else if (jwk.variant == 1) {
            // UnsupportedJWK
            UnsupportedJWK memory unsupportedJWK = abi.decode(jwk.data, (UnsupportedJWK));
            return unsupportedJWK.id;
        } else {
            revert UnknownJWKVariant();
        }
    }

    /**
     * @dev 字符串比较函数（返回 -1, 0, 1）
     */
    function _compareStrings(string memory a, string memory b) internal pure returns (int256) {
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
}
