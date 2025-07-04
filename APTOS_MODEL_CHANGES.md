# Aptos Model Implementation Changes

## Summary

Successfully converted Gravity's staking mechanism from a hybrid BSC/Aptos model to a pure Aptos model, eliminating the logical conflicts between epoch-based state transitions and fixed unbonding periods.

## Key Changes

### 1. StakeCredit.sol

#### Removed:
- `UnlockRequest` struct and all related storage
- `mapping(bytes32 => UnlockRequest) private _unlockRequests`
- `mapping(address => DoubleEndedQueue.Bytes32Deque) private _unlockRequestsQueue`
- `mapping(address => uint256) private _unlockSequence`
- Import of `DoubleEndedQueue` library
- Complex unlock request tracking logic

#### Simplified:
- **unlock()**: Now simply moves funds from active → pendingInactive
- **claim()**: Users claim their proportional share of the inactive pool
- **onNewEpoch()**: Already correctly moves pendingInactive → inactive
- **reactivateStake()**: Simplified to move funds back from pendingInactive → active

#### Updated Helper Functions:
- `getClaimableAmount()`: Returns user's proportional share of inactive pool
- `getPendingUnlockAmount()`: Returns user's proportional share of pendingInactive pool
- `processUserUnlocks()`: Now a no-op (processing happens automatically at epoch)
- `getUnlockRequestStatus()`: Checks if user has pendingInactive stake

### 2. StakeConfig.sol

- Changed `recurringLockupDuration` from 14 days to 2 hours
- Added comment explaining alignment with epoch interval

## Benefits

1. **Logical Consistency**: Stake transitions now follow pure Aptos model
2. **Code Simplicity**: Removed ~200 lines of complex UnlockRequest logic
3. **User Experience**: 2-hour unlock period instead of 14 days
4. **Maintainability**: Simpler code with fewer edge cases

## How It Works Now

1. **Delegate**: User delegates → receives shares → funds go to active/pendingActive
2. **Unlock**: User unlocks → burns shares → funds move to pendingInactive
3. **Epoch Transition** (every 2 hours):
   - pendingActive → active
   - pendingInactive → inactive
4. **Claim**: User can claim their proportional share from inactive pool

## Important Notes

- Voting power correctly reflects: `active + pendingInactive` for current epoch
- Rewards only accrue to active stake (pendingInactive doesn't earn rewards)
- All state transitions happen atomically at epoch boundaries
- No more time-based unlock requests - everything is epoch-based

## Migration Considerations

For existing deployments:
1. Ensure no pending unlock requests before upgrade
2. Update frontend to remove unlock timer UI
3. Educate users about new 2-hour unlock period
4. Consider keeping 14-day period initially and reducing gradually