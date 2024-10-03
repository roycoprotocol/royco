// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "src/base/RecipeKernelBase.sol";
import "src/WrappedVault.sol";

import { MockERC20, ERC20 } from "../../mocks/MockERC20.sol";
import { RecipeKernelTestBase } from "../../utils/RecipeKernel/RecipeKernelTestBase.sol";
import { FixedPointMathLib } from "lib/solmate/src/utils/FixedPointMathLib.sol";

contract Test_Cancel_IPOffer_RecipeKernel is RecipeKernelTestBase {
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

    function test_cancelIPOffer_WithTokens() external {
        uint256 marketId = recipeKernel.createMarket(address(mockLiquidityToken), 30 days, 0.001e18, NULL_RECIPE, NULL_RECIPE, RewardStyle.Upfront);

        uint256 quantity = 100_000e18; // The amount of input tokens to be deposited

        // Create the IP offer
        uint256 offerId = createIPOffer_WithTokens(marketId, quantity, IP_ADDRESS);
        (,,,, uint256 initialRemainingQuantity) = recipeKernel.offerIDToIPOffer(offerId);
        assertEq(initialRemainingQuantity, quantity);

        // Use the helper function to retrieve values from storage
        uint256 protocolFeeStored = recipeKernel.getIncentiveToProtocolFeeAmountForIPOffer(offerId, address(mockIncentiveToken));
        uint256 frontendFeeStored = recipeKernel.getIncentiveToFrontendFeeAmountForIPOffer(offerId, address(mockIncentiveToken));
        uint256 incentiveAmountStored = recipeKernel.getIncentiveAmountsOfferedForIPOffer(offerId, address(mockIncentiveToken));

        vm.expectEmit(true, true, true, true, address(mockIncentiveToken));
        emit ERC20.Transfer(address(recipeKernel), IP_ADDRESS, incentiveAmountStored + frontendFeeStored + protocolFeeStored);

        vm.expectEmit(true, false, false, true, address(recipeKernel));
        emit RecipeKernelBase.IPOfferCancelled(offerId);

        vm.startPrank(IP_ADDRESS);
        recipeKernel.cancelIPOffer(offerId);
        vm.stopPrank();

        // Check if offer was deleted from mapping on upfront
        (uint256 _targetMarketID, address _ip, uint256 _expiry, uint256 _quantity, uint256 _remainingQuantity) = recipeKernel.offerIDToIPOffer(offerId);
        assertEq(_targetMarketID, 0);
        assertEq(_ip, address(0));
        assertEq(_expiry, 0);
        assertEq(_quantity, 0);
        assertEq(_remainingQuantity, 0);

        // Check that refund was made
        assertApproxEqRel(mockIncentiveToken.balanceOf(IP_ADDRESS), incentiveAmountStored + frontendFeeStored + protocolFeeStored, 0.0001e18);
    }

    function test_cancelIPOffer_WithTokens_PartiallyFilled() external {
        uint256 marketId = recipeKernel.createMarket(address(mockLiquidityToken), 30 days, 0.001e18, NULL_RECIPE, NULL_RECIPE, RewardStyle.Upfront);

        uint256 quantity = 100_000e18; // The amount of input tokens to be deposited

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
        recipeKernel.fillIPOffers(offerId, quantity.mulWadDown(5e17), address(0), DAN_ADDRESS);
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
        assertApproxEqRel(mockIncentiveToken.balanceOf(IP_ADDRESS), incentivesRemaining + unchargedFrontendFeeAmount + unchargedProtocolFeeStored, 0.0001e18);
    }

    function test_cancelIPOffer_WithTokens_Arrear_PartiallyFilled() external {
        uint256 marketId = recipeKernel.createMarket(address(mockLiquidityToken), 30 days, 0.001e18, NULL_RECIPE, NULL_RECIPE, RewardStyle.Arrear);

        uint256 quantity = 100_000e18; // The amount of input tokens to be deposited

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
        recipeKernel.fillIPOffers(offerId, quantity.mulWadDown(5e17), address(0), DAN_ADDRESS);
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
        assertGt(_expiry, 0);
        assertEq(_quantity, quantity);
        assertEq(_remainingQuantity, 0);

        // Check that refund was made
        assertApproxEqRel(mockIncentiveToken.balanceOf(IP_ADDRESS), incentivesRemaining + unchargedFrontendFeeAmount + unchargedProtocolFeeStored, 0.0001e18);
    }

    function test_cancelIPOffer_WithTokens_Forfeitable_PartiallyFilled() external {
        uint256 marketId = recipeKernel.createMarket(address(mockLiquidityToken), 30 days, 0.001e18, NULL_RECIPE, NULL_RECIPE, RewardStyle.Forfeitable);

        uint256 quantity = 100_000e18; // The amount of input tokens to be deposited

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
        recipeKernel.fillIPOffers(offerId, quantity.mulWadDown(5e17), address(0), DAN_ADDRESS);
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
        assertGt(_expiry, 0);
        assertEq(_quantity, quantity);
        assertEq(_remainingQuantity, 0);

        // Check that refund was made
        assertApproxEqRel(mockIncentiveToken.balanceOf(IP_ADDRESS), incentivesRemaining + unchargedFrontendFeeAmount + unchargedProtocolFeeStored, 0.0001e18);
    }

    function test_cancelIPOffer_WithPoints() external {
        uint256 marketId = recipeKernel.createMarket(address(mockLiquidityToken), 30 days, 0.001e18, NULL_RECIPE, NULL_RECIPE, RewardStyle.Upfront);

        uint256 quantity = 100_000e18; // The amount of input tokens to be deposited

        // Create the IP offer
        (uint256 offerId,) = createIPOffer_WithPoints(marketId, quantity, IP_ADDRESS);
        (,,,, uint256 initialRemainingQuantity) = recipeKernel.offerIDToIPOffer(offerId);
        assertEq(initialRemainingQuantity, quantity);

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
    }

    function test_RevertIf_cancelIPOffer_NotOwner() external {
        uint256 marketId = recipeKernel.createMarket(address(mockLiquidityToken), 30 days, 0.001e18, NULL_RECIPE, NULL_RECIPE, RewardStyle.Upfront);

        uint256 quantity = 100_000e18; // The amount of input tokens to be deposited

        // Create the IP offer
        uint256 offerId = createIPOffer_WithTokens(marketId, quantity, IP_ADDRESS);

        vm.startPrank(AP_ADDRESS);
        vm.expectRevert(RecipeKernelBase.NotOwner.selector);
        recipeKernel.cancelIPOffer(offerId);
        vm.stopPrank();
    }

    function test_RevertIf_cancelIPOffer_OfferWithIndefiniteExpiry() external {
        uint256 marketId = recipeKernel.createMarket(address(mockLiquidityToken), 30 days, 0.001e18, NULL_RECIPE, NULL_RECIPE, RewardStyle.Upfront);

        uint256 quantity = 100_000e18; // The amount of input tokens to be deposited

        // Create the IP offer with indefinite expiry
        uint256 offerId = createIPOffer_WithTokens(marketId, quantity, 0, IP_ADDRESS);

        vm.startPrank(IP_ADDRESS);
        vm.expectRevert(RecipeKernelBase.OfferCannotExpire.selector);
        recipeKernel.cancelIPOffer(offerId);
        vm.stopPrank();
    }

    function test_RevertIf_cancelIPOffer_NoRemainingQuantity() external {
        uint256 marketId = createMarket();
        uint256 quantity = 100_000e18;
        // Create a fillable IP offer
        uint256 offerId = createIPOffer_WithTokens(marketId, quantity, IP_ADDRESS);

        // Mint liquidity tokens to the AP to fill the offer
        mockLiquidityToken.mint(AP_ADDRESS, quantity);
        vm.startPrank(AP_ADDRESS);
        mockLiquidityToken.approve(address(recipeKernel), quantity);
        vm.stopPrank();

        vm.startPrank(AP_ADDRESS);
        recipeKernel.fillIPOffers(offerId, quantity, address(0), DAN_ADDRESS);
        vm.stopPrank();

        // Should be completely filled and uncancellable
        (,,,, uint256 remainingQuantity) = recipeKernel.offerIDToIPOffer(offerId);
        assertEq(remainingQuantity, 0);

        vm.startPrank(IP_ADDRESS);
        vm.expectRevert(RecipeKernelBase.NotEnoughRemainingQuantity.selector);
        recipeKernel.cancelIPOffer(offerId);
        vm.stopPrank();
    }
}
