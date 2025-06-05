// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "@src/interfaces/IParamSubscriber.sol";

/**
 * @title IKeylessAccount
 * @dev Interface for managing keyless account system using BN254 curve zero-knowledge proof verification
 * Based on Aptos keyless_account module design, adapted for Ethereum architecture
 */
interface IKeylessAccount is IParamSubscriber {
    // ======== Error Definitions ========
    error KeylessAccount__ParameterNotFound(string key);
    error InvalidTrainingWheelsPK();
    error InvalidProof();
    error InvalidSignature();
    error NotAuthorized();
    error AccountCreationFailed();
    error JWTVerificationFailed();
    error ExceededMaxSignaturesPerTxn();
    error ExceededMaxExpHorizon();

    // ======== Struct Definitions ========
    /**
     * @dev System configuration parameters
     */
    struct Configuration {
        /// @dev Override `aud` values for recovery service
        string[] override_aud_vals;
        /// @dev Maximum number of keyless signatures supported per transaction
        uint16 max_signatures_per_txn;
        /// @dev Maximum seconds EPK can be set to expire after JWT issuance time
        uint64 max_exp_horizon_secs;
        /// @dev Training wheels public key, if enabled
        bytes training_wheels_pubkey;
        /// @dev Maximum ephemeral public key length supported by circuit (93 bytes)
        uint16 max_commited_epk_bytes;
        /// @dev Maximum length of JWT `iss` field value supported by circuit
        uint16 max_iss_val_bytes;
        /// @dev Maximum length of JWT field names and values supported by circuit
        uint16 max_extra_field_bytes;
        /// @dev Maximum length of base64url-encoded JWT header supported by circuit
        uint32 max_jwt_header_b64_bytes;
        /// @dev Verifier contract address
        address verifier_address;
    }

    /**
     * @dev Keyless account information
     */
    struct KeylessAccountInfo {
        address account;
        uint256 nonce;
        bytes32 jwkHash;
        string issuer;
        uint256 creationTimestamp;
    }

    // ======== Event Definitions ========
    event KeylessAccountCreated(address indexed account, string indexed issuer, bytes32 jwkHash);
    event KeylessAccountRecovered(address indexed account, string indexed issuer, bytes32 newJwkHash);
    event VerifierContractUpdated(address newVerifier);
    event ConfigurationUpdated(bytes32 configHash);
    event OverrideAudAdded(string value);
    event OverrideAudRemoved(string value);
    event ConfigParamUpdated(string indexed key, uint256 oldValue, uint256 newValue);

    // ======== Function Declarations ========
    /**
     * @dev Initializes the KeylessAccount contract
     */
    function initialize() external;

    /**
     * @dev Create keyless account
     * @param proof Groth16 proof (uncompressed, EIP-197 standard)
     * @param jwkHash JWK hash
     * @param issuer JWT issuer (e.g., "https://accounts.google.com")
     * @param publicInputs Public inputs for proof verification
     */
    function createKeylessAccount(
        uint256[8] calldata proof,
        bytes32 jwkHash,
        string calldata issuer,
        uint256[3] calldata publicInputs
    ) external returns (address);

    /**
     * @dev Create keyless account using compressed proof format
     * @param compressedProof Compressed Groth16 proof
     * @param jwkHash JWK hash
     * @param issuer JWT issuer
     * @param publicInputs Public inputs for proof verification
     */
    function createKeylessAccountCompressed(
        uint256[4] calldata compressedProof,
        bytes32 jwkHash,
        string calldata issuer,
        uint256[3] calldata publicInputs
    ) external returns (address);

    /**
     * @dev Recover keyless account (change JWK)
     * @param proof Groth16 proof (uncompressed)
     * @param accountAddress Account address to recover
     * @param newJwkHash New JWK hash
     * @param publicInputs Public inputs for proof verification
     */
    function recoverKeylessAccount(
        uint256[8] calldata proof,
        address accountAddress,
        bytes32 newJwkHash,
        uint256[3] calldata publicInputs
    ) external;

    /**
     * @dev Recover keyless account using compressed proof format
     * @param compressedProof Compressed Groth16 proof
     * @param accountAddress Account address to recover
     * @param newJwkHash New JWK hash
     * @param publicInputs Public inputs for proof verification
     */
    function recoverKeylessAccountCompressed(
        uint256[4] calldata compressedProof,
        address accountAddress,
        bytes32 newJwkHash,
        uint256[3] calldata publicInputs
    ) external;

    /**
     * @dev Get account information
     * @param account Account address
     * @return Account information struct
     */
    function getAccountInfo(
        address account
    ) external view returns (KeylessAccountInfo memory);

    /**
     * @dev Get current configuration
     * @return Current system configuration
     */
    function getConfiguration() external view returns (Configuration memory);
}
