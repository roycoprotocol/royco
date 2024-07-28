// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {VM} from "../lib/weiroll/contracts/VM.sol";
import {Clone} from "../lib/clones-with-immutable-args/src/Clone.sol";

import {ERC20} from "../lib/solmate/src/tokens/ERC20.sol";

/// @title OrderFactory
/// @author Royco
/// @notice Order implementation contract.
/// Responsible for holding Rewards and completing Actions.
contract Order is Clone, VM {
    /*//////////////////////////////////////////////////////////////
                               MODIFIERS
    //////////////////////////////////////////////////////////////*/

    error NotOwner();
    error NotMarket();
    error WalletLocked();

    /// @notice Only the owner of the contract can call the function
    modifier onlyOwner() {
        if (msg.sender != owner()) {
            revert NotOwner();
        }
        _;
    }

    /// @notice Only the orderbook contract can call the function
    modifier onlyMarket() {
        if (msg.sender != market()) {
            revert NotMarket();
        }
        _;
    }

    /// @notice The wallet cannot be locked
    modifier notLocked() {
        if (lockedUntil > block.timestamp) {
            revert WalletLocked();
        }
        _;
    }

    /*//////////////////////////////////////////////////////////////
                          INITIALIZATION LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Quantity of each token utilized as a reward in the market.
    /// @dev Only necessary if the order is a Reward Order.
    uint256[] public amounts;

    /// @notice State to be passed to the Weiroll VM.
    /// @dev Only necessary if the order is an Action Order.
    bytes[] public weirollState;

    /// @notice Initialize an order made by either the Reward Provider or Action Provider.
    function initialize(uint256[] calldata _amounts, bytes[] calldata _weirollState) public onlyMarket {
        // Set the amounts proposed by the offerer.
        // We don't need to store the addresses of the tokens because the market contract already has them.
        // Note: If this is a RewardOrder, the tokens must be transferred to this contract.
        amounts = _amounts;

        // Set the state to be passed to the Weiroll VM.
        weirollState = _weirollState;
    }

    /*//////////////////////////////////////////////////////////////
                               STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice The side of the order.
    /// @dev A RewardOrder/bid is an order created by the Reward Provider and holds the reward.
    /// @dev An ActionOrder/ask is an order created by the Action Provider.
    enum Side {
        RewardOrder,
        ActionOrder
    }

    /// @notice The address of the order creator (owner)
    function owner() public pure returns (address) {
        return _getArgAddress(0);
    }

    /// @notice The address of the Market contract.
    function market() public pure returns (address) {
        return _getArgAddress(20);
    }

    /// @notice The address of the Market contract.
    function side() public pure returns (Side) {
        return Side(_getArgUint256(40));
    }

    /*//////////////////////////////////////////////////////////////
                               LOCKING LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice The time until the wallet is locked.
    uint256 public lockedUntil;

    /// @notice Lock the wallet until a certain time.
    function lockWallet(uint256 unlockTime) public onlyMarket {
        lockedUntil = unlockTime;
    }

    /*//////////////////////////////////////////////////////////////
                               EXECUTION LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice This function can only be called if the order is an Action Order.
    error ActionOrderOnly();

    /// @notice Execute the Weiroll VM with the given commands.
    /// @param commands The commands to be executed by the Weiroll VM.
    /// @dev No state parameter is necessary because the proposed state is stored in the contract.
    function executeWeiroll(bytes32[] calldata commands) public payable onlyMarket notLocked returns (bytes[] memory) {
        // Only Action Orders can execute Weiroll commands.
        if (side() == Side.RewardOrder) {
            revert ActionOrderOnly();
        }

        return _execute(commands, weirollState);
    }

    /// @notice Execute a generic call to another contract.
    /// note: SHOULD THIS FUNCTION BE ALLOWED IF THIS IS A REWARD ORDER?
    function execute(address to, uint256 value, bytes memory data) public onlyOwner notLocked returns (bytes memory) {
        // Only Action Orders can have this function called.
        if (side() == Side.RewardOrder) {
            revert ActionOrderOnly();
        }

        // Execute the call.
        (bool success, bytes memory result) = to.call{value: value}(data);
        if (!success) {
            revert("Generic execute proxy failed"); //TODO: Better revert message (stringify result?)
        }
        return result;
    }

    /*//////////////////////////////////////////////////////////////
                        REWARD DISTRIBUTION LOGIC
    //////////////////////////////////////////////////////////////*/
    /// @notice This function can only be called if the order is an Reward Order.
    error RewardOrderOnly();

    /// @notice Distribute the rewards to the Reward Provider.
    /// @dev Only the Market contract can call this function.
    /// @param tokens The tokens to be distributed.
    /// @param recipient The address of the Action Provider receiving the rewards.
    function distributeRewards(ERC20[] calldata tokens, address recipient) public onlyMarket notLocked {
        // Only Reward Orders can distribute rewards.
        if (side() == Side.ActionOrder) {
            revert RewardOrderOnly();
        }

        // Transfer the rewards to the Action .
        for (uint256 i = 0; i < amounts.length; i++) {
            ERC20 token = tokens[i];
            token.transfer(recipient, amounts[i]);
        }
    }
}
