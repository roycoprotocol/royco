// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "src/base/RecipeOrderbookBase.sol";
import "src/ERC4626i.sol";

import { MockERC20, ERC20 } from "../../mocks/MockERC20.sol";
import { RecipeOrderbookTestBase } from "../../utils/RecipeOrderbook/RecipeOrderbookTestBase.sol";
import { FixedPointMathLib } from "lib/solmate/src/utils/FixedPointMathLib.sol";

contract Test_Cancel_IPOrder_RecipeOrderbook is RecipeOrderbookTestBase {
    using FixedPointMathLib for uint256;

    address AP_ADDRESS;
    address IP_ADDRESS;

    function setUp() external {
        uint256 protocolFee = 0.01e18; // 1% protocol fee
        uint256 minimumFrontendFee = 0.001e18; // 0.1% minimum frontend fee
        setUpRecipeOrderbookTests(protocolFee, minimumFrontendFee);

        AP_ADDRESS = ALICE_ADDRESS;
        IP_ADDRESS = DAN_ADDRESS;
    }

    function test_cancelIPOrder_WithTokens() external {
        uint256 marketId = orderbook.createMarket(address(mockLiquidityToken), 30 days, 0.001e18, NULL_RECIPE, NULL_RECIPE, RewardStyle.Upfront);

        uint256 quantity = 100_000e18; // The amount of input tokens to be deposited

        // Create the IP order
        uint256 orderId = createIPOrder_WithTokens(marketId, quantity, IP_ADDRESS);
        (,,,, uint256 initialRemainingQuantity) = orderbook.orderIDToIPOrder(orderId);
        assertEq(initialRemainingQuantity, quantity);

        // Use the helper function to retrieve values from storage
        uint256 protocolFeeStored = orderbook.getTokenToProtocolFeeAmountForIPOrder(orderId, address(mockIncentiveToken));
        uint256 frontendFeeStored = orderbook.getTokenToFrontendFeeAmountForIPOrder(orderId, address(mockIncentiveToken));
        uint256 incentiveAmountStored = orderbook.getTokenAmountsOfferedForIPOrder(orderId, address(mockIncentiveToken));

        vm.expectEmit(true, true, true, true, address(mockIncentiveToken));
        emit ERC20.Transfer(address(orderbook), IP_ADDRESS, incentiveAmountStored + frontendFeeStored + protocolFeeStored);

        vm.expectEmit(true, false, false, true, address(orderbook));
        emit RecipeOrderbookBase.IPOfferCancelled(orderId);

        vm.startPrank(IP_ADDRESS);
        orderbook.cancelIPOrder(orderId);
        vm.stopPrank();

        // Check if order was deleted from mapping on upfront
        (uint256 _targetMarketID, address _ip, uint256 _expiry, uint256 _quantity, uint256 _remainingQuantity) = orderbook.orderIDToIPOrder(orderId);
        assertEq(_targetMarketID, 0);
        assertEq(_ip, address(0));
        assertEq(_expiry, 0);
        assertEq(_quantity, 0);
        assertEq(_remainingQuantity, 0);

        // Check that refund was made
        assertApproxEqRel(mockIncentiveToken.balanceOf(IP_ADDRESS), incentiveAmountStored + frontendFeeStored + protocolFeeStored, 0.0001e18);
    }

    function test_cancelIPOrder_WithTokens_PartiallyFilled() external {
        uint256 marketId = orderbook.createMarket(address(mockLiquidityToken), 30 days, 0.001e18, NULL_RECIPE, NULL_RECIPE, RewardStyle.Upfront);

        uint256 quantity = 100_000e18; // The amount of input tokens to be deposited

        // Create the IP order
        uint256 orderId = createIPOrder_WithTokens(marketId, quantity, IP_ADDRESS);
        (,,,, uint256 initialRemainingQuantity) = orderbook.orderIDToIPOrder(orderId);
        assertEq(initialRemainingQuantity, quantity);

        // Mint liquidity tokens to the AP to fill the order
        mockLiquidityToken.mint(AP_ADDRESS, quantity);
        vm.startPrank(AP_ADDRESS);
        mockLiquidityToken.approve(address(orderbook), quantity);
        vm.stopPrank();

        vm.startPrank(AP_ADDRESS);
        // fill 50% of the order
        orderbook.fillIPOrder(orderId, quantity.mulWadDown(5e17), address(0), DAN_ADDRESS);
        vm.stopPrank();

        (,,,, uint256 remainingQuantity) = orderbook.orderIDToIPOrder(orderId);

        // Calculate amount to be refunded
        uint256 protocolFeeStored = orderbook.getTokenToProtocolFeeAmountForIPOrder(orderId, address(mockIncentiveToken));
        uint256 frontendFeeStored = orderbook.getTokenToFrontendFeeAmountForIPOrder(orderId, address(mockIncentiveToken));
        uint256 incentiveAmountStored = orderbook.getTokenAmountsOfferedForIPOrder(orderId, address(mockIncentiveToken));

        uint256 percentNotFilled = remainingQuantity.divWadDown(quantity);
        uint256 unchargedFrontendFeeAmount = frontendFeeStored.mulWadDown(percentNotFilled);
        uint256 unchargedProtocolFeeStored = protocolFeeStored.mulWadDown(percentNotFilled);
        uint256 incentivesRemaining = incentiveAmountStored.mulWadDown(percentNotFilled);

        vm.expectEmit(true, true, true, true, address(mockIncentiveToken));
        emit ERC20.Transfer(address(orderbook), IP_ADDRESS, incentivesRemaining + unchargedFrontendFeeAmount + unchargedProtocolFeeStored);

        vm.expectEmit(true, false, false, true, address(orderbook));
        emit RecipeOrderbookBase.IPOfferCancelled(orderId);

        vm.startPrank(IP_ADDRESS);
        orderbook.cancelIPOrder(orderId);
        vm.stopPrank();

        // Check if order was deleted from mapping
        (uint256 _targetMarketID, address _ip, uint256 _expiry, uint256 _quantity, uint256 _remainingQuantity) = orderbook.orderIDToIPOrder(orderId);
        assertEq(_targetMarketID, 0);
        assertEq(_ip, address(0));
        assertEq(_expiry, 0);
        assertEq(_quantity, 0);
        assertEq(_remainingQuantity, 0);

        // Check that refund was made
        assertApproxEqRel(mockIncentiveToken.balanceOf(IP_ADDRESS), incentivesRemaining + unchargedFrontendFeeAmount + unchargedProtocolFeeStored, 0.0001e18);
    }

    function test_cancelIPOrder_WithTokens_Arrear_PartiallyFilled() external {
        uint256 marketId = orderbook.createMarket(address(mockLiquidityToken), 30 days, 0.001e18, NULL_RECIPE, NULL_RECIPE, RewardStyle.Arrear);

        uint256 quantity = 100_000e18; // The amount of input tokens to be deposited

        // Create the IP order
        uint256 orderId = createIPOrder_WithTokens(marketId, quantity, IP_ADDRESS);
        (,,,, uint256 initialRemainingQuantity) = orderbook.orderIDToIPOrder(orderId);
        assertEq(initialRemainingQuantity, quantity);

        // Mint liquidity tokens to the AP to fill the order
        mockLiquidityToken.mint(AP_ADDRESS, quantity);
        vm.startPrank(AP_ADDRESS);
        mockLiquidityToken.approve(address(orderbook), quantity);
        vm.stopPrank();

        vm.startPrank(AP_ADDRESS);
        // fill 50% of the order
        orderbook.fillIPOrder(orderId, quantity.mulWadDown(5e17), address(0), DAN_ADDRESS);
        vm.stopPrank();

        (,,,, uint256 remainingQuantity) = orderbook.orderIDToIPOrder(orderId);

        // Calculate amount to be refunded
        uint256 protocolFeeStored = orderbook.getTokenToProtocolFeeAmountForIPOrder(orderId, address(mockIncentiveToken));
        uint256 frontendFeeStored = orderbook.getTokenToFrontendFeeAmountForIPOrder(orderId, address(mockIncentiveToken));
        uint256 incentiveAmountStored = orderbook.getTokenAmountsOfferedForIPOrder(orderId, address(mockIncentiveToken));

        uint256 percentNotFilled = remainingQuantity.divWadDown(quantity);
        uint256 unchargedFrontendFeeAmount = frontendFeeStored.mulWadDown(percentNotFilled);
        uint256 unchargedProtocolFeeStored = protocolFeeStored.mulWadDown(percentNotFilled);
        uint256 incentivesRemaining = incentiveAmountStored.mulWadDown(percentNotFilled);

        vm.expectEmit(true, true, true, true, address(mockIncentiveToken));
        emit ERC20.Transfer(address(orderbook), IP_ADDRESS, incentivesRemaining + unchargedFrontendFeeAmount + unchargedProtocolFeeStored);

        vm.expectEmit(true, false, false, true, address(orderbook));
        emit RecipeOrderbookBase.IPOfferCancelled(orderId);

        vm.startPrank(IP_ADDRESS);
        orderbook.cancelIPOrder(orderId);
        vm.stopPrank();

        // Check if order was deleted from mapping
        (uint256 _targetMarketID, address _ip, uint256 _expiry, uint256 _quantity, uint256 _remainingQuantity) = orderbook.orderIDToIPOrder(orderId);
        assertEq(_targetMarketID, 0);
        assertEq(_ip, address(0));
        assertGt(_expiry, 0);
        assertEq(_quantity, quantity);
        assertEq(_remainingQuantity, 0);

        // Check that refund was made
        assertApproxEqRel(mockIncentiveToken.balanceOf(IP_ADDRESS), incentivesRemaining + unchargedFrontendFeeAmount + unchargedProtocolFeeStored, 0.0001e18);
    }

    function test_cancelIPOrder_WithTokens_Forfeitable_PartiallyFilled() external {
        uint256 marketId = orderbook.createMarket(address(mockLiquidityToken), 30 days, 0.001e18, NULL_RECIPE, NULL_RECIPE, RewardStyle.Forfeitable);

        uint256 quantity = 100_000e18; // The amount of input tokens to be deposited

        // Create the IP order
        uint256 orderId = createIPOrder_WithTokens(marketId, quantity, IP_ADDRESS);
        (,,,, uint256 initialRemainingQuantity) = orderbook.orderIDToIPOrder(orderId);
        assertEq(initialRemainingQuantity, quantity);

        // Mint liquidity tokens to the AP to fill the order
        mockLiquidityToken.mint(AP_ADDRESS, quantity);
        vm.startPrank(AP_ADDRESS);
        mockLiquidityToken.approve(address(orderbook), quantity);
        vm.stopPrank();

        vm.startPrank(AP_ADDRESS);
        // fill 50% of the order
        orderbook.fillIPOrder(orderId, quantity.mulWadDown(5e17), address(0), DAN_ADDRESS);
        vm.stopPrank();

        (,,,, uint256 remainingQuantity) = orderbook.orderIDToIPOrder(orderId);

        // Calculate amount to be refunded
        uint256 protocolFeeStored = orderbook.getTokenToProtocolFeeAmountForIPOrder(orderId, address(mockIncentiveToken));
        uint256 frontendFeeStored = orderbook.getTokenToFrontendFeeAmountForIPOrder(orderId, address(mockIncentiveToken));
        uint256 incentiveAmountStored = orderbook.getTokenAmountsOfferedForIPOrder(orderId, address(mockIncentiveToken));

        uint256 percentNotFilled = remainingQuantity.divWadDown(quantity);
        uint256 unchargedFrontendFeeAmount = frontendFeeStored.mulWadDown(percentNotFilled);
        uint256 unchargedProtocolFeeStored = protocolFeeStored.mulWadDown(percentNotFilled);
        uint256 incentivesRemaining = incentiveAmountStored.mulWadDown(percentNotFilled);

        vm.expectEmit(true, true, true, true, address(mockIncentiveToken));
        emit ERC20.Transfer(address(orderbook), IP_ADDRESS, incentivesRemaining + unchargedFrontendFeeAmount + unchargedProtocolFeeStored);

        vm.expectEmit(true, false, false, true, address(orderbook));
        emit RecipeOrderbookBase.IPOfferCancelled(orderId);

        vm.startPrank(IP_ADDRESS);
        orderbook.cancelIPOrder(orderId);
        vm.stopPrank();

        // Check if order was deleted from mapping
        (uint256 _targetMarketID, address _ip, uint256 _expiry, uint256 _quantity, uint256 _remainingQuantity) = orderbook.orderIDToIPOrder(orderId);
        assertEq(_targetMarketID, 0);
        assertEq(_ip, address(0));
        assertGt(_expiry, 0);
        assertEq(_quantity, quantity);
        assertEq(_remainingQuantity, 0);

        // Check that refund was made
        assertApproxEqRel(mockIncentiveToken.balanceOf(IP_ADDRESS), incentivesRemaining + unchargedFrontendFeeAmount + unchargedProtocolFeeStored, 0.0001e18);
    }

    function test_cancelIPOrder_WithPoints() external {
        uint256 marketId = orderbook.createMarket(address(mockLiquidityToken), 30 days, 0.001e18, NULL_RECIPE, NULL_RECIPE, RewardStyle.Upfront);

        uint256 quantity = 100_000e18; // The amount of input tokens to be deposited

        // Create the IP order
        (uint256 orderId,) = createIPOrder_WithPoints(marketId, quantity, IP_ADDRESS);
        (,,,, uint256 initialRemainingQuantity) = orderbook.orderIDToIPOrder(orderId);
        assertEq(initialRemainingQuantity, quantity);

        vm.expectEmit(true, false, false, true, address(orderbook));
        emit RecipeOrderbookBase.IPOfferCancelled(orderId);

        vm.startPrank(IP_ADDRESS);
        orderbook.cancelIPOrder(orderId);
        vm.stopPrank();

        // Check if order was deleted from mapping
        (uint256 _targetMarketID, address _ip, uint256 _expiry, uint256 _quantity, uint256 _remainingQuantity) = orderbook.orderIDToIPOrder(orderId);
        assertEq(_targetMarketID, 0);
        assertEq(_ip, address(0));
        assertEq(_expiry, 0);
        assertEq(_quantity, 0);
        assertEq(_remainingQuantity, 0);
    }

    function test_RevertIf_cancelIPOrder_NotOwner() external {
        uint256 marketId = orderbook.createMarket(address(mockLiquidityToken), 30 days, 0.001e18, NULL_RECIPE, NULL_RECIPE, RewardStyle.Upfront);

        uint256 quantity = 100_000e18; // The amount of input tokens to be deposited

        // Create the IP order
        uint256 orderId = createIPOrder_WithTokens(marketId, quantity, IP_ADDRESS);

        vm.startPrank(AP_ADDRESS);
        vm.expectRevert(RecipeOrderbookBase.NotOwner.selector);
        orderbook.cancelIPOrder(orderId);
        vm.stopPrank();
    }

    function test_RevertIf_cancelIPOrder_OrderWithIndefiniteExpiry() external {
        uint256 marketId = orderbook.createMarket(address(mockLiquidityToken), 30 days, 0.001e18, NULL_RECIPE, NULL_RECIPE, RewardStyle.Upfront);

        uint256 quantity = 100_000e18; // The amount of input tokens to be deposited

        // Create the IP order with indefinite expiry
        uint256 orderId = createIPOrder_WithTokens(marketId, quantity, 0, IP_ADDRESS);

        vm.startPrank(IP_ADDRESS);
        vm.expectRevert(RecipeOrderbookBase.OrderCannotExpire.selector);
        orderbook.cancelIPOrder(orderId);
        vm.stopPrank();
    }

    function test_RevertIf_cancelIPOrder_NoRemainingQuantity() external {
        uint256 marketId = createMarket();
        uint256 quantity = 100_000e18;
        // Create a fillable IP order
        uint256 orderId = createIPOrder_WithTokens(marketId, quantity, IP_ADDRESS);

        // Mint liquidity tokens to the AP to fill the order
        mockLiquidityToken.mint(AP_ADDRESS, quantity);
        vm.startPrank(AP_ADDRESS);
        mockLiquidityToken.approve(address(orderbook), quantity);
        vm.stopPrank();

        vm.startPrank(AP_ADDRESS);
        orderbook.fillIPOrder(orderId, quantity, address(0), DAN_ADDRESS);
        vm.stopPrank();

        // Should be completely filled and uncancellable
        (,,,, uint256 remainingQuantity) = orderbook.orderIDToIPOrder(orderId);
        assertEq(remainingQuantity, 0);

        vm.startPrank(IP_ADDRESS);
        vm.expectRevert(RecipeOrderbookBase.NotEnoughRemainingQuantity.selector);
        orderbook.cancelIPOrder(orderId);
        vm.stopPrank();
    }
}
