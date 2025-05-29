# 验证者管理 (ValidatorManager) 📊

## 验证者注册工作流程 🔐

### 概述
本文档描述了在 Gravity Core 质押系统中注册成为验证者的过程。注册是验证者生命周期的第一步，之后是质押、加入验证者集合、验证交易以及可能的退出。

### 注册参数 📋

注册验证者时，需要在 `ValidatorRegistrationParams` 结构中提供以下参数：

| 参数 | 类型 | 描述 |
|-----------|------|-------------|
| `consensusPublicKey` | `bytes` | 用于共识操作的公钥 |
| `networkAddresses` | `bytes` | 验证者通信的网络信息 |
| `fullnodeAddresses` | `bytes` | 全节点服务的网络信息 |
| `voteAddress` | `bytes` | 验证者的 BLS 投票地址 |
| `blsProof` | `bytes` | BLS 密钥的所有权证明 |
| `commissionRate` | `uint64` | 验证者声明的奖励百分比（以基点表示） |
| `moniker` | `string` | 验证者的可读名称 |
| `initialOperator` | `address` | 可选的不同操作者地址 |
| `initialVoter` | `address` | 可选的不同投票者地址 |

### 注册工作流程 🔄

#### 步骤 1：准备参数和质押
- 生成共识密钥对
- 生成 BLS 密钥对并创建所有权证明
- 准备网络地址
- 确定佣金率（必须 <= maxCommissionRate）
- 准备初始质押的 ETH（必须 >= minValidatorStake）

#### 步骤 2：注册验证者
调用 ValidatorManager 合约的 `registerValidator` 函数：

```solidity
function registerValidator(ValidatorRegistrationParams calldata params) external payable
```

此函数必须携带足够的 ETH 以满足最低质押要求。流程如下：

1. 函数验证验证者尚未注册
2. 验证 BLS 投票地址和证明
3. 检查质押金额是否满足最低要求
4. 检查佣金率是否有效
5. 为验证者部署新的 StakeCredit 合约
6. 在 AccessControl 中注册角色映射
7. 存储验证者信息
8. 注册投票地址映射
9. 将初始质押委托给验证者

#### 步骤 3：配置验证者节点
- 使用注册的参数设置验证者节点
- 使用共识密钥配置节点
- 确保可以通过提供的网络地址访问节点

#### 步骤 4：加入验证者集合
注册后，验证者需要通过调用以下函数加入活跃集合：

```solidity
function joinValidatorSet(address validator) external
```

此函数：
1. 验证验证者存在且尚未激活
2. 检查验证者是否有足够的质押
3. 验证是否允许验证者集合变更
4. 将验证者添加到 pending_active 队列
5. 更新总加入权重

#### 步骤 5：等待激活
- pending_active 队列中的验证者在下一个 epoch 转换期间被处理
- 在 epoch 转换时，验证者从 pending_active 状态移动到 active 状态
- 一旦激活，验证者参与共识并获得奖励

### 注册状态转换 📊

```
未注册 → 已注册(INACTIVE) → PENDING_ACTIVE → ACTIVE
```

### 技术说明 🔧

- BLS 公钥长度应为 48 字节
- BLS 证明长度应为 96 字节
- 如果未另行指定，`msg.sender` 成为默认所有者
- 注册自动为验证者部署唯一的 StakeCredit 合约
- 注册后验证者状态从 INACTIVE 开始
- 验证者必须显式调用 joinValidatorSet 才能参与

### 示例注册流程 📝

1. 准备验证者节点并生成密钥
2. 使用所需参数和质押调用 `registerValidator`
3. 使用注册的参数设置验证者节点
4. 调用 `joinValidatorSet` 加入活跃集合
5. 等待 epoch 转换以变为活跃状态
6. 开始验证并获得奖励

### 常见问题 ❓

**问：如何生成有效的 BLS 密钥和证明？**
答：您可以使用我们提供的工具生成 BLS 密钥对和证明，确保它们符合网络要求。

**问：注册后可以更改参数吗？**
答：是的，大多数参数（如网络地址、佣金率等）可以在注册后通过专门的更新函数修改。

**问：如果质押不足会怎样？**
答：如果质押低于最低要求，注册交易将失败。

**问：如何检查注册状态？**
答：可以调用 `getValidatorState` 或 `getValidatorInfo` 函数检查验证者的当前状态和信息。

## 奖励分配机制 💰

验证者通过以下方式获得奖励：

1. **区块奖励** - 验证者作为区块提议者可以收集交易费用
2. **质押奖励** - 基于验证者的性能和质押量分配

奖励分配在每个epoch结束时进行，基于以下因素：

- 验证者的质押量
- 成功提案数量
- 总提案数量
- 验证者的佣金率

### 奖励分配流程

当一个新的epoch开始时，系统会：

1. 分发基于性能的奖励给所有活跃验证者
2. 分发累积的区块奖励
3. 分发最终确定性奖励（如果有）

所有奖励通过验证者的StakeCredit合约分配，按照设定的佣金比例在验证者和委托人之间分配。

## 验证者退出工作流程 🔐

### 概述
本文档描述了在 Gravity Core 质押系统中验证者退出验证者集合的过程。退出是验证者生命周期的一部分，可能发生在任何时候。

### 退出工作流程 🔄

#### 步骤 1：准备退出
- 验证者必须满足退出条件
- 验证者必须调用 `leaveValidatorSet` 函数

#### 步骤 2：处理退出
- 系统验证退出条件
- 系统处理退出逻辑

### 退出状态转换 📊

```
未注册 → 已注册(INACTIVE) → PENDING_ACTIVE → ACTIVE → PENDING_INACTIVE → INACTIVE
```

### 技术说明 ��

- 验证者必须满足退出条件才能退出
- 验证者必须调用 `leaveValidatorSet` 函数才能退出
- 退出后验证者状态从 ACTIVE 移动到 PENDING_INACTIVE
- 在下一个 epoch 转换时，验证者从 PENDING_INACTIVE 移动到 INACTIVE

### 示例退出流程 📝

1. 验证者满足退出条件
2. 验证者调用 `leaveValidatorSet` 函数
3. 系统验证退出条件
4. 系统处理退出逻辑
5. 等待 epoch 转换以变为非活跃状态
6. 退出完成

### 常见问题 ❓

**问：如何满足退出条件？**
答：验证者必须满足退出条件才能退出。退出条件可能包括但不限于：

- 验证者主动退出
- 验证者被系统强制退出

**问：退出后可以重新加入吗？**
答：是的，验证者可以在退出后重新加入。验证者需要重新注册并满足加入条件。

**问：退出后可以更改参数吗？**
答：退出后验证者参数不能更改。验证者必须重新注册并满足加入条件才能更改参数。

**问：退出后可以检查状态吗？**
答：是的，验证者退出后可以检查状态。可以调用 `getValidatorState` 或 `getValidatorInfo` 函数检查验证者的当前状态和信息。
