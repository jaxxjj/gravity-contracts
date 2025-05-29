# 质押凭证 (StakeCredit) 📝

## 概述

StakeCredit 合约是验证者质押管理的核心组件，实现了基于 ERC20 代币模型的质押凭证系统。每个验证者在注册时会部署一个专属的 StakeCredit 合约，用于管理该验证者的所有质押资金、委托和奖励分配。

StakeCredit 借鉴了 Aptos 的 StakePool 资源模型，实现了四状态质押管理：active、inactive、pending_active 和 pending_inactive。这种设计确保了质押资金的安全转换和正确的投票权计算。

## 质押凭证模型 🔄

当用户向验证者质押资金时，他们会收到代表其份额的 StakeCredit 代币。这些代币：

- 代表用户在验证者质押池中的所有权份额
- 不可转让（ERC20 转账功能被禁用）
- 价值会随着奖励累积而增长
- 可用于解锁和提取原始质押及奖励

## 质押委托工作流程 👥

### 步骤 1：委托质押
在验证者注册并获得专属的 StakeCredit 合约后，用户可以开始委托质押：

```solidity
function delegate(address delegator) external payable onlyStakeHub returns (uint256 shares)
```

此操作：
1. 接收用户发送的 ETH
2. 计算对应的份额（shares）
3. 将资金添加到适当的质押状态（active 或 pending_active）
4. 铸造相应份额的 StakeCredit 代币给委托人

| 参数 | 描述 |
|------|------|
| delegator | 委托人地址（接收质押凭证的地址） |

🔍 **注意**：如果验证者当前活跃（有 active 或 pending_inactive 资金），新质押会进入 pending_active 状态，需要等待下一个 epoch 才能生效；否则直接进入 active 状态。

### 步骤 2：解锁质押
当用户想要撤回质押时，首先需要解锁资金：

```solidity
function unlock(address delegator, uint256 shares) external onlyStakeHub returns (uint256 gAmount)
```

此操作：
1. 计算 shares 对应的 ETH 数量
2. 将相应资金从 active 移动到 pending_inactive 状态
3. 销毁相应的 StakeCredit 代币
4. 资金需要等待锁定期结束才能提取

| 参数 | 描述 |
|------|------|
| delegator | 委托人地址 |
| shares | 要解锁的份额数量 |

### 步骤 3：提取质押
当锁定期结束后，用户可以提取已解锁的资金：

```solidity
function withdraw(address payable delegator, uint256 shares) external onlyStakeHub nonReentrant returns (uint256 withdrawnAmount)
```

此操作：
1. 检查锁定期并处理状态转换
2. 计算可提取的 ETH 数量
3. 从 inactive 状态减少相应资金
4. 销毁相应的 StakeCredit 代币
5. 将 ETH 转账给委托人

| 参数 | 描述 |
|------|------|
| delegator | 接收资金的地址 |
| shares | 要提取的份额数量（0 表示提取全部可用） |

## 质押状态转换 📊

StakeCredit 实现了四种质押状态，遵循以下转换规则：
