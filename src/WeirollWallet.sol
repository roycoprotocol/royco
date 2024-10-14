// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import { VM } from "lib/weiroll/contracts/VM.sol";
import { Clone } from "lib/clones-with-immutable-args/src/Clone.sol";

/// @title WeirollWallet
/// @author Royco
/// @notice WeirollWallet implementation contract.
/// @notice Implements a simple smart contract wallet that can execute Weiroll VM commands
contract WeirollWallet is Clone, VM {
    /// @notice Let the Weiroll Wallet receive ether directly if needed
    receive() external payable { }
    /// @notice Also allow a fallback with no logic if erroneous data is provided
    fallback() external payable { }
    /*//////////////////////////////////////////////////////////////
                               MODIFIERS
    //////////////////////////////////////////////////////////////*/

    // Emit when owner executes an arbitrary script (not a market script)
    event WeirollWalletExecutedManually();

    error NotOwner();
    error NotRecipeMarketHub();
    error WalletLocked();
    error WalletNotForfeitable();

    /// @notice Only the owner of the contract can call the function
    modifier onlyOwner() {
        if (msg.sender != owner()) {
            revert NotOwner();
        }
        _;
    }

    /// @notice Only the recipeMarketHub contract can call the function
    modifier onlyRecipeMarketHub() {
        if (msg.sender != recipeMarketHub()) {
            revert NotRecipeMarketHub();
        }
        _;
    }

    /// @notice The wallet can be locked
    modifier notLocked() {
        if (!forfeited && lockedUntil() > block.timestamp) {
            revert WalletLocked();
        }
        _;
    }

    /*//////////////////////////////////////////////////////////////
                               STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    /// @dev Whether or not this offer has been executed
    bool public executed;
    /// @dev Whether or not the wallet has been forfeited
    bool public forfeited;

    /// @notice Forfeit all rewards to get control of the wallet back
    function forfeit() public onlyRecipeMarketHub {
        if (!isForfeitable() || block.timestamp >= lockedUntil()) {
            // Can't forfeit if:
            // 1. Wallet not created through a forfeitable market
            // 2. Lock time has passed and claim window has started
            revert WalletNotForfeitable();
        }

        forfeited = true;
    }

    /// @notice The address of the offer creator (owner)
    function owner() public pure returns (address) {
        return _getArgAddress(0);
    }

    /// @notice The address of the RecipeMarketHub contract
    function recipeMarketHub() public pure returns (address) {
        return _getArgAddress(20);
    }

    /// @notice The amount of tokens deposited into this wallet from the recipeMarketHub
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

    /// @notice Returns the hash of the market associated with this weiroll wallet
    function marketHash() public pure returns (bytes32) {
        return bytes32(_getArgUint256(105));
    }

    /*//////////////////////////////////////////////////////////////
                               EXECUTION LOGIC
    //////////////////////////////////////////////////////////////*/
    /// @notice Execute the Weiroll VM with the given commands.
    /// @param commands The commands to be executed by the Weiroll VM.
    function executeWeiroll(bytes32[] calldata commands, bytes[] calldata state) public payable onlyRecipeMarketHub returns (bytes[] memory) {
        executed = true;
        // Execute the Weiroll VM.
        return _execute(commands, state);
    }

    /// @notice Execute the Weiroll VM with the given commands.
    /// @param commands The commands to be executed by the Weiroll VM.
    function manualExecuteWeiroll(bytes32[] calldata commands, bytes[] calldata state) public payable onlyOwner notLocked returns (bytes[] memory) {
        // Prevent people from approving w/e then rugging during vesting
        require(executed, "Royco: Offer unfilled");

        emit WeirollWalletExecutedManually();
        // Execute the Weiroll VM.
        return _execute(commands, state);
    }

    /// @notice Execute a generic call to another contract.
    /// @param to The address to call
    /// @param value The ether value of the execution
    /// @param data The data to pass along with the call
    function execute(address to, uint256 value, bytes memory data) public payable onlyOwner notLocked returns (bytes memory) {
        // Prevent people from approving w/e then rugging during vesting
        require(executed, "Royco: Offer unfilled");

        // Execute the call.
        (bool success, bytes memory result) = to.call{ value: value }(data);
        if (!success) {
            revert("Generic execute proxy failed");
        }

        emit WeirollWalletExecutedManually();
        return result;
    }
}
