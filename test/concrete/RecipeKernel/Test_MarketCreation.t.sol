// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "src/base/RecipeKernelBase.sol";
import { RecipeKernelTestBase } from "../../utils/RecipeKernel/RecipeKernelTestBase.sol";

contract Test_MarketCreation_RecipeKernel is RecipeKernelTestBase {
    function setUp() external {
        uint256 protocolFee = 0.01e18; // 1% protocol fee
        uint256 minimumFrontendFee = 0.001e18; // 0.1% minimum frontend fee
        setUpRecipeKernelTests(protocolFee, minimumFrontendFee);
    }

    function test_CreateMarket() external {
        // Market creation params
        address inputTokenAddress = address(mockLiquidityToken);
        uint256 lockupTime = 1 days; // Weiroll wallet lockup time
        uint256 frontendFee = 0.002e18; // 0.2% frontend fee
        RewardStyle rewardStyle = RewardStyle.Upfront;

        // Expected market ID of the next market created
        uint256 expectedMarketId = recipeKernel.numMarkets();

        // Check for MarketCreated event
        vm.expectEmit(true, true, false, true, address(recipeKernel));
        emit RecipeKernelBase.MarketCreated(expectedMarketId, inputTokenAddress, lockupTime, frontendFee, rewardStyle);

        // Create market
        uint256 marketId = recipeKernel.createMarket(
            inputTokenAddress,
            lockupTime,
            frontendFee,
            NULL_RECIPE, // Deposit Recipe
            NULL_RECIPE, // Withdraw Recipe
            rewardStyle
        );
        // Assert basic recipeKernel and market state
        assertEq(marketId, expectedMarketId);
        assertEq(recipeKernel.numMarkets(), expectedMarketId + 1);

        // Check that the newly added market was added correctly to the recipeKernel
        (
            ERC20 resultingInputToken,
            uint256 resultingLockupTime,
            uint256 resultingFrontendFee,
            RecipeKernelBase.Recipe memory depositRecipe,
            RecipeKernelBase.Recipe memory withdrawRecipe,
            RewardStyle resultingRewardStyle
        ) = recipeKernel.marketIDToWeirollMarket(marketId);
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
        vm.expectRevert(abi.encodeWithSelector(RecipeKernelBase.FrontendFeeTooLow.selector));
        recipeKernel.createMarket(
            address(mockLiquidityToken),
            1 days, // Weiroll wallet lockup time
            (initialMinimumFrontendFee - 1), // less than minimum frontend fee
            NULL_RECIPE, // Deposit Recipe
            NULL_RECIPE, // Withdraw Recipe
            RewardStyle.Upfront
        );
    }

    function test_RevertIf_CreateMarketWithInvalidFrontendFee() external {
        vm.expectRevert(abi.encodeWithSelector(RecipeKernelBase.FrontendFeeTooLow.selector));
        recipeKernel.createMarket(
            address(mockLiquidityToken),
            1 days, // Weiroll wallet lockup time
            (initialMinimumFrontendFee - 1), // less than minimum frontend fee
            NULL_RECIPE, // Deposit Recipe
            NULL_RECIPE, // Withdraw Recipe
            RewardStyle.Upfront
        );
    }

    function test_RevertIf_CreateMarketWithInvalidTotalFee() external {
        vm.expectRevert(abi.encodeWithSelector(RecipeKernelBase.TotalFeeTooHigh.selector));
        recipeKernel.createMarket(
            address(mockLiquidityToken),
            1 days, // Weiroll wallet lockup time
            (1e18 + 1), // Resulting total fee > 100%
            NULL_RECIPE, // Deposit Recipe
            NULL_RECIPE, // Withdraw Recipe
            RewardStyle.Upfront
        );
    }
}
