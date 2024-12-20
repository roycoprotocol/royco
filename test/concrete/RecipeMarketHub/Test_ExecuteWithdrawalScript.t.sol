// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "src/base/RecipeMarketHubBase.sol";
import { RecipeMarketHubTestBase } from "../../utils/RecipeMarketHub/RecipeMarketHubTestBase.sol";

contract Test_ExecuteWithdrawalScript_RecipeMarketHub is RecipeMarketHubTestBase {
    address IP_ADDRESS;
    address AP_ADDRESS;
    address FRONTEND_FEE_RECIPIENT;

    function setUp() external {
        uint256 protocolFee = 0.01e18; // 1% protocol fee
        uint256 minimumFrontendFee = 0.001e18; // 0.1% minimum frontend fee
        setUpRecipeMarketHubTests(protocolFee, minimumFrontendFee);

        IP_ADDRESS = ALICE_ADDRESS;
        AP_ADDRESS = BOB_ADDRESS;
        FRONTEND_FEE_RECIPIENT = CHARLIE_ADDRESS;
    }

    function test_ExecuteWithdrawalScript() external {
        uint256 frontendFee = recipeMarketHub.minimumFrontendFee();
        bytes32 marketHash = recipeMarketHub.createMarket(address(mockLiquidityToken), 30 days, frontendFee, NULL_RECIPE, NULL_RECIPE, RewardStyle.Forfeitable);

        uint256 offerAmount = 100_000e18; // Offer amount requested
        uint256 fillAmount = 1000e18; // Fill amount

        // Create a fillable IP offer
        bytes32 offerHash = createIPOffer_WithTokens(marketHash, offerAmount, IP_ADDRESS);

        // Mint liquidity tokens to the AP to fill the offer
        mockLiquidityToken.mint(AP_ADDRESS, fillAmount);
        vm.startPrank(AP_ADDRESS);
        mockLiquidityToken.approve(address(recipeMarketHub), fillAmount);
        vm.stopPrank();

        // Record the logs to capture Transfer events to get Weiroll wallet address
        vm.recordLogs();
        // Fill the offer
        vm.startPrank(AP_ADDRESS);
        recipeMarketHub.fillIPOffers(offerHash, fillAmount, address(0), FRONTEND_FEE_RECIPIENT);
        vm.stopPrank();

        address weirollWallet = address(uint160(uint256(vm.getRecordedLogs()[0].topics[2])));

        vm.warp(block.timestamp + 30 days); // fast forward to a time when the wallet is unlocked

        (,,,,, RecipeMarketHubBase.Recipe memory withdrawRecipe,) = recipeMarketHub.marketHashToWeirollMarket(marketHash);
        vm.expectCall(
            weirollWallet, 0, abi.encodeWithSelector(WeirollWallet.executeWeiroll.selector, withdrawRecipe.weirollCommands, withdrawRecipe.weirollState)
        );

        vm.startPrank(AP_ADDRESS);
        recipeMarketHub.executeWithdrawalScript(weirollWallet);
        vm.stopPrank();
    }

    function test_RevertIf_ExecuteWithdrawalScript_WithWalletLocked() external {
        uint256 frontendFee = recipeMarketHub.minimumFrontendFee();
        bytes32 marketHash = recipeMarketHub.createMarket(address(mockLiquidityToken), 30 days, frontendFee, NULL_RECIPE, NULL_RECIPE, RewardStyle.Forfeitable);

        uint256 offerAmount = 100_000e18; // Offer amount requested
        uint256 fillAmount = 1000e18; // Fill amount

        // Create a fillable IP offer
        bytes32 offerHash = createIPOffer_WithTokens(marketHash, offerAmount, IP_ADDRESS);

        // Mint liquidity tokens to the AP to fill the offer
        mockLiquidityToken.mint(AP_ADDRESS, fillAmount);
        vm.startPrank(AP_ADDRESS);
        mockLiquidityToken.approve(address(recipeMarketHub), fillAmount);
        vm.stopPrank();

        // Record the logs to capture Transfer events to get Weiroll wallet address
        vm.recordLogs();
        // Fill the offer
        vm.startPrank(AP_ADDRESS);
        recipeMarketHub.fillIPOffers(offerHash, fillAmount, address(0), FRONTEND_FEE_RECIPIENT);
        vm.stopPrank();

        address weirollWallet = address(uint160(uint256(vm.getRecordedLogs()[0].topics[2])));

        vm.expectRevert(abi.encodeWithSelector(RecipeMarketHubBase.WalletLocked.selector));

        vm.startPrank(AP_ADDRESS);
        recipeMarketHub.executeWithdrawalScript(weirollWallet);
        vm.stopPrank();
    }

    function test_RevertIf_ExecuteWithdrawalScript_NonOwner() external {
        uint256 frontendFee = recipeMarketHub.minimumFrontendFee();
        bytes32 marketHash = recipeMarketHub.createMarket(address(mockLiquidityToken), 30 days, frontendFee, NULL_RECIPE, NULL_RECIPE, RewardStyle.Forfeitable);

        uint256 offerAmount = 100_000e18; // Offer amount requested
        uint256 fillAmount = 1000e18; // Fill amount

        // Create a fillable IP offer
        bytes32 offerHash = createIPOffer_WithTokens(marketHash, offerAmount, IP_ADDRESS);

        // Mint liquidity tokens to the AP to fill the offer
        mockLiquidityToken.mint(AP_ADDRESS, fillAmount);
        vm.startPrank(AP_ADDRESS);
        mockLiquidityToken.approve(address(recipeMarketHub), fillAmount);
        vm.stopPrank();

        // Record the logs to capture Transfer events to get Weiroll wallet address
        vm.recordLogs();
        // Fill the offer
        vm.startPrank(AP_ADDRESS);
        recipeMarketHub.fillIPOffers(offerHash, fillAmount, address(0), FRONTEND_FEE_RECIPIENT);
        vm.stopPrank();

        address weirollWallet = address(uint160(uint256(vm.getRecordedLogs()[0].topics[2])));

        vm.expectRevert(abi.encodeWithSelector(RecipeMarketHubBase.NotOwner.selector));

        vm.startPrank(IP_ADDRESS);
        recipeMarketHub.executeWithdrawalScript(weirollWallet);
        vm.stopPrank();
    }
}
