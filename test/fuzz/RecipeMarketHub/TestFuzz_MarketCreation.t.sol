// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "src/base/RecipeMarketHubBase.sol";

import { RecipeMarketHubTestBase } from "../../utils/RecipeMarketHub/RecipeMarketHubTestBase.sol";

contract TestFuzz_MarketCreation_RecipeMarketHub is RecipeMarketHubTestBase {
    function setUp() external {
        uint256 protocolFee = 0.01e18; // 1% protocol fee
        uint256 minimumFrontendFee = 0.001e18; // 0.1% minimum frontend fee
        setUpRecipeMarketHubTests(protocolFee, minimumFrontendFee);
    }

    function testFuzz_CreateMarket(
        uint256 _lockupTime,
        uint256 _frontendFee,
        uint8 _depositRecipeCommandCount,
        uint8 _depositRecipeStateCount,
        uint8 _withdrawalRecipeCommandCount,
        uint8 _withdrawalRecipeStateCount,
        address _inputTokenAddress,
        uint8 _rewardStyle
    )
        external
    {
        vm.assume(_inputTokenAddress != address(0));
        // Manually bound the inputs using modulo to limit the ranges (was hitting fuzzing reject limit)
        _frontendFee = initialMinimumFrontendFee + (_frontendFee % (1e18 - (initialMinimumFrontendFee + initialProtocolFee))); // Frontend fee + protocol fee
            // between min fee and 100%
        // Limit recipe counts to a maximum of 10 for commands and 5 for state entries
        _depositRecipeCommandCount = _depositRecipeCommandCount % 10;
        _depositRecipeStateCount = _depositRecipeStateCount % 5;
        _withdrawalRecipeCommandCount = _withdrawalRecipeCommandCount % 10;
        _withdrawalRecipeStateCount = _withdrawalRecipeStateCount % 5;
        // Bound reward style to valid enum values (0, 1, 2)
        _rewardStyle = _rewardStyle % 3;

        // Convert the fuzzed reward style index to the actual enum
        RewardStyle rewardStyle = RewardStyle(_rewardStyle);

        // Generate random recipes for deposit and withdrawal
        RecipeMarketHubBase.Recipe memory depositRecipe = generateRandomRecipe(_depositRecipeCommandCount, _depositRecipeStateCount);
        RecipeMarketHubBase.Recipe memory withdrawRecipe = generateRandomRecipe(_withdrawalRecipeCommandCount, _withdrawalRecipeStateCount);

        // Get the expected market ID
        uint256 expectedMarketId = recipeMarketHub.numMarkets();

        // Check for MarketCreated event
        vm.expectEmit(true, false, false, true, address(recipeMarketHub));
        emit RecipeMarketHubBase.MarketCreated(expectedMarketId, bytes32(0), _inputTokenAddress, _lockupTime, _frontendFee, rewardStyle);

        // Call createMarket with the fuzzed inputs
        bytes32 marketHash = recipeMarketHub.createMarket(_inputTokenAddress, _lockupTime, _frontendFee, depositRecipe, withdrawRecipe, rewardStyle);

        // Assert basic recipeMarketHub market state
        assertEq(recipeMarketHub.numMarkets(), expectedMarketId + 1);

        // Check that the market was added correctly
        (
            ,
            ERC20 resultingInputToken,
            uint256 resultingLockupTime,
            uint256 resultingFrontendFee,
            RecipeMarketHubBase.Recipe memory resultingDepositRecipe,
            RecipeMarketHubBase.Recipe memory resultingWithdrawRecipe,
            RewardStyle resultingRewardStyle
        ) = recipeMarketHub.marketHashToWeirollMarket(marketHash);

        // Ensure the resulting market matches the inputs
        assertEq(address(resultingInputToken), _inputTokenAddress);
        assertEq(resultingLockupTime, _lockupTime);
        assertEq(resultingFrontendFee, _frontendFee);
        assertEq(resultingDepositRecipe.weirollCommands, depositRecipe.weirollCommands);
        assertEq(resultingDepositRecipe.weirollState, depositRecipe.weirollState);
        assertEq(resultingWithdrawRecipe.weirollCommands, withdrawRecipe.weirollCommands);
        assertEq(resultingWithdrawRecipe.weirollState, withdrawRecipe.weirollState);
        assertEq(uint8(resultingRewardStyle), uint8(rewardStyle));
    }

    function testFuzz_RevertIf_CreateMarketWithLowFrontendFee(uint256 _initialMinimumFrontendFee, uint256 _marketFrontendFee) external {
        // Make sure that the market fee is less than minimum fee so it reverts
        vm.assume(_marketFrontendFee < _initialMinimumFrontendFee);

        // Protocol fee doesn't matter for this test, so set to 1%
        setUpRecipeMarketHubTests(0.01e18, _initialMinimumFrontendFee);

        vm.expectRevert(abi.encodeWithSelector(RecipeMarketHubBase.FrontendFeeTooLow.selector));
        recipeMarketHub.createMarket(
            address(mockLiquidityToken),
            1 days, // Weiroll wallet lockup time
            _marketFrontendFee, // less than minimum frontend fee
            NULL_RECIPE, // Deposit Recipe
            NULL_RECIPE, // Withdraw Recipe
            RewardStyle.Upfront
        );
    }

    function testFuzz_RevertIf_CreateMarketWithInvalidTotalFee(uint256 _frontendFee) external {
        _frontendFee = _frontendFee % (type(uint256).max - recipeMarketHub.protocolFee()); // Bound the fee to prevent overflow and not catch the expected
            // reversion
        vm.assume((recipeMarketHub.protocolFee() + _frontendFee) > 1e18); // Ensures total fee > 100% so we expect a reversion

        vm.expectRevert(abi.encodeWithSelector(RecipeMarketHubBase.TotalFeeTooHigh.selector));
        recipeMarketHub.createMarket(
            address(mockLiquidityToken),
            1 days, // Weiroll wallet lockup time
            _frontendFee, // Resulting total fee > 100%
            NULL_RECIPE, // Deposit Recipe
            NULL_RECIPE, // Withdraw Recipe
            RewardStyle.Upfront
        );
    }
}
