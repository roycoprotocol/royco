// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../../../src/RecipeKernel.sol";
import "../../../src/PointsFactory.sol";

import { RecipeKernelTestBase } from "../../utils/RecipeKernel/RecipeKernelTestBase.sol";

contract Test_RecipekernelCreation_RecipeKernel is RecipeKernelTestBase {
    function setUp() external {
        uint256 protocolFee = 0.01e18; // 1% protocol fee
        uint256 minimumFrontendFee = 0.001e18; // 0.1% minimum frontend fee
        setUpRecipeKernelTests(protocolFee, minimumFrontendFee);
    }

    function test_CreateRecipekernel() external view {
        // Check constructor args being set correctly
        assertEq(recipeKernel.WEIROLL_WALLET_IMPLEMENTATION(), address(weirollImplementation));
        assertEq(recipeKernel.POINTS_FACTORY(), address(pointsFactory));
        assertEq(recipeKernel.protocolFee(), initialProtocolFee);
        assertEq(recipeKernel.protocolFeeClaimant(), OWNER_ADDRESS);
        assertEq(recipeKernel.minimumFrontendFee(), initialMinimumFrontendFee);

        // Check initial recipeKernel state
        assertEq(recipeKernel.numAPOffers(), 0);
        assertEq(recipeKernel.numIPOffers(), 0);
        assertEq(recipeKernel.numMarkets(), 0);
    }
}
