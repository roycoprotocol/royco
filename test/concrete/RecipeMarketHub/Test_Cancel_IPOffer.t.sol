// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "src/base/RecipeMarketHubBase.sol";
import "src/WrappedVault.sol";

import { MockERC20, ERC20 } from "../../mocks/MockERC20.sol";
import { RecipeMarketHubTestBase } from "../../utils/RecipeMarketHub/RecipeMarketHubTestBase.sol";
import { FixedPointMathLib } from "lib/solmate/src/utils/FixedPointMathLib.sol";

contract Test_Cancel_IPOffer_RecipeMarketHub is RecipeMarketHubTestBase {
    using FixedPointMathLib for uint256;

    address AP_ADDRESS;
    address IP_ADDRESS;

    function setUp() external {
        uint256 protocolFee = 0.01e18; // 1% protocol fee
        uint256 minimumFrontendFee = 0.001e18; // 0.1% minimum frontend fee
        setUpRecipeMarketHubTests(protocolFee, minimumFrontendFee);

        AP_ADDRESS = ALICE_ADDRESS;
        IP_ADDRESS = DAN_ADDRESS;
    }

    function test_cancelIPOffer_WithTokens() external {
        bytes32 marketHash = recipeMarketHub.createMarket(address(mockLiquidityToken), 30 days, 0.001e18, NULL_RECIPE, NULL_RECIPE, RewardStyle.Upfront);

        uint256 quantity = 100_000e18; // The amount of input tokens to be deposited

        // Create the IP offer
        bytes32 offerHash = createIPOffer_WithTokens(marketHash, quantity, IP_ADDRESS);
        (,,,,, uint256 initialRemainingQuantity) = recipeMarketHub.offerHashToIPOffer(offerHash);
        assertEq(initialRemainingQuantity, quantity);

        // Use the helper function to retrieve values from storage
        uint256 protocolFeeStored = recipeMarketHub.getIncentiveToProtocolFeeAmountForIPOffer(offerHash, address(mockIncentiveToken));
        uint256 frontendFeeStored = recipeMarketHub.getIncentiveToFrontendFeeAmountForIPOffer(offerHash, address(mockIncentiveToken));
        uint256 incentiveAmountStored = recipeMarketHub.getIncentiveAmountsOfferedForIPOffer(offerHash, address(mockIncentiveToken));

        vm.expectEmit(true, true, true, true, address(mockIncentiveToken));
        emit ERC20.Transfer(address(recipeMarketHub), IP_ADDRESS, incentiveAmountStored + frontendFeeStored + protocolFeeStored);

        vm.expectEmit(true, false, false, true, address(recipeMarketHub));
        emit RecipeMarketHubBase.IPOfferCancelled(offerHash);

        vm.startPrank(IP_ADDRESS);
        recipeMarketHub.cancelIPOffer(offerHash);
        vm.stopPrank();

        // Check if offer was deleted from mapping on upfront
        (,bytes32 _targetmarketHash, address _ip, uint256 _expiry, uint256 _quantity, uint256 _remainingQuantity) = recipeMarketHub.offerHashToIPOffer(offerHash);
        assertEq(_targetmarketHash, bytes32(0));
        assertEq(_ip, address(0));
        assertEq(_expiry, 0);
        assertEq(_quantity, 0);
        assertEq(_remainingQuantity, 0);

        // Check that refund was made
        assertApproxEqRel(mockIncentiveToken.balanceOf(IP_ADDRESS), incentiveAmountStored + frontendFeeStored + protocolFeeStored, 0.0001e18);
    }

    function test_cancelIPOffer_WithTokens_PartiallyFilled() external {
        bytes32 marketHash = recipeMarketHub.createMarket(address(mockLiquidityToken), 30 days, 0.001e18, NULL_RECIPE, NULL_RECIPE, RewardStyle.Upfront);

        uint256 quantity = 100_000e18; // The amount of input tokens to be deposited

        // Create the IP offer
        bytes32 offerHash = createIPOffer_WithTokens(marketHash, quantity, IP_ADDRESS);
        (,,,,, uint256 initialRemainingQuantity) = recipeMarketHub.offerHashToIPOffer(offerHash);
        assertEq(initialRemainingQuantity, quantity);

        // Mint liquidity tokens to the AP to fill the offer
        mockLiquidityToken.mint(AP_ADDRESS, quantity);
        vm.startPrank(AP_ADDRESS);
        mockLiquidityToken.approve(address(recipeMarketHub), quantity);
        vm.stopPrank();

        vm.startPrank(AP_ADDRESS);
        // fill 50% of the offer
        recipeMarketHub.fillIPOffers(offerHash, quantity.mulWadDown(5e17), address(0), DAN_ADDRESS);
        vm.stopPrank();

        (,,,,, uint256 remainingQuantity) = recipeMarketHub.offerHashToIPOffer(offerHash);

        // Calculate amount to be refunded
        uint256 protocolFeeStored = recipeMarketHub.getIncentiveToProtocolFeeAmountForIPOffer(offerHash, address(mockIncentiveToken));
        uint256 frontendFeeStored = recipeMarketHub.getIncentiveToFrontendFeeAmountForIPOffer(offerHash, address(mockIncentiveToken));
        uint256 incentiveAmountStored = recipeMarketHub.getIncentiveAmountsOfferedForIPOffer(offerHash, address(mockIncentiveToken));

        uint256 percentNotFilled = remainingQuantity.divWadDown(quantity);
        uint256 unchargedFrontendFeeAmount = frontendFeeStored.mulWadDown(percentNotFilled);
        uint256 unchargedProtocolFeeStored = protocolFeeStored.mulWadDown(percentNotFilled);
        uint256 incentivesRemaining = incentiveAmountStored.mulWadDown(percentNotFilled);

        vm.expectEmit(true, true, true, true, address(mockIncentiveToken));
        emit ERC20.Transfer(address(recipeMarketHub), IP_ADDRESS, incentivesRemaining + unchargedFrontendFeeAmount + unchargedProtocolFeeStored);

        vm.expectEmit(true, false, false, true, address(recipeMarketHub));
        emit RecipeMarketHubBase.IPOfferCancelled(offerHash);

        vm.startPrank(IP_ADDRESS);
        recipeMarketHub.cancelIPOffer(offerHash);
        vm.stopPrank();

        // Check if offer was deleted from mapping
        (,bytes32 _targetmarketHash, address _ip, uint256 _expiry, uint256 _quantity, uint256 _remainingQuantity) = recipeMarketHub.offerHashToIPOffer(offerHash);
        assertEq(_targetmarketHash, bytes32(0));
        assertEq(_ip, address(0));
        assertEq(_expiry, 0);
        assertEq(_quantity, 0);
        assertEq(_remainingQuantity, 0);

        // Check that refund was made
        assertApproxEqRel(mockIncentiveToken.balanceOf(IP_ADDRESS), incentivesRemaining + unchargedFrontendFeeAmount + unchargedProtocolFeeStored, 0.0001e18);
    }

    function test_cancelIPOffer_WithTokens_Arrear_PartiallyFilled() external {
        bytes32 marketHash = recipeMarketHub.createMarket(address(mockLiquidityToken), 30 days, 0.001e18, NULL_RECIPE, NULL_RECIPE, RewardStyle.Arrear);

        uint256 quantity = 100_000e18; // The amount of input tokens to be deposited

        // Create the IP offer
        bytes32 offerHash = createIPOffer_WithTokens(marketHash, quantity, IP_ADDRESS);
        (,,,,, uint256 initialRemainingQuantity) = recipeMarketHub.offerHashToIPOffer(offerHash);
        assertEq(initialRemainingQuantity, quantity);

        // Mint liquidity tokens to the AP to fill the offer
        mockLiquidityToken.mint(AP_ADDRESS, quantity);
        vm.startPrank(AP_ADDRESS);
        mockLiquidityToken.approve(address(recipeMarketHub), quantity);
        vm.stopPrank();

        vm.startPrank(AP_ADDRESS);
        // fill 50% of the offer
        recipeMarketHub.fillIPOffers(offerHash, quantity.mulWadDown(5e17), address(0), DAN_ADDRESS);
        vm.stopPrank();

        (,,,,, uint256 remainingQuantity) = recipeMarketHub.offerHashToIPOffer(offerHash);

        // Calculate amount to be refunded
        uint256 protocolFeeStored = recipeMarketHub.getIncentiveToProtocolFeeAmountForIPOffer(offerHash, address(mockIncentiveToken));
        uint256 frontendFeeStored = recipeMarketHub.getIncentiveToFrontendFeeAmountForIPOffer(offerHash, address(mockIncentiveToken));
        uint256 incentiveAmountStored = recipeMarketHub.getIncentiveAmountsOfferedForIPOffer(offerHash, address(mockIncentiveToken));

        uint256 percentNotFilled = remainingQuantity.divWadDown(quantity);
        uint256 unchargedFrontendFeeAmount = frontendFeeStored.mulWadDown(percentNotFilled);
        uint256 unchargedProtocolFeeStored = protocolFeeStored.mulWadDown(percentNotFilled);
        uint256 incentivesRemaining = incentiveAmountStored.mulWadDown(percentNotFilled);

        vm.expectEmit(true, true, true, true, address(mockIncentiveToken));
        emit ERC20.Transfer(address(recipeMarketHub), IP_ADDRESS, incentivesRemaining + unchargedFrontendFeeAmount + unchargedProtocolFeeStored);

        vm.expectEmit(true, false, false, true, address(recipeMarketHub));
        emit RecipeMarketHubBase.IPOfferCancelled(offerHash);

        vm.startPrank(IP_ADDRESS);
        recipeMarketHub.cancelIPOffer(offerHash);
        vm.stopPrank();

        // Check if offer was deleted from mapping
        (,bytes32 _targetmarketHash, address _ip, uint256 _expiry, uint256 _quantity, uint256 _remainingQuantity) = recipeMarketHub.offerHashToIPOffer(offerHash);
        assertEq(_targetmarketHash, bytes32(0));
        assertEq(_ip, address(0));
        assertGt(_expiry, 0);
        assertEq(_quantity, quantity);
        assertEq(_remainingQuantity, 0);

        // Check that refund was made
        assertApproxEqRel(mockIncentiveToken.balanceOf(IP_ADDRESS), incentivesRemaining + unchargedFrontendFeeAmount + unchargedProtocolFeeStored, 0.0001e18);
    }

    function test_cancelIPOffer_WithTokens_Forfeitable_PartiallyFilled() external {
        bytes32 marketHash = recipeMarketHub.createMarket(address(mockLiquidityToken), 30 days, 0.001e18, NULL_RECIPE, NULL_RECIPE, RewardStyle.Forfeitable);

        uint256 quantity = 100_000e18; // The amount of input tokens to be deposited

        // Create the IP offer
        bytes32 offerHash = createIPOffer_WithTokens(marketHash, quantity, IP_ADDRESS);
        (,,,,, uint256 initialRemainingQuantity) = recipeMarketHub.offerHashToIPOffer(offerHash);
        assertEq(initialRemainingQuantity, quantity);

        // Mint liquidity tokens to the AP to fill the offer
        mockLiquidityToken.mint(AP_ADDRESS, quantity);
        vm.startPrank(AP_ADDRESS);
        mockLiquidityToken.approve(address(recipeMarketHub), quantity);
        vm.stopPrank();

        vm.startPrank(AP_ADDRESS);
        // fill 50% of the offer
        recipeMarketHub.fillIPOffers(offerHash, quantity.mulWadDown(5e17), address(0), DAN_ADDRESS);
        vm.stopPrank();

        (,,,,, uint256 remainingQuantity) = recipeMarketHub.offerHashToIPOffer(offerHash);

        // Calculate amount to be refunded
        uint256 protocolFeeStored = recipeMarketHub.getIncentiveToProtocolFeeAmountForIPOffer(offerHash, address(mockIncentiveToken));
        uint256 frontendFeeStored = recipeMarketHub.getIncentiveToFrontendFeeAmountForIPOffer(offerHash, address(mockIncentiveToken));
        uint256 incentiveAmountStored = recipeMarketHub.getIncentiveAmountsOfferedForIPOffer(offerHash, address(mockIncentiveToken));

        uint256 percentNotFilled = remainingQuantity.divWadDown(quantity);
        uint256 unchargedFrontendFeeAmount = frontendFeeStored.mulWadDown(percentNotFilled);
        uint256 unchargedProtocolFeeStored = protocolFeeStored.mulWadDown(percentNotFilled);
        uint256 incentivesRemaining = incentiveAmountStored.mulWadDown(percentNotFilled);

        vm.expectEmit(true, true, true, true, address(mockIncentiveToken));
        emit ERC20.Transfer(address(recipeMarketHub), IP_ADDRESS, incentivesRemaining + unchargedFrontendFeeAmount + unchargedProtocolFeeStored);

        vm.expectEmit(true, false, false, true, address(recipeMarketHub));
        emit RecipeMarketHubBase.IPOfferCancelled(offerHash);

        vm.startPrank(IP_ADDRESS);
        recipeMarketHub.cancelIPOffer(offerHash);
        vm.stopPrank();

        // Check if offer was deleted from mapping
        (,bytes32 _targetmarketHash, address _ip, uint256 _expiry, uint256 _quantity, uint256 _remainingQuantity) = recipeMarketHub.offerHashToIPOffer(offerHash);
        assertEq(_targetmarketHash, bytes32(0));
        assertEq(_ip, address(0));
        assertGt(_expiry, 0);
        assertEq(_quantity, quantity);
        assertEq(_remainingQuantity, 0);

        // Check that refund was made
        assertApproxEqRel(mockIncentiveToken.balanceOf(IP_ADDRESS), incentivesRemaining + unchargedFrontendFeeAmount + unchargedProtocolFeeStored, 0.0001e18);
    }

    function test_cancelIPOffer_WithPoints() external {
        bytes32 marketHash = recipeMarketHub.createMarket(address(mockLiquidityToken), 30 days, 0.001e18, NULL_RECIPE, NULL_RECIPE, RewardStyle.Upfront);

        uint256 quantity = 100_000e18; // The amount of input tokens to be deposited

        // Create the IP offer
        (bytes32 offerHash,) = createIPOffer_WithPoints(marketHash, quantity, IP_ADDRESS);
        (,,,,, uint256 initialRemainingQuantity) = recipeMarketHub.offerHashToIPOffer(offerHash);
        assertEq(initialRemainingQuantity, quantity);

        vm.expectEmit(true, false, false, true, address(recipeMarketHub));
        emit RecipeMarketHubBase.IPOfferCancelled(offerHash);

        vm.startPrank(IP_ADDRESS);
        recipeMarketHub.cancelIPOffer(offerHash);
        vm.stopPrank();

        // Check if offer was deleted from mapping
        (,bytes32 _targetmarketHash, address _ip, uint256 _expiry, uint256 _quantity, uint256 _remainingQuantity) = recipeMarketHub.offerHashToIPOffer(offerHash);
        assertEq(_targetmarketHash, bytes32(0));
        assertEq(_ip, address(0));
        assertEq(_expiry, 0);
        assertEq(_quantity, 0);
        assertEq(_remainingQuantity, 0);
    }

    function test_RevertIf_cancelIPOffer_NotOwner() external {
        bytes32 marketHash = recipeMarketHub.createMarket(address(mockLiquidityToken), 30 days, 0.001e18, NULL_RECIPE, NULL_RECIPE, RewardStyle.Upfront);

        uint256 quantity = 100_000e18; // The amount of input tokens to be deposited

        // Create the IP offer
        bytes32 offerHash = createIPOffer_WithTokens(marketHash, quantity, IP_ADDRESS);

        vm.startPrank(AP_ADDRESS);
        vm.expectRevert(RecipeMarketHubBase.NotOwner.selector);
        recipeMarketHub.cancelIPOffer(offerHash);
        vm.stopPrank();
    }

    function test_RevertIf_cancelIPOffer_NoRemainingQuantity() external {
        bytes32 marketHash = createMarket();
        uint256 quantity = 100_000e18;
        // Create a fillable IP offer
        bytes32 offerHash = createIPOffer_WithTokens(marketHash, quantity, IP_ADDRESS);

        // Mint liquidity tokens to the AP to fill the offer
        mockLiquidityToken.mint(AP_ADDRESS, quantity);
        vm.startPrank(AP_ADDRESS);
        mockLiquidityToken.approve(address(recipeMarketHub), quantity);
        vm.stopPrank();

        vm.startPrank(AP_ADDRESS);
        recipeMarketHub.fillIPOffers(offerHash, quantity, address(0), DAN_ADDRESS);
        vm.stopPrank();

        // Should be completely filled and uncancellable
        (,,,,, uint256 remainingQuantity) = recipeMarketHub.offerHashToIPOffer(offerHash);
        assertEq(remainingQuantity, 0);

        vm.startPrank(IP_ADDRESS);
        vm.expectRevert(RecipeMarketHubBase.NotEnoughRemainingQuantity.selector);
        recipeMarketHub.cancelIPOffer(offerHash);
        vm.stopPrank();
    }
}
