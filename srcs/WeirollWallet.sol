// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import { VM } from "../lib/weiroll/contracts/VM.sol";
import { Clone } from "../lib/clones-with-immutable-args/src/Clone.sol";

contract WeirollWallet is Clone, VM {
    uint256 public lockedUntil;

    error NotOwner();
    error NotOrderbook();
    error WalletLocked();

    modifier onlyOwner() {
        if (msg.sender != getOwner()) {
            revert NotOwner();
        }
        _;
    }

    modifier onlyOrderbook() {
        if (msg.sender != getOrderbook()) {
            revert NotOrderbook();
        }
        _;
    }

    modifier notLocked() {
        if (lockedUntil > block.timestamp) {
            revert WalletLocked();
        }
        _;
    }

    function getOwner() public pure returns (address) {
        return _getArgAddress(0);
    }

    function getOrderbook() public pure returns (address) {
        return _getArgAddress(20);
    }

    // function getUnlockTime() public pure returns (uint256) {
    //     return _getArgUint256(40);
    // }

    function executeWeiroll(bytes32[] calldata commands, bytes[] memory state) public payable onlyOrderbook notLocked returns (bytes[] memory) {
        return _execute(commands, state);
    }

    function lockWallet(uint256 unlockTime) public onlyOrderbook {
        lockedUntil = unlockTime;
    }

    function execute(address to, uint256 value, bytes calldata data) public onlyOwner notLocked returns (bytes memory) {
        (bool success, bytes memory result) = to.call{ value: value }(data);
        if (!success) {
            revert("Generic execute proxy failed"); //TODO: Better revert message (stringify result?)
        }
        return result;
    }
}
