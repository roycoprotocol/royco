// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

struct Market {
    bytes32[] weirollCommands;
    bytes[] weirollState;
}
// ...

enum OrderType {
    NOT_FOUND, // default value for uninitialized enum
    BID,
    ASK
}

struct Order {
    OrderType orderType;
    address maker;
    uint32 expiration; // uint32 sufficent until Feb 2106, upgrade to uint64 if there's space in the packing
    uint256 price;
    uint256 quantity;
}
// uint256 fillAmount; // partial fills must be possible, can decide if "fillamounts" should be handled in a separate mapping vs in the order struct vs separate
// variable
// ...

contract Orderbook {
// mapping(id => Order[]) public orders; // some storage for the orders, (would be red/black tree for onchain order matching)
// function createMarket(bytes32[] weirollCommands, bytes[] weirollState) public {}
// function createBid(market, price, expiration) public {}
// function createAsk(market, price, expiration) public {}
// function cancelOrder(market, order) public onlyMaker {}
/* function fillOrder(market, order, quantity) public {
        
    } */
}
