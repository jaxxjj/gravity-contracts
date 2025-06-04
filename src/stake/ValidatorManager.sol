// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "../System.sol";
import "@src/interfaces/IStakeConfig.sol";
import "@src/interfaces/IEpochManager.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@src/access/Protectable.sol";
import "@src/interfaces/IStakeCredit.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@src/stake/StakeCredit.sol";
import "@src/interfaces/IValidatorManager.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@src/interfaces/ITimestamp.sol";
import "@src/interfaces/IValidatorPerformanceTracker.sol";

import "@src/interfaces/IReconfigurableModule.sol";
/**
 * @title ValidatorManager
 * @dev Contract for unified validator set management
 */

contract ValidatorManager is System, ReentrancyGuard, Protectable, IValidatorManager, Initializable {
    using EnumerableSet for EnumerableSet.AddressSet;

    uint256 private constant BLS_PUBKEY_LENGTH = 48;
    uint256 private constant BLS_SIG_LENGTH = 96;
    uint256 private constant BREATHE_BLOCK_INTERVAL = 1 days;
    uint64 public constant MAX_VALIDATOR_SET_SIZE = 65536;

    ValidatorSetData public validatorSetData;

    // validator info mapping
    mapping(address validator => ValidatorInfo validatorInfo) public validatorInfos;

    // BLS vote address mapping
    mapping(bytes voteAddress => address validator) public voteAddressToValidator; // vote address => validator address
    mapping(bytes voteAddress => uint256 expiration) public voteExpiration; // vote address => expiration time

    // consensus address mapping
    mapping(bytes consensusAddress => address operator) public consensusToValidator; // consensus address => validator address

    // validator name mapping
    mapping(bytes32 monikerHash => bool exists) private _monikerSet; // validator name hash => exists

    // validator set management
    EnumerableSet.AddressSet private activeValidators; // active validators
    EnumerableSet.AddressSet private pendingActive; // pending active validators
    EnumerableSet.AddressSet private pendingInactive; // pending inactive validators

    // index mapping
    mapping(address validator => uint256 index) private activeValidatorIndex;
    mapping(address validator => uint256 index) private pendingActiveIndex;
    mapping(address validator => uint256 index) private pendingInactiveIndex;

    mapping(address operator => address validator) public operatorToValidator; // operator => validator

    // initialized flag
    bool private initialized;

    // mapping for tracking validator accumulated rewards
    uint256 public totalIncoming;

    /*----------------- Modifiers -----------------*/

    modifier validatorExists(address validator) {
        if (!validatorInfos[validator].registered) {
            revert ValidatorNotExists(validator);
        }
        _;
    }

    modifier onlyValidatorSelf(address validator) {
        if (msg.sender != validator) {
            revert NotValidator(msg.sender, validator);
        }
        _;
    }

    modifier validAddress(address addr) {
        if (addr == address(0)) {
            revert InvalidAddress(address(0));
        }
        _;
    }

    modifier onlyValidatorOperator(address validator) {
        if (!hasOperatorPermission(validator, msg.sender)) {
            revert UnauthorizedCaller(msg.sender, validator);
        }
        _;
    }

    modifier whenValidatorSetChangeAllowed() {
        if (!IStakeConfig(STAKE_CONFIG_ADDR).allowValidatorSetChange()) {
            revert ValidatorSetChangeDisabled();
        }
        _;
    }

    /// @inheritdoc IValidatorManager
    function initialize(
        address[] calldata validatorAddresses,
        address[] calldata consensusAddresses,
        address payable[] calldata feeAddresses,
        uint64[] calldata votingPowers,
        bytes[] calldata voteAddresses
    ) external onlyGenesis {
        if (initialized) revert AlreadyInitialized();

        if (
            validatorAddresses.length != consensusAddresses.length || validatorAddresses.length != feeAddresses.length
                || validatorAddresses.length != votingPowers.length || validatorAddresses.length != voteAddresses.length
        ) revert ArrayLengthMismatch();

        initialized = true;

        // initialize ValidatorSetData
        validatorSetData = ValidatorSetData({totalVotingPower: 0, totalJoiningPower: 0});

        // add initial validators
        for (uint256 i = 0; i < validatorAddresses.length; i++) {
            address validator = validatorAddresses[i];
            address consensusAddress = consensusAddresses[i];
            address payable feeAddress = feeAddresses[i];
            uint64 votingPower = votingPowers[i];
            bytes memory voteAddress = voteAddresses[i];

            if (votingPower == 0) revert InvalidVotingPower(votingPower);

            // create basic validator info
            validatorInfos[validator] = ValidatorInfo({
                consensusPublicKey: abi.encodePacked(consensusAddress),
                feeAddress: feeAddress,
                voteAddress: voteAddress,
                commission: Commission({
                    rate: 0,
                    maxRate: 5000, // default max commission rate 50%
                    maxChangeRate: 500 // default max daily change rate 5%
                }),
                moniker: string(abi.encodePacked("VAL", uint256(i))), // generate default name
                createdTime: ITimestamp(TIMESTAMP_ADDR).nowSeconds(),
                registered: true,
                stakeCreditAddress: address(0),
                status: ValidatorStatus.ACTIVE,
                votingPower: votingPower,
                validatorIndex: i,
                lastEpochActive: 0,
                updateTime: ITimestamp(TIMESTAMP_ADDR).nowSeconds(),
                operator: validator // default self as operator
            });

            // Add to active validators set
            activeValidators.add(validator);
            activeValidatorIndex[validator] = i;

            // Update total voting power
            validatorSetData.totalVotingPower += votingPower;

            // Set reverse mapping
            operatorToValidator[validator] = validator;

            // Set consensus address mapping
            if (consensusAddress != address(0)) {
                consensusToValidator[abi.encodePacked(consensusAddress)] = validator;
            }

            // Set vote address mapping
            if (voteAddress.length > 0) {
                voteAddressToValidator[voteAddress] = validator;
            }
        }
    }

    /// @inheritdoc IValidatorManager
    function registerValidator(ValidatorRegistrationParams calldata params)
        external
        payable
        nonReentrant
        whenNotPaused
    {
        address validator = msg.sender;

        // validate params
        _validateRegistrationParams(validator, params);

        // check stake requirements
        uint256 stakeMinusLock = msg.value - IStakeConfig(STAKE_CONFIG_ADDR).lockAmount();
        uint256 minStake = IStakeConfig(STAKE_CONFIG_ADDR).minValidatorStake();
        if (stakeMinusLock < minStake) {
            revert InvalidStakeAmount(stakeMinusLock, minStake);
        }

        // set beneficiary
        address beneficiary = params.initialBeneficiary == address(0) ? validator : params.initialBeneficiary;

        // deploy StakeCredit contract
        address stakeCreditAddress = _deployStakeCredit(validator, params.moniker, beneficiary);

        // create and store validator info
        _createValidatorInfo(validator, params, stakeCreditAddress);

        // setup validator mappings
        _setupValidatorMappings(validator, params);

        // record validator name
        bytes32 monikerHash = keccak256(abi.encodePacked(params.moniker));
        _monikerSet[monikerHash] = true;

        // initial stake
        StakeCredit(payable(stakeCreditAddress)).delegate{value: msg.value}(validator);

        emit ValidatorRegistered(validator, params.initialOperator, params.consensusPublicKey, params.moniker);
        emit StakeCreditDeployed(validator, stakeCreditAddress);
    }

    /**
     * @dev validate registration params
     */
    function _validateRegistrationParams(address validator, ValidatorRegistrationParams calldata params)
        internal
        view
    {
        if (validatorInfos[validator].registered) {
            revert ValidatorAlreadyExists(validator);
        }

        // check BLS vote address
        if (params.voteAddress.length > 0 && voteAddressToValidator[params.voteAddress] != address(0)) {
            revert DuplicateVoteAddress(params.voteAddress);
        }

        // check consensus address
        if (params.consensusPublicKey.length > 0 && consensusToValidator[params.consensusPublicKey] != address(0)) {
            revert DuplicateConsensusAddress(params.consensusPublicKey);
        }

        // check validator name
        if (!_checkMoniker(params.moniker)) {
            revert InvalidMoniker(params.moniker);
        }

        bytes32 monikerHash = keccak256(abi.encodePacked(params.moniker));
        if (_monikerSet[monikerHash]) {
            revert DuplicateMoniker(params.moniker);
        }

        // check commission settings
        if (
            params.commission.maxRate > IStakeConfig(STAKE_CONFIG_ADDR).MAX_COMMISSION_RATE()
                || params.commission.rate > params.commission.maxRate
                || params.commission.maxChangeRate > params.commission.maxRate
        ) {
            revert InvalidCommission();
        }

        // check BLS proof
        if (params.voteAddress.length > 0 && !_checkVoteAddress(validator, params.voteAddress, params.blsProof)) {
            revert InvalidVoteAddress();
        }

        // check address validity
        if (params.initialOperator == address(0)) {
            revert InvalidAddress(address(0));
        }

        // check address conflict
        if (operatorToValidator[params.initialOperator] != address(0)) {
            revert AddressAlreadyInUse(params.initialOperator, operatorToValidator[params.initialOperator]);
        }
    }

    /**
     * @dev create validator info
     */
    function _createValidatorInfo(
        address validator,
        ValidatorRegistrationParams calldata params,
        address stakeCreditAddress
    ) internal {
        _setValidatorBasicInfo(validator, params);
        _setValidatorAddresses(validator, params);
        _setValidatorStatus(validator, stakeCreditAddress);
    }

    function _setValidatorBasicInfo(address validator, ValidatorRegistrationParams calldata params) internal {
        ValidatorInfo storage info = validatorInfos[validator];

        info.moniker = params.moniker;
        info.commission = params.commission;
        info.createdTime = ITimestamp(TIMESTAMP_ADDR).nowSeconds();
        info.updateTime = ITimestamp(TIMESTAMP_ADDR).nowSeconds();
        info.operator = params.initialOperator;
    }

    function _setValidatorAddresses(address validator, ValidatorRegistrationParams calldata params) internal {
        ValidatorInfo storage info = validatorInfos[validator];

        info.consensusPublicKey = params.consensusPublicKey;
        info.feeAddress = params.feeAddress;
        info.voteAddress = params.voteAddress;
    }

    function _setValidatorStatus(address validator, address stakeCreditAddress) internal {
        ValidatorInfo storage info = validatorInfos[validator];

        info.registered = true;
        info.stakeCreditAddress = stakeCreditAddress;
        info.status = ValidatorStatus.INACTIVE;
        info.votingPower = 0;
        info.validatorIndex = 0;
        info.lastEpochActive = 0;
    }

    /**
     * @dev setup validator mappings
     */
    function _setupValidatorMappings(address validator, ValidatorRegistrationParams calldata params) internal {
        operatorToValidator[params.initialOperator] = validator;

        if (params.voteAddress.length > 0) {
            voteAddressToValidator[params.voteAddress] = validator;
        }

        if (params.consensusPublicKey.length > 0) {
            consensusToValidator[params.consensusPublicKey] = validator;
        }
    }

    /// @inheritdoc IValidatorManager
    function joinValidatorSet(address validator)
        external
        whenNotPaused
        whenValidatorSetChangeAllowed
        validatorExists(validator)
        onlyValidatorOperator(validator)
    {
        ValidatorInfo storage info = validatorInfos[validator];

        // check current status
        if (info.status != ValidatorStatus.INACTIVE) {
            revert ValidatorNotInactive(validator);
        }

        // get current stake and check requirements
        uint64 votingPower = uint64(_getValidatorStake(validator));
        uint256 minStake = IStakeConfig(STAKE_CONFIG_ADDR).minValidatorStake();
        uint256 maxStake = IStakeConfig(STAKE_CONFIG_ADDR).maximumStake();

        if (votingPower < minStake) {
            revert InvalidStakeAmount(votingPower, minStake);
        }

        if (votingPower > maxStake) {
            revert StakeExceedsMaximum(votingPower, maxStake);
        }

        // check validator set size limit
        uint256 totalSize = activeValidators.length() + pendingActive.length();
        if (totalSize >= MAX_VALIDATOR_SET_SIZE) {
            revert ValidatorSetReachedMax(totalSize, MAX_VALIDATOR_SET_SIZE);
        }

        // check voting power increase limit
        _checkVotingPowerIncrease(votingPower);

        // update status to PENDING_ACTIVE
        info.status = ValidatorStatus.PENDING_ACTIVE;
        info.votingPower = votingPower;

        // add to pending_active set
        pendingActive.add(validator);
        pendingActiveIndex[validator] = pendingActive.length() - 1;

        // update total joining power
        validatorSetData.totalJoiningPower += votingPower;

        uint64 currentEpoch = uint64(IEpochManager(EPOCH_MANAGER_ADDR).currentEpoch());
        emit ValidatorJoinRequested(validator, votingPower, currentEpoch);
        emit ValidatorStatusChanged(
            validator, uint8(ValidatorStatus.INACTIVE), uint8(ValidatorStatus.PENDING_ACTIVE), currentEpoch
        );
    }

    /// @inheritdoc IValidatorManager
    function leaveValidatorSet(address validator)
        external
        whenNotPaused
        whenValidatorSetChangeAllowed
        validatorExists(validator)
        onlyValidatorOperator(validator)
    {
        ValidatorInfo storage info = validatorInfos[validator];
        uint8 currentStatus = uint8(info.status);
        uint64 currentEpoch = uint64(IEpochManager(EPOCH_MANAGER_ADDR).currentEpoch());

        if (currentStatus == uint8(ValidatorStatus.PENDING_ACTIVE)) {
            // use current actual stake to update totalJoiningPower
            uint64 currentVotingPower = uint64(_getValidatorStake(validator));
            validatorSetData.totalJoiningPower -= currentVotingPower;

            // other processing logic remains unchanged
            pendingActive.remove(validator);
            delete pendingActiveIndex[validator];
            info.votingPower = 0;
            info.status = ValidatorStatus.INACTIVE;

            emit ValidatorStatusChanged(
                validator, uint8(ValidatorStatus.PENDING_ACTIVE), uint8(ValidatorStatus.INACTIVE), currentEpoch
            );
        } else if (currentStatus == uint8(ValidatorStatus.ACTIVE)) {
            // check if it's the last validator
            if (activeValidators.length() <= 1) {
                revert LastValidatorCannotLeave();
            }

            // remove from active
            activeValidators.remove(validator);
            delete activeValidatorIndex[validator];

            // add to pending_inactive
            pendingInactive.add(validator);
            pendingInactiveIndex[validator] = pendingInactive.length() - 1;

            // update total voting power
            validatorSetData.totalVotingPower -= info.votingPower;
            info.status = ValidatorStatus.PENDING_INACTIVE;

            emit ValidatorStatusChanged(
                validator, uint8(ValidatorStatus.ACTIVE), uint8(ValidatorStatus.PENDING_INACTIVE), currentEpoch
            );
        } else {
            revert ValidatorNotActive(validator);
        }

        emit ValidatorLeaveRequested(validator, currentEpoch);
    }

    /// @inheritdoc IValidatorManager
    function onNewEpoch() external onlyEpochManager {
        uint64 currentEpoch = uint64(IEpochManager(EPOCH_MANAGER_ADDR).currentEpoch());
        uint64 minStakeRequired = uint64(IStakeConfig(STAKE_CONFIG_ADDR).minValidatorStake());

        // 1. process all StakeCredit status transitions (make pending_active become active)
        _processAllStakeCreditsNewEpoch();

        // 2. activate pending_active validators (based on updated stake data)
        _activatePendingValidators(currentEpoch);

        // 3. remove pending_inactive validators
        _removePendingInactiveValidators(currentEpoch);

        // 4. distribute rewards (based on updated status)
        _distributeRewards();

        // 5. recalculate validator set (based on latest stake data)
        _recalculateValidatorSet(minStakeRequired, currentEpoch);

        // 6. notify ValidatorPerformanceTracker contract
        IValidatorPerformanceTracker(VALIDATOR_PERFORMANCE_TRACKER_ADDR).onNewEpoch();

        // 7. reset joining power
        validatorSetData.totalJoiningPower = 0;

        emit ValidatorSetUpdated(
            currentEpoch + 1,
            activeValidators.length(),
            pendingActive.length(),
            pendingInactive.length(),
            validatorSetData.totalVotingPower
        );
    }

    /**
     * @dev get validator state
     */
    function getValidatorState(address validator) public view returns (uint8) {
        if (!validatorInfos[validator].registered) {
            return uint8(ValidatorStatus.INACTIVE);
        }
        return uint8(validatorInfos[validator].status);
    }

    /// @inheritdoc IValidatorManager
    function getValidatorInfo(address validator) external view returns (ValidatorInfo memory) {
        return validatorInfos[validator];
    }

    /// @inheritdoc IValidatorManager
    function getActiveValidators() external view returns (address[] memory) {
        return activeValidators.values();
    }

    /// @inheritdoc IValidatorManager
    function isCurrentValidator(address validator) external view returns (bool) {
        return validatorInfos[validator].status == ValidatorStatus.ACTIVE;
    }

    /// @inheritdoc IValidatorManager
    function getValidatorSetData() external view returns (ValidatorSetData memory) {
        return validatorSetData;
    }

    /// @inheritdoc IValidatorManager
    function updateConsensusKey(address validator, bytes calldata newConsensusKey)
        external
        validatorExists(validator)
        onlyValidatorOperator(validator)
    {
        // check if new consensus address is duplicate and not from the same validator
        if (
            newConsensusKey.length > 0 && consensusToValidator[newConsensusKey] != address(0)
                && consensusToValidator[newConsensusKey] != validator
        ) {
            revert DuplicateConsensusAddress(newConsensusKey);
        }

        // clear old consensus address mapping
        bytes memory oldConsensusKey = validatorInfos[validator].consensusPublicKey;
        if (oldConsensusKey.length > 0) {
            delete consensusToValidator[oldConsensusKey];
        }

        // update validator info
        validatorInfos[validator].consensusPublicKey = newConsensusKey;

        // update consensus address mapping
        if (newConsensusKey.length > 0) {
            consensusToValidator[newConsensusKey] = validator;
        }

        emit ValidatorInfoUpdated(validator, "consensusKey");
    }

    /// @inheritdoc IValidatorManager
    function updateCommissionRate(address validator, uint64 newCommissionRate)
        external
        validatorExists(validator)
        onlyValidatorOperator(validator)
    {
        ValidatorInfo storage info = validatorInfos[validator];

        // check update frequency
        if (info.updateTime + BREATHE_BLOCK_INTERVAL > ITimestamp(TIMESTAMP_ADDR).nowSeconds()) {
            revert UpdateTooFrequently();
        }

        uint256 maxCommissionRate = IStakeConfig(STAKE_CONFIG_ADDR).maxCommissionRate();
        if (newCommissionRate > maxCommissionRate) {
            revert InvalidCommissionRate(newCommissionRate, uint64(maxCommissionRate));
        }

        // calculate change amount
        uint256 changeRate = newCommissionRate >= info.commission.rate
            ? newCommissionRate - info.commission.rate
            : info.commission.rate - newCommissionRate;

        // check if change exceeds daily max change rate
        if (changeRate > info.commission.maxChangeRate) {
            revert InvalidCommission();
        }

        // update commission rate
        info.commission.rate = newCommissionRate;
        info.updateTime = ITimestamp(TIMESTAMP_ADDR).nowSeconds();

        emit CommissionRateEdited(validator, newCommissionRate);
        emit ValidatorInfoUpdated(validator, "commissionRate");
    }

    /// @inheritdoc IValidatorManager
    function updateVoteAddress(address validator, bytes calldata newVoteAddress, bytes calldata blsProof)
        external
        validatorExists(validator)
        onlyValidatorOperator(validator)
    {
        // validate new vote address
        if (newVoteAddress.length > 0) {
            // BLS proof verification
            if (!_checkVoteAddress(validator, newVoteAddress, blsProof)) {
                revert InvalidVoteAddress();
            }

            // check for duplicates from different validators
            if (
                voteAddressToValidator[newVoteAddress] != address(0)
                    && voteAddressToValidator[newVoteAddress] != validator
            ) {
                revert DuplicateVoteAddress(newVoteAddress);
            }
        }

        // clear old mappings
        bytes memory oldVoteAddress = validatorInfos[validator].voteAddress;
        if (oldVoteAddress.length > 0) {
            delete voteAddressToValidator[oldVoteAddress];
            voteExpiration[oldVoteAddress] = ITimestamp(TIMESTAMP_ADDR).nowSeconds();
        }

        // update validator info
        validatorInfos[validator].voteAddress = newVoteAddress;

        // update vote address mapping
        if (newVoteAddress.length > 0) {
            voteAddressToValidator[newVoteAddress] = validator;
        }

        emit ValidatorInfoUpdated(validator, "voteAddress");
    }

    /**
     * @dev Activate pending validators
     */
    function _activatePendingValidators(uint64 currentEpoch) internal {
        address[] memory pendingValidators = pendingActive.values();

        for (uint256 i = 0; i < pendingValidators.length; i++) {
            address validator = pendingValidators[i];
            ValidatorInfo storage info = validatorInfos[validator];

            // remove from pending_active
            pendingActive.remove(validator);
            delete pendingActiveIndex[validator];

            // add to active
            activeValidators.add(validator);
            info.validatorIndex = activeValidators.length() - 1;
            activeValidatorIndex[validator] = info.validatorIndex;

            // update status
            info.status = ValidatorStatus.ACTIVE;
            info.lastEpochActive = currentEpoch;

            emit ValidatorStatusChanged(
                validator, uint8(ValidatorStatus.PENDING_ACTIVE), uint8(ValidatorStatus.ACTIVE), currentEpoch
            );
        }
    }

    /**
     * @dev Remove pending inactive validators
     */
    function _removePendingInactiveValidators(uint64 currentEpoch) internal {
        address[] memory pendingInactiveValidators = pendingInactive.values();

        for (uint256 i = 0; i < pendingInactiveValidators.length; i++) {
            address validator = pendingInactiveValidators[i];
            ValidatorInfo storage info = validatorInfos[validator];

            // remove from pending_inactive
            pendingInactive.remove(validator);
            delete pendingInactiveIndex[validator];

            // update status
            info.status = ValidatorStatus.INACTIVE;
            info.lastEpochActive = currentEpoch;

            // fund status is already handled in StakeCredit.onNewEpoch()

            emit ValidatorStatusChanged(
                validator, uint8(ValidatorStatus.PENDING_INACTIVE), uint8(ValidatorStatus.INACTIVE), currentEpoch
            );
        }
    }

    /**
     * @dev 重新计算验证者集合
     */
    function _recalculateValidatorSet(uint64 minStakeRequired, uint64 currentEpoch) internal {
        uint128 newTotalVotingPower = 0;
        address[] memory currentActive = activeValidators.values();

        for (uint256 i = 0; i < currentActive.length; i++) {
            address validator = currentActive[i];
            ValidatorInfo storage info = validatorInfos[validator];

            // update voting power
            uint64 currentStake = uint64(_getValidatorStake(validator));

            if (currentStake >= minStakeRequired) {
                info.votingPower = currentStake;
                newTotalVotingPower += currentStake;
            } else {
                // insufficient voting power, remove validator
                activeValidators.remove(validator);
                delete activeValidatorIndex[validator];

                info.status = ValidatorStatus.INACTIVE;
                info.votingPower = 0;
                info.lastEpochActive = currentEpoch;

                emit ValidatorStatusChanged(
                    validator, uint8(ValidatorStatus.ACTIVE), uint8(ValidatorStatus.INACTIVE), currentEpoch
                );
            }
        }

        // update total voting power
        validatorSetData.totalVotingPower = newTotalVotingPower;
    }

    /**
     * @dev 部署StakeCredit合约
     */
    function _deployStakeCredit(address validator, string memory moniker, address beneficiary)
        internal
        returns (address)
    {
        address creditProxy = address(new TransparentUpgradeableProxy(STAKE_CREDIT_ADDR, DEAD_ADDRESS, ""));
        IStakeCredit(creditProxy).initialize{value: msg.value}(validator, moniker, beneficiary);
        emit StakeCreditDeployed(validator, creditProxy);

        return creditProxy;
    }

    /**
     * @dev get validator stake
     */
    function _getValidatorStake(address validator) internal view returns (uint256) {
        address stakeCreditAddress = validatorInfos[validator].stakeCreditAddress;
        if (stakeCreditAddress == address(0)) {
            return 0;
        }

        // get next epoch voting power directly from StakeCredit
        return StakeCredit(payable(stakeCreditAddress)).getNextEpochVotingPower();
    }

    /**
     * @dev check voting power increase limit
     */
    function _checkVotingPowerIncrease(uint256 increaseAmount) internal view {
        uint256 votingPowerIncreaseLimit = IStakeConfig(STAKE_CONFIG_ADDR).votingPowerIncreaseLimit();

        if (validatorSetData.totalVotingPower > 0) {
            // 计算所有pending验证人的实际下一个epoch投票权
            uint256 totalPendingPower = 0;
            address[] memory pendingVals = pendingActive.values();
            for (uint256 i = 0; i < pendingVals.length; i++) {
                totalPendingPower += _getValidatorStake(pendingVals[i]);
            }

            uint256 currentJoining = totalPendingPower + increaseAmount;

            if (currentJoining * 100 > validatorSetData.totalVotingPower * votingPowerIncreaseLimit) {
                revert VotingPowerIncreaseExceedsLimit();
            }
        }
    }

    /**
     * @dev Verify BLS vote address and proof
     * @param operatorAddress Operator address
     * @param voteAddress BLS vote address
     * @param blsProof BLS proof
     * @return Whether verification succeeded
     */
    function _checkVoteAddress(address operatorAddress, bytes calldata voteAddress, bytes calldata blsProof)
        internal
        view
        returns (bool)
    {
        // check lengths
        if (voteAddress.length != BLS_PUBKEY_LENGTH || blsProof.length != BLS_SIG_LENGTH) {
            return false;
        }

        // generate message hash
        bytes32 msgHash = keccak256(abi.encodePacked(operatorAddress, voteAddress, block.chainid));
        bytes memory msgBz = new bytes(32);
        assembly {
            mstore(add(msgBz, 32), msgHash)
        }

        // call precompiled contract to verify BLS signature
        // precompiled contract address is 0x66
        bytes memory input = bytes.concat(msgBz, blsProof, voteAddress); // length: 32 + 96 + 48 = 176
        bytes memory output = new bytes(1);
        assembly {
            let len := mload(input)
            if iszero(staticcall(not(0), 0x66, add(input, 0x20), len, add(output, 0x20), 0x01)) { revert(0, 0) }
        }
        uint8 result = uint8(output[0]);
        if (result != uint8(1)) {
            return false;
        }
        return true;
    }

    /**
     * @dev Process all StakeCredits for epoch transition
     */
    function _processAllStakeCreditsNewEpoch() internal {
        // 1. process active validators' StakeCredit
        address[] memory activeVals = activeValidators.values();
        for (uint256 i = 0; i < activeVals.length; i++) {
            address validator = activeVals[i];
            address stakeCreditAddress = validatorInfos[validator].stakeCreditAddress;
            if (stakeCreditAddress != address(0)) {
                StakeCredit(payable(stakeCreditAddress)).onNewEpoch();
            }
        }

        // 2. process pending active validators' StakeCredit
        address[] memory pendingActiveVals = pendingActive.values();
        for (uint256 i = 0; i < pendingActiveVals.length; i++) {
            address validator = pendingActiveVals[i];
            address stakeCreditAddress = validatorInfos[validator].stakeCreditAddress;
            if (stakeCreditAddress != address(0)) {
                StakeCredit(payable(stakeCreditAddress)).onNewEpoch();
            }
        }

        // 3. process pending inactive validators' StakeCredit
        address[] memory pendingInactiveVals = pendingInactive.values();
        for (uint256 i = 0; i < pendingInactiveVals.length; i++) {
            address validator = pendingInactiveVals[i];
            address stakeCreditAddress = validatorInfos[validator].stakeCreditAddress;
            if (stakeCreditAddress != address(0)) {
                StakeCredit(payable(stakeCreditAddress)).onNewEpoch();
            }
        }
    }

    /// @inheritdoc IValidatorManager
    function checkValidatorMinStake(address validator) external {
        _checkValidatorMinStake(validator);
    }

    function _checkValidatorMinStake(address validator) internal {
        ValidatorInfo storage info = validatorInfos[validator];
        if (info.status == ValidatorStatus.ACTIVE) {
            uint256 validatorStake = _getValidatorStake(validator);
            uint256 minStake = IStakeConfig(STAKE_CONFIG_ADDR).minValidatorStake();

            if (validatorStake < minStake) {
                uint8 oldStatus = uint8(info.status);
                info.status = ValidatorStatus.PENDING_INACTIVE;

                // add to pending_inactive set
                pendingInactive.add(validator);
                pendingInactiveIndex[validator] = pendingInactive.length() - 1;

                // only update totalVotingPower
                validatorSetData.totalVotingPower -= info.votingPower;

                uint64 currentEpoch = uint64(IEpochManager(EPOCH_MANAGER_ADDR).currentEpoch());
                emit ValidatorStatusChanged(validator, oldStatus, uint8(ValidatorStatus.PENDING_INACTIVE), currentEpoch);
            }
        }
    }

    /// @inheritdoc IValidatorManager
    function getValidatorStakeCredit(address validator) external view returns (address) {
        return validatorInfos[validator].stakeCreditAddress;
    }

    /// @inheritdoc IValidatorManager
    function checkVotingPowerIncrease(uint256 increaseAmount) external view {
        _checkVotingPowerIncrease(increaseAmount);
    }

    /// @inheritdoc IValidatorManager
    function isValidatorRegistered(address validator) external view override returns (bool) {
        return validatorInfos[validator].registered;
    }

    /// @inheritdoc IValidatorManager
    function isValidatorExists(address validator) external view returns (bool) {
        return validatorInfos[validator].registered;
    }

    /// @inheritdoc IValidatorManager
    function getTotalVotingPower() external view override returns (uint256) {
        return validatorSetData.totalVotingPower;
    }

    /**
     * @dev 获取待处理验证者列表
     */
    function getPendingValidators() external view override returns (address[] memory) {
        return pendingActive.values();
    }

    /// @inheritdoc IValidatorManager
    function isCurrentEpochValidator(address validator) public view override returns (bool) {
        return validatorInfos[validator].status == ValidatorStatus.ACTIVE;
    }

    /// @inheritdoc IValidatorManager
    function getValidatorStatus(address validator) external view override returns (ValidatorStatus) {
        if (!validatorInfos[validator].registered) {
            return ValidatorStatus.INACTIVE;
        }
        return validatorInfos[validator].status;
    }

    /// @inheritdoc IValidatorManager
    function getValidatorVoteAddress(address validator) external view returns (bytes memory) {
        return validatorInfos[validator].voteAddress;
    }

    /**
     * @dev Store validator basic information
     */
    function _storeValidatorInfo(
        address validator,
        bytes memory consensusPublicKey,
        address payable feeAddress,
        bytes memory voteAddress,
        uint64 commissionRate,
        string memory moniker,
        address stakeCreditAddress,
        ValidatorStatus status
    ) internal {
        validatorInfos[validator] = ValidatorInfo({
            consensusPublicKey: consensusPublicKey,
            feeAddress: feeAddress,
            voteAddress: voteAddress,
            commission: Commission({
                rate: commissionRate,
                maxRate: 5000, // default max commission rate 50%
                maxChangeRate: 500 // default max daily change rate 5%
            }),
            moniker: moniker,
            createdTime: ITimestamp(TIMESTAMP_ADDR).nowSeconds(),
            registered: true,
            stakeCreditAddress: stakeCreditAddress,
            status: status,
            votingPower: 0,
            validatorIndex: 0,
            lastEpochActive: 0,
            updateTime: ITimestamp(TIMESTAMP_ADDR).nowSeconds(),
            operator: validator // Default to self
        });
    }

    /**
     * @dev Get validator index in current active validator set
     * @param validator Validator address
     * @return Validator index, may return 0 or revert if not active
     */
    function getValidatorIndex(address validator) external view returns (uint64) {
        if (!isCurrentEpochValidator(validator)) {
            revert ValidatorNotActive(validator);
        }
        return uint64(activeValidatorIndex[validator]);
    }

    /**
     * @dev System caller calls, deposit transaction fees of current block as rewards
     */
    function deposit() external payable onlySystemCaller {
        // accumulate to total reward pool
        totalIncoming += msg.value;

        emit RewardsCollected(msg.value, totalIncoming);
    }

    /**
     * @dev Distribute validator rewards
     */
    function _distributeRewards() internal {
        if (totalIncoming == 0) return;

        address[] memory validators = activeValidators.values();
        uint256 totalWeight = 0;
        uint256[] memory weights = new uint256[](validators.length);

        // calculate each validator's weight (based on performance and stake)
        for (uint256 i = 0; i < validators.length; i++) {
            address validator = validators[i];
            address stakeCreditAddress = validatorInfos[validator].stakeCreditAddress;

            if (stakeCreditAddress != address(0)) {
                uint256 stake = _getValidatorCurrentEpochVotingPower(validator);

                // get validator performance data
                (uint64 successfulProposals, uint64 failedProposals,, bool exists) =
                    IValidatorPerformanceTracker(PERFORMANCE_TRACKER_ADDR).getValidatorPerformance(validator);

                if (exists) {
                    uint64 totalProposals = successfulProposals + failedProposals;

                    if (totalProposals > 0) {
                        // directly calculate weight by ratio, validators without proposals don't participate
                        weights[i] = (stake * successfulProposals) / totalProposals;
                        totalWeight += weights[i];
                    }
                }
            }
        }

        // distribute rewards by weight
        if (totalWeight > 0) {
            for (uint256 i = 0; i < validators.length; i++) {
                if (weights[i] > 0) {
                    address validator = validators[i];
                    address stakeCreditAddress = validatorInfos[validator].stakeCreditAddress;

                    // calculate validator's reward
                    uint256 reward = (totalIncoming * weights[i]) / totalWeight;

                    // check if stakeCreditAddress is valid
                    if (stakeCreditAddress == address(0)) {
                        // if stakeCreditAddress is invalid, send reward to system reward contract
                        (bool success,) = SYSTEM_REWARD_ADDR.call{value: reward}("");
                        if (success) {
                            emit RewardDistributeFailed(validator, "INVALID_STAKECREDIT");
                        }
                    } else {
                        // get commission rate
                        uint64 commissionRate = validatorInfos[validator].commission.rate;

                        // send reward - no need for try-catch, assume call always succeeds
                        StakeCredit(payable(stakeCreditAddress)).distributeReward{value: reward}(commissionRate);
                        emit RewardsDistributed(validator, reward);
                    }
                }
            }
        } else {
            // if no validators are eligible for rewards, send all rewards to system reward contract
            (bool success,) = SYSTEM_REWARD_ADDR.call{value: totalIncoming}("");
            if (success) {
                emit RewardDistributeFailed(address(0), "NO_ELIGIBLE_VALIDATORS");
            }
        }

        // reset reward pool
        totalIncoming = 0;
    }

    /**
     * @dev Get validator's current epoch voting power
     * Inherited from StakeReward._getValidatorCurrentEpochVotingPower()
     */
    function _getValidatorCurrentEpochVotingPower(address validator) internal view returns (uint256) {
        address stakeCreditAddress = validatorInfos[validator].stakeCreditAddress;
        if (stakeCreditAddress == address(0)) {
            return 0;
        }
        return StakeCredit(payable(stakeCreditAddress)).getCurrentEpochVotingPower();
    }

    /**
     * @dev Check if validator name is valid
     * @param moniker Validator name
     * @return Whether the name is valid
     */
    function _checkMoniker(string memory moniker) internal pure returns (bool) {
        bytes memory bz = bytes(moniker);

        // 1. moniker length should be between 3 and 9
        if (bz.length < 3 || bz.length > 9) {
            return false;
        }

        // 2. first character should be uppercase
        if (uint8(bz[0]) < 65 || uint8(bz[0]) > 90) {
            return false;
        }

        // 3. only alphanumeric characters are allowed
        for (uint256 i = 1; i < bz.length; ++i) {
            // Check if the ASCII value of the character falls outside the range of alphanumeric characters
            if (
                (uint8(bz[i]) < 48 || uint8(bz[i]) > 57) && (uint8(bz[i]) < 65 || uint8(bz[i]) > 90)
                    && (uint8(bz[i]) < 97 || uint8(bz[i]) > 122)
            ) {
                // Character is a special character
                return false;
            }
        }

        // No special characters found
        return true;
    }

    /**
     * @dev Check if validator name is already exists
     * @param moniker Validator name
     * @return Whether the name is already exists
     */
    function isMonikerExists(string calldata moniker) external view returns (bool) {
        bytes32 monikerHash = keccak256(abi.encodePacked(moniker));
        return _monikerSet[monikerHash];
    }

    /**
     * @dev Check if validator name is valid
     * @param moniker Validator name
     * @return Whether the name is valid
     */
    function checkMonikerFormat(string calldata moniker) external pure returns (bool) {
        return _checkMoniker(moniker);
    }

    /// @inheritdoc IValidatorManager
    function updateOperator(address validator, address newOperator)
        external
        validatorExists(validator)
        onlyValidatorSelf(validator)
        validAddress(newOperator)
    {
        // check if new operator is already used by another validator
        if (operatorToValidator[newOperator] != address(0)) {
            revert AddressAlreadyInUse(newOperator, operatorToValidator[newOperator]);
        }

        if (newOperator == validator) {
            revert NewOperatorIsValidatorSelf();
        }

        address oldOperator = validatorInfos[validator].operator;

        // update reverse mapping
        if (oldOperator != address(0)) {
            delete operatorToValidator[oldOperator];
        }
        operatorToValidator[newOperator] = validator;

        validatorInfos[validator].operator = newOperator;

        emit OperatorUpdated(validator, oldOperator, newOperator);
    }

    /// @inheritdoc IValidatorManager
    function getOperator(address validator) external view validatorExists(validator) returns (address) {
        return validatorInfos[validator].operator;
    }

    /// @inheritdoc IValidatorManager
    function isValidator(address validator, address account) public view returns (bool) {
        return validator == account && validatorInfos[validator].registered;
    }

    /// @inheritdoc IValidatorManager
    function isOperator(address validator, address account) public view returns (bool) {
        return validatorInfos[validator].registered && validatorInfos[validator].operator == account;
    }

    /// @inheritdoc IValidatorManager
    function hasOperatorPermission(address validator, address account) public view returns (bool) {
        if (!validatorInfos[validator].registered) return false;

        return account == validator || account == validatorInfos[validator].operator;
    }
}
