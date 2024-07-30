// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

// Interfaces
import { ERC20 } from "lib/solmate/src/tokens/ERC20.sol";

// Libraries
import { ECDSA } from "lib/solady/src/utils/ECDSA.sol";
import { SafeTransferLib } from "lib/solmate/src/utils/SafeTransferLib.sol";
import { FixedPointMathLib } from "lib/solady/src/utils/FixedPointMathLib.sol";
import { ClonesWithImmutableArgs } from "lib/clones-with-immutable-args/src/ClonesWithImmutableArgs.sol";

// Contracts
import { LPOrder } from "src/LPOrder.sol";

contract Orderbook {
    using ClonesWithImmutableArgs for address;
    using SafeTransferLib for ERC20;

    address public immutable ORDER_IMPLEMENTATION;

    constructor(address orderbook_impl) {
        ORDER_IMPLEMENTATION = orderbook_impl;
    }

    /*//////////////////////////////////////////////////////////////
                             INTERFACE
    //////////////////////////////////////////////////////////////*/
    event OrderSubmitted(address order, address creator, uint256[] markets);

    /*//////////////////////////////////////////////////////////////
                              STORAGE
    //////////////////////////////////////////////////////////////*/
    struct IPOrder {
        address sender;
        uint96 duration;
        uint128 amount;
        uint128 incentiveAmount;
        uint128 marketId;
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
        bytes32[] weirollCommands;
        bytes[] weirollState;
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
        Aloha calldata enterMarket,
        Aloha calldata exitMarket
    )
        public
        returns (uint256 marketId)
    {
        marketId = maxMarketId++;

        markets[marketId] =
            Market({ depositToken: _depositToken, primaryRewardToken: _primaryRewardToken, _type: marketType, enter: enterMarket, exit: enterMarket });
    }

    /*//////////////////////////////////////////////////////////////
                               ORDERS
    //////////////////////////////////////////////////////////////*/
    function createLPOrder(
        ERC20 depositToken,
        uint256 tokenAmount,
        uint96 maxDuration,
        uint256[] calldata allowedMarkets
    )
        external
        returns (LPOrder clone, uint256 orderId)
    {
        clone = LPOrder(ORDER_IMPLEMENTATION.clone(abi.encode(msg.sender, address(depositToken), tokenAmount, address(this), maxDuration)));

        orderId = maxLPOrderId++;
        clone.initialize(allowedMarkets);

        LpOrders[orderId] = clone;

        emit OrderSubmitted(address(clone), msg.sender, allowedMarkets);
    }

    function createIPOrder(uint96 _duration, uint128 _amount, uint128 _incentiveAmount, uint128 _marketId) external returns (uint256 IPOrderId) {
        Market memory _market = markets[_marketId];
        _market.primaryRewardToken.safeTransferFrom(msg.sender, address(this), _incentiveAmount);

        IPOrder memory order = IPOrder({ sender: msg.sender, duration: _duration, amount: _amount, incentiveAmount: _incentiveAmount, marketId: _marketId });

        IPOrderId = maxIPOrderId++;
        IpOrders[IPOrderId] = order;
    }

    function matchOrders(uint256 IPOrderId, uint256 LPOrderId) public {
        IPOrder memory IpOrder = IpOrders[IPOrderId];
        LPOrder _LpOrder = LpOrders[LPOrderId];

        Market memory _market = markets[IpOrder.marketId];

        // Enter the script
        _LpOrder.executeWeiroll(_market.enter.weirollCommands, _market.enter.weirollState);

        // Lock the wallet for the time if neccessary
        if (_market._type != MarketType.Streaming) {
            _LpOrder.lockWallet(block.timestamp + IpOrder.duration);
        }

        OrderRewardsOwed[_market.primaryRewardToken][_LpOrder] = IpOrder.incentiveAmount;
    }

    function validateOrder(IPOrder memory IpOrder, LPOrder lpOrder) public view {
        require(lpOrder.supportedMarkets(IpOrder.marketId), "Royco: Market Mismatch");
        require(lpOrder.maxDuration() > IpOrder.duration, "Royco: Duration Mismatch");
    }

    /// @param token The Token to Claim Rewards In
    /// @param order The (fufilled) Order to claim rewards for
    function claimRewards(ERC20 token, LPOrder order) public {
        uint256 owed = OrderRewardsOwed[token][order];
        if (order.lockedUntil() > block.timestamp) {
            return;
        }

        token.safeTransfer(order.owner(), owed);
    }
}
