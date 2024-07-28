// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {VM} from "../lib/weiroll/contracts/VM.sol";
import {Clone} from "../lib/clones-with-immutable-args/src/Clone.sol";

/// @title OrderFactory
/// @author Royco
/// @notice ordrr contract
contract Order is Clone, VM {
    /*//////////////////////////////////////////////////////////////
                               MODIFIERS
    //////////////////////////////////////////////////////////////*/

    error NotOwner();
    error NotMarket();
    error WalletLocked();

    /// @notice Only the owner of the contract can call the function
    modifier onlyOwner() {
        if (msg.sender != getOwner()) {
            revert NotOwner();
        }
        _;
    }

    /// @notice Only the orderbook contract can call the function
    modifier onlyMarket() {
        if (msg.sender != getMarket()) {
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
    function getOwner() public pure returns (address) {
        return _getArgAddress(0);
    }

    /// @notice The address of the Market contract.
    function getMarket() public pure returns (address) {
        return _getArgAddress(20);
    }

    /// @notice The address of the Market contract.
    function getSide() public pure returns (Side) {
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

    function executeWeiroll(
        bytes32[] calldata commands,
        bytes[] memory state
    ) public payable onlyMarket notLocked returns (bytes[] memory) {
        return _execute(commands, state);
    }

    function execute(address to, uint256 value, bytes calldata data) public onlyOwner notLocked returns (bytes memory) {
        (bool success, bytes memory result) = to.call{value: value}(data);
        if (!success) {
            revert("Generic execute proxy failed"); //TODO: Better revert message (stringify result?)
        }
        return result;
    }
}
