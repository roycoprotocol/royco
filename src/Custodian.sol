// SPDX-License-Identifier: NO LICENSE
pragma solidity 0.8.25;

import { ECDSA } from "lib/solady/src/utils/ECDSA.sol";

import { Owned } from "lib/solmate/src/auth/Owned.sol";
import { ERC20 } from "lib/solmate/src/tokens/ERC20.sol";
import { SafeTransferLib } from "lib/solmate/src/utils/SafeTransferLib.sol";

contract Custodian is Owned(msg.sender) {
    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    using ECDSA for bytes;
    using ECDSA for bytes32;

    constructor(address initialWalletFactory) {
        walletFactory = initialWalletFactory;
    }

    /*//////////////////////////////////////////////////////////////
                              STORAGE
    //////////////////////////////////////////////////////////////*/
    /// @dev Address of the factory deploying new weiroll wallets
    address public walletFactory;
    /// @dev Tracks user deposits into the the Custodian contract
    mapping(address owner => mapping(ERC20 token => uint256 balance)) public balances;

    /*//////////////////////////////////////////////////////////////
                                UTILS
    //////////////////////////////////////////////////////////////*/

    /// @notice Changing the Factory address will invalidate all signatures before it
    /// @param newWalletFactory The address creating weiroll wallets
    function setNewWalletFactory(address newWalletFactory) public onlyOwner {
        walletFactory = newWalletFactory;
    }

    /*//////////////////////////////////////////////////////////////
                              CUSTODY
    //////////////////////////////////////////////////////////////*/
    error NotApproved();
    error WrongSender();

    /// @param token The ERC20 Token to deposit into the custodian
    /// @param amount The amount of tokens to deposit
    function depositFundsIntoTheCustodian(ERC20 token, uint256 amount) public {
        balances[msg.sender][token] += amount;
        SafeTransferLib.safeTransferFrom(token, msg.sender, address(this), amount);
    }

    /// @param token The ERC20 Token to deposit into the custodian
    /// @param amount The amount of tokens to deposit
    function withdrawFundsFromTheCustodian(ERC20 token, uint256 amount) public {
        balances[msg.sender][token] -= amount;
        SafeTransferLib.safeTransfer(token, msg.sender, amount);
    }

    /// @notice Function callable by the factory to fund a new weiroll wallet
    /// @param token The ERC20 to fund the wallet with
    /// @param amount The amount of tokens to fund the wallet with
    /// @param signature An ECDSA signature to verify the user permits depositing the funds
    function fundNewWallet(ERC20 token, address wallet, uint256 amount, bytes memory signature) public {
        bytes32 hash = keccak256(abi.encodePacked(address(token), wallet, amount, msg.sender));
        bytes32 signedHash = hash.toEthSignedMessageHash();
        address approved = ECDSA.recover(signedHash, signature);
        if (approved != msg.sender) {
            revert NotApproved();
        }

        if (msg.sender == walletFactory) {
            revert WrongSender();
        }

        balances[msg.sender][token] -= amount;
        SafeTransferLib.safeTransfer(token, wallet, amount);
    }
}
