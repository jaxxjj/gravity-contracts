# Gravity Core 质押系统文档

## 目录

- [Gravity Core 质押系统文档](#gravity-core-质押系统文档)
  - [目录](#目录)
  - [系统概述](#系统概述)
  - [核心合约](#核心合约)
    - [StakeHub](#stakehub)
    - [StakePool](#stakepool)
    - [Validator](#validator)
    - [ValidatorSet](#validatorset)
    - [StakeConfig](#stakeconfig)
    - [ValidatorRegistry](#validatorregistry)
    - [EpochManager](#epochmanager)
  - [扩展合约](#扩展合约)
    - [Access](#access)
    - [Protectable](#protectable)
  - [接口合约](#接口合约)
  - [系统工作流程](#系统工作流程)
    - [验证者生命周期](#验证者生命周期)
    - [纪元转换流程](#纪元转换流程)
    - [质押状态转换](#质押状态转换)
    - [奖励分发机制](#奖励分发机制)
  - [系统安全考量](#系统安全考量)

## 系统概述

Gravity Core 质押系统是一个基于权益证明(PoS)的验证者管理系统，允许验证者质押代币以参与网络共识和区块生产。系统支持验证者的注册、质押管理、投票权重计算、奖励分发以及验证者集合的动态调整。

系统设计遵循模块化原则，将不同功能分散到专门的合约中，通过接口进行交互。核心功能包括质押管理、验证者集合维护、纪元管理和奖励分发。

## 核心合约

### StakeHub

`StakeHub` 是质押系统的中心枢纽，协调各个组件之间的交互，管理验证者的注册和质押操作。

**主要状态变量：**
- `mapping(address => StakePool) stakePools`：存储每个验证者地址对应的质押池
- `IValidatorSet validatorSet`：验证者集合接口引用
- `IValidatorRegistry validatorRegistry`：验证者注册表接口引用
- `IStakeConfig stakeConfig`：质押配置接口引用
- `IEpochManager epochManager`：纪元管理器接口引用

**主要函数：**

```solidity
// 初始化函数
function initialize(
    address validatorSetAddress,
    address validatorRegistryAddress,
    address stakeConfigAddress,
    address epochManagerAddress
) external initializer;

// 注册验证者
function registerValidator(
    bytes calldata consensusPubkey,
    bytes calldata consensusProofOfPossession,
    bytes calldata networkAddresses,
    bytes calldata fullnodeAddresses
) external;

// 添加质押
function addStake(uint256 amount) external;

// 解锁质押
function unlockStake(uint256 amount) external;

// 提取质押
function withdrawStake(uint256 amount) external;

// 加入验证者集合
function joinValidatorSet() external;

// 离开验证者集合
function leaveValidatorSet() external;

// 设置验证者操作者
function setOperator(address newOperator) external;

// 设置验证者投票委托人
function setDelegatedVoter(address newVoter) external;

// 更新共识密钥
function rotateConsensusKey(
    bytes calldata newConsensusKey,
    bytes calldata proofOfPossession
) external;

// 更新网络和全节点地址
function updateNetworkAndFullnodeAddresses(
    bytes calldata newNetworkAddresses,
    bytes calldata newFullnodeAddresses
) external;

// 纪元推进（由EpochManager调用）
function advanceEpoch() external;

// 分发奖励给活跃验证者
function _distributeRewardsToActiveValidators() internal;

// 处理待处理的验证者
function _processPendingValidators() internal;
```

**系统角色：**
`StakeHub` 作为系统的中央协调器，负责：
1. 管理验证者的注册和生命周期
2. 处理质押的添加、解锁和提取
3. 在纪元转换时协调验证者集合的更新
4. 分发奖励给活跃验证者

### StakePool

`StakePool` 代表一个验证者的质押池，管理不同状态的质押资金。

**主要状态变量：**
- `uint256 active`：活跃质押金额
- `uint256 inactive`：非活跃（可提取）质押金额
- `uint256 pendingActive`：待激活质押金额
- `uint256 pendingInactive`：待停用质押金额
- `uint64 lockedUntilTimestamp`：质押锁定期限
- `address operatorAddress`：验证者操作者地址
- `address delegatedVoter`：投票委托人地址

**主要函数：**

```solidity
// 初始化质押池
function initialize(address operator, address voter) external initializer;

// 添加质押
function addStake(uint256 amount) external onlyStakeHub returns (uint256);

// 解锁质押
function unlockStake(uint256 amount) external onlyStakeHub returns (uint256);

// 提取质押
function withdrawStake(uint256 amount) external onlyStakeHub returns (uint256);

// 设置操作者
function setOperator(address newOperator) external onlyStakeHub;

// 设置投票委托人
function setDelegatedVoter(address newVoter) external onlyStakeHub;

// 增加锁定期
function increaseLockup(uint64 newLockedUntilTimestamp) external onlyStakeHub;

// 处理纪元转换
function onEpochChange(uint64 currentTimestamp) external onlyStakeHub returns (uint256);

// 获取下一个纪元的投票权重
function getNextEpochVotingPower() external view returns (uint256);

// 获取当前纪元的投票权重
function getCurrentEpochVotingPower() external view returns (uint256);

// 获取质押信息
function getStakeAmounts() external view returns (uint256, uint256, uint256, uint256);
```

**系统角色：**
`StakePool` 负责：
1. 追踪验证者的不同状态质押金额
2. 管理质押的锁定期
3. 在纪元转换时处理质押状态转换
4. 计算验证者的投票权重

### Validator

`Validator` 存储验证者的配置信息，如共识公钥和网络地址。

**主要状态变量：**
- `struct ValidatorInfo`：包含验证者的详细信息
  - `bytes consensusPubkey`：共识公钥
  - `bytes networkAddresses`：网络地址
  - `bytes fullnodeAddresses`：全节点地址
  - `uint256 validatorIndex`：验证者在活跃集合中的索引

**主要函数：**

```solidity
// 初始化验证者
function initialize(
    bytes memory consensusPubkey,
    bytes memory networkAddresses,
    bytes memory fullnodeAddresses
) external initializer;

// 更新共识公钥
function rotateConsensusKey(bytes calldata newConsensusKey) external onlyStakeHub;

// 更新网络和全节点地址
function updateNetworkAndFullnodeAddresses(
    bytes calldata newNetworkAddresses,
    bytes calldata newFullnodeAddresses
) external onlyStakeHub;

// 设置验证者索引
function setValidatorIndex(uint256 index) external onlyValidatorSet;

// 判断验证者是否有资格加入验证者集合
function isEligibleToJoinSet() external view returns (bool);

// 获取验证者配置
function getValidatorConfig() external view returns (bytes memory, bytes memory, bytes memory);
```

**系统角色：**
`Validator` 负责：
1. 存储验证者的密钥和网络地址信息
2. 提供验证者配置的更新机制
3. 判断验证者是否有资格加入验证者集合

### ValidatorSet

`ValidatorSet` 管理当前活跃的验证者集合，以及待加入和待离开的验证者。

**主要状态变量：**
- `ValidatorInfo[] activeValidators`：当前活跃的验证者列表
- `ValidatorInfo[] pendingActiveValidators`：待激活的验证者列表
- `ValidatorInfo[] pendingInactiveValidators`：待停用的验证者列表
- `mapping(address => uint256) validatorIndices`：验证者地址到索引的映射
- `uint256 totalVotingPower`：总投票权重
- `uint256 totalJoiningPower`：待加入的总投票权重

**主要函数：**

```solidity
// 初始化验证者集合
function initialize() external initializer;

// 添加验证者到待激活列表
function addToPendingActive(address validatorAddr, uint256 votingPower) external onlyStakeHub;

// 从待激活列表中移除验证者
function removeFromPendingActive(address validatorAddr) external onlyStakeHub;

// 从活跃列表中移除验证者并添加到待停用列表
function moveFromActiveToInactive(address validatorAddr) external onlyStakeHub;

// 纪元推进（由EpochManager调用）
function advanceEpoch() external onlyEpochManager;

// 获取验证者状态
function getValidatorStatus(address validatorAddr) external view returns (uint8);

// 获取活跃验证者列表
function getActiveValidators() external view returns (address[] memory);

// 获取验证者的投票权重
function getVotingPower(address validatorAddr) external view returns (uint256);

// 更新验证者的投票权重
function updateVotingPower(address validatorAddr, uint256 newVotingPower) external onlyStakeHub;
```

**系统角色：**
`ValidatorSet` 负责：
1. 维护当前活跃的验证者集合
2. 管理验证者的加入和离开过程
3. 在纪元转换时更新验证者集合
4. 计算和更新总投票权重

### StakeConfig

`StakeConfig` 存储质押系统的配置参数，如最小质押要求、奖励率等。

**主要状态变量：**
- `uint256 minStakeAmount`：最小质押金额
- `uint256 maxStakeAmount`：最大质押金额
- `uint64 lockupDuration`：质押锁定期限（秒）
- `uint64 rewardRate`：奖励率
- `uint64 rewardRateDenominator`：奖励率分母
- `bool allowValidatorSetChange`：是否允许验证者集合变更

**主要函数：**

```solidity
// 初始化配置
function initialize(
    uint256 minStake,
    uint256 maxStake,
    uint64 lockupDurationSecs,
    uint64 reward_rate,
    uint64 reward_rate_denominator,
    bool allowValidatorSetChange
) external initializer;

// 更新最小和最大质押金额
function updateStakeAmountRequirements(uint256 minStake, uint256 maxStake) external onlyOwner;

// 更新锁定期限
function updateLockupDuration(uint64 newLockupDurationSecs) external onlyOwner;

// 更新奖励率
function updateRewardRate(uint64 newRewardRate, uint64 newRewardRateDenominator) external onlyOwner;

// 设置是否允许验证者集合变更
function setAllowValidatorSetChange(bool allow) external onlyOwner;

// 获取所需质押金额范围
function getRequiredStakeAmount() external view returns (uint256, uint256);

// 获取锁定期限
function getLockupDuration() external view returns (uint64);

// 获取奖励率
function getRewardRate() external view returns (uint64, uint64);
```

**系统角色：**
`StakeConfig` 负责：
1. 定义系统参数如最小/最大质押金额
2. 设置质押锁定期限
3. 配置奖励率参数
4. 控制验证者集合变更权限

### ValidatorRegistry

`ValidatorRegistry` 管理验证者的注册和性能统计。

**主要状态变量：**
- `mapping(address => ValidatorPerformance) validatorPerformance`：验证者性能统计
- `mapping(address => bool) registeredValidators`：已注册的验证者

**主要函数：**

```solidity
// 初始化注册表
function initialize() external initializer;

// 注册验证者
function registerValidator(address validatorAddr) external onlyStakeHub;

// 更新验证者性能
function updatePerformanceStats(
    address validatorAddr,
    uint64 successfulProposals,
    uint64 failedProposals
) external onlyEpochManager;

// 重置验证者性能统计
function resetPerformanceStats(address validatorAddr) external onlyEpochManager;

// 获取验证者性能统计
function getPerformanceStats(address validatorAddr) external view returns (uint64, uint64);

// 检查验证者是否已注册
function isRegisteredValidator(address validatorAddr) external view returns (bool);
```

**系统角色：**
`ValidatorRegistry` 负责：
1. 维护已注册验证者的记录
2. 追踪验证者的性能统计
3. 在纪元转换时重置性能统计

### EpochManager

`EpochManager` 管理系统的纪元转换，协调各组件在纪元变更时的行为。

**主要状态变量：**
- `uint64 currentEpoch`：当前纪元编号
- `uint64 lastEpochTransitionTime`：上次纪元转换时间
- `uint64 epochInterval`：纪元间隔（秒）
- `IStakeHub stakeHub`：质押中心接口引用
- `IValidatorSet validatorSet`：验证者集合接口引用
- `IValidatorRegistry validatorRegistry`：验证者注册表接口引用

**主要函数：**

```solidity
// 初始化纪元管理器
function initialize(
    address stakeHubAddress,
    address validatorSetAddress,
    address validatorRegistryAddress,
    uint64 epochIntervalSecs
) external initializer;

// 处理纪元转换
function triggerEpochTransition() external;

// 更新纪元间隔
function updateEpochInterval(uint64 newEpochInterval) external onlyOwner;

// 获取当前纪元信息
function getCurrentEpochInfo() external view returns (uint64, uint64, uint64);

// 检查是否可以进行纪元转换
function canTriggerEpochTransition() external view returns (bool);
```

**系统角色：**
`EpochManager` 负责：
1. 追踪当前纪元和转换时间
2. 触发纪元转换流程
3. 协调各组件在纪元变更时的行为
4. 控制纪元间隔设置

## 扩展合约

### Access

`Access` 提供基于角色的访问控制机制，允许合约定义和管理不同的权限角色。

**主要状态变量：**
- `mapping(bytes32 => mapping(address => bool)) roles`：角色到地址的权限映射
- `mapping(bytes32 => address) roleAdmins`：角色管理员映射

**主要函数：**

```solidity
// 初始化访问控制
function initialize() external initializer;

// 授予角色
function grantRole(bytes32 role, address account) external;

// 撤销角色
function revokeRole(bytes32 role, address account) external;

// 放弃角色
function renounceRole(bytes32 role) external;

// 设置角色管理员
function setRoleAdmin(bytes32 role, bytes32 adminRole) external;

// 检查账户是否有角色
function hasRole(bytes32 role, address account) external view returns (bool);

// 获取角色管理员
function getRoleAdmin(bytes32 role) external view returns (bytes32);
```

**系统角色：**
`Access` 负责：
1. 提供细粒度的权限控制
2. 管理系统中的不同角色和权限
3. 支持角色的授予、撤销和管理

### Protectable

`Protectable` 提供基本的保护机制，限制只有特定角色可以调用某些函数。

**主要状态变量：**
- `IAccessControl accessControl`：访问控制接口引用

**主要函数：**

```solidity
// 初始化保护机制
function initialize(address accessControlAddress) external initializer;

// 检查调用者是否有特定角色
function checkRole(bytes32 role) internal view;

// 修改访问控制合约地址
function setAccessControl(address newAccessControl) external onlyRole(DEFAULT_ADMIN_ROLE);
```

**系统角色：**
`Protectable` 负责：
1. 提供基本的访问控制机制
2. 允许合约限制只有特定角色可以调用某些函数
3. 与Access合约集成以实现角色管理

## 接口合约

系统使用多个接口合约来定义组件之间的交互协议：

1. **IStakeHub**：定义与StakeHub交互的方法
2. **IStakePool**：定义与StakePool交互的方法
3. **IValidator**：定义与Validator交互的方法
4. **IValidatorSet**：定义与ValidatorSet交互的方法
5. **IStakeConfig**：定义与StakeConfig交互的方法
6. **IValidatorRegistry**：定义与ValidatorRegistry交互的方法
7. **IEpochManager**：定义与EpochManager交互的方法
8. **IAccessControl**：定义访问控制接口

这些接口确保组件之间的松耦合，便于升级和替换单个组件而不影响整个系统。

## 系统工作流程

### 验证者生命周期

1. **注册阶段**：
   - 验证者调用 `StakeHub.registerValidator()` 注册自己的共识公钥和网络地址
   - 系统创建相应的 `Validator` 和 `StakePool` 实例

2. **质押阶段**：
   - 验证者调用 `StakeHub.addStake()` 添加质押
   - 质押金额被存入 `StakePool` 的相应状态（活跃或待激活）

3. **加入验证者集合**：
   - 验证者调用 `StakeHub.joinValidatorSet()` 申请加入验证者集合
   - 如果满足最低质押要求，验证者被添加到待激活列表
   - 在下一个纪元转换时，待激活验证者被移至活跃验证者列表

4. **活跃验证**：
   - 活跃验证者参与共识和区块生产
   - 系统记录验证者的性能统计（成功和失败的提案）
   - 在每个纪元结束时，根据性能分发奖励

5. **离开验证者集合**：
   - 验证者可以调用 `StakeHub.leaveValidatorSet()` 申请离开
   - 验证者被移至待停用列表
   - 在下一个纪元转换时，验证者从活跃列表中移除

6. **解锁和提取**：
   - 验证者可以调用 `StakeHub.unlockStake()` 解锁质押
   - 解锁的质押被移至待停用状态
   - 当锁定期过期后，待停用质押被移至非活跃状态
   - 验证者可以调用 `StakeHub.withdrawStake()` 提取非活跃质押

### 纪元转换流程

1. **触发纪元转换**：
   - 当当前时间超过上次纪元转换时间加上纪元间隔时，可以触发纪元转换
   - 任何人都可以调用 `EpochManager.triggerEpochTransition()` 触发转换

2. **更新验证者集合**：
   - `EpochManager` 调用 `ValidatorSet.advanceEpoch()`
   - 待激活验证者被移至活跃列表
   - 待停用验证者被从活跃列表中移除
   - 更新验证者索引和总投票权重

3. **处理质押状态**：
   - `EpochManager` 调用 `StakeHub.advanceEpoch()`
   - `StakeHub` 对每个质押池调用 `onEpochChange()`
   - 待激活质押被移至活跃状态
   - 如果锁定期已过，待停用质押被移至非活跃状态

4. **分发奖励**：
   - `StakeHub` 调用 `_distributeRewardsToActiveValidators()`
   - 根据验证者性能计算奖励
   - 奖励被添加到验证者的活跃质押中

5. **重置性能统计**：
   - `EpochManager` 调用 `ValidatorRegistry.resetPerformanceStats()`
   - 所有活跃验证者的性能统计被重置为零

6. **更新纪元信息**：
   - 增加 `currentEpoch` 计数器
   - 更新 `lastEpochTransitionTime` 为当前时间

### 质押状态转换

质押在不同状态之间的转换遵循以下规则：

1. **添加质押**：
   - 如果验证者是当前纪元的验证者：新质押 -> 待激活
   - 如果验证者不是当前纪元的验证者：新质押 -> 活跃

2. **解锁质押**：
   - 活跃质押 -> 待停用质押

3. **纪元转换时**：
   - 待激活质押 -> 活跃质押
   - 如果锁定期已过：待停用质押 -> 非活跃质押

4. **提取质押**：
   - 只能提取非活跃质押

### 奖励分发机制

1. **奖励计算**：
   - 奖励基于验证者的活跃质押金额和性能
   - 奖励公式：`reward = stake * (rewardRate / rewardRateDenominator) * (successfulProposals / totalProposals)`

2. **奖励分发**：
   - 在每个纪元结束时分发奖励
   - 奖励直接添加到验证者的活跃质押中
   - 只有活跃验证者和待停用验证者（本纪元仍活跃）能获得奖励

## 系统安全考量

1. **角色分离**：
   - 系统支持验证者所有者、操作者和投票委托人的分离
   - 允许更灵活的权限管理和责任分配

2. **质押锁定**：
   - 质押有锁定期，防止验证者快速退出
   - 锁定期自动续期，确保验证者长期参与

3. **投票权重限制**：
   - 设置最小和最大质押金额，防止权力过度集中
   - 限制每个纪元投票权重的增长率

4. **访问控制**：
   - 使用基于角色的访问控制
   - 关键操作需要特定角色权限

5. **验证者性能追踪**：
   - 记录验证者的提案成功和失败次数
   - 根据性能分发奖励，激励良好行为
