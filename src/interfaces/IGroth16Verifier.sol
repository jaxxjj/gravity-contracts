// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title IVerifier
 * @dev 用于验证Groth16零知识证明的接口
 */
interface IGroth16Verifier {
    /// 部分提供的公共输入值大于字段模数
    /// @dev 由于这可能是错误的危险来源，因此公共输入元素不会自动减少
    error PublicInputNotInField();

    /// 证明无效
    /// @dev 这意味着提供的Groth16证明点不在其曲线上，配对方程失败，或证明不适用于提供的公共输入
    error ProofInvalid();

    /**
     * @dev 压缩证明
     * @notice 如果曲线点无效，将使用InvalidProof回滚，但不验证证明本身
     * @param proof 未压缩的Groth16证明。元素按照与verifyProof相同的顺序。即按照EIP-197编码的Groth16点(A, B, C)
     * @return compressed 压缩的证明。元素按照与verifyCompressedProof相同的顺序。即压缩格式的点(A, B, C)
     */
    function compressProof(uint256[8] calldata proof) external view returns (uint256[4] memory compressed);

    /**
     * @dev 验证带有压缩点的Groth16证明
     * @notice 如果证明无效则使用InvalidProof回滚，如果公共输入未归约则使用PublicInputNotInField回滚
     * @notice 没有返回值。如果函数不回滚，则证明已成功验证
     * @param compressedProof 压缩格式的点(A, B, C)，与compressProof的输出匹配
     * @param input 标量字段Fr中的公共输入字段元素。元素必须已归约
     */
    function verifyCompressedProof(uint256[4] calldata compressedProof, uint256[3] calldata input) external view;

    /**
     * @dev 验证未压缩的Groth16证明
     * @notice 如果证明无效则使用InvalidProof回滚，如果公共输入未归约则使用PublicInputNotInField回滚
     * @notice 没有返回值。如果函数不回滚，则证明已成功验证
     * @param proof EIP-197格式的点(A, B, C)，与compressProof的输出匹配
     * @param input 标量字段Fr中的公共输入字段元素。元素必须已归约
     */
    function verifyProof(uint256[8] calldata proof, uint256[3] calldata input) external view;
}
