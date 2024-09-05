// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../../src/WeirollWallet.sol";
import "../../src/RecipeOrderbook.sol";
import "../../src/PointsFactory.sol";

import { RecipeOrderbookTestBase } from "../utils/RecipeOrderbook/RecipeOrderbookTestBase.sol";

contract TestFuzz_RecipeOrderbook is RecipeOrderbookTestBase {
    function setUp() external {
        uint256 protocolFee = 0.01e18; // 1% protocol fee
        uint256 minimumFrontendFee = 0.001e18; // 0.1% minimum frontend fee
        setUpRecipeOrderbookTests(protocolFee, minimumFrontendFee);
    }

    function testFuzz_SetProtocolFeeClaimant(address newClaimant) external prankModifier(OWNER_ADDRESS) {
        assertEq(orderbook.protocolFeeClaimant(), OWNER_ADDRESS);
        orderbook.setProtocolFeeClaimant(newClaimant);
        assertEq(orderbook.protocolFeeClaimant(), newClaimant);
    }

    function testFuzz_RevertIf_NonOwnerSetProtocolFeeClaimant(address nonOwner, address newClaimant) external prankModifier(nonOwner) {
        vm.assume(nonOwner != OWNER_ADDRESS);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, nonOwner));
        orderbook.setProtocolFeeClaimant(newClaimant);
    }

    function testFuzz_SetProtocolFee(uint256 newProtocolFee) external prankModifier(OWNER_ADDRESS) {
        orderbook.setProtocolFee(newProtocolFee);
        assertEq(orderbook.protocolFee(), newProtocolFee);
    }

    function testFuzz_RevertIf_NonOwnerSetProtocolFee(address nonOwner, uint256 newProtocolFee) external prankModifier(nonOwner) {
        vm.assume(nonOwner != OWNER_ADDRESS);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, nonOwner));
        orderbook.setProtocolFee(newProtocolFee);
    }

    function testFuzz_SetMinimumFrontendFee(uint256 newMinimumFrontendFee) external prankModifier(OWNER_ADDRESS) {
        orderbook.setMinimumFrontendFee(newMinimumFrontendFee);
        assertEq(orderbook.minimumFrontendFee(), newMinimumFrontendFee);
    }

    function testFuzz_RevertIf_NonOwnerSetMinimumFrontendFee(address nonOwner, uint256 newMinimumFrontendFee) external prankModifier(nonOwner) {
        vm.assume(nonOwner != OWNER_ADDRESS);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, nonOwner));
        orderbook.setMinimumFrontendFee(newMinimumFrontendFee);
    }

    // function testFuzz_CreateMarket(
    //     uint256 _initialProtocolFee,
    //     uint256 _initialMinimumFrontendFee,
    //     uint256 _lockupTime,
    //     uint256 _frontendFee,
    //     uint256 _depositRecipeCommandCount,
    //     uint256 _depositRecipeStateCount,
    //     uint256 _withdrawalRecipeCommandCount,
    //     uint256 _withdrawalRecipeStateCount,
    //     address _inputTokenAddress,
    //     uint8 _rewardStyle
    // )
    //     external
    // {
    //     vm.assume(_initialProtocolFee <= 1e18); // Protocol fee should be less than or equal to 100% (1e18)
    //     vm.assume(_initialMinimumFrontendFee <= 1e18); // Minimum frontend fee should be less than or equal to 100%
    //     vm.assume(_lockupTime >= 1 hours && _lockupTime <= 30 days); // Lockup time between 1 hour and 30 days
    //     vm.assume(_frontendFee >= _initialMinimumFrontendFee && _frontendFee <= 1e18); // Frontend fee between minimum fee and 100%
    //     vm.assume(_depositRecipeCommandCount <= 10 && _depositRecipeStateCount <= 5); // Limit recipe size for memory purposes
    //     vm.assume(_withdrawalRecipeCommandCount <= 10 && _withdrawalRecipeStateCount <= 5); // Limit recipe size for memory purposes
    //     vm.assume(_rewardStyle < 3); // Valid RewardStyle enum values are 0, 1, and 2 (Upfront, Arrear, Forfeitable)

    //     // Setup the RecipeOrderbook with the provided fuzzed fees
    //     setUpRecipeOrderbookTests(_initialProtocolFee, _initialMinimumFrontendFee);

    //     // Convert the fuzzed reward style index to the actual enum
    //     RewardStyle rewardStyle = RewardStyle(_rewardStyle);

    //     // Generate random recipes for deposit and withdrawal
    //     RecipeOrderbook.Recipe memory depositRecipe = generateRandomRecipe(_depositRecipeCommandCount, _depositRecipeStateCount);
    //     RecipeOrderbook.Recipe memory withdrawRecipe = generateRandomRecipe(_withdrawalRecipeCommandCount, _withdrawalRecipeStateCount);

    //     // Get the expected market ID
    //     uint256 expectedMarketId = orderbook.numMarkets();

    //     // Check for MarketCreated event
    //     vm.expectEmit(true, true, false, true, address(orderbook));
    //     emit RecipeOrderbook.MarketCreated(expectedMarketId, _inputTokenAddress, _lockupTime, _frontendFee, rewardStyle);

    //     // Call createMarket with the fuzzed inputs
    //     uint256 marketId = orderbook.createMarket(_inputTokenAddress, _lockupTime, _frontendFee, depositRecipe, withdrawRecipe, rewardStyle);

    //     // Assert basic orderbook market state
    //     assertEq(marketId, expectedMarketId);
    //     assertEq(orderbook.numMarkets(), expectedMarketId + 1);

    //     // Check that the market was added correctly
    //     (
    //         ERC20 resultingInputToken,
    //         uint256 resultingLockupTime,
    //         uint256 resultingFrontendFee,
    //         RecipeOrderbook.Recipe memory resultingDepositRecipe,
    //         RecipeOrderbook.Recipe memory resultingWithdrawRecipe,
    //         RewardStyle resultingRewardStyle
    //     ) = orderbook.marketIDToWeirollMarket(marketId);

    //     // Ensure the resulting market matches the inputs
    //     assertEq(address(resultingInputToken), _inputTokenAddress);
    //     assertEq(resultingLockupTime, _lockupTime);
    //     assertEq(resultingFrontendFee, _frontendFee);
    //     assertEq(resultingDepositRecipe.weirollCommands, depositRecipe.weirollCommands);
    //     assertEq(resultingDepositRecipe.weirollState, depositRecipe.weirollState);
    //     assertEq(resultingWithdrawRecipe.weirollCommands, withdrawRecipe.weirollCommands);
    //     assertEq(resultingWithdrawRecipe.weirollState, withdrawRecipe.weirollState);
    //     assertEq(uint8(resultingRewardStyle), uint8(rewardStyle));
    // }

    function testFuzz_RevertIf_CreateMarketWithInvalidFrontendFee(uint256 _initialMinimumFrontendFee, uint256 _marketFrontendFee) external {
        // Make sure that the market fee is less than minimum fee so it reverts
        vm.assume(_marketFrontendFee < _initialMinimumFrontendFee);

        // Protocol fee doesn't matter for this test, so set to 1%
        setUpRecipeOrderbookTests(0.01e18, _initialMinimumFrontendFee);

        vm.expectRevert(abi.encodeWithSelector(RecipeOrderbook.FrontendFeeTooLow.selector));
        orderbook.createMarket(
            address(mockToken),
            1 days, // Weiroll wallet lockup time
            _marketFrontendFee, // less than minimum frontend fee
            NULL_RECIPE, // Deposit Recipe
            NULL_RECIPE, // Withdraw Recipe
            RewardStyle.Upfront
        );
    }
}
