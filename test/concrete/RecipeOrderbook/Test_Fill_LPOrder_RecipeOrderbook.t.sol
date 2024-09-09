// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../../../src/RecipeOrderbook.sol";
import "../../../src/ERC4626i.sol";

import { MockERC20, ERC20 } from "../../mocks/MockERC20.sol";
import { MockERC4626 } from "test/mocks/MockERC4626.sol";
import { RecipeOrderbookTestBase } from "../../utils/RecipeOrderbook/RecipeOrderbookTestBase.sol";
import { FixedPointMathLib } from "lib/solmate/src/utils/FixedPointMathLib.sol";

contract Test_Fill_LPOrder_RecipeOrderbook is RecipeOrderbookTestBase {
    using FixedPointMathLib for uint256;

    address LP_ADDRESS;
    address IP_ADDRESS;
    address FRONTEND_FEE_RECIPIENT;

    function setUp() external {
        uint256 protocolFee = 0.01e18; // 1% protocol fee
        uint256 minimumFrontendFee = 0.001e18; // 0.1% minimum frontend fee
        setUpRecipeOrderbookTests(protocolFee, minimumFrontendFee);

        LP_ADDRESS = ALICE_ADDRESS;
        IP_ADDRESS = DAN_ADDRESS;
        FRONTEND_FEE_RECIPIENT = CHARLIE_ADDRESS;
    }

    function test_DirectFill_Upfront_LPOrder_ForTokens() external {
        uint256 frontendFee = orderbook.minimumFrontendFee();
        uint256 marketId = orderbook.createMarket(address(mockLiquidityToken), 30 days, frontendFee, NULL_RECIPE, NULL_RECIPE, RewardStyle.Upfront);

        uint256 orderAmount = 1000e18; // Order amount requested
        uint256 fillAmount = 100e18; // Fill amount

        (, RecipeOrderbook.LPOrder memory order) = createLPOrder_ForTokens(marketId, address(0), orderAmount, LP_ADDRESS);

        (, uint256 expectedFrontendFeeAmount, uint256 expectedProtocolFeeAmount, uint256 expectedIncentiveAmount) =
            calculateLPOrderExpectedIncentiveAndFrontendFee(orderbook.protocolFee(), frontendFee, orderAmount, fillAmount, 100e18);

        // Mint liquidity tokens to the LP to be able to pay IP who fills it
        mockLiquidityToken.mint(LP_ADDRESS, orderAmount);
        vm.startPrank(LP_ADDRESS);
        mockLiquidityToken.approve(address(orderbook), fillAmount);
        vm.stopPrank();

        // Mint incentive tokens to IP
        mockIncentiveToken.mint(IP_ADDRESS, fillAmount);
        vm.startPrank(IP_ADDRESS);
        mockIncentiveToken.approve(address(orderbook), fillAmount);

        // Expect events for transfers
        vm.expectEmit(true, false, false, true, address(mockIncentiveToken));
        emit ERC20.Transfer(IP_ADDRESS, address(orderbook), expectedFrontendFeeAmount + expectedProtocolFeeAmount);

        vm.expectEmit(true, true, false, true, address(mockIncentiveToken));
        emit ERC20.Transfer(IP_ADDRESS, LP_ADDRESS, expectedIncentiveAmount);

        vm.expectEmit(true, false, false, true, address(mockLiquidityToken));
        emit ERC20.Transfer(LP_ADDRESS, address(0), fillAmount);

        // Expect events for order fill
        vm.expectEmit(false, false, false, false);
        emit RecipeOrderbook.LPOrderFilled(0, 0, address(0), 0, 0, address(0));

        vm.recordLogs();

        orderbook.fillLPOrder(order, fillAmount, FRONTEND_FEE_RECIPIENT);
        vm.stopPrank();

        uint256 resultingRemainingQuantity = orderbook.orderHashToRemainingQuantity(orderbook.getOrderHash(order));
        assertEq(resultingRemainingQuantity, orderAmount - fillAmount);

        // Ensure the lp got the incentives upfront
        assertEq(mockIncentiveToken.balanceOf(LP_ADDRESS), expectedIncentiveAmount);

        // Extract the Weiroll wallet address (the 'to' address from the Transfer event - third event in logs)
        address weirollWallet = address(uint160(uint256(vm.getRecordedLogs()[2].topics[2])));

        // Ensure there is a weirollWallet at the expected address
        assertGt(weirollWallet.code.length, 0);

        // Ensure the weiroll wallet got the liquidity
        assertEq(mockLiquidityToken.balanceOf(weirollWallet), fillAmount);

        // Check the frontend fee recipient received the correct fee
        assertEq(orderbook.feeClaimantToTokenToAmount(FRONTEND_FEE_RECIPIENT, address(mockIncentiveToken)), expectedFrontendFeeAmount);

        // Check the protocol fee claimant received the correct fee
        assertEq(orderbook.feeClaimantToTokenToAmount(OWNER_ADDRESS, address(mockIncentiveToken)), expectedProtocolFeeAmount);
    }

    function test_DirectFill_Upfront_LPOrder_ForPoints() external {
        uint256 frontendFee = orderbook.minimumFrontendFee();
        uint256 marketId = orderbook.createMarket(address(mockLiquidityToken), 30 days, frontendFee, NULL_RECIPE, NULL_RECIPE, RewardStyle.Upfront);

        uint256 orderAmount = 1000e18; // Order amount requested
        uint256 fillAmount = 100e18; // Fill amount

        (, RecipeOrderbook.LPOrder memory order) = createLPOrder_ForTokens(marketId, address(0), orderAmount, LP_ADDRESS);

        (, uint256 expectedFrontendFeeAmount, uint256 expectedProtocolFeeAmount, uint256 expectedIncentiveAmount) =
            calculateLPOrderExpectedIncentiveAndFrontendFee(orderbook.protocolFee(), frontendFee, orderAmount, fillAmount, 100e18);

        // Mint liquidity tokens to the LP to be able to pay IP who fills it
        mockLiquidityToken.mint(LP_ADDRESS, orderAmount);
        vm.startPrank(LP_ADDRESS);
        mockLiquidityToken.approve(address(orderbook), fillAmount);
        vm.stopPrank();

        // Mint incentive tokens to IP
        mockIncentiveToken.mint(IP_ADDRESS, fillAmount);
        vm.startPrank(IP_ADDRESS);
        mockIncentiveToken.approve(address(orderbook), fillAmount);

        // Create a fillable IP order
        (uint256 orderId,, Points points) = createLPOrder_ForPoints(marketId, address(0), orderAmount, LP_ADDRESS, IP_ADDRESS);

        // Expect events for transfers
        vm.expectEmit(true, true, false, true, address(points));
        emit Points.Award(OWNER_ADDRESS, expectedProtocolFeeAmount);

        vm.expectEmit(true, true, false, true, address(points));
        emit Points.Award(FRONTEND_FEE_RECIPIENT, expectedFrontendFeeAmount);

        vm.expectEmit(true, true, false, true, address(points));
        emit Points.Award(LP_ADDRESS, expectedIncentiveAmount);

        vm.expectEmit(true, false, false, true, address(mockLiquidityToken));
        emit ERC20.Transfer(LP_ADDRESS, address(0), fillAmount);

        vm.expectEmit(false, false, false, false, address(orderbook));
        emit RecipeOrderbook.LPOrderFilled(0, 0, address(0), 0, 0, address(0));

        // Record the logs to capture Transfer events to get Weiroll wallet address
        vm.recordLogs();

        orderbook.fillLPOrder(order, fillAmount, FRONTEND_FEE_RECIPIENT);
        vm.stopPrank();

        uint256 resultingRemainingQuantity = orderbook.orderHashToRemainingQuantity(orderbook.getOrderHash(order));
        assertEq(resultingRemainingQuantity, orderAmount - fillAmount);

        // Extract the Weiroll wallet address (the 'to' address from the Transfer event - third event in logs)
        address weirollWallet = address(uint160(uint256(vm.getRecordedLogs()[2].topics[2])));

        // Ensure there is a weirollWallet at the expected address
        assertGt(weirollWallet.code.length, 0);

        // Ensure the weiroll wallet got the liquidity
        assertEq(mockLiquidityToken.balanceOf(weirollWallet), fillAmount);
    }
}
