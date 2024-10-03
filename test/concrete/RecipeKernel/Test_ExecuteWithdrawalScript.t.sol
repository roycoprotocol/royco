// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "src/base/RecipeKernelBase.sol";
import { RecipeKernelTestBase } from "../../utils/RecipeKernel/RecipeKernelTestBase.sol";

contract Test_ExecuteWithdrawalScript_RecipeKernel is RecipeKernelTestBase {
    address IP_ADDRESS;
    address AP_ADDRESS;
    address FRONTEND_FEE_RECIPIENT;

    function setUp() external {
        uint256 protocolFee = 0.01e18; // 1% protocol fee
        uint256 minimumFrontendFee = 0.001e18; // 0.1% minimum frontend fee
        setUpRecipeKernelTests(protocolFee, minimumFrontendFee);

        IP_ADDRESS = ALICE_ADDRESS;
        AP_ADDRESS = BOB_ADDRESS;
        FRONTEND_FEE_RECIPIENT = CHARLIE_ADDRESS;
    }

    function test_ExecuteWithdrawalScript() external {
        uint256 frontendFee = recipeKernel.minimumFrontendFee();
        uint256 marketId = recipeKernel.createMarket(address(mockLiquidityToken), 30 days, frontendFee, NULL_RECIPE, NULL_RECIPE, RewardStyle.Forfeitable);

        uint256 offerAmount = 100_000e18; // Offer amount requested
        uint256 fillAmount = 1000e18; // Fill amount

        // Create a fillable IP offer
        uint256 offerId = createIPOffer_WithTokens(marketId, offerAmount, IP_ADDRESS);

        // Mint liquidity tokens to the AP to fill the offer
        mockLiquidityToken.mint(AP_ADDRESS, fillAmount);
        vm.startPrank(AP_ADDRESS);
        mockLiquidityToken.approve(address(recipeKernel), fillAmount);
        vm.stopPrank();

        // Record the logs to capture Transfer events to get Weiroll wallet address
        vm.recordLogs();
        // Fill the offer
        vm.startPrank(AP_ADDRESS);
        recipeKernel.fillIPOffers(offerId, fillAmount, address(0), FRONTEND_FEE_RECIPIENT);
        vm.stopPrank();

        address weirollWallet = address(uint160(uint256(vm.getRecordedLogs()[0].topics[2])));

        vm.warp(block.timestamp + 30 days); // fast forward to a time when the wallet is unlocked

        (,,,, RecipeKernelBase.Recipe memory withdrawRecipe,) = recipeKernel.marketIDToWeirollMarket(marketId);
        vm.expectCall(
            weirollWallet, 0, abi.encodeWithSelector(WeirollWallet.executeWeiroll.selector, withdrawRecipe.weirollCommands, withdrawRecipe.weirollState)
        );

        vm.startPrank(AP_ADDRESS);
        recipeKernel.executeWithdrawalScript(weirollWallet);
        vm.stopPrank();
    }

    function test_RevertIf_ExecuteWithdrawalScript_WithWalletLocked() external {
        uint256 frontendFee = recipeKernel.minimumFrontendFee();
        uint256 marketId = recipeKernel.createMarket(address(mockLiquidityToken), 30 days, frontendFee, NULL_RECIPE, NULL_RECIPE, RewardStyle.Forfeitable);

        uint256 offerAmount = 100_000e18; // Offer amount requested
        uint256 fillAmount = 1000e18; // Fill amount

        // Create a fillable IP offer
        uint256 offerId = createIPOffer_WithTokens(marketId, offerAmount, IP_ADDRESS);

        // Mint liquidity tokens to the AP to fill the offer
        mockLiquidityToken.mint(AP_ADDRESS, fillAmount);
        vm.startPrank(AP_ADDRESS);
        mockLiquidityToken.approve(address(recipeKernel), fillAmount);
        vm.stopPrank();

        // Record the logs to capture Transfer events to get Weiroll wallet address
        vm.recordLogs();
        // Fill the offer
        vm.startPrank(AP_ADDRESS);
        recipeKernel.fillIPOffers(offerId, fillAmount, address(0), FRONTEND_FEE_RECIPIENT);
        vm.stopPrank();

        address weirollWallet = address(uint160(uint256(vm.getRecordedLogs()[0].topics[2])));

        vm.expectRevert(abi.encodeWithSelector(RecipeKernelBase.WalletLocked.selector));

        vm.startPrank(AP_ADDRESS);
        recipeKernel.executeWithdrawalScript(weirollWallet);
        vm.stopPrank();
    }

    function test_RevertIf_ExecuteWithdrawalScript_NonOwner() external {
        uint256 frontendFee = recipeKernel.minimumFrontendFee();
        uint256 marketId = recipeKernel.createMarket(address(mockLiquidityToken), 30 days, frontendFee, NULL_RECIPE, NULL_RECIPE, RewardStyle.Forfeitable);

        uint256 offerAmount = 100_000e18; // Offer amount requested
        uint256 fillAmount = 1000e18; // Fill amount

        // Create a fillable IP offer
        uint256 offerId = createIPOffer_WithTokens(marketId, offerAmount, IP_ADDRESS);

        // Mint liquidity tokens to the AP to fill the offer
        mockLiquidityToken.mint(AP_ADDRESS, fillAmount);
        vm.startPrank(AP_ADDRESS);
        mockLiquidityToken.approve(address(recipeKernel), fillAmount);
        vm.stopPrank();

        // Record the logs to capture Transfer events to get Weiroll wallet address
        vm.recordLogs();
        // Fill the offer
        vm.startPrank(AP_ADDRESS);
        recipeKernel.fillIPOffers(offerId, fillAmount, address(0), FRONTEND_FEE_RECIPIENT);
        vm.stopPrank();

        address weirollWallet = address(uint160(uint256(vm.getRecordedLogs()[0].topics[2])));

        vm.expectRevert(abi.encodeWithSelector(RecipeKernelBase.NotOwner.selector));

        vm.startPrank(IP_ADDRESS);
        recipeKernel.executeWithdrawalScript(weirollWallet);
        vm.stopPrank();
    }
}
