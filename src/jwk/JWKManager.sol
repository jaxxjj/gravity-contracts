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
 * @dev Manages JSON Web Keys (JWKs), supporting OIDC providers and federated JWKs
 * Based on Aptos JWK system design, adapted for Gravity chain architecture
 */
contract JWKManager is System, Protectable, IParamSubscriber, IJWKManager, Initializable {
    using Strings for string;

    // ======== Constants ========
    uint256 public constant MAX_FEDERATED_JWKS_SIZE_BYTES = 2 * 1024; // 2 KiB
    uint256 public constant MAX_PROVIDERS_PER_REQUEST = 50;
    uint256 public constant MAX_JWKS_PER_PROVIDER = 100;

    // ======== State Variables ========

    /// @dev Supported OIDC providers
    OIDCProvider[] public supportedProviders;
    mapping(string => uint256) public providerIndex; // name => index (index + 1, 0 means not exists)

    /// @dev Validator observed JWKs (written by consensus)
    AllProvidersJWKs private observedJWKs;

    /// @dev JWKs after applying patches (final used)
    AllProvidersJWKs private patchedJWKs;

    /// @dev Governance set patches
    Patch[] public patches;

    /// @dev Federated JWKs: dapp address => AllProvidersJWKs
    mapping(address => AllProvidersJWKs) private federatedJWKs;

    /// @dev Configuration parameters
    uint256 public maxSignaturesPerTxn;
    uint256 public maxExpHorizonSecs;
    uint256 public maxCommittedEpkBytes;
    uint256 public maxIssValBytes;
    uint256 public maxExtraFieldBytes;
    uint256 public maxJwtHeaderB64Bytes;

    modifier validIssuer(
        string memory issuer
    ) {
        if (bytes(issuer).length == 0) revert InvalidOIDCProvider();
        _;
    }

    // ======== Initialization ========

    /**
     * @dev Disable initializers in constructor
     * @custom:oz-upgrades-unsafe-allow constructor
     */
    constructor() {
        _disableInitializers();
    }

    /// @inheritdoc IJWKManager
    function initialize() external initializer onlyGenesis {
        maxSignaturesPerTxn = 10;
        maxExpHorizonSecs = 3600; // 1 hour
        maxCommittedEpkBytes = 93;
        maxIssValBytes = 256;
        maxExtraFieldBytes = 256;
        maxJwtHeaderB64Bytes = 1024;
    }

    // ======== Parameter Management ========

    /// @inheritdoc IParamSubscriber
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

    // ======== OIDC Provider Management ========

    /// @inheritdoc IJWKManager
    function upsertOIDCProvider(string calldata name, string calldata configUrl) external onlyGov validIssuer(name) {
        uint256 index = providerIndex[name];

        if (index == 0) {
            // Add new provider
            supportedProviders.push(OIDCProvider({ name: name, configUrl: configUrl, active: true }));
            providerIndex[name] = supportedProviders.length;
            emit OIDCProviderAdded(name, configUrl);
        } else {
            // Update existing provider
            OIDCProvider storage provider = supportedProviders[index - 1];
            provider.configUrl = configUrl;
            provider.active = true;
            emit OIDCProviderUpdated(name, configUrl);
        }
    }

    /// @inheritdoc IJWKManager
    function removeOIDCProvider(
        string calldata name
    ) external onlyGov {
        uint256 index = providerIndex[name];
        if (index == 0) revert IssuerNotFound();

        // Mark as inactive instead of deleting to maintain index consistency
        supportedProviders[index - 1].active = false;
        emit OIDCProviderRemoved(name);
    }

    /// @inheritdoc IJWKManager
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

    // ======== ObservedJWKs Management (called by consensus layer) ========

    /// @inheritdoc IJWKManager
    function upsertObservedJWKs(
        ProviderJWKs[] calldata providerJWKsArray
    ) external onlySystemCaller {
        // Update observedJWKs
        for (uint256 i = 0; i < providerJWKsArray.length; i++) {
            _upsertProviderJWKs(observedJWKs, providerJWKsArray[i]);
        }

        // Regenerate patchedJWKs
        _regeneratePatchedJWKs();

        emit ObservedJWKsUpdated(block.number, keccak256(abi.encode(observedJWKs)));
    }

    /// @inheritdoc IJWKManager
    function removeIssuerFromObservedJWKs(
        string calldata issuer
    ) external onlyGov validIssuer(issuer) {
        _removeIssuer(observedJWKs, issuer);
        _regeneratePatchedJWKs();
        emit ObservedJWKsUpdated(block.number, keccak256(abi.encode(observedJWKs)));
    }

    // ======== Patch Management ========

    /// @inheritdoc IJWKManager
    function setPatches(
        Patch[] calldata newPatches
    ) external onlyGov {
        delete patches;
        for (uint256 i = 0; i < newPatches.length; i++) {
            patches.push(newPatches[i]);
        }

        _regeneratePatchedJWKs();
        emit PatchesUpdated(newPatches.length);
    }

    /// @inheritdoc IJWKManager
    function addPatch(
        Patch calldata patch
    ) external onlyGov {
        patches.push(patch);
        _regeneratePatchedJWKs();
        emit PatchesUpdated(patches.length);
    }

    // ======== Federated JWKs Management ========

    /// @inheritdoc IJWKManager
    function updateFederatedJWKSet(
        string calldata issuer,
        string[] calldata kidArray,
        string[] calldata algArray,
        string[] calldata eArray,
        string[] calldata nArray
    ) external validIssuer(issuer) {
        if (kidArray.length == 0) revert InvalidJWKFormat();
        if (kidArray.length != algArray.length || kidArray.length != eArray.length || kidArray.length != nArray.length)
        {
            revert InvalidJWKFormat();
        }

        // Get or create dapp's federated JWKs
        AllProvidersJWKs storage dappJWKs = federatedJWKs[msg.sender];

        // First remove all existing JWKs for this issuer
        _removeIssuer(dappJWKs, issuer);

        // Create new ProviderJWKs
        ProviderJWKs memory newProviderJWKs = ProviderJWKs({
            issuer: issuer,
            version: 1, // Simplified version management
            jwks: new JWK[](kidArray.length)
        });

        // Add all JWKs
        for (uint256 i = 0; i < kidArray.length; i++) {
            RSA_JWK memory rsaJWK =
                RSA_JWK({ kid: kidArray[i], kty: "RSA", alg: algArray[i], e: eArray[i], n: nArray[i] });

            newProviderJWKs.jwks[i] = JWK({
                variant: 0, // RSA_JWK
                data: abi.encode(rsaJWK)
            });
        }

        // Insert new ProviderJWKs
        _upsertProviderJWKs(dappJWKs, newProviderJWKs);

        // Check size limit
        bytes memory encoded = abi.encode(dappJWKs);
        if (encoded.length > MAX_FEDERATED_JWKS_SIZE_BYTES) {
            revert FederatedJWKsTooLarge();
        }

        emit FederatedJWKsUpdated(msg.sender, issuer);
    }

    /// @inheritdoc IJWKManager
    function patchFederatedJWKs(
        Patch[] calldata patchArray
    ) external {
        AllProvidersJWKs storage dappJWKs = federatedJWKs[msg.sender];

        for (uint256 i = 0; i < patchArray.length; i++) {
            _applyPatch(dappJWKs, patchArray[i]);
        }

        // Check size limit
        bytes memory encoded = abi.encode(dappJWKs);
        if (encoded.length > MAX_FEDERATED_JWKS_SIZE_BYTES) {
            revert FederatedJWKsTooLarge();
        }

        emit FederatedJWKsUpdated(msg.sender, "");
    }

    // ======== Query Functions ========

    /// @inheritdoc IJWKManager
    function getPatchedJWK(string calldata issuer, bytes calldata jwkId) external view returns (JWK memory) {
        return _getJWKByIssuer(patchedJWKs, issuer, jwkId);
    }

    /// @inheritdoc IJWKManager
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

    /// @inheritdoc IJWKManager
    function getFederatedJWK(
        address dapp,
        string calldata issuer,
        bytes calldata jwkId
    ) external view returns (JWK memory) {
        return _getJWKByIssuer(federatedJWKs[dapp], issuer, jwkId);
    }

    /// @inheritdoc IJWKManager
    function getObservedJWKs() external view returns (AllProvidersJWKs memory) {
        return observedJWKs;
    }

    /// @inheritdoc IJWKManager
    function getPatchedJWKs() external view returns (AllProvidersJWKs memory) {
        return patchedJWKs;
    }

    /// @inheritdoc IJWKManager
    function getFederatedJWKs(
        address dapp
    ) external view returns (AllProvidersJWKs memory) {
        return federatedJWKs[dapp];
    }

    /// @inheritdoc IJWKManager
    function getPatches() external view returns (Patch[] memory) {
        return patches;
    }

    // ======== Internal Functions ========

    /**
     * @dev Regenerates patched JWKs by applying all patches to observed JWKs
     */
    function _regeneratePatchedJWKs() internal {
        // Copy observedJWKs to patchedJWKs
        _copyAllProvidersJWKs(patchedJWKs, observedJWKs);

        // Apply all patches
        for (uint256 i = 0; i < patches.length; i++) {
            _applyPatch(patchedJWKs, patches[i]);
        }

        emit PatchedJWKsRegenerated(keccak256(abi.encode(patchedJWKs)));
    }

    /**
     * @dev Copies AllProvidersJWKs from source to destination
     */
    function _copyAllProvidersJWKs(AllProvidersJWKs storage dest, AllProvidersJWKs storage src) internal {
        // Clear destination
        delete dest.entries;

        // Copy all entries
        for (uint256 i = 0; i < src.entries.length; i++) {
            dest.entries.push();
            ProviderJWKs storage destEntry = dest.entries[dest.entries.length - 1];
            ProviderJWKs storage srcEntry = src.entries[i];

            // Copy fields individually instead of direct struct assignment
            destEntry.issuer = srcEntry.issuer;
            destEntry.version = srcEntry.version;

            delete destEntry.jwks;
            for (uint256 j = 0; j < srcEntry.jwks.length; j++) {
                destEntry.jwks.push(srcEntry.jwks[j]);
            }
        }
    }

    /**
     * @dev Applies a patch to the JWK set
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
     * @dev Inserts or updates ProviderJWKs
     */
    function _upsertProviderJWKs(AllProvidersJWKs storage jwks, ProviderJWKs memory providerJWKs) internal {
        // Find if already exists
        for (uint256 i = 0; i < jwks.entries.length; i++) {
            if (Strings.equal(jwks.entries[i].issuer, providerJWKs.issuer)) {
                // Update existing entry - avoid direct assignment, copy fields individually
                jwks.entries[i].issuer = providerJWKs.issuer;
                jwks.entries[i].version = providerJWKs.version;

                // Clear and re-add jwks array
                delete jwks.entries[i].jwks;
                for (uint256 j = 0; j < providerJWKs.jwks.length; j++) {
                    jwks.entries[i].jwks.push(providerJWKs.jwks[j]);
                }
                return;
            }
        }

        // Insert new entry (maintain sorting by issuer)
        uint256 insertIndex = 0;
        for (uint256 i = 0; i < jwks.entries.length; i++) {
            if (_compareStrings(providerJWKs.issuer, jwks.entries[i].issuer) < 0) {
                insertIndex = i;
                break;
            }
            insertIndex = i + 1;
        }

        // Insert at specified position - avoid direct assignment, copy fields individually
        jwks.entries.push();
        for (uint256 i = jwks.entries.length - 1; i > insertIndex; i--) {
            // Copy fields individually
            jwks.entries[i].issuer = jwks.entries[i - 1].issuer;
            jwks.entries[i].version = jwks.entries[i - 1].version;
            delete jwks.entries[i].jwks;
            for (uint256 j = 0; j < jwks.entries[i - 1].jwks.length; j++) {
                jwks.entries[i].jwks.push(jwks.entries[i - 1].jwks[j]);
            }
        }

        // Set new entry
        jwks.entries[insertIndex].issuer = providerJWKs.issuer;
        jwks.entries[insertIndex].version = providerJWKs.version;
        delete jwks.entries[insertIndex].jwks;
        for (uint256 j = 0; j < providerJWKs.jwks.length; j++) {
            jwks.entries[insertIndex].jwks.push(providerJWKs.jwks[j]);
        }
    }

    /**
     * @dev Removes an issuer from the JWK set
     */
    function _removeIssuer(AllProvidersJWKs storage jwks, string memory issuer) internal {
        for (uint256 i = 0; i < jwks.entries.length; i++) {
            if (Strings.equal(jwks.entries[i].issuer, issuer)) {
                // Remove this entry - copy fields individually instead of direct assignment
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
     * @dev Inserts or updates a JWK
     */
    function _upsertJWK(AllProvidersJWKs storage jwks, string memory issuer, JWK memory jwk) internal {
        // Find or create ProviderJWKs
        int256 _providerIndex = -1;
        for (uint256 i = 0; i < jwks.entries.length; i++) {
            if (Strings.equal(jwks.entries[i].issuer, issuer)) {
                _providerIndex = int256(i);
                break;
            }
        }

        if (_providerIndex == -1) {
            // Create new ProviderJWKs
            ProviderJWKs memory newProvider = ProviderJWKs({ issuer: issuer, version: 1, jwks: new JWK[](1) });
            newProvider.jwks[0] = jwk;
            _upsertProviderJWKs(jwks, newProvider);
        } else {
            // Update JWK in existing ProviderJWKs
            ProviderJWKs storage provider = jwks.entries[uint256(_providerIndex)];
            bytes memory jwkId = _getJWKId(jwk);

            // Find if JWK already exists
            bool found = false;
            for (uint256 i = 0; i < provider.jwks.length; i++) {
                if (keccak256(_getJWKId(provider.jwks[i])) == keccak256(jwkId)) {
                    provider.jwks[i] = jwk;
                    found = true;
                    break;
                }
            }

            if (!found) {
                // Add new JWK (maintain sorting by kid)
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
     * @dev Removes a specific JWK
     */
    function _removeJWK(AllProvidersJWKs storage jwks, string memory issuer, bytes memory jwkId) internal {
        for (uint256 i = 0; i < jwks.entries.length; i++) {
            if (Strings.equal(jwks.entries[i].issuer, issuer)) {
                ProviderJWKs storage provider = jwks.entries[i];
                for (uint256 j = 0; j < provider.jwks.length; j++) {
                    if (keccak256(_getJWKId(provider.jwks[j])) == keccak256(jwkId)) {
                        // Remove this JWK
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
     * @dev Gets JWK by issuer and JWK ID
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
     * @dev Gets the ID of a JWK
     */
    function _getJWKId(
        JWK memory jwk
    ) internal pure returns (bytes memory) {
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
     * @dev String comparison function (returns -1, 0, 1)
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
