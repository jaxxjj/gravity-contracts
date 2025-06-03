// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

import "@src/System.sol";
import "@src/interfaces/IEpochManager.sol";
import "@src/interfaces/IValidatorManager.sol";
import "@src/interfaces/IValidatorPerformanceTracker.sol";

contract ValidatorPerformanceTracker is System, IValidatorPerformanceTracker {
    /// 当前性能数据 - 将动态数组单独存储
    IndividualValidatorPerformance[] private currentValidators;

    /// 历史epoch的性能记录 - 使用映射存储
    mapping(uint256 => mapping(uint256 => IndividualValidatorPerformance)) private epochValidatorPerformance;
    mapping(uint256 => uint256) private epochValidatorCount;

    /// 当前活跃验证者列表（按index排序，对应Aptos中的active_validators顺序）
    address[] public activeValidators;

    /// 验证者地址到index的映射（用于快速查找）
    mapping(address => uint256) public validatorIndex;

    /// 验证者是否存在的标记
    mapping(address => bool) public isActiveValidator;

    /// 是否已初始化
    bool private initialized;

    modifier validValidatorIndex(uint256 index) {
        if (index >= currentValidators.length) {
            revert InvalidValidatorIndex(index, currentValidators.length);
        }
        _;
    }

    /**
     * @dev 初始化合约（对应Aptos的initialize函数）
     * 只能调用一次，设置初始验证者集合
     * @param initialValidators 初始验证者地址列表
     */
    function initialize(address[] calldata initialValidators) external onlySystemCaller {
        if (initialized) revert AlreadyInitialized();

        initialized = true;

        if (initialValidators.length > 0) {
            _initializeValidatorSet(initialValidators);
        }
    }

    /**
     * @dev 更新验证者性能统计（对应Aptos的update_performance_statistics）
     * 只能由系统调用
     *
     * @param proposerIndex 当前提案者的索引（使用type(uint256).max表示None）
     * @param failedProposerIndices 失败提案者的索引数组
     *
     * 对应Aptos中的函数签名：
     * public(friend) fun update_performance_statistics(
     *     proposer_index: Option<u64>,
     *     failed_proposer_indices: vector<u64>
     * )
     */
    function updatePerformanceStatistics(uint64 proposerIndex, uint64[] calldata failedProposerIndices)
        external
        onlySystemCaller
    {
        // 直接从EpochManager获取当前epoch
        uint256 epoch = IEpochManager(EPOCH_MANAGER_ADDR).currentEpoch();

        uint256 validatorCount = currentValidators.length;

        // 处理成功的提案者（对应Aptos中的proposer_index处理）
        if (proposerIndex != type(uint256).max) {
            if (proposerIndex < validatorCount) {
                // 增加成功提案数
                currentValidators[proposerIndex].successfulProposals += 1;

                // 发出事件
                emit ProposalResult(activeValidators[proposerIndex], proposerIndex, true, epoch);

                emit PerformanceUpdated(
                    activeValidators[proposerIndex],
                    proposerIndex,
                    currentValidators[proposerIndex].successfulProposals,
                    currentValidators[proposerIndex].failedProposals,
                    epoch
                );
            }
        }

        // 处理失败的提案者（对应Aptos中的failed_proposer_indices处理）
        for (uint256 i = 0; i < failedProposerIndices.length; i++) {
            uint256 failedIndex = failedProposerIndices[i];
            if (failedIndex < validatorCount) {
                // 增加失败提案数
                currentValidators[failedIndex].failedProposals += 1;

                // 发出事件
                emit ProposalResult(activeValidators[failedIndex], failedIndex, false, epoch);

                emit PerformanceUpdated(
                    activeValidators[failedIndex],
                    failedIndex,
                    currentValidators[failedIndex].successfulProposals,
                    currentValidators[failedIndex].failedProposals,
                    epoch
                );
            }
        }
    }

    /**
     * @dev 新epoch处理（对应Aptos stake.move中on_new_epoch的性能处理部分）
     * 重置性能统计，更新验证者集合
     */
    function onNewEpoch() external onlyValidatorManager {
        // 验证epoch顺序
        uint256 currentEpoch = IEpochManager(EPOCH_MANAGER_ADDR).currentEpoch();

        // 保存当前epoch的性能数据到历史记录
        _finalizeCurrentEpochPerformance(currentEpoch);

        // 从ValidatorManager获取新的验证者集合（对应Aptos中的validator set更新）
        _updateActiveValidatorSetFromSystem();

        // 重置所有验证者的性能统计（对应Aptos中on_new_epoch的重置逻辑）
        _resetPerformanceStatistics();

        emit PerformanceReset(currentEpoch, activeValidators.length);
    }

    /**
     * @dev 手动更新验证者集合（用于中途更新验证者列表）
     * @param newValidators 新的验证者列表
     * @param epoch 当前epoch
     */
    function updateActiveValidatorSet(address[] calldata newValidators, uint256 epoch) external onlySystemCaller {
        _updateActiveValidatorSet(newValidators, epoch);
    }

    /**
     * @dev 获取当前epoch的提案统计（对应Aptos的get_current_epoch_proposal_counts）
     * @param validatorIdx 验证者索引
     * @return successful 成功提案数
     * @return failed 失败提案数
     */
    function getCurrentEpochProposalCounts(uint256 validatorIdx)
        external
        view
        validValidatorIndex(validatorIdx)
        returns (uint64 successful, uint64 failed)
    {
        IndividualValidatorPerformance memory perf = currentValidators[validatorIdx];
        return (perf.successfulProposals, perf.failedProposals);
    }

    /**
     * @dev 根据地址获取验证者性能（自定义查询函数）
     * @param validator 验证者地址
     * @return successful 成功提案数
     * @return failed 失败提案数
     * @return index 验证者索引
     * @return exists 验证者是否存在
     */
    function getValidatorPerformance(address validator)
        external
        view
        returns (uint64 successful, uint64 failed, uint256 index, bool exists)
    {
        if (!isActiveValidator[validator]) {
            return (0, 0, 0, false);
        }

        index = validatorIndex[validator];
        IndividualValidatorPerformance memory perf = currentValidators[index];
        return (perf.successfulProposals, perf.failedProposals, index, true);
    }

    /**
     * @dev 获取历史epoch的性能数据
     * @param epoch epoch编号
     * @param validatorIdx 验证者索引
     * @return successful 成功提案数
     * @return failed 失败提案数
     */
    function getHistoricalPerformance(uint256 epoch, uint256 validatorIdx)
        external
        view
        returns (uint64 successful, uint64 failed)
    {
        uint256 currentEpoch = IEpochManager(EPOCH_MANAGER_ADDR).currentEpoch();
        require(epoch <= currentEpoch, "Future epoch not accessible");

        if (epoch == currentEpoch) {
            if (validatorIdx >= currentValidators.length) {
                revert InvalidValidatorIndex(validatorIdx, currentValidators.length);
            }
            IndividualValidatorPerformance memory perf = currentValidators[validatorIdx];
            return (perf.successfulProposals, perf.failedProposals);
        } else {
            require(validatorIdx < epochValidatorCount[epoch], "Invalid historical validator index");
            IndividualValidatorPerformance memory perf = epochValidatorPerformance[epoch][validatorIdx];
            return (perf.successfulProposals, perf.failedProposals);
        }
    }

    /**
     * @dev 获取当前所有验证者地址
     * @return 验证者地址数组
     */
    function getCurrentValidators() external view returns (address[] memory) {
        return activeValidators;
    }

    /**
     * @dev 获取当前验证者总数
     * @return 验证者数量
     */
    function getCurrentValidatorCount() external view returns (uint256) {
        return activeValidators.length;
    }

    /**
     * @dev 检查地址是否为活跃验证者
     * @param validator 验证者地址
     * @return 是否为活跃验证者
     */
    function isValidator(address validator) external view returns (bool) {
        return isActiveValidator[validator];
    }

    /**
     * @dev 获取当前验证者的完整性能数据
     * @return validators 验证者地址数组
     * @return performances 对应的性能数据数组
     */
    function getCurrentPerformanceData()
        external
        view
        returns (address[] memory validators, IndividualValidatorPerformance[] memory performances)
    {
        validators = activeValidators;
        performances = new IndividualValidatorPerformance[](currentValidators.length);

        for (uint256 i = 0; i < currentValidators.length; i++) {
            performances[i] = currentValidators[i];
        }

        return (validators, performances);
    }

    /**
     * @dev 计算验证者成功率
     * @param validator 验证者地址
     * @return successRate 成功率（基点表示，10000 = 100%）
     */
    function getValidatorSuccessRate(address validator) external view returns (uint256 successRate) {
        if (!isActiveValidator[validator]) {
            return 0;
        }

        uint256 index = validatorIndex[validator];
        IndividualValidatorPerformance memory perf = currentValidators[index];
        uint64 total = perf.successfulProposals + perf.failedProposals;

        if (total == 0) {
            return 0;
        }

        return (uint256(perf.successfulProposals) * 10000) / uint256(total);
    }

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
        returns (uint256 totalValidators, uint256 totalSuccessful, uint256 totalFailed, uint256 averageSuccessRate)
    {
        if (epoch == type(uint256).max || epoch == IEpochManager(EPOCH_MANAGER_ADDR).currentEpoch()) {
            totalValidators = currentValidators.length;

            for (uint256 i = 0; i < currentValidators.length; i++) {
                totalSuccessful += currentValidators[i].successfulProposals;
                totalFailed += currentValidators[i].failedProposals;
            }
        } else {
            require(epoch < IEpochManager(EPOCH_MANAGER_ADDR).currentEpoch(), "Future epoch not accessible");
            totalValidators = epochValidatorCount[epoch];

            for (uint256 i = 0; i < totalValidators; i++) {
                IndividualValidatorPerformance memory perf = epochValidatorPerformance[epoch][i];
                totalSuccessful += perf.successfulProposals;
                totalFailed += perf.failedProposals;
            }
        }

        uint256 grandTotal = totalSuccessful + totalFailed;
        if (grandTotal > 0) {
            averageSuccessRate = (totalSuccessful * 10000) / grandTotal;
        } else {
            averageSuccessRate = 0;
        }

        return (totalValidators, totalSuccessful, totalFailed, averageSuccessRate);
    }

    /**
     * @dev 初始化验证者集合
     */
    function _initializeValidatorSet(address[] calldata validators) internal {
        if (validators.length == 0) revert EmptyActiveValidatorSet();

        // 检查重复验证者
        for (uint256 i = 0; i < validators.length; i++) {
            for (uint256 j = i + 1; j < validators.length; j++) {
                if (validators[i] == validators[j]) {
                    revert DuplicateValidator(validators[i]);
                }
            }
        }

        _updateActiveValidatorSet(validators, 0);
    }

    /**
     * @dev 保存当前epoch性能数据到历史记录
     */
    function _finalizeCurrentEpochPerformance(uint256 epoch) internal {
        if (currentValidators.length > 0) {
            uint256 totalSuccessful = 0;
            uint256 totalFailed = 0;

            // 保存到历史映射
            epochValidatorCount[epoch] = currentValidators.length;
            for (uint256 i = 0; i < currentValidators.length; i++) {
                epochValidatorPerformance[epoch][i] = currentValidators[i];
                totalSuccessful += currentValidators[i].successfulProposals;
                totalFailed += currentValidators[i].failedProposals;
            }

            emit EpochPerformanceFinalized(epoch, currentValidators.length, totalSuccessful, totalFailed);
        }
    }

    /**
     * @dev 重置当前epoch的性能统计
     */
    function _resetPerformanceStatistics() internal {
        for (uint256 i = 0; i < currentValidators.length; i++) {
            currentValidators[i].successfulProposals = 0;
            currentValidators[i].failedProposals = 0;
        }
    }

    /**
     * @dev 从ValidatorManager获取验证者集合
     */
    function _updateActiveValidatorSetFromSystem() internal {
        address[] memory validators = IValidatorManager(VALIDATOR_MANAGER_ADDR).getActiveValidators();
        if (validators.length > 0) {
            _updateActiveValidatorSet(validators, IEpochManager(EPOCH_MANAGER_ADDR).currentEpoch());
        }
    }

    /**
     * @dev 更新活跃验证者集合和性能数据结构
     */
    function _updateActiveValidatorSet(address[] memory validators, uint256 epoch) internal {
        if (validators.length == 0) revert EmptyActiveValidatorSet();

        // 清除旧的验证者映射
        for (uint256 i = 0; i < activeValidators.length; i++) {
            isActiveValidator[activeValidators[i]] = false;
            delete validatorIndex[activeValidators[i]];
        }

        // 清空数组
        delete activeValidators;
        delete currentValidators;

        // 设置新的验证者集合
        for (uint256 i = 0; i < validators.length; i++) {
            // 检查地址有效性
            require(validators[i] != address(0), "Invalid validator address");

            // 检查重复
            require(!isActiveValidator[validators[i]], "Duplicate validator");

            activeValidators.push(validators[i]);
            validatorIndex[validators[i]] = i;
            isActiveValidator[validators[i]] = true;

            // 初始化性能数据
            currentValidators.push(IndividualValidatorPerformance({successfulProposals: 0, failedProposals: 0}));
        }

        emit ActiveValidatorSetUpdated(epoch, validators);
    }
}
