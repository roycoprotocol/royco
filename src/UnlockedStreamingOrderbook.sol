// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import { ERC20 } from "lib/solmate/src/tokens/ERC20.sol";
import { SafeTransferLib } from "lib/solmate/src/utils/SafeTransferLib.sol";
import { ClonesWithImmutableArgs } from "lib/clones-with-immutable-args/src/ClonesWithImmutableArgs.sol";

import { LPOrder } from "src/LPOrder.sol";

contract UnlockedStreamingOrderbook {
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

    uint256 public maxLPOrderId;
    mapping(uint256 LPOrderId => LPOrder) public LpOrders;

    struct Market {
        ERC20 depositToken;
        Recipe enter;
        Recipe exit;
    }

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
    function createMarket(ERC20 _depositToken, Recipe calldata enterMarket, Recipe calldata exitMarket) public returns (uint256 marketId) {
        marketId = maxMarketId++;

        markets[marketId] = Market({ depositToken: _depositToken, enter: enterMarket, exit: exitMarket });
    }

    /*//////////////////////////////////////////////////////////////
                               ORDERS
    //////////////////////////////////////////////////////////////*/

    // ...
}
