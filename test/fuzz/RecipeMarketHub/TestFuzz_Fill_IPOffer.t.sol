// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "src/base/RecipeMarketHubBase.sol";
import "src/WrappedVault.sol";

import { MockERC20, ERC20 } from "../../mocks/MockERC20.sol";
import { MockERC4626 } from "test/mocks/MockERC4626.sol";
import { RecipeMarketHubTestBase } from "../../utils/RecipeMarketHub/RecipeMarketHubTestBase.sol";
import { FixedPointMathLib } from "lib/solmate/src/utils/FixedPointMathLib.sol";

contract TestFuzz_Fill_IPOffer_RecipeMarketHub is RecipeMarketHubTestBase {
    using FixedPointMathLib for uint256;

    address IP_ADDRESS;
    address FRONTEND_FEE_RECIPIENT;

    function setUp() external {
        uint256 protocolFee = 0.01e18; // 1% protocol fee
        uint256 minimumFrontendFee = 0.001e18; // 0.1% minimum frontend fee
        setUpRecipeMarketHubTests(protocolFee, minimumFrontendFee);

        IP_ADDRESS = ALICE_ADDRESS;
        FRONTEND_FEE_RECIPIENT = CHARLIE_ADDRESS;
    }

    function testFuzz_DirectFill_Upfront_IPOffer_ForTokens(uint256 offerAmount, uint256 fillAmount) external {
        offerAmount = bound(offerAmount, 1e6, 1e30);
        fillAmount = bound(fillAmount, 1e6, offerAmount);

        uint256 frontendFee = recipeMarketHub.minimumFrontendFee();
        bytes32 marketHash = recipeMarketHub.createMarket(address(mockLiquidityToken), 30 days, frontendFee, NULL_RECIPE, NULL_RECIPE, RewardStyle.Upfront);

        // Create a fillable IP offer
        bytes32 offerHash = createIPOffer_WithTokens(marketHash, offerAmount, IP_ADDRESS);

        // Mint liquidity tokens to the AP to fill the offer
        mockLiquidityToken.mint(BOB_ADDRESS, fillAmount);
        vm.startPrank(BOB_ADDRESS);
        mockLiquidityToken.approve(address(recipeMarketHub), fillAmount);
        vm.stopPrank();

        (, uint256 expectedProtocolFeeAmount, uint256 expectedFrontendFeeAmount, uint256 expectedIncentiveAmount) =
            calculateIPOfferExpectedIncentiveAndFrontendFee(offerHash, offerAmount, fillAmount, address(mockIncentiveToken));

        // Expect events for transfers
        vm.expectEmit(true, true, false, true, address(mockIncentiveToken));
        emit ERC20.Transfer(address(recipeMarketHub), BOB_ADDRESS, expectedIncentiveAmount);

        vm.expectEmit(true, false, false, true, address(mockLiquidityToken));
        emit ERC20.Transfer(BOB_ADDRESS, address(0), fillAmount);

        vm.expectEmit(false, false, false, false, address(recipeMarketHub));
        emit RecipeMarketHubBase.IPOfferFilled(0, address(0), 0, address(0), new uint256[](0), new uint256[](0), new uint256[](0));

        // Record logs to capture Transfer events to get Weiroll wallet address
        vm.recordLogs();
        // Fill the offer
        vm.startPrank(BOB_ADDRESS);
        recipeMarketHub.fillIPOffers(offerHash, fillAmount, address(0), FRONTEND_FEE_RECIPIENT);
        vm.stopPrank();

        (,,,, uint256 resultingQuantity, uint256 resultingRemainingQuantity) = recipeMarketHub.offerHashToIPOffer(offerHash);
        assertEq(resultingRemainingQuantity, resultingQuantity - fillAmount);

        // Extract the Weiroll wallet address
        address weirollWallet = address(uint160(uint256(vm.getRecordedLogs()[1].topics[2])));
        assertGt(weirollWallet.code.length, 0); // Ensure weirollWallet is valid

        // Ensure AP received the correct incentive amount
        assertEq(mockIncentiveToken.balanceOf(BOB_ADDRESS), expectedIncentiveAmount);

        // Ensure weiroll wallet got the liquidity
        assertEq(mockLiquidityToken.balanceOf(weirollWallet), fillAmount);

        // Check frontend fee recipient received correct fee
        assertEq(recipeMarketHub.feeClaimantToTokenToAmount(FRONTEND_FEE_RECIPIENT, address(mockIncentiveToken)), expectedFrontendFeeAmount);

        // Check the protocol fee recipient received the correct fee
        assertEq(recipeMarketHub.feeClaimantToTokenToAmount(OWNER_ADDRESS, address(mockIncentiveToken)), expectedProtocolFeeAmount);
    }

    function testFuzz_DirectFill_Upfront_IPOffer_ForPoints(uint256 offerAmount, uint256 fillAmount) external {
        offerAmount = bound(offerAmount, 1e6, 1e30);
        fillAmount = bound(fillAmount, 1e6, offerAmount);

        uint256 frontendFee = recipeMarketHub.minimumFrontendFee();
        bytes32 marketHash = recipeMarketHub.createMarket(address(mockLiquidityToken), 30 days, frontendFee, NULL_RECIPE, NULL_RECIPE, RewardStyle.Upfront);

        // Mint liquidity tokens to the AP to fill the offer
        mockLiquidityToken.mint(BOB_ADDRESS, fillAmount);
        vm.startPrank(BOB_ADDRESS);
        mockLiquidityToken.approve(address(recipeMarketHub), fillAmount);
        vm.stopPrank();

        // Create a fillable IP offer
        (bytes32 offerHash, Points points) = createIPOffer_WithPoints(marketHash, offerAmount, IP_ADDRESS);

        (, uint256 expectedProtocolFeeAmount, uint256 expectedFrontendFeeAmount, uint256 expectedIncentiveAmount) =
            calculateIPOfferExpectedIncentiveAndFrontendFee(offerHash, offerAmount, fillAmount, address(points));

        // Expect events for transfers
        vm.expectEmit(true, true, false, true, address(points));
        emit Points.Award(OWNER_ADDRESS, expectedProtocolFeeAmount, IP_ADDRESS);

        vm.expectEmit(true, true, false, true, address(points));
        emit Points.Award(FRONTEND_FEE_RECIPIENT, expectedFrontendFeeAmount, IP_ADDRESS);

        // Expect events for transfers
        vm.expectEmit(true, true, false, true, address(points));
        emit Points.Award(BOB_ADDRESS, expectedIncentiveAmount, IP_ADDRESS);

        vm.expectEmit(true, false, false, true, address(mockLiquidityToken));
        emit ERC20.Transfer(BOB_ADDRESS, address(0), fillAmount);

        vm.expectEmit(false, false, false, false, address(recipeMarketHub));
        emit RecipeMarketHubBase.IPOfferFilled(0, address(0), 0, address(0), new uint256[](0), new uint256[](0), new uint256[](0));

        // Record logs to capture Transfer events to get Weiroll wallet address
        vm.recordLogs();
        // Fill the offer
        vm.startPrank(BOB_ADDRESS);
        recipeMarketHub.fillIPOffers(offerHash, fillAmount, address(0), FRONTEND_FEE_RECIPIENT);
        vm.stopPrank();

        (,,,, uint256 resultingQuantity, uint256 resultingRemainingQuantity) = recipeMarketHub.offerHashToIPOffer(offerHash);
        assertEq(resultingRemainingQuantity, resultingQuantity - fillAmount);

        // Extract the Weiroll wallet address
        address weirollWallet = address(uint160(uint256(vm.getRecordedLogs()[3].topics[2])));
        assertGt(weirollWallet.code.length, 0); // Ensure weirollWallet is valid

        // Ensure weiroll wallet got the liquidity
        assertEq(mockLiquidityToken.balanceOf(weirollWallet), fillAmount);
    }

    function testFuzz_RevertIf_OfferExpired(uint256 offerAmount, uint256 fillAmount, uint256 timeDelta) external {
        offerAmount = bound(offerAmount, 1e6, 1e30);
        fillAmount = bound(fillAmount, 1e6, offerAmount);
        timeDelta = bound(timeDelta, 30 days + 1, 365 days);

        uint256 frontendFee = recipeMarketHub.minimumFrontendFee();
        bytes32 marketHash = recipeMarketHub.createMarket(address(mockLiquidityToken), 30 days, frontendFee, NULL_RECIPE, NULL_RECIPE, RewardStyle.Upfront);

        // Create an offer with the specified amount
        bytes32 offerHash = createIPOffer_WithTokens(marketHash, offerAmount, IP_ADDRESS);

        // Warp to time beyond the expiry
        vm.warp(block.timestamp + timeDelta);

        // Expect revert due to offer expiration
        vm.expectRevert(RecipeMarketHubBase.OfferExpired.selector);
        recipeMarketHub.fillIPOffers(offerHash, fillAmount, address(0), FRONTEND_FEE_RECIPIENT);
    }

    function testFuzz_RevertIf_NotEnoughRemainingQuantity(uint256 offerAmount, uint256 fillAmount) external {
        offerAmount = bound(offerAmount, 1e18, 1e30);
        fillAmount = offerAmount + bound(fillAmount, 1, 100e18); // Fill amount exceeds offerAmount

        uint256 frontendFee = recipeMarketHub.minimumFrontendFee();
        bytes32 marketHash = recipeMarketHub.createMarket(address(mockLiquidityToken), 30 days, frontendFee, NULL_RECIPE, NULL_RECIPE, RewardStyle.Upfront);

        // Create a fillable IP offer
        bytes32 offerHash = createIPOffer_WithTokens(marketHash, offerAmount, IP_ADDRESS);

        // Expect revert due to insufficient remaining quantity
        vm.expectRevert(RecipeMarketHubBase.NotEnoughRemainingQuantity.selector);
        recipeMarketHub.fillIPOffers(offerHash, fillAmount, address(0), FRONTEND_FEE_RECIPIENT);
    }

    function testFuzz_RevertIf_MismatchedBaseAsset(uint256 offerAmount, uint256 fillAmount) external {
        offerAmount = bound(offerAmount, 1e6, 1e30);
        fillAmount = bound(fillAmount, 1e6, offerAmount);

        uint256 frontendFee = recipeMarketHub.minimumFrontendFee();
        bytes32 marketHash = recipeMarketHub.createMarket(address(mockLiquidityToken), 30 days, frontendFee, NULL_RECIPE, NULL_RECIPE, RewardStyle.Upfront);

        // Create a fillable IP offer
        bytes32 offerHash = createIPOffer_WithTokens(marketHash, offerAmount, IP_ADDRESS);

        // Use a different vault with a mismatched base asset
        address incorrectVault = address(new MockERC4626(mockIncentiveToken)); // Mismatched asset

        // Expect revert due to mismatched base asset
        vm.expectRevert(RecipeMarketHubBase.MismatchedBaseAsset.selector);
        recipeMarketHub.fillIPOffers(offerHash, fillAmount, incorrectVault, FRONTEND_FEE_RECIPIENT);
    }

    function testFuzz_RevertIf_ZeroQuantityFill(uint256 offerAmount) external {
        offerAmount = bound(offerAmount, 1e6, 1e30);

        uint256 frontendFee = recipeMarketHub.minimumFrontendFee();
        bytes32 marketHash = recipeMarketHub.createMarket(address(mockLiquidityToken), 30 days, frontendFee, NULL_RECIPE, NULL_RECIPE, RewardStyle.Upfront);

        // Create a fillable IP offer
        bytes32 offerHash = createIPOffer_WithTokens(marketHash, offerAmount, IP_ADDRESS);

        // Expect revert due to zero quantity fill
        vm.expectRevert(RecipeMarketHubBase.CannotPlaceZeroQuantityOffer.selector);
        recipeMarketHub.fillIPOffers(offerHash, 0, address(0), FRONTEND_FEE_RECIPIENT);
    }
}
