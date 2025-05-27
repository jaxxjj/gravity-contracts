// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

/**
 * @title IValidatorPerformanceTracker
 * @dev 验证者性能追踪接口，用于跟踪验证者的提案性能
 * 对应Aptos中的ValidatorPerformance功能
 */
interface IValidatorPerformanceTracker {

    /// 对应Aptos的IndividualValidatorPerformance
    struct IndividualValidatorPerformance {
        uint64 successfulProposals; // 成功提案数
        uint64 failedProposals; // 失败提案数
    }

    /// 性能更新事件（对应Aptos中的性能统计更新）
    event PerformanceUpdated(
        address indexed validator,
        uint256 indexed validatorIndex,
        uint64 successfulProposals,
        uint64 failedProposals,
        uint256 epoch
    );

    /// 单次提案结果事件
    event ProposalResult(address indexed validator, uint256 indexed validatorIndex, bool success, uint256 epoch);

    /// Epoch性能数据最终确定事件
    event EpochPerformanceFinalized(
        uint256 indexed epoch, uint256 totalValidators, uint256 totalSuccessfulProposals, uint256 totalFailedProposals
    );

    /// 活跃验证者集合更新事件
    event ActiveValidatorSetUpdated(uint256 indexed epoch, address[] validators);

    /// 验证者性能重置事件
    event PerformanceReset(uint256 indexed newEpoch, uint256 validatorCount);


    error AlreadyInitialized();
    error InvalidValidatorIndex(uint256 index, uint256 maxIndex);
    error ValidatorNotFound(address validator);
    error InvalidEpochNumber(uint256 expected, uint256 provided);
    error EmptyActiveValidatorSet();
    error DuplicateValidator(address validator);

    /**
     * @dev 初始化合约
     * @param initialValidators 初始验证者地址列表
     */
    function initialize(address[] calldata initialValidators) external;

    /**
     * @dev 更新验证者性能统计
     * @param proposerIndex 当前提案者的索引（使用type(uint256).max表示None）
     * @param failedProposerIndices 失败提案者的索引数组
     */
    function updatePerformanceStatistics(uint64 proposerIndex, uint64[] calldata failedProposerIndices) external;

    /**
     * @dev 新epoch处理，重置性能统计
     */
    function onNewEpoch() external;

    /**
     * @dev 手动更新活跃验证者集合
     * @param newValidators 新的活跃验证者列表
     * @param epoch 当前epoch
     */
    function updateActiveValidatorSet(address[] calldata newValidators, uint256 epoch) external;

    /**
     * @dev 获取当前epoch的提案统计
     * @param validatorIndex 验证者索引
     * @return successful 成功提案数
     * @return failed 失败提案数
     */
    function getCurrentEpochProposalCounts(uint256 validatorIndex)
        external
        view
        returns (uint64 successful, uint64 failed);

    /**
     * @dev 根据地址获取验证者性能
     * @param validator 验证者地址
     * @return successful 成功提案数
     * @return failed 失败提案数
     * @return index 验证者索引
     * @return exists 验证者是否存在
     */
    function getValidatorPerformance(address validator)
        external
        view
        returns (uint64 successful, uint64 failed, uint256 index, bool exists);

    /**
     * @dev 获取历史epoch的性能数据
     * @param epoch epoch编号
     * @param validatorIndex 验证者索引
     * @return successful 成功提案数
     * @return failed 失败提案数
     */
    function getHistoricalPerformance(uint256 epoch, uint256 validatorIndex)
        external
        view
        returns (uint64 successful, uint64 failed);

    /**
     * @dev 获取当前所有验证者地址
     * @return 验证者地址数组
     */
    function getCurrentValidators() external view returns (address[] memory);

    /**
     * @dev 获取当前验证者总数
     * @return 验证者数量
     */
    function getCurrentValidatorCount() external view returns (uint256);

    /**
     * @dev 检查地址是否为活跃验证者
     * @param validator 验证者地址
     * @return 是否为活跃验证者
     */
    function isValidator(address validator) external view returns (bool);

    /**
     * @dev 获取当前验证者的完整性能数据
     * @return validators 验证者地址数组
     * @return performances 对应的性能数据数组
     */
    function getCurrentPerformanceData()
        external
        view
        returns (address[] memory validators, IndividualValidatorPerformance[] memory performances);

    /**
     * @dev 计算验证者成功率
     * @param validator 验证者地址
     * @return successRate 成功率（基点表示，10000 = 100%）
     */
    function getValidatorSuccessRate(address validator) external view returns (uint256 successRate);

    /**
     * @dev 获取epoch的整体统计信息
     * @param epoch epoch编号（使用type(uint256).max表示当前epoch）
     * @return totalValidators 验证者总数
     * @return totalSuccessful 总成功提案数
     * @return totalFailed 总失败提案数
     * @return averageSuccessRate 平均成功率（基点）
     */
    function getEpochSummary(uint256 epoch)
        external
        view
        returns (uint256 totalValidators, uint256 totalSuccessful, uint256 totalFailed, uint256 averageSuccessRate);

    /**
     * @dev 获取活跃验证者的地址
     * @param index 验证者索引
     * @return 验证者地址
     */
    function activeValidators(uint256 index) external view returns (address);

    /**
     * @dev 获取验证者的索引
     * @param validator 验证者地址
     * @return 验证者索引
     */
    function validatorIndex(address validator) external view returns (uint256);

    /**
     * @dev 检查地址是否为活跃验证者
     * @param validator 验证者地址
     * @return 是否为活跃验证者
     */
    function isActiveValidator(address validator) external view returns (bool);
}
