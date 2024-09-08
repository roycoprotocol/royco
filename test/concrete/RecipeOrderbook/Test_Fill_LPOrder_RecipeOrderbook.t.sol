// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../../../src/RecipeOrderbook.sol";
import "../../../src/ERC4626i.sol";

import { MockERC20, ERC20 } from "../../mocks/MockERC20.sol";
import { MockERC4626 } from "test/mocks/MockERC4626.sol";
import { RecipeOrderbookTestBase } from "../../utils/RecipeOrderbook/RecipeOrderbookTestBase.sol";
import { FixedPointMathLib } from "lib/solmate/src/utils/FixedPointMathLib.sol";

contract TestFuzz_Fill_LPOrder_RecipeOrderbook is RecipeOrderbookTestBase {
    using FixedPointMathLib for uint256;

    address LP_ADDRESS = ALICE_ADDRESS;
    address IP_ADDRESS = DAN_ADDRESS;
    address FRONTEND_FEE_RECIPIENT = CHARLIE_ADDRESS;

    function setUp() external {
        uint256 protocolFee = 0.01e18; // 1% protocol fee
        uint256 minimumFrontendFee = 0.001e18; // 0.1% minimum frontend fee
        setUpRecipeOrderbookTests(protocolFee, minimumFrontendFee);
    }

    function test_DirectFill_Upfront_LPOrder_ForTokens() external {
        uint256 frontendFee = orderbook.minimumFrontendFee();
        uint256 marketId = orderbook.createMarket(address(mockLiquidityToken), 30 days, frontendFee, NULL_RECIPE, NULL_RECIPE, RewardStyle.Upfront);

        uint256 orderAmount = 1000e18; // Order amount requested
        uint256 fillAmount = 100e18; // Fill amount

        (uint256 orderId, RecipeOrderbook.LPOrder memory order) = createLPOrder_ForTokens(marketId, address(0), orderAmount, LP_ADDRESS);

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
        // vm.expectEmit(true, true, false, true, address(mockIncentiveToken));
        // emit ERC20.Transfer(address(orderbook), BOB_ADDRESS, expectedIncentiveAmount);

        // vm.expectEmit(true, false, false, true, address(mockLiquidityToken));
        // emit ERC20.Transfer(BOB_ADDRESS, address(0), fillAmount);

        orderbook.fillLPOrder(order, fillAmount, FRONTEND_FEE_RECIPIENT);
        vm.stopPrank();
    }
}
