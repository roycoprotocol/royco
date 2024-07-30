// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {VM} from "lib/weiroll/contracts/VM.sol";
import {Clone} from "lib/clones-with-immutable-args/src/Clone.sol";
import {Owned} from "lib/solmate/src/auth/Owned.sol";
import {ERC20} from "lib/solmate/src/tokens/ERC20.sol";

/// @title OrderFactory
/// @author Royco
/// @notice LPOrder implementation contract.
///   Implements a simple LP order to supply an asset for a given action
contract LPOrder is Clone, VM, Owned(msg.sender) {
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
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    ERC20 immutable public depositToken;
    bool public executed;

    function fundOrder() external {

    }

    function initialize(
      uint256[] calldata markets
    ) external {
      ERC20 _depositToken = depositToken();
      _depositToken.transferFrom(owner(), address(this), amount());

      /// Allowlist all markets
      for(uint256 i; i < markets.length; i++) {
        supportedMarkets[i] = true;
      }
    }

    /*//////////////////////////////////////////////////////////////
                               STATE VARIABLES
    //////////////////////////////////////////////////////////////*/
    mapping(uint256 marketId => bool) public supportedMarkets;   

    /// @notice The address of the order creator (owner)
    function owner() public pure returns (address) {
        return _getArgAddress(0);
    }

    function depositToken() public pure returns (ERC20) {
      return ERC20(_getArgAddress(20));
    }

    function amount() public pure returns (uint256) {
      return _getArgUint256(40);
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
                            CANCELLATION LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice The order has been cancelled.
    bool public cancelled;

    /// @notice Cancel the order.
    /// @dev Only the owner of the order can cancel it.
    function cancel(ERC20[] calldata tokens) public onlyMarket {
        // Mark the order as cancelled.
        cancelled = true;
    }

    /*//////////////////////////////////////////////////////////////
                               EXECUTION LOGIC
    //////////////////////////////////////////////////////////////*/
    error AlreadyRan()

    /// @notice Execute the Weiroll VM with the given commands.
    /// @param commands The commands to be executed by the Weiroll VM.
    /// @dev No state parameter is necessary because the proposed state is stored in the contract.
    function executeWeiroll(
        bytes32[] calldata commands,
        bytes[] calldata state
    ) public payable onlyMarket notLocked returns (bytes[] memory) {
        if (executed) {
          revert AlreadyRan();
        }

        executed = true;
        // Execute the Weiroll VM.
        return _execute(commands, state);
    }

    /// @notice Execute a generic call to another contract.
    function execute(
        address to,
        uint256 value,
        bytes memory data
    ) public onlyOwner notLocked returns (bytes memory) {
        // Execute the call.
        (bool success, bytes memory result) = to.call{value: value}(data);
        if (!success) {
            revert("Generic execute proxy failed"); //TODO: Better revert message (stringify result?)
        }
        return result;
    }
}
