// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "src/base/RecipeMarketHubBase.sol";
import "src/WrappedVault.sol";

import { MockERC20, ERC20 } from "../../mocks/MockERC20.sol";
import { RecipeMarketHubTestBase } from "../../utils/RecipeMarketHub/RecipeMarketHubTestBase.sol";
import { FixedPointMathLib } from "lib/solmate/src/utils/FixedPointMathLib.sol";

contract Test_ClaimFees_RecipeMarketHub is RecipeMarketHubTestBase {
    using FixedPointMathLib for uint256;

    function setUp() external {
        uint256 protocolFee = 0.01e18; // 1% protocol fee
        uint256 minimumFrontendFee = 0.001e18; // 0.1% minimum frontend fee
        setUpRecipeMarketHubTests(protocolFee, minimumFrontendFee);
    }

    function test_ClaimFeesAfterFillingIPOffer() external {
        uint256 frontendFee = recipeMarketHub.minimumFrontendFee();
        bytes32 marketHash = recipeMarketHub.createMarket(address(mockLiquidityToken), 30 days, frontendFee, NULL_RECIPE, NULL_RECIPE, RewardStyle.Upfront);

        uint256 offerAmount = 100000e18; // Offer amount requested
        uint256 fillAmount = 1000e18; // Fill amount

        // Create a fillable IP offer
        bytes32 offerHash = createIPOffer_WithTokens(marketHash, offerAmount, ALICE_ADDRESS);

        // Mint liquidity tokens to the AP to fill the offer
        mockLiquidityToken.mint(BOB_ADDRESS, fillAmount);
        vm.startPrank(BOB_ADDRESS);
        mockLiquidityToken.approve(address(recipeMarketHub), fillAmount);
        vm.stopPrank();

        // Calculate expected frontend and protocol fees
        (, uint256 expectedProtocolFeeAmount, uint256 expectedFrontendFeeAmount, ) =
            calculateIPOfferExpectedIncentiveAndFrontendFee(offerHash, offerAmount, fillAmount, address(mockIncentiveToken));

        // Fill the offer and accumulate fees
        vm.startPrank(BOB_ADDRESS);
        recipeMarketHub.fillIPOffers(offerHash, fillAmount, address(0), CHARLIE_ADDRESS);
        vm.stopPrank();

        // **Claim protocol fees by owner**
        vm.startPrank(OWNER_ADDRESS);
        vm.expectEmit(true, true, false, true, address(mockIncentiveToken));
        emit ERC20.Transfer(address(recipeMarketHub), OWNER_ADDRESS, expectedProtocolFeeAmount);

        vm.expectEmit(true, true, false, true, address(recipeMarketHub));
        emit RecipeMarketHubBase.FeesClaimed(OWNER_ADDRESS, address(mockIncentiveToken), expectedProtocolFeeAmount);

        // Protocol fee claim
        recipeMarketHub.claimFees(address(mockIncentiveToken), OWNER_ADDRESS);
        vm.stopPrank();

        // **Verify that protocol fees were claimed**
        assertEq(mockIncentiveToken.balanceOf(OWNER_ADDRESS), expectedProtocolFeeAmount);
        assertEq(recipeMarketHub.feeClaimantToTokenToAmount(OWNER_ADDRESS, address(mockIncentiveToken)), 0);

        // **Claim frontend fees by CHARLIE**
        vm.startPrank(CHARLIE_ADDRESS);
        vm.expectEmit(true, true, false, true, address(mockIncentiveToken));
        emit ERC20.Transfer(address(recipeMarketHub), CHARLIE_ADDRESS, expectedFrontendFeeAmount);

        vm.expectEmit(true, true, false, true, address(recipeMarketHub));
        emit RecipeMarketHubBase.FeesClaimed(CHARLIE_ADDRESS, address(mockIncentiveToken), expectedFrontendFeeAmount);

        // Frontend fee claim
        recipeMarketHub.claimFees(address(mockIncentiveToken), CHARLIE_ADDRESS);
        vm.stopPrank();

        // **Verify that frontend fees were claimed**
        assertEq(mockIncentiveToken.balanceOf(CHARLIE_ADDRESS), expectedFrontendFeeAmount);
        assertEq(recipeMarketHub.feeClaimantToTokenToAmount(CHARLIE_ADDRESS, address(mockIncentiveToken)), 0);
    }
}
