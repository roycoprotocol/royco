// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "src/base/RecipeOrderbookBase.sol";
import { RecipeOrderbookTestBase } from "../../utils/RecipeOrderbook/RecipeOrderbookTestBase.sol";

contract Test_ExecuteWithdrawalScript_RecipeOrderbook is RecipeOrderbookTestBase {
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

    function test_ExecuteWithdrawalScript() external {
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
        orderbook.fillIPOrders(orderId, fillAmount, address(0), FRONTEND_FEE_RECIPIENT);
        vm.stopPrank();

        address weirollWallet = address(uint160(uint256(vm.getRecordedLogs()[0].topics[2])));

        vm.warp(block.timestamp + 30 days); // fast forward to a time when the wallet is unlocked

        (,,,, RecipeOrderbookBase.Recipe memory withdrawRecipe,) = orderbook.marketIDToWeirollMarket(marketId);
        vm.expectCall(
            weirollWallet, 0, abi.encodeWithSelector(WeirollWallet.executeWeiroll.selector, withdrawRecipe.weirollCommands, withdrawRecipe.weirollState)
        );

        vm.startPrank(AP_ADDRESS);
        orderbook.executeWithdrawalScript(weirollWallet);
        vm.stopPrank();
    }

    function test_RevertIf_ExecuteWithdrawalScript_WithWalletLocked() external {
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
        orderbook.fillIPOrders(orderId, fillAmount, address(0), FRONTEND_FEE_RECIPIENT);
        vm.stopPrank();

        address weirollWallet = address(uint160(uint256(vm.getRecordedLogs()[0].topics[2])));

        vm.expectRevert(abi.encodeWithSelector(RecipeOrderbookBase.WalletLocked.selector));

        vm.startPrank(AP_ADDRESS);
        orderbook.executeWithdrawalScript(weirollWallet);
        vm.stopPrank();
    }

    function test_RevertIf_ExecuteWithdrawalScript_NonOwner() external {
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
        orderbook.fillIPOrders(orderId, fillAmount, address(0), FRONTEND_FEE_RECIPIENT);
        vm.stopPrank();

        address weirollWallet = address(uint160(uint256(vm.getRecordedLogs()[0].topics[2])));

        vm.expectRevert(abi.encodeWithSelector(RecipeOrderbookBase.NotOwner.selector));

        vm.startPrank(IP_ADDRESS);
        orderbook.executeWithdrawalScript(weirollWallet);
        vm.stopPrank();
    }
}
