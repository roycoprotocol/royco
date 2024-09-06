// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../../../src/RecipeOrderbook.sol";
import "../../../src/PointsFactory.sol";

import { RecipeOrderbookTestBase } from "../../utils/RecipeOrderbook/RecipeOrderbookTestBase.sol";

contract Test_OrderbookCreation_RecipeOrderbook is RecipeOrderbookTestBase {
    function setUp() external {
        uint256 protocolFee = 0.01e18; // 1% protocol fee
        uint256 minimumFrontendFee = 0.001e18; // 0.1% minimum frontend fee
        setUpRecipeOrderbookTests(protocolFee, minimumFrontendFee);
    }

    function test_CreateOrderbook() external view {
        // Check constructor args being set correctly
        assertEq(orderbook.WEIROLL_WALLET_IMPLEMENTATION(), address(weirollImplementation));
        assertEq(orderbook.POINTS_FACTORY(), address(pointsFactory));
        assertEq(orderbook.protocolFee(), initialProtocolFee);
        assertEq(orderbook.protocolFeeClaimant(), OWNER_ADDRESS);
        assertEq(orderbook.minimumFrontendFee(), initialMinimumFrontendFee);

        // Check initial orderbook state
        assertEq(orderbook.numLPOrders(), 0);
        assertEq(orderbook.numIPOrders(), 0);
        assertEq(orderbook.numMarkets(), 0);
    }
}
