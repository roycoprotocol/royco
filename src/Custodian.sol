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

    error FundsOnHold();

    constructor(address initialWalletFactory) {
        walletFactory = initialWalletFactory;
    }

    /*//////////////////////////////////////////////////////////////
                              STORAGE
    //////////////////////////////////////////////////////////////*/
    /// @dev Address of the factory deploying new weiroll wallets
    address public walletFactory;

    struct DepositKey {
      ERC20 token;
      address owner;
      address spender;
    }

    /// @dev Tracks user deposits into the the Custodian contract
    mapping(address DepositKey => uint256 balance) public balances;
    /// @dev Tracks how much funds are locked by the spender
    mapping(address DepositKey => uint256 balance) public holds;

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
    function depositFundsIntoTheCustodian(ERC20 token, uint256 amount, address spender) public {
        DepositKey memory key = DepositKey({
          token: token,
          owner: msg.sender, 
          spender: spender
        });

        balances[key] += amount;
        SafeTransferLib.safeTransferFrom(token, msg.sender, address(this), amount);
    }

    /// @param token The ERC20 Token 
    /// @param owner The depositor of the funds 
    /// @param hold The amount of tokens to add the hold on
    function placeHoldOnFunds(ERC20 token, address owner, uint256 hold) public {
        DepositKey memory key = DepositKey({
          token: token,
          owner: owner, 
          spender: msg.sender
        });

        holds[key] += hold;
    }

    /// @param token The ERC20 Token 
    /// @param owner The depositor of the funds 
    /// @param hold The amount of tokens to remove the hold from
    function removeHoldOnFunds(ERC20 token, address owner, uint256 hold) public {
        DepositKey memory key = DepositKey({
          token: token,
          owner: owner, 
          spender: msg.sender
        });

        holds[key] -= hold;
    }


    /// @param token The ERC20 Token to deposit into the custodian
    /// @param amount The amount of tokens to deposit
    function withdrawFundsFromTheCustodian(ERC20 token, uint256 amount, address spender) public {
        DepositKey memory key = DepositKey({
          token: token,
          owner: msg.sender, 
          spender: spender
        });

        balances[key] -= amount;
        if (balances[key] < holds[key]) {
          revert FundsOnHold();
        }
        SafeTransferLib.safeTransfer(token, msg.sender, amount);
    }

    /// @param token The ERC20 to fund the wallet with
    /// @param to The address to "spend" the funds to
    /// @param from The users funds to spend
    /// @param amount The amount of tokens to fund the wallet with
    function spendFunds(ERC20 token, address to, address from, uint256 amount) public {
      DepositKey memory key = DepositKey({
        token: token,
        owner: from, 
        spender: msg.sender
      });

      balances[key] -= amount;
      SafeTransferLib.safeTransfer(token, to, amount);
    }
}
