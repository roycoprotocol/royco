// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import { VM } from "lib/weiroll/contracts/VM.sol";
import { Clone } from "lib/clones-with-immutable-args/src/Clone.sol";

/// @title OrderFactory
/// @author Royco
/// @notice WeirollWallet implementation contract.
///   Implements a simple smart contract wallet that can execute Weiroll VM commands
contract WeirollWallet is Clone, VM {
    /*//////////////////////////////////////////////////////////////
                               MODIFIERS
    //////////////////////////////////////////////////////////////*/

    error NotOwner();
    error NotOrderbook();
    error WalletLocked();
    error WalletNotForfeitable();

    /// @notice Only the owner of the contract can call the function
    modifier onlyOwner() {
        if (msg.sender != owner()) {
            revert NotOwner();
        }
        _;
    }

    /// @notice Only the orderbook contract can call the function
    modifier onlyOrderbook() {
        if (msg.sender != orderbook()) {
            revert NotOrderbook();
        }
        _;
    }

    /// @notice The wallet cannot be locked
    modifier notLocked() {
        if (!forfeited && lockedUntil() > block.timestamp) {
            revert WalletLocked();
        }
        _;
    }

    /*//////////////////////////////////////////////////////////////
                               STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    /// @dev Whether or not this order has been executed
    bool public executed;

    bool public forfeited;
    address[] public unlockRewardTokens;
    uint256[] public unlockRewardAmounts;
    address public forfeitRecipient;

    /// @notice Forfeit all rewards to get control of the wallet back 
    function forfeit() public onlyOrderbook {
        if (!isForfeitable()) {
            revert WalletNotForfeitable();
        }

        forfeited = true;
    }

    /// @notice The address of the order creator (owner)
    function owner() public pure returns (address) {
        return _getArgAddress(0);
    }

    /// @notice The address of the orderbook exchange contract
    function orderbook() public pure returns (address) {
        return _getArgAddress(20);
    }

    /// @notice The amount of tokens to be LP'ed
    function amount() public pure returns (uint256) {
        return _getArgUint256(40);
    }

    /// @notice The timestamp after which the wallet may be interacted with
    function lockedUntil() public pure returns (uint256) {
        return _getArgUint256(72);
    }

    /// @notice Returns whether or not the wallet is forfeitable
    function isForfeitable() public pure returns (bool) {
        return _getArgUint8(104) != 0;
    }

    /*//////////////////////////////////////////////////////////////
                               EXECUTION LOGIC
    //////////////////////////////////////////////////////////////*/
    /// @notice Execute the Weiroll VM with the given commands.
    /// @param commands The commands to be executed by the Weiroll VM.
    function executeWeiroll(bytes32[] calldata commands, bytes[] calldata state) public payable onlyOrderbook returns (bytes[] memory) {
        executed = true;
        // Execute the Weiroll VM.
        return _execute(commands, state);
    }

    /// @notice Execute the Weiroll VM with the given commands.
    /// @param commands The commands to be executed by the Weiroll VM.
    function manualExecuteWeiroll(bytes32[] calldata commands, bytes[] calldata state) public payable onlyOwner notLocked returns (bytes[] memory) {
        // Prevent people from approving w/e then rugging during vesting
        require(executed, "Royco: Order unfilled");
        // Execute the Weiroll VM.
        return _execute(commands, state);
    }

    /// @notice Execute a generic call to another contract.
    /// @param to The address to call
    /// @param value The ether value of the execution
    /// @param data The data to pass along with the call
    function execute(address to, uint256 value, bytes memory data) public payable onlyOwner notLocked returns (bytes memory) {
        // Prevent people from approving w/e then rugging during vesting
        require(executed, "Royco: Order unfilled");
        // Execute the call.
        (bool success, bytes memory result) = to.call{ value: value }(data);
        if (!success) {
            revert("Generic execute proxy failed");
        }
        return result;
    }
}
