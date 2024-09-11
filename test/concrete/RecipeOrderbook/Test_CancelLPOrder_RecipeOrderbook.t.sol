// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../../../src/RecipeOrderbook.sol";
import "../../../src/ERC4626i.sol";

import { MockERC20, ERC20 } from "../../mocks/MockERC20.sol";
import { RecipeOrderbookTestBase } from "../../utils/RecipeOrderbook/RecipeOrderbookTestBase.sol";

contract Test_CancelLPOrder_RecipeOrderbook is RecipeOrderbookTestBase {
    address LP_ADDRESS;
    address IP_ADDRESS;

    function setUp() external {
        uint256 protocolFee = 0.01e18; // 1% protocol fee
        uint256 minimumFrontendFee = 0.001e18; // 0.1% minimum frontend fee
        setUpRecipeOrderbookTests(protocolFee, minimumFrontendFee);

        LP_ADDRESS = ALICE_ADDRESS;
        IP_ADDRESS = DAN_ADDRESS;
    }

    function test_cancelLPOrder_WithTokens() external {
        uint256 marketId = createMarket();

        uint256 quantity = 100000e18; // The amount of input tokens to be deposited

        // Create the LP order
        (uint256 orderId, RecipeOrderbook.LPOrder memory order) = createLPOrder_ForTokens(marketId, address(0), quantity, LP_ADDRESS);

        uint256 initialQuantity = orderbook.orderHashToRemainingQuantity(orderbook.getOrderHash(order));
        assertEq(initialQuantity, quantity);

        vm.expectEmit(true, false, false, true, address(orderbook));
        emit RecipeOrderbook.LPOrderCancelled(orderId);

        vm.startPrank(LP_ADDRESS);
        orderbook.cancelLPOrder(order);
        vm.stopPrank();

        uint256 resultingQuantity = orderbook.orderHashToRemainingQuantity(orderbook.getOrderHash(order));
        assertEq(resultingQuantity, 0);
    }

    function test_cancelLPOrder_WithPoints() external {
        uint256 marketId = createMarket();
        uint256 quantity = 100000e18; // The amount of input tokens to be deposited

        // Create the LP order
        (uint256 orderId, RecipeOrderbook.LPOrder memory order,) = createLPOrder_ForPoints(marketId, address(0), quantity, LP_ADDRESS, IP_ADDRESS);

        uint256 initialQuantity = orderbook.orderHashToRemainingQuantity(orderbook.getOrderHash(order));
        assertEq(initialQuantity, quantity);

        vm.expectEmit(true, false, false, true, address(orderbook));
        emit RecipeOrderbook.LPOrderCancelled(orderId);

        vm.startPrank(LP_ADDRESS);
        orderbook.cancelLPOrder(order);
        vm.stopPrank();

        uint256 resultingQuantity = orderbook.orderHashToRemainingQuantity(orderbook.getOrderHash(order));
        assertEq(resultingQuantity, 0);
    }

    function test_RevertIf_cancelLPOrder_NotOwner() external {
        uint256 marketId = createMarket();
        uint256 quantity = 100000e18;

        (, RecipeOrderbook.LPOrder memory order) = createLPOrder_ForTokens(marketId, address(0), quantity, LP_ADDRESS);

        vm.startPrank(IP_ADDRESS);
        vm.expectRevert(RecipeOrderbook.NotOwner.selector);
        orderbook.cancelLPOrder(order);
        vm.stopPrank();
    }

    function test_RevertIf_cancelLPOrder_OrderExpired() external {
        uint256 marketId = createMarket();
        uint256 quantity = 100000e18;

        (, RecipeOrderbook.LPOrder memory order) = createLPOrder_ForTokens(marketId, address(0), quantity, LP_ADDRESS);

        vm.warp(order.expiry + 1 seconds);

        vm.startPrank(LP_ADDRESS);
        vm.expectRevert(RecipeOrderbook.OrderExpired.selector);
        orderbook.cancelLPOrder(order);
        vm.stopPrank();
    }

    function test_RevertIf_cancelLPOrder_NoRemainingQuantity() external {
        uint256 marketId = createMarket();
        uint256 quantity = 100000e18;

        (, RecipeOrderbook.LPOrder memory order) = createLPOrder_ForTokens(marketId, address(0), quantity, LP_ADDRESS);

        mockLiquidityToken.mint(LP_ADDRESS, quantity);
        vm.startPrank(LP_ADDRESS);
        mockLiquidityToken.approve(address(orderbook), quantity);
        vm.stopPrank();

        // Mint incentive tokens to IP and fill
        mockIncentiveToken.mint(IP_ADDRESS, 100000e18);
        vm.startPrank(IP_ADDRESS);
        mockIncentiveToken.approve(address(orderbook), 100000e18);

        orderbook.fillLPOrder(order, quantity, DAN_ADDRESS);
        vm.stopPrank();

        // Should be completely filled and uncancellable
        uint256 resultingQuantity = orderbook.orderHashToRemainingQuantity(orderbook.getOrderHash(order));
        assertEq(resultingQuantity, 0);

        vm.startPrank(LP_ADDRESS);
        vm.expectRevert(RecipeOrderbook.NotEnoughRemainingQuantity.selector);
        orderbook.cancelLPOrder(order);
        vm.stopPrank();
    }
}
