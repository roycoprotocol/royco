// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../../../src/RecipeMarketHub.sol";
import "../../../src/PointsFactory.sol";

import { RecipeMarketHubTestBase } from "../../utils/RecipeMarketHub/RecipeMarketHubTestBase.sol";

contract Test_RecipeMarketHubCreation_RecipeMarketHub is RecipeMarketHubTestBase {
    function setUp() external {
        uint256 protocolFee = 0.01e18; // 1% protocol fee
        uint256 minimumFrontendFee = 0.001e18; // 0.1% minimum frontend fee
        setUpRecipeMarketHubTests(protocolFee, minimumFrontendFee);
    }

    function test_CreateRecipeMarketHub() external view {
        // Check constructor args being set correctly
        assertEq(recipeMarketHub.WEIROLL_WALLET_IMPLEMENTATION(), address(weirollImplementation));
        assertEq(recipeMarketHub.POINTS_FACTORY(), address(pointsFactory));
        assertEq(recipeMarketHub.protocolFee(), initialProtocolFee);
        assertEq(recipeMarketHub.protocolFeeClaimant(), OWNER_ADDRESS);
        assertEq(recipeMarketHub.minimumFrontendFee(), initialMinimumFrontendFee);

        // Check initial recipeMarketHub state
        assertEq(recipeMarketHub.numAPOffers(), 0);
        assertEq(recipeMarketHub.numIPOffers(), 0);
        assertEq(recipeMarketHub.numMarkets(), 0);
    }
}
