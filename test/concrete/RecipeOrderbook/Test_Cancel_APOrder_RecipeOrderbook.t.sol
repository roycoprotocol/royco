// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../../../src/RecipeOrderbook.sol";
import "../../../src/ERC4626i.sol";

import { MockERC20, ERC20 } from "../../mocks/MockERC20.sol";
import { RecipeOrderbookTestBase } from "../../utils/RecipeOrderbook/RecipeOrderbookTestBase.sol";

contract Test_Cancel_APOrder_RecipeOrderbook is RecipeOrderbookTestBase {
    address AP_ADDRESS;
    address IP_ADDRESS;

    function setUp() external {
        uint256 protocolFee = 0.01e18; // 1% protocol fee
        uint256 minimumFrontendFee = 0.001e18; // 0.1% minimum frontend fee
        setUpRecipeOrderbookTests(protocolFee, minimumFrontendFee);

        AP_ADDRESS = ALICE_ADDRESS;
        IP_ADDRESS = DAN_ADDRESS;
    }

    function test_cancelAPOrder_WithTokens() external {
        uint256 marketId = createMarket();

        uint256 quantity = 100000e18; // The amount of input tokens to be deposited

        // Create the AP order
        (uint256 orderId, RecipeOrderbook.APOrder memory order) = createAPOrder_ForTokens(marketId, address(0), quantity, AP_ADDRESS);

        uint256 initialQuantity = orderbook.orderHashToRemainingQuantity(orderbook.getOrderHash(order));
        assertEq(initialQuantity, quantity);

        vm.expectEmit(true, false, false, true, address(orderbook));
        emit RecipeOrderbook.APOrderCancelled(orderId);

        vm.startPrank(AP_ADDRESS);
        orderbook.cancelAPOrder(order);
        vm.stopPrank();

        uint256 resultingQuantity = orderbook.orderHashToRemainingQuantity(orderbook.getOrderHash(order));
        assertEq(resultingQuantity, 0);
    }

    function test_cancelAPOrder_WithPoints() external {
        uint256 marketId = createMarket();
        uint256 quantity = 100000e18; // The amount of input tokens to be deposited

        // Create the AP order
        (uint256 orderId, RecipeOrderbook.APOrder memory order,) = createAPOrder_ForPoints(marketId, address(0), quantity, AP_ADDRESS, IP_ADDRESS);

        uint256 initialQuantity = orderbook.orderHashToRemainingQuantity(orderbook.getOrderHash(order));
        assertEq(initialQuantity, quantity);

        vm.expectEmit(true, false, false, true, address(orderbook));
        emit RecipeOrderbook.APOrderCancelled(orderId);

        vm.startPrank(AP_ADDRESS);
        orderbook.cancelAPOrder(order);
        vm.stopPrank();

        uint256 resultingQuantity = orderbook.orderHashToRemainingQuantity(orderbook.getOrderHash(order));
        assertEq(resultingQuantity, 0);
    }

    function test_RevertIf_cancelAPOrder_NotOwner() external {
        uint256 marketId = createMarket();
        uint256 quantity = 100000e18;

        (, RecipeOrderbook.APOrder memory order) = createAPOrder_ForTokens(marketId, address(0), quantity, AP_ADDRESS);

        vm.startPrank(IP_ADDRESS);
        vm.expectRevert(RecipeOrderbook.NotOwner.selector);
        orderbook.cancelAPOrder(order);
        vm.stopPrank();
    }

    function test_RevertIf_cancelAPOrder_WithIndefiniteExpiry() external {
        uint256 marketId = createMarket();
        uint256 quantity = 100000e18;

        (, RecipeOrderbook.APOrder memory order) = createAPOrder_ForTokens(marketId, address(0), quantity, 0, AP_ADDRESS);

        // not needed but just to test that expiry doesn't apply if set to 0
        vm.warp(order.expiry + 1 seconds);

        vm.startPrank(AP_ADDRESS);
        vm.expectRevert(RecipeOrderbook.OrderCannotExpire.selector);
        orderbook.cancelAPOrder(order);
        vm.stopPrank();
    }

    function test_RevertIf_cancelAPOrder_NoRemainingQuantity() external {
        uint256 marketId = createMarket();
        uint256 quantity = 100000e18;

        (, RecipeOrderbook.APOrder memory order) = createAPOrder_ForTokens(marketId, address(0), quantity, AP_ADDRESS);

        mockLiquidityToken.mint(AP_ADDRESS, quantity);
        vm.startPrank(AP_ADDRESS);
        mockLiquidityToken.approve(address(orderbook), quantity);
        vm.stopPrank();

        // Mint incentive tokens to IP and fill
        mockIncentiveToken.mint(IP_ADDRESS, 100000e18);
        vm.startPrank(IP_ADDRESS);
        mockIncentiveToken.approve(address(orderbook), 100000e18);

        orderbook.fillAPOrder(order, quantity, DAN_ADDRESS);
        vm.stopPrank();

        // Should be completely filled and uncancellable
        uint256 resultingQuantity = orderbook.orderHashToRemainingQuantity(orderbook.getOrderHash(order));
        assertEq(resultingQuantity, 0);

        vm.startPrank(AP_ADDRESS);
        vm.expectRevert(RecipeOrderbook.NotEnoughRemainingQuantity.selector);
        orderbook.cancelAPOrder(order);
        vm.stopPrank();
    }
}
