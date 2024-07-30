// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

// Interfaces 
import { ERC20 } from "lib/solmate/src/tokens/ERC20.sol";

// Libraries 
import { ECDSA } from "lib/solady/src/utils/ECDSA.sol";
import { SafeTransferLib } from "lib/solmate/src/utils/SafeTransferLib.sol";

// Contracts
import { Custodian } from "src/Custodian.sol";
import { WalletFactory } from "src/WalletFactory.sol";
import { WeirollWallet } from "src/WeirollWallet.sol";
import { DssVestTransferrable } from "src/DssVest.sol";

contract Orderbook is WalletFactory {
  using ECDSA for bytes32;
  using ECDSA for bytes;
  /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR
  //////////////////////////////////////////////////////////////*/
  constructor(address _impl, address _custodian) WalletFactory(_impl) {
    custodian = Custodian(_custodian);
  }

  event OrderSubmitted(Order order, bytes signature);

  /*//////////////////////////////////////////////////////////////
                            STORAGE
  //////////////////////////////////////////////////////////////*/
  struct Market {
    ERC20 token;
    bytes32[] weirollCommands;
    bytes[] weirollState;
  }

  uint96 public maxMarketId;

  struct Order {
    Side side;
    Type _type;
    ERC20 token;
    uint96 duration;
    uint128 amount;
    uint128 incentiveAmount;
    uint96 marketId;
    address sender;
    uint128 nonce;
  }

  mapping(address user => mapping(uint128 nonce => bool cancelled)) public cancelledNonces;
  mapping(uint96 marketId => Market _market) public markets;

  Custodian public custodian;

  mapping(ERC20 token => DssVestTransferrable vesting) public vestingContracts;
  /*//////////////////////////////////////////////////////////////
                              INTERFACE
  //////////////////////////////////////////////////////////////*/
  error MarketMismatch();
  error WrongSidesTaken();
  error DurationMistach();
  error OrderCancelled();
  error TypeMismatch();
  error IncorrectSignature();

  event NewOrder();
  
  event NonceCancelled(address user, uint256 nonce);

  /*//////////////////////////////////////////////////////////////
                            ORDERBOOK
  //////////////////////////////////////////////////////////////*/

  function cancelNonce(uint128 nonce) public {
    cancelledNonces[msg.sender][nonce] = false;

    emit NonceCancelled(msg.sender, nonce);
  }

  function submitOrder(Order calldata order, bytes memory sig) public {
    emit OrderSubmitted(order, sig);
  }

  function matchOrders(Order calldata bid, bytes memory bidSignature, Order calldata ask, bytes memory askSignature) public returns (address newWallet){

    // 1. Validate Orders are correct and truthful
    bytes32 hash = keccak256(abi.encode(bid));
    bytes32 signedHash = hash.toEthSignedMessageHash();
    address approved = ECDSA.recover(signedHash, bidSignature);
    if (approved != bid.sender) {
      revert IncorrectSignature();
    }

    hash = keccak256(abi.encode(ask));
    signedHash = hash.toEthSignedMessageHash();
    approved = ECDSA.recover(signedHash, askSignature);
    if (approved != ask.sender) {
      revert IncorrectSignature();
    }

    if (bid.marketId != ask.marketId) {
      revert MarketMismatch();
    }

    if (bid.side != Side.Bid && ask.side != Side.Ask) {
      revert WrongSidesTaken();
    }

    if (bid._type != ask._type) {
      revert TypeMismatch();
    }

    if (bid.duration < ask.duration) {
      revert DurationMistach();
    }

    if (!cancelledNonces[bid.sender][bid.nonce] || !cancelledNonces[ask.sender][ask.nonce]) {
      revert OrderCancelled();
    }

    // 2. Fund and create a new wallet
    Market memory _market = markets[bid.marketId];
    newWallet = address(deployClone(bid.sender, address(this)));

    // 2.1 Fund wallet
    custodian.spendFunds(_market.token, newWallet, ask.sender, ask.amount);
    // 2.2 Execute Script
    WeirollWallet(newWallet).executeWeiroll(_market.weirollCommands, _market.weirollState);

    // 3. Handle Rewards Logic
    if (bid._type == Type.LumpsumUnlocked) {
      // Pay out rewards right away
      custodian.spendFunds(_market.token, ask.sender, bid.sender, bid.incentiveAmount);
    } else if (bid._type == Type.LumpsumLocked) {
      WeirollWallet(newWallet).lockWallet(bid.duration);
      DssVestTransferrable vest = vestingContracts[bid.token];
      if (address(vest) == address(0)) {
        vest = new DssVestTransferrable(address(_market.token), address(this));
        vestingContracts[bid.token] = vest;
      }
      vest.create(ask.sender, ask.incentiveAmount, block.timestamp, bid.duration, bid.duration, address(0));
    } else if (bid._type == Type.StreamingUnlocked) {
      // Deploy and fund a new pastry chef
    } else if (bid._type == Type.StreamingLocked) {
      WeirollWallet(newWallet).lockWallet(bid.duration);
      
      DssVestTransferrable vest = vestingContracts[bid.token];
      if (address(vest) == address(0)) {
        vest = new DssVestTransferrable(address(_market.token), address(this));
        vestingContracts[bid.token] = vest;
      }
      
      vest.create(ask.sender, ask.incentiveAmount, block.timestamp, bid.duration, 0, address(0));
    }
  }
}
