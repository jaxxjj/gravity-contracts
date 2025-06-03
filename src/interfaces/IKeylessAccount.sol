// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@src/interfaces/IParamSubscriber.sol";

/**
 * @title IKeylessAccount
 * @dev 管理无密钥账户系统的接口，使用BN254曲线的零知识证明验证
 * 基于Aptos keyless_account模块设计，适配以太坊架构
 */
interface IKeylessAccount is IParamSubscriber {
    // ======== 错误定义 ========
    error KeylessAccount__ParameterNotFound(string key);
    error InvalidTrainingWheelsPK();
    error InvalidProof();
    error InvalidSignature();
    error NotAuthorized();
    error AccountCreationFailed();
    error JWTVerificationFailed();
    error ExceededMaxSignaturesPerTxn();
    error ExceededMaxExpHorizon();

    // ======== 结构体定义 ========
    /**
     * @dev 系统配置参数
     */
    struct Configuration {
        /// @dev 覆盖`aud`值，用于恢复服务
        string[] override_aud_vals;
        /// @dev 每个交易最多支持的无密钥签名数量
        uint16 max_signatures_per_txn;
        /// @dev JWT发布时间后EPK过期可设置的最大秒数
        uint64 max_exp_horizon_secs;
        /// @dev 训练轮公钥，如果启用
        bytes training_wheels_pubkey;
        /// @dev 电路支持的最大临时公钥长度（93字节）
        uint16 max_commited_epk_bytes;
        /// @dev 电路支持的JWT的`iss`字段值的最大长度
        uint16 max_iss_val_bytes;
        /// @dev 电路支持的JWT字段名和值的最大长度
        uint16 max_extra_field_bytes;
        /// @dev 电路支持的base64url编码的JWT头的最大长度
        uint32 max_jwt_header_b64_bytes;
        /// @dev 验证器合约地址
        address verifier_address;
    }

    /**
     * @dev 无密钥账户信息
     */
    struct KeylessAccountInfo {
        address account;
        uint256 nonce;
        bytes32 jwkHash;
        string issuer;
        uint256 creationTimestamp;
    }

    // ======== 事件定义 ========
    event KeylessAccountCreated(address indexed account, string indexed issuer, bytes32 jwkHash);
    event KeylessAccountRecovered(address indexed account, string indexed issuer, bytes32 newJwkHash);
    event VerifierContractUpdated(address newVerifier);
    event ConfigurationUpdated(bytes32 configHash);
    event OverrideAudAdded(string value);
    event OverrideAudRemoved(string value);
    event ConfigParamUpdated(string indexed key, uint256 oldValue, uint256 newValue);

    // ======== 函数声明 ========
    /**
     * @dev 初始化函数
     */
    function initialize() external;

    /**
     * @dev 创建无密钥账户
     * @param proof Groth16证明（未压缩格式，按EIP-197标准）
     * @param jwkHash JWK哈希
     * @param issuer JWT发行者（如"https://accounts.google.com"）
     * @param publicInputs 公共输入
     */
    function createKeylessAccount(
        uint256[8] calldata proof,
        bytes32 jwkHash,
        string calldata issuer,
        uint256[3] calldata publicInputs
    ) external returns (address);

    /**
     * @dev 创建无密钥账户（使用压缩格式的证明）
     */
    function createKeylessAccountCompressed(
        uint256[4] calldata compressedProof,
        bytes32 jwkHash,
        string calldata issuer,
        uint256[3] calldata publicInputs
    ) external returns (address);

    /**
     * @dev 恢复无密钥账户（更改jwk）
     */
    function recoverKeylessAccount(
        uint256[8] calldata proof,
        address accountAddress,
        bytes32 newJwkHash,
        uint256[3] calldata publicInputs
    ) external;

    /**
     * @dev 恢复无密钥账户（使用压缩格式的证明）
     */
    function recoverKeylessAccountCompressed(
        uint256[4] calldata compressedProof,
        address accountAddress,
        bytes32 newJwkHash,
        uint256[3] calldata publicInputs
    ) external;

    /**
     * @dev 获取账户信息
     */
    function getAccountInfo(address account) external view returns (KeylessAccountInfo memory);

    /**
     * @dev 获取当前配置
     */
    function getConfiguration() external view returns (Configuration memory);
}
