// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../../../src/RecipeOrderbook.sol";
import "../../../src/ERC4626i.sol";

import { MockERC20, ERC20 } from "../../mocks/MockERC20.sol";
import { MockERC4626 } from "test/mocks/MockERC4626.sol";
import { RecipeOrderbookTestBase } from "../../utils/RecipeOrderbook/RecipeOrderbookTestBase.sol";
import { FixedPointMathLib } from "lib/solmate/src/utils/FixedPointMathLib.sol";

contract TestFuzz_Fill_IPOrder_RecipeOrderbook is RecipeOrderbookTestBase {
    using FixedPointMathLib for uint256;

    address IP_ADDRESS = ALICE_ADDRESS;
    address FRONTEND_FEE_RECIPIENT = CHARLIE_ADDRESS;

    function setUp() external {
        uint256 protocolFee = 0.01e18; // 1% protocol fee
        uint256 minimumFrontendFee = 0.001e18; // 0.1% minimum frontend fee
        setUpRecipeOrderbookTests(protocolFee, minimumFrontendFee);
    }

    function testFuzz_DirectFill_Upfront_IPOrder_ForTokens(uint256 orderAmount, uint256 fillAmount) external {
        orderAmount = bound(orderAmount, 1e6, 1e30);
        fillAmount = bound(fillAmount, 1e6, orderAmount);

        uint256 frontendFee = orderbook.minimumFrontendFee();
        uint256 marketId = orderbook.createMarket(address(mockLiquidityToken), 30 days, frontendFee, NULL_RECIPE, NULL_RECIPE, RewardStyle.Upfront);

        // Create a fillable IP order
        uint256 orderId = createIPOrder_WithTokens(marketId, orderAmount, IP_ADDRESS);

        // Mint liquidity tokens to the LP to fill the order
        mockLiquidityToken.mint(BOB_ADDRESS, fillAmount);
        vm.startPrank(BOB_ADDRESS);
        mockLiquidityToken.approve(address(orderbook), fillAmount);
        vm.stopPrank();

        (, uint256 expectedFrontendFeeAmount, uint256 expectedIncentiveAmount) =
            calculateIPOrderExpectedIncentiveAndFrontendFee(orderId, orderAmount, fillAmount, address(mockIncentiveToken));

        // Expect events for transfers
        vm.expectEmit(true, true, false, true, address(mockIncentiveToken));
        emit ERC20.Transfer(address(orderbook), BOB_ADDRESS, expectedIncentiveAmount);

        vm.expectEmit(true, false, false, true, address(mockLiquidityToken));
        emit ERC20.Transfer(BOB_ADDRESS, address(0), fillAmount);

        // Record logs to capture Transfer events to get Weiroll wallet address
        vm.recordLogs();
        // Fill the order
        vm.startPrank(BOB_ADDRESS);
        orderbook.fillIPOrder(orderId, fillAmount, address(0), FRONTEND_FEE_RECIPIENT);
        vm.stopPrank();

        (,,, uint256 resultingQuantity, uint256 resultingRemainingQuantity) = orderbook.orderIDToIPOrder(orderId);
        assertEq(resultingRemainingQuantity, resultingQuantity - fillAmount);

        // Extract the Weiroll wallet address
        address weirollWallet = address(uint160(uint256(vm.getRecordedLogs()[1].topics[2])));
        assertGt(weirollWallet.code.length, 0); // Ensure weirollWallet is valid

        // Ensure LP received the correct incentive amount
        assertEq(mockIncentiveToken.balanceOf(BOB_ADDRESS), expectedIncentiveAmount);

        // Ensure weiroll wallet got the liquidity
        assertEq(mockLiquidityToken.balanceOf(weirollWallet), fillAmount);

        // Check frontend fee recipient received correct fee
        assertEq(orderbook.feeClaimantToTokenToAmount(FRONTEND_FEE_RECIPIENT, address(mockIncentiveToken)), expectedFrontendFeeAmount);
    }

    function testFuzz_DirectFill_Upfront_IPOrder_ForPoints(uint256 orderAmount, uint256 fillAmount) external {
        orderAmount = bound(orderAmount, 1e6, 1e30);
        fillAmount = bound(fillAmount, 1e6, orderAmount);

        uint256 frontendFee = orderbook.minimumFrontendFee();
        uint256 marketId = orderbook.createMarket(address(mockLiquidityToken), 30 days, frontendFee, NULL_RECIPE, NULL_RECIPE, RewardStyle.Upfront);

        // Mint liquidity tokens to the LP to fill the order
        mockLiquidityToken.mint(BOB_ADDRESS, fillAmount);
        vm.startPrank(BOB_ADDRESS);
        mockLiquidityToken.approve(address(orderbook), fillAmount);
        vm.stopPrank();

        // Create a fillable IP order
        (uint256 orderId, Points points) = createIPOrder_WithPoints(marketId, orderAmount, IP_ADDRESS);

        (, uint256 expectedFrontendFeeAmount, uint256 expectedIncentiveAmount) =
            calculateIPOrderExpectedIncentiveAndFrontendFee(orderId, orderAmount, fillAmount, address(points));

        // Expect events for transfers
        vm.expectEmit(true, true, false, true, address(points));
        emit Points.Award(BOB_ADDRESS, expectedIncentiveAmount);

        vm.expectEmit(true, true, false, true, address(points));
        emit Points.Award(FRONTEND_FEE_RECIPIENT, expectedFrontendFeeAmount);

        vm.expectEmit(true, false, false, true, address(mockLiquidityToken));
        emit ERC20.Transfer(BOB_ADDRESS, address(0), fillAmount);

        // Record logs to capture Transfer events to get Weiroll wallet address
        vm.recordLogs();
        // Fill the order
        vm.startPrank(BOB_ADDRESS);
        orderbook.fillIPOrder(orderId, fillAmount, address(0), FRONTEND_FEE_RECIPIENT);
        vm.stopPrank();

        (,,, uint256 resultingQuantity, uint256 resultingRemainingQuantity) = orderbook.orderIDToIPOrder(orderId);
        assertEq(resultingRemainingQuantity, resultingQuantity - fillAmount);

        // Extract the Weiroll wallet address
        address weirollWallet = address(uint160(uint256(vm.getRecordedLogs()[2].topics[2])));
        assertGt(weirollWallet.code.length, 0); // Ensure weirollWallet is valid

        // Ensure weiroll wallet got the liquidity
        assertEq(mockLiquidityToken.balanceOf(weirollWallet), fillAmount);
    }

    function testFuzz_RevertIf_OrderExpired(uint256 orderAmount, uint256 fillAmount, uint256 timeDelta) external {
        orderAmount = bound(orderAmount, 1e6, 1e30);
        fillAmount = bound(fillAmount, 1e6, orderAmount);
        timeDelta = bound(timeDelta, 30 days + 1, 365 days);

        uint256 frontendFee = orderbook.minimumFrontendFee();
        uint256 marketId = orderbook.createMarket(address(mockLiquidityToken), 30 days, frontendFee, NULL_RECIPE, NULL_RECIPE, RewardStyle.Upfront);

        // Create an order with the specified amount
        uint256 orderId = createIPOrder_WithTokens(marketId, orderAmount, IP_ADDRESS);

        // Warp to time beyond the expiry
        vm.warp(block.timestamp + timeDelta);

        // Expect revert due to order expiration
        vm.expectRevert(RecipeOrderbook.OrderExpired.selector);
        orderbook.fillIPOrder(orderId, fillAmount, address(0), FRONTEND_FEE_RECIPIENT);
    }

    function testFuzz_RevertIf_NotEnoughRemainingQuantity(uint256 orderAmount, uint256 fillAmount) external {
        orderAmount = bound(orderAmount, 1e6, 1e30);
        fillAmount = orderAmount + bound(fillAmount, 1, 1e18); // Fill amount exceeds orderAmount

        uint256 frontendFee = orderbook.minimumFrontendFee();
        uint256 marketId = orderbook.createMarket(address(mockLiquidityToken), 30 days, frontendFee, NULL_RECIPE, NULL_RECIPE, RewardStyle.Upfront);

        // Create a fillable IP order
        uint256 orderId = createIPOrder_WithTokens(marketId, orderAmount, IP_ADDRESS);

        // Expect revert due to insufficient remaining quantity
        vm.expectRevert(RecipeOrderbook.NotEnoughRemainingQuantity.selector);
        orderbook.fillIPOrder(orderId, fillAmount, address(0), FRONTEND_FEE_RECIPIENT);
    }

    function testFuzz_RevertIf_MismatchedBaseAsset(uint256 orderAmount, uint256 fillAmount) external {
        orderAmount = bound(orderAmount, 1e6, 1e30);
        fillAmount = bound(fillAmount, 1e6, orderAmount);

        uint256 frontendFee = orderbook.minimumFrontendFee();
        uint256 marketId = orderbook.createMarket(address(mockLiquidityToken), 30 days, frontendFee, NULL_RECIPE, NULL_RECIPE, RewardStyle.Upfront);

        // Create a fillable IP order
        uint256 orderId = createIPOrder_WithTokens(marketId, orderAmount, IP_ADDRESS);

        // Use a different vault with a mismatched base asset
        address incorrectVault = address(new MockERC4626(mockIncentiveToken)); // Mismatched asset

        // Expect revert due to mismatched base asset
        vm.expectRevert(RecipeOrderbook.MismatchedBaseAsset.selector);
        orderbook.fillIPOrder(orderId, fillAmount, incorrectVault, FRONTEND_FEE_RECIPIENT);
    }

    function testFuzz_RevertIf_ZeroQuantityFill(uint256 orderAmount) external {
        orderAmount = bound(orderAmount, 1e6, 1e30);

        uint256 frontendFee = orderbook.minimumFrontendFee();
        uint256 marketId = orderbook.createMarket(address(mockLiquidityToken), 30 days, frontendFee, NULL_RECIPE, NULL_RECIPE, RewardStyle.Upfront);

        // Create a fillable IP order
        uint256 orderId = createIPOrder_WithTokens(marketId, orderAmount, IP_ADDRESS);

        // Expect revert due to zero quantity fill
        vm.expectRevert(RecipeOrderbook.CannotPlaceZeroQuantityOrder.selector);
        orderbook.fillIPOrder(orderId, 0, address(0), FRONTEND_FEE_RECIPIENT);
    }
}
