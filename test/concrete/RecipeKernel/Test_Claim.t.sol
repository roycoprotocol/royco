// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "src/base/RecipeKernelBase.sol";
import {Points} from "src/Points.sol";
import { RecipeKernelTestBase } from "../../utils/RecipeKernel/RecipeKernelTestBase.sol";

contract Test_Claim_RecipeKernel is RecipeKernelTestBase {
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

    function test_Claim_TokenIncentives() external {
        uint256 frontendFee = recipeKernel.minimumFrontendFee();
        uint256 marketId = recipeKernel.createMarket(address(mockLiquidityToken), 30 days, frontendFee, NULL_RECIPE, NULL_RECIPE, RewardStyle.Forfeitable);

        uint256 offerAmount = 100000e18; // Offer amount requested
        uint256 fillAmount = 1000e18; // Fill amount

        // Create a fillable IP offer
        bytes32 offerHash = createIPOffer_WithTokens(marketId, offerAmount, IP_ADDRESS);

        // Mint liquidity tokens to the AP to fill the offer
        mockLiquidityToken.mint(AP_ADDRESS, fillAmount);
        vm.startPrank(AP_ADDRESS);
        mockLiquidityToken.approve(address(recipeKernel), fillAmount);
        vm.stopPrank();

        // Record the logs to capture Transfer events to get Weiroll wallet address
        vm.recordLogs();
        // Fill the offer
        vm.startPrank(AP_ADDRESS);
        recipeKernel.fillIPOffers(offerHash, fillAmount, address(0), FRONTEND_FEE_RECIPIENT);
        vm.stopPrank();

        (,,,, uint256 resultingQuantity, uint256 resultingRemainingQuantity) = recipeKernel.offerHashToIPOffer(offerHash);
        assertEq(resultingRemainingQuantity, resultingQuantity - fillAmount);

        address weirollWallet = address(uint160(uint256(vm.getRecordedLogs()[0].topics[2])));

        (, uint256[] memory amounts,) = recipeKernel.getLockedIncentiveParams(weirollWallet);

        vm.expectEmit(true, true, false, true, address(mockIncentiveToken));
        emit ERC20.Transfer(address(recipeKernel), AP_ADDRESS, amounts[0]);

        vm.warp(block.timestamp + 30 days); // make rewards claimable
        vm.startPrank(AP_ADDRESS);
        recipeKernel.claim(weirollWallet, AP_ADDRESS);
        vm.stopPrank();

        // Check the weiroll wallet was deleted from recipeKernel state
        (address[] memory resultingTokens, uint256[] memory resultingAmounts, address resultingIp) = recipeKernel.getLockedIncentiveParams(weirollWallet);
        assertEq(resultingTokens, new address[](0));
        assertEq(resultingAmounts, new uint256[](0));
        assertEq(resultingIp, address(0));
    }

    function test_Claim_PointIncentives() external {
        uint256 frontendFee = recipeKernel.minimumFrontendFee();
        uint256 marketId = recipeKernel.createMarket(address(mockLiquidityToken), 30 days, frontendFee, NULL_RECIPE, NULL_RECIPE, RewardStyle.Forfeitable);

        uint256 offerAmount = 100000e18; // Offer amount requested
        uint256 fillAmount = 1000e18; // Fill amount

        // Mint liquidity tokens to the AP to fill the offer
        mockLiquidityToken.mint(AP_ADDRESS, fillAmount);
        vm.startPrank(AP_ADDRESS);
        mockLiquidityToken.approve(address(recipeKernel), fillAmount);
        vm.stopPrank();

        // Create a fillable IP offer
        (bytes32 offerHash, Points points) = createIPOffer_WithPoints(marketId, offerAmount, IP_ADDRESS);

        // Record the logs to capture Transfer events to get Weiroll wallet address
        vm.recordLogs();
        // Fill the offer
        vm.startPrank(AP_ADDRESS);
        recipeKernel.fillIPOffers(offerHash, fillAmount, address(0), FRONTEND_FEE_RECIPIENT);
        vm.stopPrank();

        // Extract the Weiroll wallet address (the 'to' address from the Transfer event - first event in logs)
        address weirollWallet = address(uint160(uint256(vm.getRecordedLogs()[0].topics[2])));

        (, uint256[] memory amounts,) = recipeKernel.getLockedIncentiveParams(weirollWallet);

        vm.expectEmit(true, true, false, true, address(points));
        emit Points.Award(AP_ADDRESS, amounts[0], IP_ADDRESS);

        vm.warp(block.timestamp + 30 days); // make rewards claimable
        vm.startPrank(AP_ADDRESS);
        recipeKernel.claim(weirollWallet, AP_ADDRESS);
        vm.stopPrank();

        // Check the weiroll wallet was deleted from recipeKernel state
        (address[] memory resultingTokens, uint256[] memory resultingAmounts, address resultingIp) = recipeKernel.getLockedIncentiveParams(weirollWallet);
        assertEq(resultingTokens, new address[](0));
        assertEq(resultingAmounts, new uint256[](0));
        assertEq(resultingIp, address(0));
    }

    function test_RevertIf_Claim_NonOwner() external {
        uint256 frontendFee = recipeKernel.minimumFrontendFee();
        uint256 marketId = recipeKernel.createMarket(address(mockLiquidityToken), 30 days, frontendFee, NULL_RECIPE, NULL_RECIPE, RewardStyle.Forfeitable);

        uint256 offerAmount = 100000e18; // Offer amount requested
        uint256 fillAmount = 1000e18; // Fill amount

        // Mint liquidity tokens to the AP to fill the offer
        mockLiquidityToken.mint(AP_ADDRESS, fillAmount);
        vm.startPrank(AP_ADDRESS);
        mockLiquidityToken.approve(address(recipeKernel), fillAmount);
        vm.stopPrank();

        // Create a fillable IP offer
        (bytes32 offerHash,) = createIPOffer_WithPoints(marketId, offerAmount, IP_ADDRESS);

        // Record the logs to capture Transfer events to get Weiroll wallet address
        vm.recordLogs();
        // Fill the offer
        vm.startPrank(AP_ADDRESS);
        recipeKernel.fillIPOffers(offerHash, fillAmount, address(0), FRONTEND_FEE_RECIPIENT);
        vm.stopPrank();

        // Extract the Weiroll wallet address (the 'to' address from the Transfer event - third event in logs)
        address weirollWallet = address(uint160(uint256(vm.getRecordedLogs()[0].topics[2])));

        vm.expectRevert(abi.encodeWithSelector(RecipeKernelBase.NotOwner.selector));
        vm.startPrank(IP_ADDRESS);
        recipeKernel.claim(weirollWallet, IP_ADDRESS);
        vm.stopPrank();
    }

    function test_RevertIf_Claim_LockedIncentives() external {
        uint256 frontendFee = recipeKernel.minimumFrontendFee();
        uint256 marketId = recipeKernel.createMarket(address(mockLiquidityToken), 30 days, frontendFee, NULL_RECIPE, NULL_RECIPE, RewardStyle.Forfeitable);

        uint256 offerAmount = 100000e18; // Offer amount requested
        uint256 fillAmount = 1000e18; // Fill amount

        // Mint liquidity tokens to the AP to fill the offer
        mockLiquidityToken.mint(AP_ADDRESS, fillAmount);
        vm.startPrank(AP_ADDRESS);
        mockLiquidityToken.approve(address(recipeKernel), fillAmount);
        vm.stopPrank();

        // Create a fillable IP offer
        (bytes32 offerHash,) = createIPOffer_WithPoints(marketId, offerAmount, IP_ADDRESS);

        // Record the logs to capture Transfer events to get Weiroll wallet address
        vm.recordLogs();
        // Fill the offer
        vm.startPrank(AP_ADDRESS);
        recipeKernel.fillIPOffers(offerHash, fillAmount, address(0), FRONTEND_FEE_RECIPIENT);
        vm.stopPrank();

        // Extract the Weiroll wallet address (the 'to' address from the Transfer event - first event in logs)
        address weirollWallet = address(uint160(uint256(vm.getRecordedLogs()[0].topics[2])));

        vm.expectRevert(abi.encodeWithSelector(RecipeKernelBase.WalletLocked.selector));
        vm.startPrank(AP_ADDRESS);
        recipeKernel.claim(weirollWallet, AP_ADDRESS);
        vm.stopPrank();
    }
}
