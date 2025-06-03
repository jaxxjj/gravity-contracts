// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

import "@openzeppelin-upgrades/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin-upgrades/token/ERC20/extensions/ERC20BurnableUpgradeable.sol";
import "@openzeppelin-upgrades/token/ERC20/extensions/ERC20PermitUpgradeable.sol";
import "@openzeppelin-upgrades/token/ERC20/extensions/ERC20VotesUpgradeable.sol";

import "@src/System.sol";
import "@src/interfaces/IGovToken.sol";
import "@src/interfaces/IStakeCredit.sol";

contract GovToken is
    System,
    Initializable,
    ERC20Upgradeable,
    ERC20BurnableUpgradeable,
    ERC20PermitUpgradeable,
    ERC20VotesUpgradeable,
    IGovToken
{
    /*----------------- constants -----------------*/
    string private constant NAME = "BSC Governance Token";
    string private constant SYMBOL = "govG";

    /*----------------- storage -----------------*/
    // validator StakeCredit contract => user => amount
    mapping(address => mapping(address => uint256)) public mintedMap;

    /*----------------- init -----------------*/
    function initialize() public initializer onlyGenesis {
        __ERC20_init(NAME, SYMBOL);
        __ERC20Burnable_init();
        __ERC20Permit_init(NAME);
        __ERC20Votes_init();
    }

    /*----------------- external functions -----------------*/
    /**
     * @dev Sync the account's govG amount to the actual G value of the StakingCredit he holds
     * @param stakeCredit the stakeCredit Token contract
     * @param account the account to sync gov tokens to
     */
    function sync(address stakeCredit, address account) external onlyValidatorManager {
        _sync(stakeCredit, account);
    }

    /**
     * @dev Batch sync the account's govG amount to the actual G value of the StakingCredit he holds
     * @param stakeCredits the stakeCredit Token contracts
     * @param account the account to sync gov tokens to
     */
    function syncBatch(address[] calldata stakeCredits, address account) external onlyValidatorManager {
        uint256 _length = stakeCredits.length;
        for (uint256 i = 0; i < _length; ++i) {
            _sync(stakeCredits[i], account);
        }
    }

    /**
     * @dev delegate govG votes to delegatee
     * @param delegator the delegator
     * @param delegatee the delegatee
     */
    function delegateVote(address delegator, address delegatee) external onlyValidatorManager {
        _delegate(delegator, delegatee);
    }

    function totalSupply() public view override(ERC20Upgradeable, IGovToken) returns (uint256) {
        return super.totalSupply();
    }
    /**
     * @dev Burn tokens (disabled - will always revert)
     */

    function burn(uint256) public pure override(ERC20BurnableUpgradeable, IGovToken) {
        revert BurnNotAllowed();
    }

    /**
     * @dev Burn tokens from account (disabled - will always revert)
     */
    function burnFrom(address, uint256) public pure override(ERC20BurnableUpgradeable, IGovToken) {
        revert BurnNotAllowed();
    }

    /*----------------- internal functions -----------------*/
    function _sync(address stakeCredit, address account) internal {
        uint256 latestGAmount = IStakeCredit(stakeCredit).getTotalPooledG();
        uint256 _mintedAmount = mintedMap[stakeCredit][account];

        if (_mintedAmount < latestGAmount) {
            uint256 _needMint = latestGAmount - _mintedAmount;
            mintedMap[stakeCredit][account] = latestGAmount;
            _mint(account, _needMint);
        } else if (_mintedAmount > latestGAmount) {
            uint256 _needBurn = _mintedAmount - latestGAmount;
            mintedMap[stakeCredit][account] = latestGAmount;
            _burn(account, _needBurn);
        }
    }

    /**
     * @dev Override _update to prevent transfers while allowing mint/burn
     * In v5.x, _update is the core function that handles mint, burn, and transfer
     */
    function _update(address from, address to, uint256 value)
        internal
        override(ERC20Upgradeable, ERC20VotesUpgradeable)
    {
        // Allow minting (from == address(0)) and burning (to == address(0))
        if (from != address(0) && to != address(0)) {
            revert TransferNotAllowed();
        }

        // Call the parent _update function which handles the voting logic
        ERC20VotesUpgradeable._update(from, to, value);
    }

    /**
     * @dev Override _approve to prevent any approvals
     * Need to override both variants in v5.x
     */
    function _approve(
        address,
        /*owner*/
        address,
        /*spender*/
        uint256,
        /*value*/
        bool /*emitEvent*/
    ) internal pure override {
        revert ApproveNotAllowed();
    }

    /**
     * @dev Resolve nonces function conflict between ERC20Permit and ERC20Votes
     * Use ERC20Permit's implementation for permit functionality
     */
    function nonces(address owner)
        public
        view
        virtual
        override(ERC20PermitUpgradeable, NoncesUpgradeable)
        returns (uint256)
    {
        return super.nonces(owner);
    }
}
