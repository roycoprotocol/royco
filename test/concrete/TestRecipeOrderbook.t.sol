// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../../src/WeirollWallet.sol";
import "../../src/RecipeOrderbook.sol";
import "../../src/PointsFactory.sol";

import "lib/forge-std/src/Test.sol";
import "lib/openzeppelin-contracts/contracts/access/Ownable2Step.sol";

import { RecipeOrderbookTestBase } from "../utils/RecipeOrderbook/RecipeOrderbookTestBase.sol";

contract TestRecipeOrderbook is RecipeOrderbookTestBase {
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

    function test_SetProtocolFeeClaimant() external prankModifier(OWNER_ADDRESS) {
        assertEq(orderbook.protocolFeeClaimant(), OWNER_ADDRESS);
        orderbook.setProtocolFeeClaimant(ALICE_ADDRESS);
        assertEq(orderbook.protocolFeeClaimant(), ALICE_ADDRESS);
    }

    function test_RevertIf_NonOwnerSetProtocolFeeClaimant() external prankModifier(ALICE_ADDRESS) {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, ALICE_ADDRESS));
        orderbook.setProtocolFeeClaimant(BOB_ADDRESS);
    }

    function test_SetProtocolFee() external prankModifier(OWNER_ADDRESS) {
        uint256 newProtocolFee = 0.02e18;
        assertEq(orderbook.protocolFee(), initialProtocolFee);
        orderbook.setProtocolFee(newProtocolFee);
        assertEq(orderbook.protocolFee(), newProtocolFee);
    }

    function test_RevertIf_NonOwnerSetProtocolFee() external prankModifier(ALICE_ADDRESS) {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, ALICE_ADDRESS));
        orderbook.setProtocolFee(0.02e18);
    }

    function test_SetMinimumFrontendFee() external prankModifier(OWNER_ADDRESS) {
        uint256 newMinimumFrontendFee = 0.002e18;
        assertEq(orderbook.minimumFrontendFee(), initialMinimumFrontendFee);
        orderbook.setMinimumFrontendFee(newMinimumFrontendFee);
        assertEq(orderbook.minimumFrontendFee(), newMinimumFrontendFee);
    }

    function test_RevertIf_NonOwnerSetMinimumFrontendFee() external prankModifier(ALICE_ADDRESS) {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, ALICE_ADDRESS));
        orderbook.setMinimumFrontendFee(0.002e18);
    }

    function test_CreateMarket() external {
        // Market creation params
        address inputTokenAddress = address(mockToken);
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

    function test_RevertIf_CreateMarketWithInvalidFrontendFee() external {
        vm.expectRevert(abi.encodeWithSelector(RecipeOrderbook.FrontendFeeTooLow.selector));
        orderbook.createMarket(
            address(mockToken),
            1 days, // Weiroll wallet lockup time
            (initialMinimumFrontendFee - 1), // less than minimum frontend fee
            NULL_RECIPE, // Deposit Recipe
            NULL_RECIPE, // Withdraw Recipe
            RewardStyle.Upfront
        );
    }
}
