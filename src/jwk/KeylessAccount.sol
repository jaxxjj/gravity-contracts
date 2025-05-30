// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@src/System.sol";
import "@src/access/Protectable.sol";
import "@src/interfaces/IParamSubscriber.sol";
import "@src/interfaces/IReconfigurableModule.sol";
import "@openzeppelin-upgrades/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "./Verifier.sol"; // 引入Verifier合约

/**
 * @title KeylessAccount
 * @dev 管理无密钥账户系统，使用BN254曲线的零知识证明验证
 * 基于Aptos keyless_account模块设计，适配以太坊架构
 */
contract KeylessAccount is System, Protectable, IParamSubscriber, IReconfigurableModule, Initializable {
    using Strings for string;

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

    // ======== 状态变量 ========
    
    /// @dev 系统配置
    Configuration private configuration;
    
    /// @dev 注册的无密钥账户: 地址 => 账户信息
    mapping(address => KeylessAccountInfo) public accounts;
    
    /// @dev 待定的配置更新
    Configuration private pendingConfiguration;
    
    /// @dev 配置是否有待定更新
    bool private hasPendingConfigUpdate;

    /// @dev 验证器实例（使用合约工厂模式）
    Verifier public verifier;

    // ======== 事件定义 ========
    event KeylessAccountCreated(address indexed account, string indexed issuer, bytes32 jwkHash);
    event KeylessAccountRecovered(address indexed account, string indexed issuer, bytes32 newJwkHash);
    event TrainingWheelsUpdated(bool enabled, bytes publicKey);
    event VerifierContractUpdated(address newVerifier);
    event ConfigurationUpdated(bytes32 configHash);
    event OverrideAudAdded(string value);
    event OverrideAudRemoved(string value);
    event ConfigParamUpdated(string indexed key, uint256 oldValue, uint256 newValue);

    // ======== 修饰符 ========
    modifier onlyEOA() {
        if (tx.origin != msg.sender) {
            revert NotAuthorized();
        }
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
     * @param _config 初始配置
     * @param _verifierAddress Groth16验证器合约地址
     */
    function initialize(Configuration calldata _config, address _verifierAddress) 
        external initializer 
    {
        configuration = _config;
        hasPendingConfigUpdate = false;
        verifier = Verifier(_verifierAddress);
        
        emit ConfigurationUpdated(keccak256(abi.encode(_config)));
        emit VerifierContractUpdated(_verifierAddress);
    }

    // ======== 参数管理 ========

    /**
     * @dev 统一参数更新函数
     */
    function updateParam(string calldata key, bytes calldata value) external override onlyGov {
        if (Strings.equal(key, "maxSignaturesPerTxn")) {
            uint16 newValue = abi.decode(value, (uint16));
            uint16 oldValue = configuration.max_signatures_per_txn;
            configuration.max_signatures_per_txn = newValue;
            emit ConfigParamUpdated("maxSignaturesPerTxn", oldValue, newValue);
        } else if (Strings.equal(key, "maxExpHorizonSecs")) {
            uint64 newValue = abi.decode(value, (uint64));
            uint64 oldValue = configuration.max_exp_horizon_secs;
            configuration.max_exp_horizon_secs = newValue;
            emit ConfigParamUpdated("maxExpHorizonSecs", oldValue, newValue);
        } else if (Strings.equal(key, "maxCommitedEpkBytes")) {
            uint16 newValue = abi.decode(value, (uint16));
            uint16 oldValue = configuration.max_commited_epk_bytes;
            configuration.max_commited_epk_bytes = newValue;
            emit ConfigParamUpdated("maxCommitedEpkBytes", oldValue, newValue);
        } else if (Strings.equal(key, "maxIssValBytes")) {
            uint16 newValue = abi.decode(value, (uint16));
            uint16 oldValue = configuration.max_iss_val_bytes;
            configuration.max_iss_val_bytes = newValue;
            emit ConfigParamUpdated("maxIssValBytes", oldValue, newValue);
        } else if (Strings.equal(key, "maxExtraFieldBytes")) {
            uint16 newValue = abi.decode(value, (uint16));
            uint16 oldValue = configuration.max_extra_field_bytes;
            configuration.max_extra_field_bytes = newValue;
            emit ConfigParamUpdated("maxExtraFieldBytes", oldValue, newValue);
        } else if (Strings.equal(key, "maxJwtHeaderB64Bytes")) {
            uint32 newValue = abi.decode(value, (uint32));
            uint32 oldValue = configuration.max_jwt_header_b64_bytes;
            configuration.max_jwt_header_b64_bytes = newValue;
            emit ConfigParamUpdated("maxJwtHeaderB64Bytes", oldValue, newValue);
        } else {
            revert KeylessAccount__ParameterNotFound(key);
        }

        emit ParamChange(key, value);
    }

    // ======== 验证器管理 ========

    /**
     * @dev 更新验证器合约
     */
    function updateVerifier(address _verifierAddress) external onlyGov {
        verifier = Verifier(_verifierAddress);
        emit VerifierContractUpdated(_verifierAddress);
    }

    // ======== 配置管理 ========

    /**
     * @dev 更新系统配置，只能通过治理调用
     */
    function updateConfiguration(Configuration calldata newConfig) external onlyGov {
        configuration = newConfig;
        emit ConfigurationUpdated(keccak256(abi.encode(newConfig)));
    }

    /**
     * @dev 为下一个纪元设置配置更新
     */
    function setConfigurationForNextEpoch(Configuration calldata newConfig) external onlyGov {
        pendingConfiguration = newConfig;
        hasPendingConfigUpdate = true;
    }

    /**
     * @dev 更新训练轮公钥
     */
    function updateTrainingWheels(bool enabled, bytes calldata publicKey) external onlyGov {
        if (enabled) {
            if (publicKey.length != 32) {
                revert InvalidTrainingWheelsPK();
            }
            configuration.training_wheels_pubkey = publicKey;
        } else {
            delete configuration.training_wheels_pubkey;
        }
        emit TrainingWheelsUpdated(enabled, publicKey);
    }

    /**
     * @dev 添加覆盖aud值
     */
    function addOverrideAud(string calldata aud) external onlyGov {
        for (uint i = 0; i < configuration.override_aud_vals.length; i++) {
            if (Strings.equal(configuration.override_aud_vals[i], aud)) {
                return; // 已存在，直接返回
            }
        }
        configuration.override_aud_vals.push(aud);
        emit OverrideAudAdded(aud);
    }

    /**
     * @dev 移除覆盖aud值
     */
    function removeOverrideAud(string calldata aud) external onlyGov {
        uint256 length = configuration.override_aud_vals.length;
        for (uint i = 0; i < length; i++) {
            if (Strings.equal(configuration.override_aud_vals[i], aud)) {
                // 将最后一个元素移到当前位置，然后弹出最后一个元素
                if (i < length - 1) {
                    configuration.override_aud_vals[i] = configuration.override_aud_vals[length - 1];
                }
                configuration.override_aud_vals.pop();
                emit OverrideAudRemoved(aud);
                break;
            }
        }
    }

    // ======== 账户管理 ========

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
    ) external onlyEOA returns (address) {
        // 使用Verifier合约验证ZK证明
        try verifier.verifyProof(proof, publicInputs) {
            // 证明有效，继续处理
        } catch Error(string memory) {
            // 证明无效
            revert InvalidProof();
        }
        
        // 计算账户地址
        address accountAddress = _deriveAccountAddress(jwkHash, issuer);
        
        // 确保账户尚未创建
        if (accounts[accountAddress].creationTimestamp != 0) {
            revert AccountCreationFailed();
        }
        
        // 创建账户信息
        accounts[accountAddress] = KeylessAccountInfo({
            account: accountAddress,
            nonce: 0,
            jwkHash: jwkHash,
            issuer: issuer,
            creationTimestamp: block.timestamp
        });
        
        emit KeylessAccountCreated(accountAddress, issuer, jwkHash);
        
        return accountAddress;
    }

    /**
     * @dev 创建无密钥账户（使用压缩格式的证明）
     */
    function createKeylessAccountCompressed(
        uint256[4] calldata compressedProof, 
        bytes32 jwkHash, 
        string calldata issuer, 
        uint256[3] calldata publicInputs
    ) external onlyEOA returns (address) {
        // 使用Verifier合约验证压缩ZK证明
        try verifier.verifyCompressedProof(compressedProof, publicInputs) {
            // 证明有效，继续处理
        } catch Error(string memory) {
            // 证明无效
            revert InvalidProof();
        }
        
        // 计算账户地址
        address accountAddress = _deriveAccountAddress(jwkHash, issuer);
        
        // 确保账户尚未创建
        if (accounts[accountAddress].creationTimestamp != 0) {
            revert AccountCreationFailed();
        }
        
        // 创建账户信息
        accounts[accountAddress] = KeylessAccountInfo({
            account: accountAddress,
            nonce: 0,
            jwkHash: jwkHash,
            issuer: issuer,
            creationTimestamp: block.timestamp
        });
        
        emit KeylessAccountCreated(accountAddress, issuer, jwkHash);
        
        return accountAddress;
    }

    /**
     * @dev 恢复无密钥账户（更改jwk）
     */
    function recoverKeylessAccount(
        uint256[8] calldata proof,
        address accountAddress,
        bytes32 newJwkHash,
        uint256[3] calldata publicInputs
    ) external onlyEOA {
        // 验证账户存在
        KeylessAccountInfo storage accountInfo = accounts[accountAddress];
        if (accountInfo.creationTimestamp == 0) {
            revert NotAuthorized();
        }
        
        // 使用Verifier合约验证ZK证明
        try verifier.verifyProof(proof, publicInputs) {
            // 证明有效，继续处理
        } catch Error(string memory) {
            // 证明无效
            revert InvalidProof();
        }
        
        // 更新JWK哈希
        accountInfo.jwkHash = newJwkHash;
        
        emit KeylessAccountRecovered(accountAddress, accountInfo.issuer, newJwkHash);
    }

    /**
     * @dev 恢复无密钥账户（使用压缩格式的证明）
     */
    function recoverKeylessAccountCompressed(
        uint256[4] calldata compressedProof,
        address accountAddress,
        bytes32 newJwkHash,
        uint256[3] calldata publicInputs
    ) external onlyEOA {
        // 验证账户存在
        KeylessAccountInfo storage accountInfo = accounts[accountAddress];
        if (accountInfo.creationTimestamp == 0) {
            revert NotAuthorized();
        }
        
        // 使用Verifier合约验证ZK证明
        try verifier.verifyCompressedProof(compressedProof, publicInputs) {
            // 证明有效，继续处理
        } catch Error(string memory) {
            // 证明无效
            revert InvalidProof();
        }
        
        // 更新JWK哈希
        accountInfo.jwkHash = newJwkHash;
        
        emit KeylessAccountRecovered(accountAddress, accountInfo.issuer, newJwkHash);
    }

    /**
     * @dev 获取账户信息
     */
    function getAccountInfo(address account) external view returns (KeylessAccountInfo memory) {
        return accounts[account];
    }

    /**
     * @dev 获取当前配置
     */
    function getConfiguration() external view returns (Configuration memory) {
        return configuration;
    }

    // ======== IReconfigurableModule实现 ========

    /**
     * @dev 新纪元回调，应用待定的配置更新
     */
    function onNewEpoch() external override returns (bool) {
        if (hasPendingConfigUpdate) {
            configuration = pendingConfiguration;
            hasPendingConfigUpdate = false;
            emit ConfigurationUpdated(keccak256(abi.encode(configuration)));
        }
        
        return true;
    }

    // ======== 内部函数 ========

    /**
     * @dev 从JWK哈希和发行者导出账户地址
     */
    function _deriveAccountAddress(bytes32 jwkHash, string memory issuer) internal pure returns (address) {
        return address(uint160(uint256(keccak256(abi.encodePacked(jwkHash, issuer)))));
    }
}