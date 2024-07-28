// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

// MarketFactory and Market Contracts
import {MarketFactory} from "../src/MarketFactory.sol";
import {LumpSumMarket} from "../src/markets/LumpSumMarket.sol";
import {MarketType} from "../src/markets/interfaces/Market.sol";

// Order contract
import {Order} from "../src/Order.sol";
import {OrderFactory} from "../src/markets/interfaces/OrderFactory.sol";

// Testing contracts
import {DSTestPlus} from "../lib/solmate/src/test/utils/DSTestPlus.sol";

/// @title MarketFactoryTest
/// @author Royco
/// @notice Tests for the MarketFactory contract
contract OrderTest is DSTestPlus {
    // // Implementation addresses
    // address public marketImplementation;
    // MarketFactory public marketFactory;

    // Order Implementation Contract
    Order public order;

    // OrderFactory Example Contract
    OrderFactoryExample public orderFactoryExample;

    function setUp() public {
        // Deploy order implementation
        order = new Order();

        // Deploy OrderFactoryExample
        orderFactoryExample = new OrderFactoryExample(address(order));
    }

    function testOrderGetFunctions() public {
        // Deploy the clone.
        Order clone = Order(
            orderFactoryExample.deployOrder(address(this), address(0xEE), uint256(Order.Side.ActionOrder))
        );

        // Check if the owner is correct
        assertEq(clone.owner(), address(this));

        // Check if the market is correct
        assertEq(clone.market(), address(0xEE));

        // Check if the side is correct
        assertEq(uint256(clone.side()), uint256(Order.Side.ActionOrder));
    }
}

/// @notice Order Factory Example
contract OrderFactoryExample is OrderFactory {
    constructor(address _orderImplementation) {
        orderImplementation = _orderImplementation;
    }

    function deployOrder(address owner, address market, uint256 side) external returns (address clone) {
        clone = deployClone(owner, market, side);
    }
}
