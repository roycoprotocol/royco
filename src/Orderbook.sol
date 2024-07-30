// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

// Interfaces 
import { ERC20 } from "lib/solmate/src/tokens/ERC20.sol";

// Libraries 
import { ECDSA } from "lib/solady/src/utils/ECDSA.sol";
import { SafeTransferLib } from "lib/solmate/src/utils/SafeTransferLib.sol";
import { FixedPointMathLib } from "lib/solady/src/utils/FixedPointMathLib.sol";

// Contracts 
import { LPOrder } from "src/LPOrder.sol";

contract LSUnlockedOrderbook {
  /*//////////////////////////////////////////////////////////////
                             INTERFACE
  //////////////////////////////////////////////////////////////*/
  event OrderSubmitted {
    address order, 
    address creator,
    uint256[] markets
  }

  /*//////////////////////////////////////////////////////////////
                              STORAGE
  //////////////////////////////////////////////////////////////*/
  struct IPOrder {
    address sender;
    uint96 duration;
    uint128 amount;
    uint128 incentiveAmount;
    uint128 marketId;
    uint128 nonce;
  }

  uint256 public maxIPOrderId;
  mapping(uint256 IPOrderId => IPOrder) public IpOrders; 
  
  uint256 public maxLPOrderId;
  mapping(uint256 LPOrderId => LPOrder) public LpOrders; 

  enum MarketType {
    FL_Vesting, // Front-loaded Vesting
    BL_Vesting, // Back-loaded Vesting 
    Streaming,
    Forfeitable_Vested
  }
  
  struct Market {
    ERC20 depositToken;
    ERC20 primaryRewardToken;
    MarketType _type;
    Aloha enter;
    Aloha exit;
  }
  
  /// @dev Its for both enter/exit so the named fit
  struct Aloha {
    bytes32[] weirollCommands,
    bytes[] weirollState
  }

  uint256 public maxMarketId;
  mapping(uint256 marketId => Market _market) public markets;

  mapping(ERC20 rewardToken => mapping(LPOrder order => uint256 rewardsOwed)) public OrderRewardsOwed;

  /*//////////////////////////////////////////////////////////////
                           MARKET ACTIONS
  //////////////////////////////////////////////////////////////*/
  function createMarket(
    ERC20 _depositToken,
    ERC20 _primaryRewardToken,
    MarketType marketType, 
    Aloha enterMarket,
    Aloha exitMarekt
  ) public returns (uint256 marketId) {
    marketId = maxMarketId++;

    markets[marketId] = Market({
      depositToken: _depositToken,
      primaryRewardToken: _primaryRewardToken,
      _type: marketType,
      enter: enterMarket,
      exit: enterMarket
    });
  }

  /*//////////////////////////////////////////////////////////////
                               ORDERS
  //////////////////////////////////////////////////////////////*/
  function createLPOrder(ERC20 depositToken, uint256 tokenAmount, uint96 maxDuration, uint256[] calldata markets) external returns (address clone, uint256 orderId) {
    LPOrder clone = LPOrder(deployClone(msg.sender, address(depositToken), tokenAmount, address(this)));
    
    orderId = maxLPOrderId++
    clone.initialize(markets);

    LpOrders[orderId] = clone;

    emit OrderSubmitted(address(clone), msg.sender, markets);
  }

  function createIPOrder(uint96 _duration, uint128 _amount, uint128 _incentiveAmount, uint128 _marketId) external returns (uint256 IPOrderId){
    Market memory _market = markets[_marketId];
    _market.primaryRewardToken.safeTransferFrom(msg.sender, address(this), _incentiveAmount);

    Order memory order = Order({
      sender: msg.sender,
      duration: _duration,
      amount: _amount,
      incentiveAmount: _incentiveAmount,
      marketId: _marketId
    });

    IPOrderId = maxIPOrderId++;
    IpOrders[IPOrderId] = order;
  }

  function matchOrders(uint256 IPOrderId, uint256 LPOrderId) public {
    Order memory IpOrder = IpOrders[IPOrderId];
    LPOrder _LpOrder = LpOrders[LPOrderId];

    Market memory _market = markets[IpOrder.marketId];

    // Enter the script
    _LpOrder.executeWeiroll(_market.weirollCommands, _market.weirollState);

    // Lock the wallet for the time if neccessary 
    if (_market._type != MarketType.Streaming) {
      _LpOrder.lockWallet(block.timestamp + IpOrder.duration);
    }

    OrderRewardsOwed[_market.primaryRewardToken][_LpOrder] = IpOrder.incentiveAmount;
  }

  function validateOrder(Order memory IpOrder, LPOrder lpOrder) view public {
    require(lpOrder.supportedMarkets(IpOrder.marketId), "Royco: Market Mismatch");
    require(lpOrder.duration() > IpOrder.duration, "Royco: Duration Mismatch");
    
  }

  function claimRewards(LPOrder order) public {
     
  }

}
