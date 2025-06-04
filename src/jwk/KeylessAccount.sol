// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "@src/System.sol";
import "@src/access/Protectable.sol";
import "@src/interfaces/IParamSubscriber.sol";
import "@src/interfaces/IReconfigurableModule.sol";
import "@src/interfaces/IKeylessAccount.sol";
import "@openzeppelin-upgrades/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@src/interfaces/IGroth16Verifier.sol"; // 引入Verifier合约

/**
 * @title KeylessAccount
 * @dev 管理无密钥账户系统，使用BN254曲线的零知识证明验证
 * 基于Aptos keyless_account模块设计，适配以太坊架构
 */
contract KeylessAccount is System, Protectable, IKeylessAccount, Initializable {
    using Strings for string;

    // ======== 状态变量 ========

    /// @dev 系统配置
    Configuration private configuration;

    /// @dev 注册的无密钥账户: 地址 => 账户信息
    mapping(address => KeylessAccountInfo) public accounts;

    /// @dev 验证器实例（使用合约工厂模式）
    IGroth16Verifier public verifier;

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
     */
    function initialize() external override initializer onlyGenesis {
        // 使用硬编码默认值初始化
        configuration = Configuration({
            max_signatures_per_txn: 16,
            max_exp_horizon_secs: 86400, // 24小时
            max_commited_epk_bytes: 128,
            max_iss_val_bytes: 128,
            max_extra_field_bytes: 2048,
            max_jwt_header_b64_bytes: 4096,
            verifier_address: 0x0000000000000000000000000000000000001010, // 预部署的验证器地址
            training_wheels_pubkey: new bytes(0),
            override_aud_vals: new string[](0)
        });

        // 初始化验证器实例
        verifier = IGroth16Verifier(configuration.verifier_address);
    }

    // ======== 参数管理 ========

    /**
     * @dev 统一参数更新函数 - 立即生效模式
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
        } else if (Strings.equal(key, "verifier")) {
            address newValue = abi.decode(value, (address));
            address oldValue = configuration.verifier_address;
            configuration.verifier_address = newValue;

            // 立即更新验证器实例
            verifier = IGroth16Verifier(newValue);
            emit VerifierContractUpdated(newValue);

            emit ConfigParamUpdated("verifier", uint256(uint160(oldValue)), uint256(uint160(newValue)));
        } else if (Strings.equal(key, "trainingWheels")) {
            bytes memory newPublicKey = abi.decode(value, (bytes));
            bytes memory oldPublicKey = configuration.training_wheels_pubkey;

            // 验证长度 - 要么为0(禁用)，要么为32(启用)
            if (newPublicKey.length != 0 && newPublicKey.length != 32) {
                revert InvalidTrainingWheelsPK();
            }

            configuration.training_wheels_pubkey = newPublicKey;

            // 使用哈希值在ConfigParamUpdated事件中表示bytes变化
            emit ConfigParamUpdated(
                "trainingWheels", uint256(keccak256(oldPublicKey)), uint256(keccak256(newPublicKey))
            );
        } else if (Strings.equal(key, "addOverrideAud")) {
            string memory newAud = abi.decode(value, (string));

            // 检查是否已存在
            bool exists = false;
            for (uint256 i = 0; i < configuration.override_aud_vals.length; i++) {
                if (Strings.equal(configuration.override_aud_vals[i], newAud)) {
                    exists = true;
                    break;
                }
            }

            // 如果不存在则添加
            if (!exists) {
                configuration.override_aud_vals.push(newAud);
                emit OverrideAudAdded(newAud);
                emit ConfigParamUpdated(
                    "addOverrideAud",
                    0, // 没有真正的"旧值"
                    uint256(keccak256(bytes(newAud)))
                );
            }
        } else if (Strings.equal(key, "removeOverrideAud")) {
            string memory audToRemove = abi.decode(value, (string));
            uint256 length = configuration.override_aud_vals.length;

            for (uint256 i = 0; i < length; i++) {
                if (Strings.equal(configuration.override_aud_vals[i], audToRemove)) {
                    // 将最后一个元素移到当前位置，然后弹出最后一个元素
                    if (i < length - 1) {
                        configuration.override_aud_vals[i] = configuration.override_aud_vals[length - 1];
                    }
                    configuration.override_aud_vals.pop();

                    emit OverrideAudRemoved(audToRemove);
                    emit ConfigParamUpdated(
                        "removeOverrideAud",
                        uint256(keccak256(bytes(audToRemove))),
                        0 // 没有真正的"新值"
                    );
                    break;
                }
            }
        } else {
            revert KeylessAccount__ParameterNotFound(key);
        }

        // 配置更新后发出通知
        emit ConfigurationUpdated(keccak256(abi.encode(configuration)));
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
    ) external override onlyEOA returns (address) {
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
    ) external override onlyEOA returns (address) {
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
    ) external override onlyEOA {
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
    ) external override onlyEOA {
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
    function getAccountInfo(
        address account
    ) external view override returns (KeylessAccountInfo memory) {
        return accounts[account];
    }

    /**
     * @dev 获取当前配置
     */
    function getConfiguration() external view override returns (Configuration memory) {
        return configuration;
    }

    // ======== 内部函数 ========

    /**
     * @dev 从JWK哈希和发行者导出账户地址
     */
    function _deriveAccountAddress(bytes32 jwkHash, string memory issuer) internal pure returns (address) {
        return address(uint160(uint256(keccak256(abi.encodePacked(jwkHash, issuer)))));
    }
}
