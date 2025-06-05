// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "@src/interfaces/IParamSubscriber.sol";

/**
 * @title IJWKManager
 * @dev Interface for managing JSON Web Keys (JWKs), supporting OIDC providers and federated JWKs
 * Based on Aptos JWK system design, adapted for Gravity chain architecture
 */
interface IJWKManager is IParamSubscriber {
    // ======== Error Definitions ========
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

    // ======== Struct Definitions ========

    /// @dev OIDC provider information
    struct OIDCProvider {
        string name; // Provider name, e.g., "https://accounts.google.com"
        string configUrl; // OpenID configuration URL
        bool active; // Whether the provider is active
    }

    /// @dev RSA JWK structure
    struct RSA_JWK {
        string kid; // Key ID
        string kty; // Key Type (RSA)
        string alg; // Algorithm (RS256, etc.)
        string e; // Public exponent
        string n; // Modulus
    }

    /// @dev Unsupported JWK type
    struct UnsupportedJWK {
        bytes id;
        bytes payload;
    }

    /// @dev JWK union type
    struct JWK {
        uint8 variant; // 0: RSA_JWK, 1: UnsupportedJWK
        bytes data; // Encoded JWK data
    }

    /// @dev Provider's JWK collection
    struct ProviderJWKs {
        string issuer; // Issuer
        uint64 version; // Version number
        JWK[] jwks; // JWK array, sorted by kid
    }

    /// @dev All providers' JWK collection
    struct AllProvidersJWKs {
        ProviderJWKs[] entries; // Provider array sorted by issuer
    }

    /// @dev Patch operation types
    enum PatchType {
        RemoveAll, // Remove all
        RemoveIssuer, // Remove specific issuer
        RemoveJWK, // Remove specific JWK
        UpsertJWK // Insert or update JWK

    }

    /// @dev Patch operation
    struct Patch {
        PatchType patchType;
        string issuer; // For RemoveIssuer, RemoveJWK, UpsertJWK
        bytes jwkId; // For RemoveJWK
        JWK jwk; // For UpsertJWK
    }

    // ======== Event Definitions ========
    event OIDCProviderAdded(string indexed name, string configUrl);
    event OIDCProviderRemoved(string indexed name);
    event OIDCProviderUpdated(string indexed name, string newConfigUrl);
    event ObservedJWKsUpdated(uint256 indexed epoch, bytes32 indexed dataHash);
    event PatchedJWKsRegenerated(bytes32 indexed dataHash);
    event PatchesUpdated(uint256 patchCount);
    event FederatedJWKsUpdated(address indexed dapp, string indexed issuer);
    event ConfigParamUpdated(string indexed key, uint256 oldValue, uint256 newValue);

    // ======== Function Declarations ========

    /**
     * @dev Initializes the JWKManager contract
     * Sets default configuration parameters for JWT validation
     */
    function initialize() external;

    /**
     * @dev Adds or updates an OIDC provider
     * @param name The provider name (issuer URL)
     * @param configUrl The OpenID configuration URL
     */
    function upsertOIDCProvider(string calldata name, string calldata configUrl) external;

    /**
     * @dev Removes an OIDC provider by marking it as inactive
     * @param name The provider name to remove
     */
    function removeOIDCProvider(
        string calldata name
    ) external;

    /**
     * @dev Returns all active OIDC providers
     * @return Array of active OIDCProvider structs
     */
    function getActiveProviders() external view returns (OIDCProvider[] memory);

    /**
     * @dev Updates observed JWKs (called by consensus layer only)
     * Corresponds to Aptos's upsert_into_observed_jwks function
     * @param providerJWKsArray Array of provider JWK sets to update
     */
    function upsertObservedJWKs(
        ProviderJWKs[] calldata providerJWKsArray
    ) external;

    /**
     * @dev Removes an issuer from observed JWKs (governance only)
     * @param issuer The issuer to remove
     */
    function removeIssuerFromObservedJWKs(
        string calldata issuer
    ) external;

    /**
     * @dev Sets patches for JWK modifications (governance only)
     * @param newPatches Array of patches to apply
     */
    function setPatches(
        Patch[] calldata newPatches
    ) external;

    /**
     * @dev Adds a single patch to the existing patch set
     * @param patch The patch to add
     */
    function addPatch(
        Patch calldata patch
    ) external;

    /**
     * @dev Updates federated JWK set for a dApp
     * Corresponds to Aptos's update_federated_jwk_set function
     * @param issuer The issuer for the JWK set
     * @param kidArray Array of key IDs
     * @param algArray Array of algorithms
     * @param eArray Array of public exponents
     * @param nArray Array of moduli
     */
    function updateFederatedJWKSet(
        string calldata issuer,
        string[] calldata kidArray,
        string[] calldata algArray,
        string[] calldata eArray,
        string[] calldata nArray
    ) external;

    /**
     * @dev Applies patches to federated JWKs for the calling dApp
     * @param patchArray Array of patches to apply
     */
    function patchFederatedJWKs(
        Patch[] calldata patchArray
    ) external;

    /**
     * @dev Gets a patched JWK by issuer and key ID
     * @param issuer The issuer of the JWK
     * @param jwkId The key ID to look up
     * @return The JWK struct
     */
    function getPatchedJWK(string calldata issuer, bytes calldata jwkId) external view returns (JWK memory);

    /**
     * @dev Attempts to get a patched JWK without reverting on failure
     * @param issuer The issuer of the JWK
     * @param jwkId The key ID to look up
     * @return found Whether the JWK was found
     * @return jwk The JWK struct (empty if not found)
     */
    function tryGetPatchedJWK(
        string calldata issuer,
        bytes calldata jwkId
    ) external view returns (bool found, JWK memory jwk);

    /**
     * @dev Gets a federated JWK for a specific dApp
     * @param dapp The dApp address
     * @param issuer The issuer of the JWK
     * @param jwkId The key ID to look up
     * @return The JWK struct
     */
    function getFederatedJWK(
        address dapp,
        string calldata issuer,
        bytes calldata jwkId
    ) external view returns (JWK memory);

    /**
     * @dev Returns all observed JWKs
     * @return The complete observed JWK set
     */
    function getObservedJWKs() external view returns (AllProvidersJWKs memory);

    /**
     * @dev Returns all patched JWKs (observed + patches applied)
     * @return The complete patched JWK set
     */
    function getPatchedJWKs() external view returns (AllProvidersJWKs memory);

    /**
     * @dev Returns federated JWKs for a specific dApp
     * @param dapp The dApp address
     * @return The dApp's federated JWK set
     */
    function getFederatedJWKs(
        address dapp
    ) external view returns (AllProvidersJWKs memory);

    /**
     * @dev Returns all current patches
     * @return Array of all patches
     */
    function getPatches() external view returns (Patch[] memory);

    /**
     * @dev Maximum size in bytes for federated JWKs
     * @return The maximum size limit
     */
    function MAX_FEDERATED_JWKS_SIZE_BYTES() external view returns (uint256);

    /**
     * @dev Maximum number of providers per request
     * @return The maximum provider limit
     */
    function MAX_PROVIDERS_PER_REQUEST() external view returns (uint256);

    /**
     * @dev Maximum number of JWKs per provider
     * @return The maximum JWK limit per provider
     */
    function MAX_JWKS_PER_PROVIDER() external view returns (uint256);

    /**
     * @dev Maximum number of signatures per transaction
     * @return The current limit
     */
    function maxSignaturesPerTxn() external view returns (uint256);

    /**
     * @dev Maximum expiration horizon in seconds
     * @return The current limit
     */
    function maxExpHorizonSecs() external view returns (uint256);

    /**
     * @dev Maximum committed EPK bytes
     * @return The current limit
     */
    function maxCommittedEpkBytes() external view returns (uint256);

    /**
     * @dev Maximum issuer value bytes
     * @return The current limit
     */
    function maxIssValBytes() external view returns (uint256);

    /**
     * @dev Maximum extra field bytes
     * @return The current limit
     */
    function maxExtraFieldBytes() external view returns (uint256);

    /**
     * @dev Maximum JWT header base64 bytes
     * @return The current limit
     */
    function maxJwtHeaderB64Bytes() external view returns (uint256);

    /**
     * @dev Gets supported provider information by index
     * @param index The provider index
     * @return name The provider name
     * @return configUrl The configuration URL
     * @return active Whether the provider is active
     */
    function supportedProviders(
        uint256 index
    ) external view returns (string memory name, string memory configUrl, bool active);

    /**
     * @dev Gets the index of a provider by name
     * @param name The provider name
     * @return The provider index (0 if not found)
     */
    function providerIndex(
        string calldata name
    ) external view returns (uint256);
}
