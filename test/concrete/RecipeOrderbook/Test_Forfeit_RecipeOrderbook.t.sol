// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../../../src/RecipeOrderbook.sol";
import { RecipeOrderbookTestBase } from "../../utils/RecipeOrderbook/RecipeOrderbookTestBase.sol";

contract Test_Forfeit_RecipeOrderbook is RecipeOrderbookTestBase {
    address IP_ADDRESS;
    address AP_ADDRESS;
    address FRONTEND_FEE_RECIPIENT;

    function setUp() external {
        uint256 protocolFee = 0.01e18; // 1% protocol fee
        uint256 minimumFrontendFee = 0.001e18; // 0.1% minimum frontend fee
        setUpRecipeOrderbookTests(protocolFee, minimumFrontendFee);

        IP_ADDRESS = ALICE_ADDRESS;
        AP_ADDRESS = BOB_ADDRESS;
        FRONTEND_FEE_RECIPIENT = CHARLIE_ADDRESS;
    }

    function test_Forfeit_TokenIncentives() external {
        uint256 frontendFee = orderbook.minimumFrontendFee();
        uint256 marketId = orderbook.createMarket(address(mockLiquidityToken), 30 days, frontendFee, NULL_RECIPE, NULL_RECIPE, RewardStyle.Forfeitable);

        uint256 orderAmount = 100_000e18; // Order amount requested
        uint256 fillAmount = 1000e18; // Fill amount

        // Create a fillable IP order
        uint256 orderId = createIPOrder_WithTokens(marketId, orderAmount, IP_ADDRESS);

        // Mint liquidity tokens to the AP to fill the order
        mockLiquidityToken.mint(AP_ADDRESS, fillAmount);
        vm.startPrank(AP_ADDRESS);
        mockLiquidityToken.approve(address(orderbook), fillAmount);
        vm.stopPrank();

        // Record the logs to capture Transfer events to get Weiroll wallet address
        vm.recordLogs();
        // Fill the order
        vm.startPrank(AP_ADDRESS);
        orderbook.fillIPOrder(orderId, fillAmount, address(0), FRONTEND_FEE_RECIPIENT);
        vm.stopPrank();

        (,,, uint256 resultingQuantity, uint256 resultingRemainingQuantity) = orderbook.orderIDToIPOrder(orderId);
        assertEq(resultingRemainingQuantity, resultingQuantity - fillAmount);

        address weirollWallet = address(uint160(uint256(vm.getRecordedLogs()[0].topics[2])));

        (, uint256[] memory amounts,) = orderbook.getLockedRewardParams(weirollWallet);

        // make sure withdrawal recipe is executed on frofeiture
        (,,,, RecipeOrderbook.Recipe memory withdrawRecipe,) = orderbook.marketIDToWeirollMarket(marketId);
        vm.expectCall(
            weirollWallet, 0, abi.encodeWithSelector(WeirollWallet.executeWeiroll.selector, withdrawRecipe.weirollCommands, withdrawRecipe.weirollState)
        );

        vm.startPrank(AP_ADDRESS);
        orderbook.forfeit(weirollWallet, true);
        vm.stopPrank();

        // Check the weiroll wallet was deleted from orderbook state
        (address[] memory resultingTokens, uint256[] memory resultingAmounts, address resultingIp) = orderbook.getLockedRewardParams(weirollWallet);
        assertEq(resultingTokens, new address[](0));
        assertEq(resultingAmounts, new uint256[](0));
        assertEq(resultingIp, address(0));
    }

    function test_Forfeit_TokenIncentives_NoExec() external {
        uint256 frontendFee = orderbook.minimumFrontendFee();
        uint256 marketId = orderbook.createMarket(address(mockLiquidityToken), 30 days, frontendFee, NULL_RECIPE, NULL_RECIPE, RewardStyle.Forfeitable);

        uint256 orderAmount = 100_000e18; // Order amount requested
        uint256 fillAmount = 1000e18; // Fill amount

        // Create a fillable IP order
        uint256 orderId = createIPOrder_WithTokens(marketId, orderAmount, IP_ADDRESS);

        // Mint liquidity tokens to the AP to fill the order
        mockLiquidityToken.mint(AP_ADDRESS, fillAmount);
        vm.startPrank(AP_ADDRESS);
        mockLiquidityToken.approve(address(orderbook), fillAmount);
        vm.stopPrank();

        // Record the logs to capture Transfer events to get Weiroll wallet address
        vm.recordLogs();
        // Fill the order
        vm.startPrank(AP_ADDRESS);
        orderbook.fillIPOrder(orderId, fillAmount, address(0), FRONTEND_FEE_RECIPIENT);
        vm.stopPrank();

        (,,, uint256 resultingQuantity, uint256 resultingRemainingQuantity) = orderbook.orderIDToIPOrder(orderId);
        assertEq(resultingRemainingQuantity, resultingQuantity - fillAmount);

        address weirollWallet = address(uint160(uint256(vm.getRecordedLogs()[0].topics[2])));

        (, uint256[] memory amounts,) = orderbook.getLockedRewardParams(weirollWallet);

        vm.startPrank(AP_ADDRESS);
        orderbook.forfeit(weirollWallet, false);
        vm.stopPrank();

        // Check the weiroll wallet was deleted from orderbook state
        (address[] memory resultingTokens, uint256[] memory resultingAmounts, address resultingIp) = orderbook.getLockedRewardParams(weirollWallet);
        assertEq(resultingTokens, new address[](0));
        assertEq(resultingAmounts, new uint256[](0));
        assertEq(resultingIp, address(0));
    }

    function test_Forfeit_PointIncentives() external {
        uint256 frontendFee = orderbook.minimumFrontendFee();
        uint256 marketId = orderbook.createMarket(address(mockLiquidityToken), 30 days, frontendFee, NULL_RECIPE, NULL_RECIPE, RewardStyle.Forfeitable);

        uint256 orderAmount = 100_000e18; // Order amount requested
        uint256 fillAmount = 1000e18; // Fill amount

        // Mint liquidity tokens to the AP to fill the order
        mockLiquidityToken.mint(AP_ADDRESS, fillAmount);
        vm.startPrank(AP_ADDRESS);
        mockLiquidityToken.approve(address(orderbook), fillAmount);
        vm.stopPrank();

        // Create a fillable IP order
        (uint256 orderId, Points points) = createIPOrder_WithPoints(marketId, orderAmount, IP_ADDRESS);

        (, uint256 expectedProtocolFeeAmount, uint256 expectedFrontendFeeAmount, uint256 expectedIncentiveAmount) =
            calculateIPOrderExpectedIncentiveAndFrontendFee(orderId, orderAmount, fillAmount, address(points));

        // Record the logs to capture Transfer events to get Weiroll wallet address
        vm.recordLogs();
        // Fill the order
        vm.startPrank(AP_ADDRESS);
        orderbook.fillIPOrder(orderId, fillAmount, address(0), FRONTEND_FEE_RECIPIENT);
        vm.stopPrank();

        (,,, uint256 resultingQuantity, uint256 resultingRemainingQuantity) = orderbook.orderIDToIPOrder(orderId);
        assertEq(resultingRemainingQuantity, resultingQuantity - fillAmount);

        // Extract the Weiroll wallet address (the 'to' address from the Transfer event - third event in logs)
        address weirollWallet = address(uint160(uint256(vm.getRecordedLogs()[0].topics[2])));

        (,,,, RecipeOrderbook.Recipe memory withdrawRecipe,) = orderbook.marketIDToWeirollMarket(marketId);
        vm.expectCall(
            weirollWallet, 0, abi.encodeWithSelector(WeirollWallet.executeWeiroll.selector, withdrawRecipe.weirollCommands, withdrawRecipe.weirollState)
        );

        vm.startPrank(AP_ADDRESS);
        orderbook.forfeit(weirollWallet, true);
        vm.stopPrank();

        (,,,, uint256 newResultingRemainingQuantity) = orderbook.orderIDToIPOrder(orderId);
        assertEq(newResultingRemainingQuantity, resultingQuantity);

        // Check the weiroll wallet was deleted from orderbook state
        (address[] memory resultingTokens, uint256[] memory resultingAmounts, address resultingIp) = orderbook.getLockedRewardParams(weirollWallet);
        assertEq(resultingTokens, new address[](0));
        assertEq(resultingAmounts, new uint256[](0));
        assertEq(resultingIp, address(0));
    }

    function test_Forfeit_PointIncentives_NoExecution() external {
        uint256 frontendFee = orderbook.minimumFrontendFee();
        uint256 marketId = orderbook.createMarket(address(mockLiquidityToken), 30 days, frontendFee, NULL_RECIPE, NULL_RECIPE, RewardStyle.Forfeitable);

        uint256 orderAmount = 100_000e18; // Order amount requested
        uint256 fillAmount = 1000e18; // Fill amount

        // Mint liquidity tokens to the AP to fill the order
        mockLiquidityToken.mint(AP_ADDRESS, fillAmount);
        vm.startPrank(AP_ADDRESS);
        mockLiquidityToken.approve(address(orderbook), fillAmount);
        vm.stopPrank();

        // Create a fillable IP order
        (uint256 orderId, Points points) = createIPOrder_WithPoints(marketId, orderAmount, IP_ADDRESS);

        // Record the logs to capture Transfer events to get Weiroll wallet address
        vm.recordLogs();
        // Fill the order
        vm.startPrank(AP_ADDRESS);
        orderbook.fillIPOrder(orderId, fillAmount, address(0), FRONTEND_FEE_RECIPIENT);
        vm.stopPrank();

        (,,, uint256 resultingQuantity, uint256 resultingRemainingQuantity) = orderbook.orderIDToIPOrder(orderId);
        assertEq(resultingRemainingQuantity, resultingQuantity - fillAmount);

        // Extract the Weiroll wallet address (the 'to' address from the Transfer event - third event in logs)
        address weirollWallet = address(uint160(uint256(vm.getRecordedLogs()[0].topics[2])));

        vm.startPrank(AP_ADDRESS);
        orderbook.forfeit(weirollWallet, false);
        vm.stopPrank();

        (,,,, uint256 newResultingRemainingQuantity) = orderbook.orderIDToIPOrder(orderId);
        assertEq(newResultingRemainingQuantity, resultingQuantity);

        // Check the weiroll wallet was deleted from orderbook state
        (address[] memory resultingTokens, uint256[] memory resultingAmounts, address resultingIp) = orderbook.getLockedRewardParams(weirollWallet);
        assertEq(resultingTokens, new address[](0));
        assertEq(resultingAmounts, new uint256[](0));
        assertEq(resultingIp, address(0));
    }

    function test_RevertIf_Forfeit_NonOwner() external {
        uint256 frontendFee = orderbook.minimumFrontendFee();
        uint256 marketId = orderbook.createMarket(address(mockLiquidityToken), 30 days, frontendFee, NULL_RECIPE, NULL_RECIPE, RewardStyle.Forfeitable);

        uint256 orderAmount = 100_000e18; // Order amount requested
        uint256 fillAmount = 1000e18; // Fill amount

        // Mint liquidity tokens to the AP to fill the order
        mockLiquidityToken.mint(AP_ADDRESS, fillAmount);
        vm.startPrank(AP_ADDRESS);
        mockLiquidityToken.approve(address(orderbook), fillAmount);
        vm.stopPrank();

        // Create a fillable IP order
        (uint256 orderId,) = createIPOrder_WithPoints(marketId, orderAmount, IP_ADDRESS);

        // Record the logs to capture Transfer events to get Weiroll wallet address
        vm.recordLogs();
        // Fill the order
        vm.startPrank(AP_ADDRESS);
        orderbook.fillIPOrder(orderId, fillAmount, address(0), FRONTEND_FEE_RECIPIENT);
        vm.stopPrank();

        // Extract the Weiroll wallet address (the 'to' address from the Transfer event - third event in logs)
        address weirollWallet = address(uint160(uint256(vm.getRecordedLogs()[0].topics[2])));

        vm.expectRevert(abi.encodeWithSelector(RecipeOrderbook.NotOwner.selector));
        vm.startPrank(IP_ADDRESS);
        orderbook.forfeit(weirollWallet, true);
        vm.stopPrank();
    }
}
