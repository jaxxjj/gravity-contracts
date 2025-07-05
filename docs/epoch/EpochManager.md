# Epoch 管理器 (EpochManager) ⏱️

## 概述

Epoch 管理器是 Gravity Core 网络的核心组件，负责协调区块链的时间划分和系统级重新配置。Epoch（纪元）是一个固定时间段，在此期间验证者集合保持不变，网络参数固定，并在结束时进行系统级同步。

Epoch 管理机制确保了网络的平稳运行，使系统能够协调地更新验证者集合、分配奖励、应用治理决策，并在固定的时间间隔内执行其他关键操作。

## Epoch 转换工作流程 🔄

### 初始化流程

当系统首次部署时，EpochManager 通过以下方式初始化：

```solidity
function initialize() external initializer {
    currentEpoch = 0;
    epochIntervalMicrosecs = 2 hours * MICRO_CONVERSION_FACTOR;
    lastEpochTransitionTime = ITimestamp(TIMESTAMP_ADDR).nowSeconds();
}
```

初始化设置：
- 当前 Epoch 为 0
- Epoch 间隔默认为 2 小时（以微秒计）
- 最后一次转换时间设置为当前时间

### Epoch 转换触发条件

Epoch 转换满足以下条件时可以被触发：

1. 距离上次 Epoch 转换已经过去了至少一个 Epoch 间隔的时间
2. 由授权调用者（系统调用者、StakeHub 或 Block 合约）发起调用

可以通过 `canTriggerEpochTransition()` 函数检查当前是否可以触发 Epoch 转换：

```solidity
function canTriggerEpochTransition() external view returns (bool)
```

### Epoch 转换步骤

#### 步骤 1：触发 Epoch 转换

由授权调用者调用 `triggerEpochTransition()` 函数：

```solidity
function triggerEpochTransition() external onlyAuthorizedCallers
```

执行流程：

1. **时间验证**：检查是否已经过去足够的时间（至少一个 Epoch 间隔）
   ```solidity
   uint256 currentTime = ITimestamp(TIMESTAMP_ADDR).nowSeconds();
   uint256 epoch_interval_seconds = epochIntervalMicrosecs / 1000000;
   if (currentTime < lastEpochTransitionTime + epoch_interval_seconds) {
       revert EpochDurationNotPassed(currentTime, lastEpochTransitionTime + epoch_interval_seconds);
   }
   ```

2. **更新 Epoch 数据**：
   - 将 currentEpoch 递增 1
   - 更新 lastEpochTransitionTime 为当前时间

3. **通知系统模块**：调用 `_notifySystemModules()` 函数通知所有系统合约

4. **触发事件**：发出 `NewEpoch` 事件，记录新的 Epoch 编号和转换时间和active validators

#### 步骤 2：系统模块通知

`_notifySystemModules()` 函数会安全地通知各个系统模块 Epoch 已经转换：

```solidity
function _notifySystemModules(uint256 newEpoch, uint256 transitionTime) internal
```

此函数：
1. 通知 StakeHub 合约（验证者管理）
2. 通知 Governor 合约（治理决策执行）
3. 使用 try-catch 机制确保即使某个模块失败也不会中断整个转换过程

#### 步骤 3：系统模块响应

各系统模块在收到 Epoch 转换通知后执行各自的 Epoch 转换逻辑：

1. **StakeHub/ValidatorManager**：
   - 处理验证者状态转换（激活 pending_active 验证者，移除 pending_inactive 验证者）
   - 分发基于性能的奖励
   - 更新验证者集合和投票权重
   - 重置性能计数器

2. **Governor**：
   - 执行已批准的治理提案
   - 更新系统参数

### Epoch 转换结果

成功的 Epoch 转换会导致：

1. 当前 Epoch 编号增加 1
2. 最后转换时间更新为当前时间
3. 验证者集合可能发生变化
4. 奖励分配完成
5. 治理决策执行
6. 发出 `NewEpoch` 事件

## Epoch 参数配置 ⚙️

系统通过治理机制可以调整 Epoch 间隔：

```solidity
function updateParam(string calldata key, bytes calldata value) external override onlyGov
```

当 key 为 "epochIntervalMicrosecs" 时，可以更新 Epoch 间隔时间（以微秒为单位）。

| 参数 | 描述 | 默认值 |
|------|------|-------|
| epochIntervalMicrosecs | Epoch 持续时间（微秒） | 2 小时 |

## 查询功能 🔍

EpochManager 提供以下查询功能：

```solidity
function getCurrentEpochInfo() external view returns (uint256 epoch, uint256 lastTransitionTime, uint256 interval)
```
返回当前 Epoch 编号、上次转换时间和 Epoch 间隔。

```solidity
function getRemainingTime() external view returns (uint256 remainingTime)
```
返回距离下次 Epoch 转换的剩余时间（秒）。

## 错误处理 ⚠️

Epoch 转换过程中可能遇到的错误：

1. **时间间隔不足**：如果尝试在满足 Epoch 间隔前触发转换
2. **授权错误**：非授权调用者尝试触发 Epoch 转换
3. **模块通知失败**：某个系统模块在处理 Epoch 转换时失败

EpochManager 设计为即使部分模块通知失败，也会继续完成 Epoch 转换，确保系统整体稳定性。

## 技术注意事项 📝

- Epoch 间隔在内部以微秒存储，但与时间戳比较时会转换为秒
- 所有时间计算使用 ITimestamp 接口获取当前时间，确保测试环境中可以模拟时间流逝
- 系统使用固定地址模式，不需要动态注册模块
- 合约是可升级的，使用 OpenZeppelin 的 Initializable 模式
