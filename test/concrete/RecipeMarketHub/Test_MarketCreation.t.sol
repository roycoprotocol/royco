// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "src/base/RecipeMarketHubBase.sol";
import { RecipeMarketHubTestBase } from "../../utils/RecipeMarketHub/RecipeMarketHubTestBase.sol";

contract Test_MarketCreation_RecipeMarketHub is RecipeMarketHubTestBase {
    function setUp() external {
        uint256 protocolFee = 0.01e18; // 1% protocol fee
        uint256 minimumFrontendFee = 0.001e18; // 0.1% minimum frontend fee
        setUpRecipeMarketHubTests(protocolFee, minimumFrontendFee);
    }

    function test_CreateMarket() external {
        // Market creation params
        address inputTokenAddress = address(mockLiquidityToken);
        uint256 lockupTime = 1 days; // Weiroll wallet lockup time
        uint256 frontendFee = 0.002e18; // 0.2% frontend fee
        RewardStyle rewardStyle = RewardStyle.Upfront;

        // Check for MarketCreated event
        vm.expectEmit(true, false, false, true, address(recipeMarketHub));
        emit RecipeMarketHubBase.MarketCreated(0, bytes32(0), inputTokenAddress, lockupTime, frontendFee, rewardStyle);

        // Create market
        bytes32 marketHash = recipeMarketHub.createMarket(
            inputTokenAddress,
            lockupTime,
            frontendFee,
            NULL_RECIPE, // Deposit Recipe
            NULL_RECIPE, // Withdraw Recipe
            rewardStyle
        );

        // Check that the newly added market was added correctly to the recipeMarketHub
        (
            uint256 marketId,
            ERC20 resultingInputToken,
            uint256 resultingLockupTime,
            uint256 resultingFrontendFee,
            RecipeMarketHubBase.Recipe memory depositRecipe,
            RecipeMarketHubBase.Recipe memory withdrawRecipe,
            RewardStyle resultingRewardStyle
        ) = recipeMarketHub.marketHashToWeirollMarket(marketHash);
        assertEq(marketId, 0);
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
        vm.expectRevert(abi.encodeWithSelector(RecipeMarketHubBase.FrontendFeeTooLow.selector));
        recipeMarketHub.createMarket(
            address(mockLiquidityToken),
            1 days, // Weiroll wallet lockup time
            (initialMinimumFrontendFee - 1), // less than minimum frontend fee
            NULL_RECIPE, // Deposit Recipe
            NULL_RECIPE, // Withdraw Recipe
            RewardStyle.Upfront
        );
    }

    function test_RevertIf_CreateMarketWithInvalidFrontendFee() external {
        vm.expectRevert(abi.encodeWithSelector(RecipeMarketHubBase.FrontendFeeTooLow.selector));
        recipeMarketHub.createMarket(
            address(mockLiquidityToken),
            1 days, // Weiroll wallet lockup time
            (initialMinimumFrontendFee - 1), // less than minimum frontend fee
            NULL_RECIPE, // Deposit Recipe
            NULL_RECIPE, // Withdraw Recipe
            RewardStyle.Upfront
        );
    }

    function test_RevertIf_CreateMarketWithInvalidTotalFee() external {
        vm.expectRevert(abi.encodeWithSelector(RecipeMarketHubBase.TotalFeeTooHigh.selector));
        recipeMarketHub.createMarket(
            address(mockLiquidityToken),
            1 days, // Weiroll wallet lockup time
            (1e18 + 1), // Resulting total fee > 100%
            NULL_RECIPE, // Deposit Recipe
            NULL_RECIPE, // Withdraw Recipe
            RewardStyle.Upfront
        );
    }
}
