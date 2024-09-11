// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../../../src/RecipeOrderbook.sol";
import "../../../src/ERC4626i.sol";

import { MockERC20, ERC20 } from "../../mocks/MockERC20.sol";
import { RecipeOrderbookTestBase } from "../../utils/RecipeOrderbook/RecipeOrderbookTestBase.sol";
import { FixedPointMathLib } from "lib/solmate/src/utils/FixedPointMathLib.sol";

contract Test_ClaimFees_RecipeOrderbook is RecipeOrderbookTestBase {
    using FixedPointMathLib for uint256;

    function setUp() external {
        uint256 protocolFee = 0.01e18; // 1% protocol fee
        uint256 minimumFrontendFee = 0.001e18; // 0.1% minimum frontend fee
        setUpRecipeOrderbookTests(protocolFee, minimumFrontendFee);
    }

    function test_ClaimFeesAfterFillingIPOrder() external {
        uint256 frontendFee = orderbook.minimumFrontendFee();
        uint256 marketId = orderbook.createMarket(address(mockLiquidityToken), 30 days, frontendFee, NULL_RECIPE, NULL_RECIPE, RewardStyle.Upfront);

        uint256 orderAmount = 100000e18; // Order amount requested
        uint256 fillAmount = 1000e18; // Fill amount

        // Create a fillable IP order
        uint256 orderId = createIPOrder_WithTokens(marketId, orderAmount, ALICE_ADDRESS);

        // Mint liquidity tokens to the LP to fill the order
        mockLiquidityToken.mint(BOB_ADDRESS, fillAmount);
        vm.startPrank(BOB_ADDRESS);
        mockLiquidityToken.approve(address(orderbook), fillAmount);
        vm.stopPrank();

        // Calculate expected frontend and protocol fees
        (, uint256 expectedProtocolFeeAmount, uint256 expectedFrontendFeeAmount, ) =
            calculateIPOrderExpectedIncentiveAndFrontendFee(orderId, orderAmount, fillAmount, address(mockIncentiveToken));

        // Fill the order and accumulate fees
        vm.startPrank(BOB_ADDRESS);
        orderbook.fillIPOrder(orderId, fillAmount, address(0), CHARLIE_ADDRESS);
        vm.stopPrank();

        // **Claim protocol fees by owner**
        vm.startPrank(OWNER_ADDRESS);
        vm.expectEmit(true, true, false, true, address(mockIncentiveToken));
        emit ERC20.Transfer(address(orderbook), OWNER_ADDRESS, expectedProtocolFeeAmount);

        vm.expectEmit(true, true, false, true, address(orderbook));
        emit RecipeOrderbook.FeesClaimed(OWNER_ADDRESS, expectedProtocolFeeAmount);

        // Protocol fee claim
        orderbook.claimFees(address(mockIncentiveToken), OWNER_ADDRESS);
        vm.stopPrank();

        // **Verify that protocol fees were claimed**
        assertEq(mockIncentiveToken.balanceOf(OWNER_ADDRESS), expectedProtocolFeeAmount);
        assertEq(orderbook.feeClaimantToTokenToAmount(OWNER_ADDRESS, address(mockIncentiveToken)), 0);

        // **Claim frontend fees by CHARLIE**
        vm.startPrank(CHARLIE_ADDRESS);
        vm.expectEmit(true, true, false, true, address(mockIncentiveToken));
        emit ERC20.Transfer(address(orderbook), CHARLIE_ADDRESS, expectedFrontendFeeAmount);

        vm.expectEmit(true, true, false, true, address(orderbook));
        emit RecipeOrderbook.FeesClaimed(CHARLIE_ADDRESS, expectedFrontendFeeAmount);

        // Frontend fee claim
        orderbook.claimFees(address(mockIncentiveToken), CHARLIE_ADDRESS);
        vm.stopPrank();

        // **Verify that frontend fees were claimed**
        assertEq(mockIncentiveToken.balanceOf(CHARLIE_ADDRESS), expectedFrontendFeeAmount);
        assertEq(orderbook.feeClaimantToTokenToAmount(CHARLIE_ADDRESS, address(mockIncentiveToken)), 0);
    }
}
