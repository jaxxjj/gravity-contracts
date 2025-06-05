// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title IVerifier
 * @dev Interface for verifying Groth16 zero-knowledge proofs
 */
interface IGroth16Verifier {
    /// @dev Public input value exceeds field modulus
    error PublicInputNotInField();

    /// @dev Invalid proof
    error ProofInvalid();

    /**
     * @dev Compress proof
     * @notice If curve point is invalid, revert with InvalidProof, but do not verify proof itself
     * @param proof Uncompressed Groth16 proof. Elements in the same order as verifyProof.
     * @return compressed Compressed proof. Elements in the same order as verifyCompressedProof.
     */
    function compressProof(
        uint256[8] calldata proof
    ) external view returns (uint256[4] memory compressed);

    /**
     * @dev Verify Groth16 proof with compressed points
     * @notice Revert with InvalidProof if proof is invalid, revert with PublicInputNotInField if public input is not reduced
     * @notice No return value. If the function does not revert, the proof has been successfully verified
     * @param compressedProof Compressed points (A, B, C) matching the output of compressProof
     * @param input Public input field elements in the scalar field Fr. Elements must be reduced
     */
    function verifyCompressedProof(uint256[4] calldata compressedProof, uint256[3] calldata input) external view;

    /**
     * @dev Verify uncompressed Groth16 proof
     * @notice Revert with InvalidProof if proof is invalid, revert with PublicInputNotInField if public input is not reduced
     * @notice No return value. If the function does not revert, the proof has been successfully verified
     * @param proof EIP-197 formatted points (A, B, C) matching the output of compressProof
     * @param input Public input field elements in the scalar field Fr. Elements must be reduced
     */
    function verifyProof(uint256[8] calldata proof, uint256[3] calldata input) external view;
}
