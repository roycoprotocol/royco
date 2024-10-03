// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "src/base/RecipeKernelBase.sol";
import "src/VaultWrapper.sol";

import { MockERC20, ERC20 } from "../../mocks/MockERC20.sol";
import { RecipeKernelTestBase } from "../../utils/RecipeKernel/RecipeKernelTestBase.sol";
import { FixedPointMathLib } from "lib/solmate/src/utils/FixedPointMathLib.sol";

contract TestFuzz_Cancel_IPOffer_RecipeKernel is RecipeKernelTestBase {
    using FixedPointMathLib for uint256;

    address AP_ADDRESS;
    address IP_ADDRESS;

    function setUp() external {
        uint256 protocolFee = 0.01e18; // 1% protocol fee
        uint256 minimumFrontendFee = 0.001e18; // 0.1% minimum frontend fee
        setUpRecipeKernelTests(protocolFee, minimumFrontendFee);

        AP_ADDRESS = ALICE_ADDRESS;
        IP_ADDRESS = DAN_ADDRESS;
    }

    function test_cancelIPOffer_WithTokens_PartiallyFilled(uint256 _fillAmount) external {
        uint256 quantity = 100000e18; // The amount of input tokens to be deposited
        vm.assume(_fillAmount > 0);
        vm.assume(_fillAmount <= quantity);

        uint256 marketId = recipeKernel.createMarket(address(mockLiquidityToken), 30 days, 0.001e18, NULL_RECIPE, NULL_RECIPE, RewardStyle.Upfront);

        // Create the IP offer
        uint256 offerId = createIPOffer_WithTokens(marketId, quantity, IP_ADDRESS);
        (,,,, uint256 initialRemainingQuantity) = recipeKernel.offerIDToIPOffer(offerId);
        assertEq(initialRemainingQuantity, quantity);

        // Mint liquidity tokens to the AP to fill the offer
        mockLiquidityToken.mint(AP_ADDRESS, quantity);
        vm.startPrank(AP_ADDRESS);
        mockLiquidityToken.approve(address(recipeKernel), quantity);
        vm.stopPrank();

        vm.startPrank(AP_ADDRESS);
        // fill 50% of the offer
        recipeKernel.fillIPOffers(offerId, _fillAmount, address(0), DAN_ADDRESS);
        vm.stopPrank();

        (,,,, uint256 remainingQuantity) = recipeKernel.offerIDToIPOffer(offerId);

        // Calculate amount to be refunded
        uint256 protocolFeeStored = recipeKernel.getIncentiveToProtocolFeeAmountForIPOffer(offerId, address(mockIncentiveToken));
        uint256 frontendFeeStored = recipeKernel.getIncentiveToFrontendFeeAmountForIPOffer(offerId, address(mockIncentiveToken));
        uint256 incentiveAmountStored = recipeKernel.getIncentiveAmountsOfferedForIPOffer(offerId, address(mockIncentiveToken));

        uint256 percentNotFilled = remainingQuantity.divWadDown(quantity);
        uint256 unchargedFrontendFeeAmount = frontendFeeStored.mulWadDown(percentNotFilled);
        uint256 unchargedProtocolFeeStored = protocolFeeStored.mulWadDown(percentNotFilled);
        uint256 incentivesRemaining = incentiveAmountStored.mulWadDown(percentNotFilled);

        vm.expectEmit(true, true, true, true, address(mockIncentiveToken));
        emit ERC20.Transfer(address(recipeKernel), IP_ADDRESS, incentivesRemaining + unchargedFrontendFeeAmount + unchargedProtocolFeeStored);

        vm.expectEmit(true, false, false, true, address(recipeKernel));
        emit RecipeKernelBase.IPOfferCancelled(offerId);

        vm.startPrank(IP_ADDRESS);
        recipeKernel.cancelIPOffer(offerId);
        vm.stopPrank();

        // Check if offer was deleted from mapping
        (uint256 _targetMarketID, address _ip, uint256 _expiry, uint256 _quantity, uint256 _remainingQuantity) = recipeKernel.offerIDToIPOffer(offerId);
        assertEq(_targetMarketID, 0);
        assertEq(_ip, address(0));
        assertEq(_expiry, 0);
        assertEq(_quantity, 0);
        assertEq(_remainingQuantity, 0);

        // Check that refund was made
        assertApproxEqRel(mockIncentiveToken.balanceOf(IP_ADDRESS), incentivesRemaining + unchargedFrontendFeeAmount + unchargedProtocolFeeStored + 1, 0.0001e18);
    }

    function test_RevertIf_cancelIPOffer_NotOwner(address _nonOwner) external {
        vm.assume(_nonOwner != IP_ADDRESS);

        uint256 marketId = recipeKernel.createMarket(address(mockLiquidityToken), 30 days, 0.001e18, NULL_RECIPE, NULL_RECIPE, RewardStyle.Upfront);

        uint256 quantity = 100000e18; // The amount of input tokens to be deposited

        // Create the IP offer
        uint256 offerId = createIPOffer_WithTokens(marketId, quantity, IP_ADDRESS);

        vm.startPrank(_nonOwner);
        vm.expectRevert(RecipeKernelBase.NotOwner.selector);
        recipeKernel.cancelIPOffer(offerId);
        vm.stopPrank();
    }

    function testFuzz_RevertIf_cancelIPOffer_OfferWithIndefiniteExpiry(uint256 _blockTimestamp) external {
        uint256 marketId = recipeKernel.createMarket(address(mockLiquidityToken), 30 days, 0.001e18, NULL_RECIPE, NULL_RECIPE, RewardStyle.Upfront);

        uint256 quantity = 100000e18; // The amount of input tokens to be deposited

        // Create the IP offer
        uint256 offerId = createIPOffer_WithTokens(marketId, quantity, 0, IP_ADDRESS);

        vm.warp(_blockTimestamp);

        vm.startPrank(IP_ADDRESS);
        vm.expectRevert(RecipeKernelBase.OfferCannotExpire.selector);
        recipeKernel.cancelIPOffer(offerId);
        vm.stopPrank();
    }
}
