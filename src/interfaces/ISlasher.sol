// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/**
 * @title ISlasher
 * @dev Slash 功能接口定义
 * @notice 定义验证者违规惩罚相关的核心接口
 */
interface ISlasher {
    // ======== 事件定义 ========

    /**
     * @dev 验证者被slash事件
     * @param validator 被slash的验证者地址
     * @param amount slash金额
     * @param slashType slash类型
     * @param evidence 违规证据哈希
     */
    event ValidatorSlashed(
        address indexed validator, uint256 amount, SlashType indexed slashType, bytes32 indexed evidence
    );

    /**
     * @dev slash资金分配事件
     * @param validator 被slash的验证者
     * @param burned 销毁的金额
     * @param redistributed 重新分配的金额
     * @param treasury 进入国库的金额
     */
    event SlashDistributed(address indexed validator, uint256 burned, uint256 redistributed, uint256 treasury);

    // ======== 枚举定义 ========

    /**
     * @dev slash类型枚举
     */
    enum SlashType {
        DOUBLE_SIGN, // 双签
        UNAVAILABILITY, // 不可用性
        MALICIOUS_FORK, // 恶意分叉
        INVALID_BLOCK, // 无效区块
        CONSENSUS_VIOLATION // 共识违规

    }

    /**
     * @dev slash状态枚举
     */
    enum SlashStatus {
        PENDING, // 待处理
        EXECUTED, // 已执行
        CANCELLED // 已取消

    }

    // ======== 结构体定义 ========

    /**
     * @dev slash记录结构体
     */
    struct SlashRecord {
        address validator; // 验证者地址
        uint256 amount; // slash金额
        SlashType slashType; // slash类型
        SlashStatus status; // slash状态
        bytes32 evidence; // 证据哈希
        uint256 blockNumber; // 违规区块号
        uint256 timestamp; // slash时间
        address reporter; // 举报者
        uint256 executionTime; // 执行时间
    }

    // ======== 核心slash接口 ========

    /**
     * @dev 提交slash提案
     * @param validator 要slash的验证者地址
     * @param amount slash金额
     * @param slashType slash类型
     * @param evidence 违规证据
     * @param blockNumber 违规区块号
     * @return proposalId 提案ID
     */
    function proposeSlash(
        address validator,
        uint256 amount,
        SlashType slashType,
        bytes32 evidence,
        uint256 blockNumber
    ) external returns (uint256 proposalId);

    /**
     * @dev 执行slash
     * @param proposalId 提案ID
     */
    function executeSlash(
        uint256 proposalId
    ) external;

    /**
     * @dev 取消slash提案
     * @param proposalId 提案ID
     */
    function cancelSlash(
        uint256 proposalId
    ) external;

    // ======== slash参数配置 ========

    /**
     * @dev 设置slash比例
     * @param slashType slash类型
     * @param percentage slash比例 (基数10000)
     */
    function setSlashPercentage(SlashType slashType, uint256 percentage) external;

    /**
     * @dev 设置最小slash金额
     * @param amount 最小slash金额
     */
    function setMinSlashAmount(
        uint256 amount
    ) external;

    /**
     * @dev 设置最大slash金额
     * @param amount 最大slash金额
     */
    function setMaxSlashAmount(
        uint256 amount
    ) external;

    // ======== 查询接口 ========

    /**
     * @dev 获取slash记录
     * @param proposalId 提案ID
     * @return slash记录
     */
    function getSlashRecord(
        uint256 proposalId
    ) external view returns (SlashRecord memory);

    /**
     * @dev 获取验证者slash历史
     * @param validator 验证者地址
     * @return proposalIds 提案ID数组
     */
    function getValidatorSlashHistory(
        address validator
    ) external view returns (uint256[] memory proposalIds);

    /**
     * @dev 获取slash比例
     * @param slashType slash类型
     * @return percentage slash比例
     */
    function getSlashPercentage(
        SlashType slashType
    ) external view returns (uint256 percentage);

    /**
     * @dev 检查验证者是否可以被slash
     * @param validator 验证者地址
     * @param amount slash金额
     * @return 是否可以slash
     */
    function canSlash(address validator, uint256 amount) external view returns (bool);

    /**
     * @dev 计算slash金额
     * @param validator 验证者地址
     * @param slashType slash类型
     * @return amount 计算出的slash金额
     */
    function calculateSlashAmount(address validator, SlashType slashType) external view returns (uint256 amount);

    // ======== 权限管理 ========

    /**
     * @dev 检查是否有slash权限
     * @param account 账户地址
     * @return 是否有权限
     */
    function hasSlashPermission(
        address account
    ) external view returns (bool);

    /**
     * @dev 添加slash者
     * @param slasher slash者地址
     */
    function addSlasher(
        address slasher
    ) external;

    /**
     * @dev 移除slash者
     * @param slasher slash者地址
     */
    function removeSlasher(
        address slasher
    ) external;
}
