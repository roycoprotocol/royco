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
        uint128 incentiveAmountPerToken;
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
        Recipe enter;
        Recipe exit;
    }

    /// @dev Its for both enter/exit so the named fit
    struct Recipe {
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
        Recipe calldata enterMarket,
        Recipe calldata exitMarket
    )
        public
        returns (uint256 marketId)
    {
        marketId = maxMarketId++;

        markets[marketId] =
            Market({ depositToken: _depositToken, primaryRewardToken: _primaryRewardToken, _type: marketType, enter: enterMarket, exit: exitMarket });
    }

    /*//////////////////////////////////////////////////////////////
                               ORDERS
    //////////////////////////////////////////////////////////////*/
    function createLPOrder(
        ERC20 depositToken,
        uint256 tokenAmount,
        uint96 maxDuration,
        uint256 desiredIncentives,
        uint256[] calldata allowedMarkets
    )
        public
        returns (LPOrder clone, uint256 orderId)
    {
        clone = LPOrder(ORDER_IMPLEMENTATION.clone(abi.encode(msg.sender, address(depositToken), tokenAmount, address(this), maxDuration, desiredIncentives)));

        orderId = maxLPOrderId++;

        depositToken.safeTransferFrom(msg.sender, address(clone), tokenAmount);
        clone.initialize(allowedMarkets);

        LpOrders[orderId] = clone;

        emit OrderSubmitted(address(clone), msg.sender, allowedMarkets);
    }

    function createIPOrder(uint96 _duration, uint128 _amount, uint128 _incentiveAmountPerToken, uint128 _marketId) public returns (uint256 IPOrderId) {
        Market memory _market = markets[_marketId];
        _market.primaryRewardToken.safeTransferFrom(msg.sender, address(this), uint256(_amount) * uint256(_incentiveAmountPerToken) / 1e18);

        IPOrder memory order = IPOrder({ sender: msg.sender, duration: _duration, amount: _amount, incentiveAmountPerToken: _incentiveAmountPerToken, marketId: _marketId });

        IPOrderId = maxIPOrderId++;
        IpOrders[IPOrderId] = order;
    }

    function createLPOrderAndFill(
        ERC20 depositToken,
        uint256 tokenAmount,
        uint96 maxDuration,
        uint256 desiredIncentives,
        uint256[] calldata allowedMarkets,
        uint256 IPOrderId
    ) external {
      (LPOrder clone, uint256 LPOrderId) = createLPOrder(depositToken, tokenAmount, maxDuration, desiredIncentives, allowedMarkets);
      matchOrders(IPOrderId, LPOrderId);
    }

    function createIPOrderAndFill(
      uint96 _duration,
      uint128 _amount, 
      uint128 _incentiveAmountPerToken, 
      uint128 _marketId,
      uint256 LPOrderId,
    ) external {
      uint256 IPOrderId = createIPOrder(_duration, _amount, _incentiveAmountPerToken, _marketId, LPOrderId);
      matchOrders(IPOrderId, LPOrderId);
    }

    function cancelLPOrder(LPOrder order) external {
        require(msg.sender == order.owner(), "Royco: Not Owner");

        uint256 marketId = order.marketId();
        Market memory _market = markets[marketId];

        // 0 Out of incentives
        OrderRewardsOwed[_market.primaryRewardToken][order] = 0;
        // Exit the position
        order.executeWeiroll(_market.exit.weirollCommands, _market.exit.weirollState);
        order.cancel();
    }

    function matchOrders(uint256 IPOrderId, uint256 LPOrderId) public {
        IPOrder storage IpOrder = IpOrders[IPOrderId];
        LPOrder _LpOrder = LpOrders[LPOrderId];

        uint256 lpOrderAmount = _LpOrder.amount();

        if (IpOrder.amount > lpOrderAmount) {
            IpOrder.amount = uint128(lpOrderAmount);
            IpOrder.amount -= uint128(lpOrderAmount);
        } else {
            uint256 delta = lpOrderAmount - IpOrder.amount;

            LPOrder clone = LPOrder(
                ORDER_IMPLEMENTATION.clone(
                    abi.encode(_LpOrder.owner(), _LpOrder.depositToken(), delta, address(this), _LpOrder.maxDuration(), _LpOrder.desiredIncentives())
                )
            );

            uint256 orderId = maxLPOrderId++;
            uint256[] memory allowedMarkets = _LpOrder.allowedMarkets();
            clone.initialize(allowedMarkets);
            _LpOrder.fundSweepToNewOrder(address(clone), delta);

            LpOrders[orderId] = clone;

            emit OrderSubmitted(address(clone), msg.sender, allowedMarkets);
        }

        validateOrder(IpOrder, _LpOrder);

        Market memory _market = markets[IpOrder.marketId];

        // Enter the script
        _LpOrder.executeWeiroll(_market.enter.weirollCommands, _market.enter.weirollState);

        // Lock the wallet for the time if neccessary
        if (_market._type != MarketType.Streaming) {
            _LpOrder.lockWallet(block.timestamp + IpOrder.duration);
        }

        OrderRewardsOwed[_market.primaryRewardToken][_LpOrder] = IpOrder.incentiveAmountPerToken * lpOrderAmount;
    }

    function validateOrder(IPOrder memory IpOrder, LPOrder lpOrder) public view {
        require(lpOrder.supportedMarkets(IpOrder.marketId), "Royco: Market Mismatch");
        require(lpOrder.maxDuration() >= IpOrder.duration, "Royco: Duration Mismatch");
        require(lpOrder.desiredIncentives() >= IpOrder.incentiveAmountPerToken, "Royco: Not Enough Incentives");
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
