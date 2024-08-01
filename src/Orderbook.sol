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

/// @title Royco Orderbook
/// @author corddry, CopyPaste
/// @dev Royco Orderbook is a simple Orderbook contract to allow Liquidity Providers (LPs) and
///   Incentive Providers (IPs) to negotiate
contract Orderbook {
    using ClonesWithImmutableArgs for address;
    using SafeTransferLib for ERC20;

    /// @dev A deployment of LP Order to clone from for new orders
    address public immutable ORDER_IMPLEMENTATION;

    /// @param orderbook_impl An deployment of the LPOrder contract
    constructor(address orderbook_impl) {
        ORDER_IMPLEMENTATION = orderbook_impl;
        nextMarketId++;
    }

    /*//////////////////////////////////////////////////////////////
                             INTERFACE
    //////////////////////////////////////////////////////////////*/
    event MarketCreated(uint256 marketId, MarketType _type, address _depositToken, address _primaryRewardToken);

    event LPOrderSubmitted(address order, address creator, uint256[] markets);
    event IPOrderSubmitted(uint256 duration, uint256 amount, uint256 incentivesPerToken, uint256 marketId);

    event VestingScheduleCreated(uint256 indexed ticketId, address indexed beneficiary, uint256 totalAmount, uint256 startTime, uint256 duration);
    event TokensReleased(uint256 indexed ticketId, address indexed beneficiary, uint256 amount);

    /*//////////////////////////////////////////////////////////////
                              STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @custom:field sender The IP putting up the rewards
    /// @custom:field duration How long the LP should lock up their position for to recieve rewards
    /// @custom:field amount The amount of liquidity the IP is looking to recieve
    /// @custom:field incentiveAmountPerToken The amount of incentives the IP is offering per token (1e18) of liquidity
    /// @custom:field marketId The market the IP is offering the incentives for
    struct IPOrder {
        address sender;
        uint96 duration;
        uint128 amount;
        uint128 incentiveAmountPerToken;
        uint128 marketId;
    }

    /// @dev Counter to track IPOrderIds so they can increment
    uint256 public nextIPOrderId;
    /// @dev Mapping to match an IPOrderId to a its assosiated order information
    mapping(uint256 IPOrderId => IPOrder) public IpOrders;

    /// @dev Counter to track LPOrderIds so they can increment
    uint256 public nextLPOrderId;
    /// @dev Mapping to match an LPOrderId to a its assosiated order information
    mapping(uint256 LPOrderId => LPOrder) public LpOrders;

    enum MarketType {
        FL_Vesting, // Front-loaded Vesting
        BL_Vesting, // Back-loaded Vesting
        Streaming,
        Forfeitable_Vested
    }

    /// @custom:field depositToken The token to be deposited into the market as liquidity
    /// @custom:field primaryRewardToken The main token being given out as incentives
    /// @custom:field _type The type of the market's rewards
    /// @custom:field enter The weiroll commands needed to enter into the opportunity
    /// @custom:field exit The weiroll commands needed to exit from the opportunity
    struct Market {
        ERC20 depositToken;
        ERC20 primaryRewardToken;
        MarketType _type;
        Recipe enter;
        Recipe exit;
    }

    /// @dev Aloha!
    /// @custom:field weirollCommands The commands to execute from the weiroll wallet
    /// @custom:field weirollState The state to pass along with the weiroll commands
    struct Recipe {
        bytes32[] weirollCommands;
        bytes[] weirollState;
    }

    /// @dev The max market Id, incremented with each new market
    uint256 public nextMarketId;
    /// @dev Mapping to track a marketId to its assosiated info
    mapping(uint256 marketId => Market _market) public markets;

    /// @dev Mapping to track vested and locked rewards to a given order
    mapping(ERC20 rewardToken => mapping(LPOrder order => uint256 rewardsOwed)) public OrderRewardsOwed;

    /*//////////////////////////////////////////////////////////////
                           MARKET ACTIONS
    //////////////////////////////////////////////////////////////*/
    /// @param _depositToken The Liquidity token to deposit into the market
    /// @param _primaryRewardToken The token being offered as the main reward for the market
    /// @param marketType The reward type for the market's rewards
    /// @param enterMarket The needed weiroll commands to enter the market
    /// @param exitMarket The needed weiroll commands to exit the market
    function createMarket(
        ERC20 _depositToken,
        ERC20 _primaryRewardToken,
        MarketType marketType,
        Recipe calldata enterMarket,
        Recipe calldata exitMarket
    )
        external
        returns (uint256 marketId)
    {
        marketId = nextMarketId++;

        markets[marketId] =
            Market({ depositToken: _depositToken, primaryRewardToken: _primaryRewardToken, _type: marketType, enter: enterMarket, exit: exitMarket });

        emit MarketCreated(marketId, marketType, address(_depositToken), address(_primaryRewardToken));
    }

    /*//////////////////////////////////////////////////////////////
                                VESTING
    //////////////////////////////////////////////////////////////*/

    /// @custom:field rewardToken The token being offered as a reward at the end of vesting
    /// @custom:field beneficiary The address to recieve the tokens at vesting
    /// @custom:field startTime The time the vesting term begins
    /// @custom:field duration How long the vesting should continue for
    /// @custom:field totalAmount The totalAmount of tokens rewarded in the vesting period
    /// @custom:field releasedAmount How many reward tokens we've already paid out
    struct VestingSchedule {
        ERC20 rewardToken;
        address beneficiary;
        uint64 startTime;
        uint64 duration;
        uint128 totalAmount;
        uint128 releasedAmount;
    }

    /// @dev Variable to track each vesting schedule Id, using a "ticket" system to track each vesting reward schedule
    uint256 private nextTicketId = 1;
    /// @dev Mapping to track each vesting ticket to its assosiated schedule
    mapping(uint256 ticket => VestingSchedule) public vestingSchedules;

    /// @param _beneficiary The address to recieve the vested tokens
    /// @param _totalAmount The total amount of reward tokens to vest
    /// @param _duration The duration of which to vest the tokens over
    /// @param _rewardToken The token to reward the beneficiary with
    ///
    /// @return newTicketId The ticketId to track the new vesting schedule created
    function createVestingTicket(address _beneficiary, uint256 _totalAmount, uint256 _duration, ERC20 _rewardToken) internal returns (uint256 newTicketId) {
        require(_beneficiary != address(0), "Invalid beneficiary address");
        require(_totalAmount > 0 && _totalAmount <= type(uint128).max, "Invalid total amount");
        require(_duration > 0 && _duration <= type(uint64).max, "Invalid duration");

        newTicketId = nextTicketId++;

        vestingSchedules[newTicketId] = VestingSchedule({
            rewardToken: _rewardToken,
            beneficiary: _beneficiary,
            startTime: uint64(block.timestamp),
            duration: uint64(_duration),
            totalAmount: uint128(_totalAmount),
            releasedAmount: 0
        });

        emit VestingScheduleCreated(newTicketId, _beneficiary, _totalAmount, block.timestamp, _duration);
    }

    /// @param _ticketId The ticketId of the vesting schedule to claim the rewards for
    function releaseVestedTokens(uint256 _ticketId) external {
        VestingSchedule storage schedule = vestingSchedules[_ticketId];
        require(schedule.beneficiary == msg.sender, "Only the beneficiary can release tokens");

        uint256 startTime = schedule.startTime;
        uint256 duration = schedule.duration;
        uint256 totalAmount = schedule.totalAmount;
        uint256 releasedAmount = schedule.releasedAmount;

        uint256 vestedAmount;
        if (block.timestamp < startTime) {
            vestedAmount = 0;
        } else if (block.timestamp >= startTime + duration) {
            vestedAmount = totalAmount;
        } else {
            vestedAmount = (totalAmount * (block.timestamp - startTime)) / duration;
        }

        uint256 releaseableAmount = vestedAmount - releasedAmount;
        schedule.releasedAmount = uint128(releasedAmount + releaseableAmount);

        schedule.rewardToken.safeTransfer(schedule.beneficiary, releaseableAmount);

        emit TokensReleased(_ticketId, schedule.beneficiary, releaseableAmount);
    }

    /// @param token The Token to Claim Rewards In
    /// @param order The (fufilled) Order to claim rewards for
    function claimRewards(ERC20 token, LPOrder order) external {
        uint256 owed = OrderRewardsOwed[token][order];
        if (order.lockedUntil() > block.timestamp) {
            return;
        }

        token.safeTransfer(order.owner(), owed);
    }

    /*//////////////////////////////////////////////////////////////
                               ORDERS
    //////////////////////////////////////////////////////////////*/

    /// @param depositToken The token to deposit as liquidity
    /// @param tokenAmount The amount of tokens to provide as liquidity
    /// @param maxDuration The maximum duration the LP is willing to be locked for
    /// @param desiredIncentives The amount of incentives per token the LP would love to recieve
    /// @param allowedMarkets The marketIds of markets that the LP is willing to be deposited into
    ///
    /// @return clone The address of the LPOrder contract
    /// @return orderId The Id assosiated with this new LPOrder contract
    function createLPOrder(
        ERC20 depositToken,
        uint256 tokenAmount,
        uint96 maxDuration,
        uint256[] calldata desiredIncentives,
        uint256[] calldata allowedMarkets
    )
        public
        returns (LPOrder clone, uint256 orderId)
    {
        clone = LPOrder(ORDER_IMPLEMENTATION.clone(abi.encodePacked(msg.sender, address(this), address(depositToken), tokenAmount, uint256(maxDuration))));

        orderId = nextLPOrderId++;

        depositToken.safeTransferFrom(msg.sender, address(clone), tokenAmount);
        clone.initialize(allowedMarkets, desiredIncentives);

        LpOrders[orderId] = clone;

        emit LPOrderSubmitted(address(clone), msg.sender, allowedMarkets);
    }

    /// @param _duration The duration the LP should lockup for to recieve incentives
    /// @param _amount The amount of tokens the LP should lockup
    /// @param _incentiveAmountPerToken The amount of incentives per token the LP should recieve
    /// @param _marketId The marketId the order should be valid for
    ///
    /// @return IPOrderId The orderId of the new IPOrder
    function createIPOrder(uint96 _duration, uint128 _amount, uint128 _incentiveAmountPerToken, uint128 _marketId) public returns (uint256 IPOrderId) {
        Market memory _market = markets[_marketId];
        _market.primaryRewardToken.safeTransferFrom(msg.sender, address(this), uint256(_amount) * uint256(_incentiveAmountPerToken) / 1e18);

        IPOrder memory order =
            IPOrder({ sender: msg.sender, duration: _duration, amount: _amount, incentiveAmountPerToken: _incentiveAmountPerToken, marketId: _marketId });

        IPOrderId = nextIPOrderId++;
        IpOrders[IPOrderId] = order;
    
        emit IPOrderSubmitted(uint256(_duration), uint256(_amount), uint256(_incentiveAmountPerToken), uint256(_marketId));
    }

    /// @param depositToken The token to deposit as liquidity
    /// @param tokenAmount The amount of tokens to provide as liquidity
    /// @param maxDuration The maximum duration the LP is willing to be locked for
    /// @param desiredIncentives The amount of incentives per token the LP would love to recieve
    /// @param allowedMarkets The marketIds of markets that the LP is willing to be deposited into
    /// @param IPOrderId The IPOrderId To match and fill with
    function createLPOrderAndFill(
        ERC20 depositToken,
        uint256 tokenAmount,
        uint96 maxDuration,
        uint256[] calldata desiredIncentives,
        uint256[] calldata allowedMarkets,
        uint256 IPOrderId
    )
        external
    {
        (, uint256 LPOrderId) = createLPOrder(depositToken, tokenAmount, maxDuration, desiredIncentives, allowedMarkets);
        matchOrders(IPOrderId, LPOrderId);
    }

    /// @param _duration The duration the LP should lockup for to recieve incentives
    /// @param _amount The amount of tokens the LP should lockup
    /// @param _incentiveAmountPerToken The amount of incentives per token the LP should recieve
    /// @param _marketId The marketId the order should be valid for
    /// @param LPOrderId The LP Order to match and fill with
    function createIPOrderAndFill(uint96 _duration, uint128 _amount, uint128 _incentiveAmountPerToken, uint128 _marketId, uint256 LPOrderId) external {
        uint256 IPOrderId = createIPOrder(_duration, _amount, _incentiveAmountPerToken, _marketId);
        matchOrders(IPOrderId, LPOrderId);
    }

    /// @param IPOrderId The Incentive Provider Order Id to cancel
    function cancelIPOrder(uint256 IPOrderId) external {
      IPOrder memory order = IpOrders[IPOrderId];
      require(msg.sender == order.sender, "Royco: Not Owner");

      Market storage _market = markets[order.marketId];
      _market.primaryRewardToken.safeTransfer(msg.sender, order.amount * order.incentiveAmountPerToken / 1e18);
     
      delete IpOrders[IPOrderId];
    }

    function cancelUnfufilledLPOrder(LPOrder order) external {
        require(msg.sender == order.owner(), "Royco: Not Owner");
        require(order.marketId() == 0, "Royco: Order Fufilled");

        order.cancel();
    }

    /// @param order Address of the order to cancel
    function cancelLPOrder(LPOrder order) external {
        require(msg.sender == order.owner(), "Royco: Not Owner");

        uint256 marketId = order.marketId();
        Market memory _market = markets[marketId];

        // 0 Out of incentives
        delete OrderRewardsOwed[_market.primaryRewardToken][order];
        // Exit the position
        order.executeWeiroll(_market.exit.weirollCommands, _market.exit.weirollState);
        order.cancel();
    }

    /// @param IPOrderId The Id of the Incentive Provider Order to fill
    /// @param LPOrderId The Id of the Liquidity Provider Order to fill
    function matchOrders(uint256 IPOrderId, uint256 LPOrderId) public {
        IPOrder storage IpOrder = IpOrders[IPOrderId];
        LPOrder _LpOrder = LpOrders[LPOrderId];

        uint256 lpOrderAmount = _LpOrder.amount();

        if (IpOrder.amount > lpOrderAmount) {
            IpOrder.amount -= uint128(lpOrderAmount);
        } else if (IpOrder.amount != lpOrderAmount) {
            uint256 delta = lpOrderAmount - IpOrder.amount;

            LPOrder clone = LPOrder(
                ORDER_IMPLEMENTATION.clone(
                    abi.encodePacked(_LpOrder.owner(), address(this), _LpOrder.depositToken(), delta, _LpOrder.maxDuration(), _LpOrder.desiredIncentives())
                )
            );

            uint256 orderId = nextLPOrderId++;
            uint256[] memory allowedMarkets = _LpOrder.allowedMarkets();
            uint256[] memory desiredIncentives = _LpOrder.desiredIncentives();
            clone.initialize(allowedMarkets, desiredIncentives);
            _LpOrder.fundSweepToNewOrder(address(clone), delta);

            LpOrders[orderId] = clone;

            emit LPOrderSubmitted(address(clone), msg.sender, allowedMarkets);
        }

        require(_LpOrder.supportedMarkets(IpOrder.marketId), "Royco: Market Mismatch");
        require(_LpOrder.maxDuration() >= IpOrder.duration, "Royco: Duration Mismatch");
        require(_LpOrder.expectedIncentives(IpOrder.marketId) >= IpOrder.incentiveAmountPerToken, "Royco: Not Enough Incentives");

        Market memory _market = markets[IpOrder.marketId];

        // Enter the script
        _LpOrder.executeWeiroll(_market.enter.weirollCommands, _market.enter.weirollState);

        // Lock the wallet for the time if neccessary
        if (_market._type != MarketType.Streaming) {
            _LpOrder.lockWallet(block.timestamp + IpOrder.duration);
            if (_market._type == MarketType.BL_Vesting) {
                OrderRewardsOwed[_market.primaryRewardToken][_LpOrder] = IpOrder.incentiveAmountPerToken * lpOrderAmount / 1e18;
            } else {
                _market.primaryRewardToken.safeTransfer(_LpOrder.owner(), IpOrder.incentiveAmountPerToken * lpOrderAmount / 1e18);
            }
        } else {
            createVestingTicket(_LpOrder.owner(), IpOrder.incentiveAmountPerToken * lpOrderAmount / 1e18, IpOrder.duration, _market.primaryRewardToken);
        }
    }
}
