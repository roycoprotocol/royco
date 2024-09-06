// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../../../src/RecipeOrderbook.sol";
import { RecipeOrderbookTestBase } from "../../utils/RecipeOrderbook/RecipeOrderbookTestBase.sol";

contract Test_MarketCreation_RecipeOrderbook is RecipeOrderbookTestBase {
    function setUp() external {
        uint256 protocolFee = 0.01e18; // 1% protocol fee
        uint256 minimumFrontendFee = 0.001e18; // 0.1% minimum frontend fee
        setUpRecipeOrderbookTests(protocolFee, minimumFrontendFee);
    }

    function test_CreateMarket() external {
        // Market creation params
        address inputTokenAddress = address(mockLiquidityToken);
        uint256 lockupTime = 1 days; // Weiroll wallet lockup time
        uint256 frontendFee = 0.002e18; // 0.2% frontend fee
        RewardStyle rewardStyle = RewardStyle.Upfront;

        // Expected market ID of the next market created
        uint256 expectedMarketId = orderbook.numMarkets();

        // Check for MarketCreated event
        vm.expectEmit(true, true, false, true, address(orderbook));
        emit RecipeOrderbook.MarketCreated(expectedMarketId, inputTokenAddress, lockupTime, frontendFee, rewardStyle);

        // Create market
        uint256 marketId = orderbook.createMarket(
            inputTokenAddress,
            lockupTime,
            frontendFee,
            NULL_RECIPE, // Deposit Recipe
            NULL_RECIPE, // Withdraw Recipe
            rewardStyle
        );
        // Assert basic orderbook and market state
        assertEq(marketId, expectedMarketId);
        assertEq(orderbook.numMarkets(), expectedMarketId + 1);

        // Check that the newly added market was added correctly to the orderbook
        (
            ERC20 resultingInputToken,
            uint256 resultingLockupTime,
            uint256 resultingFrontendFee,
            RecipeOrderbook.Recipe memory depositRecipe,
            RecipeOrderbook.Recipe memory withdrawRecipe,
            RewardStyle resultingRewardStyle
        ) = orderbook.marketIDToWeirollMarket(marketId);
        assertEq(address(resultingInputToken), inputTokenAddress);
        assertEq(resultingLockupTime, lockupTime);
        assertEq(resultingFrontendFee, frontendFee);
        assertEq(depositRecipe.weirollCommands, NULL_RECIPE.weirollCommands);
        assertEq(depositRecipe.weirollState, NULL_RECIPE.weirollState);
        assertEq(withdrawRecipe.weirollCommands, NULL_RECIPE.weirollCommands);
        assertEq(withdrawRecipe.weirollState, NULL_RECIPE.weirollState);
        assertEq(uint8(resultingRewardStyle), uint8(rewardStyle));
    }

    function test_RevertIf_CreateMarketWithLowFrontendFee() external {
        vm.expectRevert(abi.encodeWithSelector(RecipeOrderbook.FrontendFeeTooLow.selector));
        orderbook.createMarket(
            address(mockLiquidityToken),
            1 days, // Weiroll wallet lockup time
            (initialMinimumFrontendFee - 1), // less than minimum frontend fee
            NULL_RECIPE, // Deposit Recipe
            NULL_RECIPE, // Withdraw Recipe
            RewardStyle.Upfront
        );
    }

    function test_RevertIf_CreateMarketWithInvalidFrontendFee() external {
        vm.expectRevert(abi.encodeWithSelector(RecipeOrderbook.FrontendFeeTooLow.selector));
        orderbook.createMarket(
            address(mockLiquidityToken),
            1 days, // Weiroll wallet lockup time
            (initialMinimumFrontendFee - 1), // less than minimum frontend fee
            NULL_RECIPE, // Deposit Recipe
            NULL_RECIPE, // Withdraw Recipe
            RewardStyle.Upfront
        );
    }

    function test_RevertIf_CreateMarketWithInvalidTotalFee() external {
        vm.expectRevert(abi.encodeWithSelector(RecipeOrderbook.TotalFeeTooHigh.selector));
        orderbook.createMarket(
            address(mockLiquidityToken),
            1 days, // Weiroll wallet lockup time
            (1e18 + 1), // Resulting total fee > 100%
            NULL_RECIPE, // Deposit Recipe
            NULL_RECIPE, // Withdraw Recipe
            RewardStyle.Upfront
        );
    }
}
