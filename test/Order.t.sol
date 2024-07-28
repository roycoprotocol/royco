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
import {ERC20} from "../lib/solmate/src/tokens/ERC20.sol";

/// @title MarketFactoryTest
/// @author Royco
/// @notice Tests for the MarketFactory contract
contract OrderTest is DSTestPlus {
    /*//////////////////////////////////////////////////////////////
                                 SETUP
    //////////////////////////////////////////////////////////////*/

    // // Implementation addresses
    // address public marketImplementation;
    // MarketFactory public marketFactory;

    // Order Implementation Contract
    Order public order;

    // OrderFactory Example Contract
    OrderFactoryExample public orderFactoryExample;

    // Order Clone Contract
    Order public clone;

    // Setup the contracts.
    function setUp() public {
        // Deploy order implementation
        order = new Order();

        // Deploy OrderFactoryExample
        orderFactoryExample = new OrderFactoryExample(address(order));
    }

    function deployClone(address owner, address market, Order.Side side) public {
        // Deploy the clone.
        clone = Order(orderFactoryExample.deployOrder(owner, market, uint256(side)));
    }

    /*//////////////////////////////////////////////////////////////
                           INITIALIZATION TESTS
    //////////////////////////////////////////////////////////////*/

    // Test the order initialize function.
    function testOrderInitialization() public {
        // Deploy a clone.
        deployClone(address(this), address(this), Order.Side.ActionOrder);

        // Set token amounts.
        uint256[] memory tokenAmounts = new uint256[](2);
        tokenAmounts[0] = uint256(1);
        tokenAmounts[1] = uint256(2);

        // Set weiroll state.
        bytes[] memory weirollState = new bytes[](2);
        weirollState[0] = bytes("1");
        weirollState[1] = bytes("2");

        // Initialize the order.
        clone.initialize(tokenAmounts, weirollState);

        // Check if the token amounts are correct
        assertEq(clone.amounts(0), uint256(1));
        assertEq(clone.amounts(1), uint256(2));

        // Check if the weiroll state is correct
        assertEq(keccak256(clone.weirollState(0)), keccak256(bytes("1")));
        assertEq(keccak256(clone.weirollState(1)), keccak256(bytes("2")));
    }

    // Test the order initialization permissions.
    function testFailIncorrectMarket() public {
        // Deploy a clone with a random market address.
        deployClone(address(this), address(0), Order.Side.ActionOrder);

        // Attempt to initialize the order from an address different from Order.market()
        clone.initialize(new uint256[](0), new bytes[](0));
    }

    /*//////////////////////////////////////////////////////////////
                          STATE MANAGEMENT TESTS
    //////////////////////////////////////////////////////////////*/

    // Test the order get functions.
    function testVariableAssignment() public {
        // Deploy a clone.
        deployClone(address(this), address(0xEE), Order.Side.ActionOrder);

        // Check if the owner is correct
        assertEq(clone.owner(), address(this));

        // Check if the market is correct
        assertEq(clone.market(), address(0xEE));

        // Check if the side is correct
        assertEq(uint256(clone.side()), uint256(Order.Side.ActionOrder));
    }

    function testLockingMechanism() public {}
    function testFailLockingOnlyMarket() public {
        // Deploy a clone.
        deployClone(address(this), address(0xEE), Order.Side.ActionOrder);

        // Attempt to lock the order from an address different from Order.market()
        clone.lockWallet(block.timestamp + 5);
    }

    function testCancellationLogic() public {}
    function testFailCancellationOnlyMarket() public {
        // Deploy a clone.
        deployClone(msg.sender, address(0xEE), Order.Side.ActionOrder);

        // Attempt to cancel the order from an address different from Order.market()
        ERC20[] memory tokens = new ERC20[](0);
        clone.cancel(tokens);
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
