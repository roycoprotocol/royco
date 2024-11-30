// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "lib/forge-std/src/console.sol";

import "src/base/RecipeMarketHubBase.sol";
import "src/WrappedVault.sol";

import { MockERC20, ERC20 } from "../../mocks/MockERC20.sol";
import { MockERC4626 } from "test/mocks/MockERC4626.sol";
import { ERC4626 } from "src/RecipeMarketHub.sol";
import { RecipeMarketHubTestBase } from "../../utils/RecipeMarketHub/RecipeMarketHubTestBase.sol";
import { FixedPointMathLib } from "lib/solmate/src/utils/FixedPointMathLib.sol";

contract Test_Fill_IPOffer_RecipeMarketHub is RecipeMarketHubTestBase {
    using FixedPointMathLib for uint256;

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

    function test_DirectFill_Upfront_IPOffer_ForTokens() external {
        uint256 frontendFee = recipeMarketHub.minimumFrontendFee();
        bytes32 marketHash = recipeMarketHub.createMarket(address(mockLiquidityToken), 30 days, frontendFee, NULL_RECIPE, NULL_RECIPE, RewardStyle.Upfront);
        console.log("===========RecipeMarket Created===========");
        console.log("inputToken:", address(mockLiquidityToken));
        console.log("Market created:", vm.toString(marketHash));

        uint256 offerAmount = 100_000e18; // Offer amount requested
        uint256 fillAmount = 1000e18; // Fill amount

        // Create a fillable IP offer
        bytes32 offerHash = createIPOffer_WithTokens(marketHash, offerAmount, IP_ADDRESS);
        console.log("===========IP GDA Offer Created===========");
        console.log("marketHash:", vm.toString(marketHash));
        console.log("offerAmount:", offerAmount);
        console.log("IP address:", AP_ADDRESS);

        // Mint liquidity tokens to the AP to fill the offer
        mockLiquidityToken.mint(AP_ADDRESS, fillAmount);
        vm.startPrank(AP_ADDRESS);
        mockLiquidityToken.approve(address(recipeMarketHub), fillAmount);
        vm.stopPrank();

        (, uint256 expectedProtocolFeeAmount, uint256 expectedFrontendFeeAmount, uint256 expectedIncentiveAmount) =
            calculateIPOfferExpectedIncentiveAndFrontendFee(offerHash, offerAmount, fillAmount, address(mockIncentiveToken));

        // Expect events for transfers
        vm.expectEmit(true, true, false, true, address(mockIncentiveToken));
        emit ERC20.Transfer(address(recipeMarketHub), AP_ADDRESS, expectedIncentiveAmount);

        vm.expectEmit(true, false, false, true, address(mockLiquidityToken));
        emit ERC20.Transfer(AP_ADDRESS, address(0), fillAmount);

        vm.expectEmit(false, false, false, false, address(recipeMarketHub));
        emit RecipeMarketHubBase.IPOfferFilled(0, 0, address(0), new uint256[](0), new uint256[](0), new uint256[](0));

        // Record the logs to capture Transfer events to get Weiroll wallet address
        vm.recordLogs();
        // Fill the offer
        vm.startPrank(AP_ADDRESS);
        recipeMarketHub.fillIPOffers(offerHash, fillAmount, address(0), FRONTEND_FEE_RECIPIENT);
        vm.stopPrank();

        (,,,, uint256 resultingQuantity, uint256 resultingRemainingQuantity) = recipeMarketHub.offerHashToIPOffer(offerHash);
        assertEq(resultingRemainingQuantity, resultingQuantity - fillAmount);

        // Extract the Weiroll wallet address (the 'to' address from the second Transfer event)
        address weirollWallet = address(uint160(uint256(vm.getRecordedLogs()[1].topics[2])));

        // Ensure there is a weirollWallet at the expected address
        assertGt(weirollWallet.code.length, 0);

        // Ensure that the deposit recipe was executed
        assertEq(WeirollWallet(payable(weirollWallet)).executed(), true);

        // Ensure the AP received the correct incentive amount
        assertEq(mockIncentiveToken.balanceOf(AP_ADDRESS), expectedIncentiveAmount);

        // Ensure the weiroll wallet got the liquidity
        assertEq(mockLiquidityToken.balanceOf(weirollWallet), fillAmount);

        // Check the frontend fee recipient received the correct fee
        assertEq(recipeMarketHub.feeClaimantToTokenToAmount(FRONTEND_FEE_RECIPIENT, address(mockIncentiveToken)), expectedFrontendFeeAmount);

        // Check the protocol fee recipient received the correct fee
        assertEq(recipeMarketHub.feeClaimantToTokenToAmount(OWNER_ADDRESS, address(mockIncentiveToken)), expectedProtocolFeeAmount);
    }

    function test_DirectFill_Upfront_IPGdaOffer_ForTokens() external {
        vm.warp(vm.getBlockTimestamp() + 100_000);
        uint256 frontendFee = recipeMarketHub.minimumFrontendFee();
        bytes32 marketHash = recipeMarketHub.createMarket(address(mockLiquidityToken), 30 days, frontendFee, NULL_RECIPE, NULL_RECIPE, RewardStyle.Upfront);
        console.log("===========RecipeMarket Created===========");
        console.log("inputToken:", address(mockLiquidityToken));
        console.log("Market created:", vm.toString(marketHash));

        uint256 offerAmount = 100_000e18; // Offer amount requested
        uint256 fillAmount = 1000e18; // Fill amount

        // Create a fillable IP offer
        bytes32 offerHash = createIPGdaOffer_WithTokens(marketHash, offerAmount, IP_ADDRESS);
        console.log("===========IP Offer Created===========");
        console.log("marketHash:", vm.toString(marketHash));
        console.log("offerAmount:", offerAmount);
        console.log("IP address:", AP_ADDRESS);

        // Mint liquidity tokens to the AP to fill the offer
        mockLiquidityToken.mint(AP_ADDRESS, fillAmount);
        vm.startPrank(AP_ADDRESS);
        mockLiquidityToken.approve(address(recipeMarketHub), fillAmount);
        vm.stopPrank();

        (, uint256 expectedProtocolFeeAmount, uint256 expectedFrontendFeeAmount, uint256 expectedIncentiveAmount) =
            calculateIPGdaOfferExpectedIncentiveAndFrontendFee(offerHash, offerAmount, fillAmount, address(mockIncentiveToken));

        // Expect events for transfers
        vm.expectEmit(true, true, false, true, address(mockIncentiveToken));
        emit ERC20.Transfer(address(recipeMarketHub), AP_ADDRESS, expectedIncentiveAmount);

        vm.expectEmit(true, false, false, true, address(mockLiquidityToken));
        emit ERC20.Transfer(AP_ADDRESS, address(0), fillAmount);

        vm.expectEmit(false, false, false, false, address(recipeMarketHub));
        emit RecipeMarketHubBase.IPOfferFilled(0, 0, address(0), new uint256[](0), new uint256[](0), new uint256[](0));

        // Record the logs to capture Transfer events to get Weiroll wallet address
        vm.recordLogs();
        // Fill the offer
        vm.startPrank(AP_ADDRESS);
        recipeMarketHub.fillIPGdaOffers(offerHash, fillAmount, address(0), FRONTEND_FEE_RECIPIENT);
        vm.stopPrank();

        (,,,, uint256 resultingQuantity, uint256 resultingRemainingQuantity) = recipeMarketHub.offerHashToIPOffer(offerHash);
        assertEq(resultingRemainingQuantity, resultingQuantity - fillAmount);

        // Extract the Weiroll wallet address (the 'to' address from the second Transfer event)
        address weirollWallet = address(uint160(uint256(vm.getRecordedLogs()[1].topics[2])));

        // Ensure there is a weirollWallet at the expected address
        assertGt(weirollWallet.code.length, 0);

        // Ensure that the deposit recipe was executed
        assertEq(WeirollWallet(payable(weirollWallet)).executed(), true);

        // Ensure the AP received the correct incentive amount
        assertEq(mockIncentiveToken.balanceOf(AP_ADDRESS), expectedIncentiveAmount);

        // Ensure the weiroll wallet got the liquidity
        assertEq(mockLiquidityToken.balanceOf(weirollWallet), fillAmount);

        // Check the frontend fee recipient received the correct fee
        assertEq(recipeMarketHub.feeClaimantToTokenToAmount(FRONTEND_FEE_RECIPIENT, address(mockIncentiveToken)), expectedFrontendFeeAmount);

        // Check the protocol fee recipient received the correct fee
        assertEq(recipeMarketHub.feeClaimantToTokenToAmount(OWNER_ADDRESS, address(mockIncentiveToken)), expectedProtocolFeeAmount);
    }

    function test_DirectFullFill_Upfront_IPOffer_ForTokens() external {
        uint256 frontendFee = recipeMarketHub.minimumFrontendFee();
        bytes32 marketHash = recipeMarketHub.createMarket(address(mockLiquidityToken), 30 days, frontendFee, NULL_RECIPE, NULL_RECIPE, RewardStyle.Upfront);

        uint256 offerAmount = 100_000e18; // Offer amount requested
        uint256 fillAmount = 100_000e18; // Fill amount

        // Create a fillable IP offer
        bytes32 offerHash = createIPOffer_WithTokens(marketHash, offerAmount, IP_ADDRESS);

        // Mint liquidity tokens to the AP to fill the offer
        mockLiquidityToken.mint(AP_ADDRESS, fillAmount);
        vm.startPrank(AP_ADDRESS);
        mockLiquidityToken.approve(address(recipeMarketHub), fillAmount);
        vm.stopPrank();

        (, uint256 expectedProtocolFeeAmount, uint256 expectedFrontendFeeAmount, uint256 expectedIncentiveAmount) =
            calculateIPOfferExpectedIncentiveAndFrontendFee(offerHash, offerAmount, fillAmount, address(mockIncentiveToken));

        // Expect events for transfers
        vm.expectEmit(true, true, false, true, address(mockIncentiveToken));
        emit ERC20.Transfer(address(recipeMarketHub), AP_ADDRESS, expectedIncentiveAmount);

        vm.expectEmit(true, false, false, true, address(mockLiquidityToken));
        emit ERC20.Transfer(AP_ADDRESS, address(0), fillAmount);

        vm.expectEmit(false, false, false, false, address(recipeMarketHub));
        emit RecipeMarketHubBase.IPOfferFilled(0, 0, address(0), new uint256[](0), new uint256[](0), new uint256[](0));

        // Record the logs to capture Transfer events to get Weiroll wallet address
        vm.recordLogs();
        // Fill the offer
        vm.startPrank(AP_ADDRESS);
        recipeMarketHub.fillIPOffers(offerHash, type(uint256).max, address(0), FRONTEND_FEE_RECIPIENT);
        vm.stopPrank();

        (,,,, uint256 resultingQuantity, uint256 resultingRemainingQuantity) = recipeMarketHub.offerHashToIPOffer(offerHash);
        assertEq(resultingRemainingQuantity, resultingQuantity - fillAmount);

        // Extract the Weiroll wallet address (the 'to' address from the second Transfer event)
        address weirollWallet = address(uint160(uint256(vm.getRecordedLogs()[1].topics[2])));

        // Ensure there is a weirollWallet at the expected address
        assertGt(weirollWallet.code.length, 0);

        // Ensure that the deposit recipe was executed
        assertEq(WeirollWallet(payable(weirollWallet)).executed(), true);

        // Ensure the AP received the correct incentive amount
        assertEq(mockIncentiveToken.balanceOf(AP_ADDRESS), expectedIncentiveAmount);

        // Ensure the weiroll wallet got the liquidity
        assertEq(mockLiquidityToken.balanceOf(weirollWallet), fillAmount);

        // Check the frontend fee recipient received the correct fee
        assertEq(recipeMarketHub.feeClaimantToTokenToAmount(FRONTEND_FEE_RECIPIENT, address(mockIncentiveToken)), expectedFrontendFeeAmount);

        // Check the protocol fee recipient received the correct fee
        assertEq(recipeMarketHub.feeClaimantToTokenToAmount(OWNER_ADDRESS, address(mockIncentiveToken)), expectedProtocolFeeAmount);
    }

    function test_DirectFill_Upfront_IPOffer_ForPoints() external {
        uint256 frontendFee = recipeMarketHub.minimumFrontendFee();
        bytes32 marketHash = recipeMarketHub.createMarket(address(mockLiquidityToken), 30 days, frontendFee, NULL_RECIPE, NULL_RECIPE, RewardStyle.Upfront);

        uint256 offerAmount = 100_000e18; // Offer amount requested
        uint256 fillAmount = 1000e18; // Fill amount

        // Mint liquidity tokens to the AP to fill the offer
        mockLiquidityToken.mint(AP_ADDRESS, fillAmount);
        vm.startPrank(AP_ADDRESS);
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

        vm.expectEmit(true, true, false, true, address(points));
        emit Points.Award(AP_ADDRESS, expectedIncentiveAmount, IP_ADDRESS);

        vm.expectEmit(true, false, false, true, address(mockLiquidityToken));
        emit ERC20.Transfer(AP_ADDRESS, address(0), fillAmount);

        vm.expectEmit(false, false, false, false, address(recipeMarketHub));
        emit RecipeMarketHubBase.IPOfferFilled(0, 0, address(0), new uint256[](0), new uint256[](0), new uint256[](0));

        // Record the logs to capture Transfer events to get Weiroll wallet address
        vm.recordLogs();
        // Fill the offer
        vm.startPrank(AP_ADDRESS);
        recipeMarketHub.fillIPOffers(offerHash, fillAmount, address(0), FRONTEND_FEE_RECIPIENT);
        vm.stopPrank();

        (,,,, uint256 resultingQuantity, uint256 resultingRemainingQuantity) = recipeMarketHub.offerHashToIPOffer(offerHash);
        assertEq(resultingRemainingQuantity, resultingQuantity - fillAmount);

        // Extract the Weiroll wallet address (the 'to' address from the Transfer event - third event in logs)
        address weirollWallet = address(uint160(uint256(vm.getRecordedLogs()[3].topics[2])));

        // Ensure there is a weirollWallet at the expected address
        assertGt(weirollWallet.code.length, 0);

        // Ensure that the deposit recipe was executed
        assertEq(WeirollWallet(payable(weirollWallet)).executed(), true);

        // Ensure the weiroll wallet got the liquidity
        assertEq(mockLiquidityToken.balanceOf(weirollWallet), fillAmount);
    }

    function test_VaultFill_Upfront_IPOffer_ForTokens() external {
        uint256 frontendFee = recipeMarketHub.minimumFrontendFee();
        bytes32 marketHash = recipeMarketHub.createMarket(address(mockLiquidityToken), 30 days, frontendFee, NULL_RECIPE, NULL_RECIPE, RewardStyle.Upfront);

        uint256 offerAmount = 100_000e18; // Offer amount requested
        uint256 fillAmount = 1000e18; // Fill amount

        // Create a fillable IP offer
        bytes32 offerHash = createIPOffer_WithTokens(marketHash, offerAmount, IP_ADDRESS);

        // Mint liquidity tokens to deposit into the vault
        mockLiquidityToken.mint(AP_ADDRESS, fillAmount);
        vm.startPrank(AP_ADDRESS);
        mockLiquidityToken.approve(address(mockVault), fillAmount);

        // Deposit tokens into the vault and approve recipeMarketHub to spend them
        mockVault.deposit(fillAmount, AP_ADDRESS);
        mockVault.approve(address(recipeMarketHub), fillAmount);

        vm.stopPrank();

        (, uint256 expectedProtocolFeeAmount, uint256 expectedFrontendFeeAmount, uint256 expectedIncentiveAmount) =
            calculateIPOfferExpectedIncentiveAndFrontendFee(offerHash, offerAmount, fillAmount, address(mockIncentiveToken));

        // Expect events for transfers
        vm.expectEmit(true, true, false, true, address(mockIncentiveToken));
        emit ERC20.Transfer(address(recipeMarketHub), AP_ADDRESS, expectedIncentiveAmount);

        // burn shares
        vm.expectEmit(true, true, false, false, address(mockVault));
        emit ERC20.Transfer(AP_ADDRESS, address(0), 0);

        vm.expectEmit(true, false, true, false, address(mockVault));
        emit ERC4626.Withdraw(address(recipeMarketHub), address(0), AP_ADDRESS, fillAmount, 0);

        vm.expectEmit(true, false, false, true, address(mockLiquidityToken));
        emit ERC20.Transfer(address(mockVault), address(0), fillAmount);

        vm.expectEmit(false, false, false, false, address(recipeMarketHub));
        emit RecipeMarketHubBase.IPOfferFilled(0, 0, address(0), new uint256[](0), new uint256[](0), new uint256[](0));

        // Record the logs to capture Transfer events to get Weiroll wallet address
        vm.recordLogs();
        // Fill the offer
        vm.startPrank(AP_ADDRESS);
        recipeMarketHub.fillIPOffers(offerHash, fillAmount, address(mockVault), FRONTEND_FEE_RECIPIENT);
        vm.stopPrank();

        (,,,, uint256 resultingQuantity, uint256 resultingRemainingQuantity) = recipeMarketHub.offerHashToIPOffer(offerHash);
        assertEq(resultingRemainingQuantity, resultingQuantity - fillAmount);

        // Extract the Weiroll wallet address (the 'to' address from the third Transfer event)
        address weirollWallet = address(uint160(uint256(vm.getRecordedLogs()[3].topics[2])));

        // Ensure there is a weirollWallet at the expected address
        assertGt(weirollWallet.code.length, 0);

        // Ensure that the deposit recipe was executed
        assertEq(WeirollWallet(payable(weirollWallet)).executed(), true);

        // Ensure the AP received the correct incentive amount
        assertEq(mockIncentiveToken.balanceOf(AP_ADDRESS), expectedIncentiveAmount);

        // Ensure the weiroll wallet got the liquidity
        assertEq(mockLiquidityToken.balanceOf(weirollWallet), fillAmount);

        // Check the frontend fee recipient received the correct fee
        assertEq(recipeMarketHub.feeClaimantToTokenToAmount(FRONTEND_FEE_RECIPIENT, address(mockIncentiveToken)), expectedFrontendFeeAmount);

        // Check the protocol fee recipient received the correct fee
        assertEq(recipeMarketHub.feeClaimantToTokenToAmount(OWNER_ADDRESS, address(mockIncentiveToken)), expectedProtocolFeeAmount);
    }

    function test_VaultFill_Upfront_IPOffer_ForPoints() external {
        uint256 frontendFee = recipeMarketHub.minimumFrontendFee();
        bytes32 marketHash = recipeMarketHub.createMarket(address(mockLiquidityToken), 30 days, frontendFee, NULL_RECIPE, NULL_RECIPE, RewardStyle.Upfront);

        uint256 offerAmount = 100_000e18; // Offer amount requested
        uint256 fillAmount = 1000e18; // Fill amount

        // Mint liquidity tokens to deposit into the vault
        mockLiquidityToken.mint(AP_ADDRESS, fillAmount);
        vm.startPrank(AP_ADDRESS);
        mockLiquidityToken.approve(address(mockVault), fillAmount);

        // Deposit tokens into the vault and approve recipeMarketHub to spend them
        mockVault.deposit(fillAmount, AP_ADDRESS);
        mockVault.approve(address(recipeMarketHub), fillAmount);

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

        vm.expectEmit(true, true, false, true, address(points));
        emit Points.Award(AP_ADDRESS, expectedIncentiveAmount, IP_ADDRESS);

        // burn shares
        vm.expectEmit(true, true, false, false, address(mockVault));
        emit ERC20.Transfer(AP_ADDRESS, address(0), 0);

        vm.expectEmit(true, false, true, false, address(mockVault));
        emit ERC4626.Withdraw(address(recipeMarketHub), address(0), AP_ADDRESS, fillAmount, 0);

        vm.expectEmit(true, false, false, true, address(mockLiquidityToken));
        emit ERC20.Transfer(address(mockVault), address(0), fillAmount);

        vm.expectEmit(false, false, false, false, address(recipeMarketHub));
        emit RecipeMarketHubBase.IPOfferFilled(0, 0, address(0), new uint256[](0), new uint256[](0), new uint256[](0));

        // Record the logs to capture Transfer events to get Weiroll wallet address
        vm.recordLogs();
        // Fill the offer
        vm.startPrank(AP_ADDRESS);
        recipeMarketHub.fillIPOffers(offerHash, fillAmount, address(mockVault), FRONTEND_FEE_RECIPIENT);
        vm.stopPrank();

        (,,,, uint256 resultingQuantity, uint256 resultingRemainingQuantity) = recipeMarketHub.offerHashToIPOffer(offerHash);
        assertEq(resultingRemainingQuantity, resultingQuantity - fillAmount);

        // Extract the Weiroll wallet address (the 'to' address from the Transfer event - third event in logs)
        address weirollWallet = address(uint160(uint256(vm.getRecordedLogs()[5].topics[2])));

        // Ensure there is a weirollWallet at the expected address
        assertGt(weirollWallet.code.length, 0);

        // Ensure that the deposit recipe was executed
        assertEq(WeirollWallet(payable(weirollWallet)).executed(), true);

        // Ensure the weiroll wallet got the liquidity
        assertEq(mockLiquidityToken.balanceOf(weirollWallet), fillAmount);
    }

    function test_DirectFill_Forfeitable_IPOffer_ForTokens() external {
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

        (, uint256 expectedProtocolFeeAmount, uint256 expectedFrontendFeeAmount, uint256 expectedIncentiveAmount) =
            calculateIPOfferExpectedIncentiveAndFrontendFee(offerHash, offerAmount, fillAmount, address(mockIncentiveToken));

        vm.expectEmit(true, false, false, true, address(mockLiquidityToken));
        emit ERC20.Transfer(AP_ADDRESS, address(0), fillAmount);

        vm.expectEmit(false, false, false, false, address(recipeMarketHub));
        emit RecipeMarketHubBase.IPOfferFilled(0, 0, address(0), new uint256[](0), new uint256[](0), new uint256[](0));

        // Record the logs to capture Transfer events to get Weiroll wallet address
        vm.recordLogs();
        // Fill the offer
        vm.startPrank(AP_ADDRESS);
        recipeMarketHub.fillIPOffers(offerHash, fillAmount, address(0), FRONTEND_FEE_RECIPIENT);
        vm.stopPrank();

        (,,,, uint256 resultingQuantity, uint256 resultingRemainingQuantity) = recipeMarketHub.offerHashToIPOffer(offerHash);
        assertEq(resultingRemainingQuantity, resultingQuantity - fillAmount);

        // Extract the Weiroll wallet address (the 'to' address from the Transfer event)
        address weirollWallet = address(uint160(uint256(vm.getRecordedLogs()[0].topics[2])));

        (, uint256[] memory amounts,) = recipeMarketHub.getLockedIncentiveParams(weirollWallet);
        assertEq(amounts[0], expectedIncentiveAmount);

        // Ensure there is a weirollWallet at the expected address
        assertGt(weirollWallet.code.length, 0);

        // Ensure that the deposit recipe was executed
        assertEq(WeirollWallet(payable(weirollWallet)).executed(), true);

        // Ensure the weiroll wallet got the liquidity
        assertEq(mockLiquidityToken.balanceOf(weirollWallet), fillAmount);

        // Check the frontend fee recipient received the correct fee
        assertEq(recipeMarketHub.feeClaimantToTokenToAmount(FRONTEND_FEE_RECIPIENT, address(mockIncentiveToken)), 0);

        // Check the protocol fee recipient received the correct fee
        assertEq(recipeMarketHub.feeClaimantToTokenToAmount(OWNER_ADDRESS, address(mockIncentiveToken)), 0);
    }

    function test_DirectFill_Forfeitable_IPOffer_ForPoints() external {
        uint256 frontendFee = recipeMarketHub.minimumFrontendFee();
        bytes32 marketHash = recipeMarketHub.createMarket(address(mockLiquidityToken), 30 days, frontendFee, NULL_RECIPE, NULL_RECIPE, RewardStyle.Forfeitable);

        uint256 offerAmount = 100_000e18; // Offer amount requested
        uint256 fillAmount = 1000e18; // Fill amount

        // Mint liquidity tokens to the AP to fill the offer
        mockLiquidityToken.mint(AP_ADDRESS, fillAmount);
        vm.startPrank(AP_ADDRESS);
        mockLiquidityToken.approve(address(recipeMarketHub), fillAmount);
        vm.stopPrank();

        // Create a fillable IP offer
        (bytes32 offerHash, Points points) = createIPOffer_WithPoints(marketHash, offerAmount, IP_ADDRESS);

        (, uint256 expectedProtocolFeeAmount, uint256 expectedFrontendFeeAmount, uint256 expectedIncentiveAmount) =
            calculateIPOfferExpectedIncentiveAndFrontendFee(offerHash, offerAmount, fillAmount, address(points));

        // vm.expectEmit(true, true, false, true, address(points));
        // emit Points.Award(OWNER_ADDRESS, expectedProtocolFeeAmount);

        // vm.expectEmit(true, true, false, true, address(points));
        // emit Points.Award(FRONTEND_FEE_RECIPIENT, expectedFrontendFeeAmount);

        vm.expectEmit(true, false, false, true, address(mockLiquidityToken));
        emit ERC20.Transfer(AP_ADDRESS, address(0), fillAmount);

        vm.expectEmit(false, false, false, false, address(recipeMarketHub));
        emit RecipeMarketHubBase.IPOfferFilled(0, 0, address(0), new uint256[](0), new uint256[](0), new uint256[](0));

        // Record the logs to capture Transfer events to get Weiroll wallet address
        vm.recordLogs();
        // Fill the offer
        vm.startPrank(AP_ADDRESS);
        recipeMarketHub.fillIPOffers(offerHash, fillAmount, address(0), FRONTEND_FEE_RECIPIENT);
        vm.stopPrank();

        (,,,, uint256 resultingQuantity, uint256 resultingRemainingQuantity) = recipeMarketHub.offerHashToIPOffer(offerHash);
        assertEq(resultingRemainingQuantity, resultingQuantity - fillAmount);

        // Extract the Weiroll wallet address (the 'to' address from the Transfer event - third event in logs)
        address weirollWallet = address(uint160(uint256(vm.getRecordedLogs()[0].topics[2])));

        (, uint256[] memory amounts,) = recipeMarketHub.getLockedIncentiveParams(weirollWallet);
        assertEq(amounts[0], expectedIncentiveAmount);

        // Ensure there is a weirollWallet at the expected address
        assertGt(weirollWallet.code.length, 0);

        // Ensure that the deposit recipe was executed
        assertEq(WeirollWallet(payable(weirollWallet)).executed(), true);

        // Ensure the weiroll wallet got the liquidity
        assertEq(mockLiquidityToken.balanceOf(weirollWallet), fillAmount);

        // Check the frontend fee recipient received the correct fee
        assertEq(recipeMarketHub.feeClaimantToTokenToAmount(FRONTEND_FEE_RECIPIENT, address(mockIncentiveToken)), 0);

        // Check the protocol fee recipient received the correct fee
        assertEq(recipeMarketHub.feeClaimantToTokenToAmount(OWNER_ADDRESS, address(mockIncentiveToken)), 0);
    }

    function test_VaultFill_Forfeitable_IPOffer_ForTokens() external {
        uint256 frontendFee = recipeMarketHub.minimumFrontendFee();
        bytes32 marketHash = recipeMarketHub.createMarket(address(mockLiquidityToken), 30 days, frontendFee, NULL_RECIPE, NULL_RECIPE, RewardStyle.Forfeitable);

        uint256 offerAmount = 100_000e18; // Offer amount requested
        uint256 fillAmount = 1000e18; // Fill amount

        // Create a fillable IP offer
        bytes32 offerHash = createIPOffer_WithTokens(marketHash, offerAmount, IP_ADDRESS);

        // Mint liquidity tokens to deposit into the vault
        mockLiquidityToken.mint(AP_ADDRESS, fillAmount);
        vm.startPrank(AP_ADDRESS);
        mockLiquidityToken.approve(address(mockVault), fillAmount);

        // Deposit tokens into the vault and approve recipeMarketHub to spend them
        mockVault.deposit(fillAmount, AP_ADDRESS);
        mockVault.approve(address(recipeMarketHub), fillAmount);

        vm.stopPrank();

        (, uint256 expectedProtocolFeeAmount, uint256 expectedFrontendFeeAmount, uint256 expectedIncentiveAmount) =
            calculateIPOfferExpectedIncentiveAndFrontendFee(offerHash, offerAmount, fillAmount, address(mockIncentiveToken));

        // burn shares
        vm.expectEmit(true, true, false, false, address(mockVault));
        emit ERC20.Transfer(AP_ADDRESS, address(0), 0);

        vm.expectEmit(true, false, true, false, address(mockVault));
        emit ERC4626.Withdraw(address(recipeMarketHub), address(0), AP_ADDRESS, fillAmount, 0);

        vm.expectEmit(true, false, false, true, address(mockLiquidityToken));
        emit ERC20.Transfer(address(mockVault), address(0), fillAmount);

        vm.expectEmit(false, false, false, false, address(recipeMarketHub));
        emit RecipeMarketHubBase.IPOfferFilled(0, 0, address(0), new uint256[](0), new uint256[](0), new uint256[](0));

        // Record the logs to capture Transfer events to get Weiroll wallet address
        vm.recordLogs();
        // Fill the offer
        vm.startPrank(AP_ADDRESS);
        recipeMarketHub.fillIPOffers(offerHash, fillAmount, address(mockVault), FRONTEND_FEE_RECIPIENT);
        vm.stopPrank();

        (,,,, uint256 resultingQuantity, uint256 resultingRemainingQuantity) = recipeMarketHub.offerHashToIPOffer(offerHash);
        assertEq(resultingRemainingQuantity, resultingQuantity - fillAmount);

        // Extract the Weiroll wallet address (the 'to' address from the third Transfer event)
        address weirollWallet = address(uint160(uint256(vm.getRecordedLogs()[2].topics[2])));

        (, uint256[] memory amounts,) = recipeMarketHub.getLockedIncentiveParams(weirollWallet);
        assertEq(amounts[0], expectedIncentiveAmount);

        // Ensure there is a weirollWallet at the expected address
        assertGt(weirollWallet.code.length, 0);

        // Ensure that the deposit recipe was executed
        assertEq(WeirollWallet(payable(weirollWallet)).executed(), true);

        // Ensure the weiroll wallet got the liquidity
        assertEq(mockLiquidityToken.balanceOf(weirollWallet), fillAmount);

        // Check the frontend fee recipient received the correct fee
        assertEq(recipeMarketHub.feeClaimantToTokenToAmount(FRONTEND_FEE_RECIPIENT, address(mockIncentiveToken)), 0);

        // Check the protocol fee recipient received the correct fee
        assertEq(recipeMarketHub.feeClaimantToTokenToAmount(OWNER_ADDRESS, address(mockIncentiveToken)), 0);
    }

    function test_VaultFill_Forfeitable_IPOffer_ForPoints() external {
        uint256 frontendFee = recipeMarketHub.minimumFrontendFee();
        bytes32 marketHash = recipeMarketHub.createMarket(address(mockLiquidityToken), 30 days, frontendFee, NULL_RECIPE, NULL_RECIPE, RewardStyle.Forfeitable);

        uint256 offerAmount = 100_000e18; // Offer amount requested
        uint256 fillAmount = 1000e18; // Fill amount

        // Mint liquidity tokens to deposit into the vault
        mockLiquidityToken.mint(AP_ADDRESS, fillAmount);
        vm.startPrank(AP_ADDRESS);
        mockLiquidityToken.approve(address(mockVault), fillAmount);

        // Deposit tokens into the vault and approve recipeMarketHub to spend them
        mockVault.deposit(fillAmount, AP_ADDRESS);
        mockVault.approve(address(recipeMarketHub), fillAmount);

        vm.stopPrank();

        // Create a fillable IP offer
        (bytes32 offerHash, Points points) = createIPOffer_WithPoints(marketHash, offerAmount, IP_ADDRESS);

        (, uint256 expectedProtocolFeeAmount, uint256 expectedFrontendFeeAmount, uint256 expectedIncentiveAmount) =
            calculateIPOfferExpectedIncentiveAndFrontendFee(offerHash, offerAmount, fillAmount, address(points));

        // vm.expectEmit(true, true, false, true, address(points));
        // emit Points.Award(OWNER_ADDRESS, expectedProtocolFeeAmount);

        // vm.expectEmit(true, true, false, true, address(points));
        // emit Points.Award(FRONTEND_FEE_RECIPIENT, expectedFrontendFeeAmount);

        // burn shares
        vm.expectEmit(true, true, false, false, address(mockVault));
        emit ERC20.Transfer(AP_ADDRESS, address(0), 0);

        vm.expectEmit(true, false, true, false, address(mockVault));
        emit ERC4626.Withdraw(address(recipeMarketHub), address(0), AP_ADDRESS, fillAmount, 0);

        vm.expectEmit(true, false, false, true, address(mockLiquidityToken));
        emit ERC20.Transfer(address(mockVault), address(0), fillAmount);

        vm.expectEmit(false, false, false, false, address(recipeMarketHub));
        emit RecipeMarketHubBase.IPOfferFilled(0, 0, address(0), new uint256[](0), new uint256[](0), new uint256[](0));

        // Record the logs to capture Transfer events to get Weiroll wallet address
        vm.recordLogs();
        // Fill the offer
        vm.startPrank(AP_ADDRESS);
        recipeMarketHub.fillIPOffers(offerHash, fillAmount, address(mockVault), FRONTEND_FEE_RECIPIENT);
        vm.stopPrank();

        (,,,, uint256 resultingQuantity, uint256 resultingRemainingQuantity) = recipeMarketHub.offerHashToIPOffer(offerHash);
        assertEq(resultingRemainingQuantity, resultingQuantity - fillAmount);

        address weirollWallet = address(uint160(uint256(vm.getRecordedLogs()[2].topics[2])));

        (, uint256[] memory amounts,) = recipeMarketHub.getLockedIncentiveParams(weirollWallet);
        assertEq(amounts[0], expectedIncentiveAmount);

        // Ensure there is a weirollWallet at the expected address
        assertGt(weirollWallet.code.length, 0);

        // Ensure that the deposit recipe was executed
        assertEq(WeirollWallet(payable(weirollWallet)).executed(), true);

        // Ensure the weiroll wallet got the liquidity
        assertEq(mockLiquidityToken.balanceOf(weirollWallet), fillAmount);

        // Check the frontend fee recipient received the correct fee
        assertEq(recipeMarketHub.feeClaimantToTokenToAmount(FRONTEND_FEE_RECIPIENT, address(mockIncentiveToken)), 0);

        // Check the protocol fee recipient received the correct fee
        assertEq(recipeMarketHub.feeClaimantToTokenToAmount(OWNER_ADDRESS, address(mockIncentiveToken)), 0);
    }

    function test_DirectFill_Arrear_IPOffer_ForTokens() external {
        uint256 frontendFee = recipeMarketHub.minimumFrontendFee();
        bytes32 marketHash = recipeMarketHub.createMarket(address(mockLiquidityToken), 30 days, frontendFee, NULL_RECIPE, NULL_RECIPE, RewardStyle.Arrear);

        uint256 offerAmount = 100_000e18; // Offer amount requested
        uint256 fillAmount = 1000e18; // Fill amount

        // Create a fillable IP offer
        bytes32 offerHash = createIPOffer_WithTokens(marketHash, offerAmount, IP_ADDRESS);

        // Mint liquidity tokens to the AP to fill the offer
        mockLiquidityToken.mint(AP_ADDRESS, fillAmount);
        vm.startPrank(AP_ADDRESS);
        mockLiquidityToken.approve(address(recipeMarketHub), fillAmount);
        vm.stopPrank();

        (, uint256 expectedProtocolFeeAmount, uint256 expectedFrontendFeeAmount, uint256 expectedIncentiveAmount) =
            calculateIPOfferExpectedIncentiveAndFrontendFee(offerHash, offerAmount, fillAmount, address(mockIncentiveToken));

        vm.expectEmit(true, false, false, true, address(mockLiquidityToken));
        emit ERC20.Transfer(AP_ADDRESS, address(0), fillAmount);

        vm.expectEmit(false, false, false, false, address(recipeMarketHub));
        emit RecipeMarketHubBase.IPOfferFilled(0, 0, address(0), new uint256[](0), new uint256[](0), new uint256[](0));

        // Record the logs to capture Transfer events to get Weiroll wallet address
        vm.recordLogs();
        // Fill the offer
        vm.startPrank(AP_ADDRESS);
        recipeMarketHub.fillIPOffers(offerHash, fillAmount, address(0), FRONTEND_FEE_RECIPIENT);
        vm.stopPrank();

        (,,,, uint256 resultingQuantity, uint256 resultingRemainingQuantity) = recipeMarketHub.offerHashToIPOffer(offerHash);
        assertEq(resultingRemainingQuantity, resultingQuantity - fillAmount);

        // Extract the Weiroll wallet address (the 'to' address from the Transfer event)
        address weirollWallet = address(uint160(uint256(vm.getRecordedLogs()[0].topics[2])));

        (, uint256[] memory amounts,) = recipeMarketHub.getLockedIncentiveParams(weirollWallet);
        assertEq(amounts[0], expectedIncentiveAmount);

        // Ensure there is a weirollWallet at the expected address
        assertGt(weirollWallet.code.length, 0);

        // Ensure that the deposit recipe was executed
        assertEq(WeirollWallet(payable(weirollWallet)).executed(), true);

        // Ensure the weiroll wallet got the liquidity
        assertEq(mockLiquidityToken.balanceOf(weirollWallet), fillAmount);

        // Check the frontend fee recipient received the correct fee
        assertEq(recipeMarketHub.feeClaimantToTokenToAmount(FRONTEND_FEE_RECIPIENT, address(mockIncentiveToken)), 0);

        // Check the protocol fee recipient received the correct fee
        assertEq(recipeMarketHub.feeClaimantToTokenToAmount(OWNER_ADDRESS, address(mockIncentiveToken)), 0);
    }

    function test_DirectFill_Arrear_IPOffer_ForPoints() external {
        uint256 frontendFee = recipeMarketHub.minimumFrontendFee();
        bytes32 marketHash = recipeMarketHub.createMarket(address(mockLiquidityToken), 30 days, frontendFee, NULL_RECIPE, NULL_RECIPE, RewardStyle.Arrear);

        uint256 offerAmount = 100_000e18; // Offer amount requested
        uint256 fillAmount = 1000e18; // Fill amount

        // Mint liquidity tokens to the AP to fill the offer
        mockLiquidityToken.mint(AP_ADDRESS, fillAmount);
        vm.startPrank(AP_ADDRESS);
        mockLiquidityToken.approve(address(recipeMarketHub), fillAmount);
        vm.stopPrank();

        // Create a fillable IP offer
        (bytes32 offerHash, Points points) = createIPOffer_WithPoints(marketHash, offerAmount, IP_ADDRESS);

        (, uint256 expectedProtocolFeeAmount, uint256 expectedFrontendFeeAmount, uint256 expectedIncentiveAmount) =
            calculateIPOfferExpectedIncentiveAndFrontendFee(offerHash, offerAmount, fillAmount, address(points));

        // vm.expectEmit(true, true, false, true, address(points));
        // emit Points.Award(OWNER_ADDRESS, expectedProtocolFeeAmount);

        // vm.expectEmit(true, true, false, true, address(points));
        // emit Points.Award(FRONTEND_FEE_RECIPIENT, expectedFrontendFeeAmount);

        vm.expectEmit(true, false, false, true, address(mockLiquidityToken));
        emit ERC20.Transfer(AP_ADDRESS, address(0), fillAmount);

        vm.expectEmit(false, false, false, false, address(recipeMarketHub));
        emit RecipeMarketHubBase.IPOfferFilled(0, 0, address(0), new uint256[](0), new uint256[](0), new uint256[](0));

        // Record the logs to capture Transfer events to get Weiroll wallet address
        vm.recordLogs();
        // Fill the offer
        vm.startPrank(AP_ADDRESS);
        recipeMarketHub.fillIPOffers(offerHash, fillAmount, address(0), FRONTEND_FEE_RECIPIENT);
        vm.stopPrank();

        (,,,, uint256 resultingQuantity, uint256 resultingRemainingQuantity) = recipeMarketHub.offerHashToIPOffer(offerHash);
        assertEq(resultingRemainingQuantity, resultingQuantity - fillAmount);

        // Extract the Weiroll wallet address (the 'to' address from the Transfer event - first event in logs)
        address weirollWallet = address(uint160(uint256(vm.getRecordedLogs()[0].topics[2])));

        (, uint256[] memory amounts,) = recipeMarketHub.getLockedIncentiveParams(weirollWallet);
        assertEq(amounts[0], expectedIncentiveAmount);

        // Ensure there is a weirollWallet at the expected address
        assertGt(weirollWallet.code.length, 0);

        // Ensure that the deposit recipe was executed
        assertEq(WeirollWallet(payable(weirollWallet)).executed(), true);

        // Ensure the weiroll wallet got the liquidity
        assertEq(mockLiquidityToken.balanceOf(weirollWallet), fillAmount);

        // Check the frontend fee recipient received the correct fee
        assertEq(recipeMarketHub.feeClaimantToTokenToAmount(FRONTEND_FEE_RECIPIENT, address(mockIncentiveToken)), 0);

        // Check the protocol fee recipient received the correct fee
        assertEq(recipeMarketHub.feeClaimantToTokenToAmount(OWNER_ADDRESS, address(mockIncentiveToken)), 0);
    }

    function test_VaultFill_Arrear_IPOffer_ForTokens() external {
        uint256 frontendFee = recipeMarketHub.minimumFrontendFee();
        bytes32 marketHash = recipeMarketHub.createMarket(address(mockLiquidityToken), 30 days, frontendFee, NULL_RECIPE, NULL_RECIPE, RewardStyle.Arrear);

        uint256 offerAmount = 100_000e18; // Offer amount requested
        uint256 fillAmount = 1000e18; // Fill amount

        // Create a fillable IP offer
        bytes32 offerHash = createIPOffer_WithTokens(marketHash, offerAmount, IP_ADDRESS);

        // Mint liquidity tokens to deposit into the vault
        mockLiquidityToken.mint(AP_ADDRESS, fillAmount);
        vm.startPrank(AP_ADDRESS);
        mockLiquidityToken.approve(address(mockVault), fillAmount);

        // Deposit tokens into the vault and approve recipeMarketHub to spend them
        mockVault.deposit(fillAmount, AP_ADDRESS);
        mockVault.approve(address(recipeMarketHub), fillAmount);

        vm.stopPrank();

        (, uint256 expectedProtocolFeeAmount, uint256 expectedFrontendFeeAmount, uint256 expectedIncentiveAmount) =
            calculateIPOfferExpectedIncentiveAndFrontendFee(offerHash, offerAmount, fillAmount, address(mockIncentiveToken));

        // burn shares
        vm.expectEmit(true, true, false, false, address(mockVault));
        emit ERC20.Transfer(AP_ADDRESS, address(0), 0);

        vm.expectEmit(true, false, true, false, address(mockVault));
        emit ERC4626.Withdraw(address(recipeMarketHub), address(0), AP_ADDRESS, fillAmount, 0);

        vm.expectEmit(true, false, false, true, address(mockLiquidityToken));
        emit ERC20.Transfer(address(mockVault), address(0), fillAmount);

        vm.expectEmit(false, false, false, false, address(recipeMarketHub));
        emit RecipeMarketHubBase.IPOfferFilled(0, 0, address(0), new uint256[](0), new uint256[](0), new uint256[](0));

        // Record the logs to capture Transfer events to get Weiroll wallet address
        vm.recordLogs();
        // Fill the offer
        vm.startPrank(AP_ADDRESS);
        recipeMarketHub.fillIPOffers(offerHash, fillAmount, address(mockVault), FRONTEND_FEE_RECIPIENT);
        vm.stopPrank();

        (,,,, uint256 resultingQuantity, uint256 resultingRemainingQuantity) = recipeMarketHub.offerHashToIPOffer(offerHash);
        assertEq(resultingRemainingQuantity, resultingQuantity - fillAmount);

        // Extract the Weiroll wallet address (the 'to' address from the third Transfer event)
        address weirollWallet = address(uint160(uint256(vm.getRecordedLogs()[2].topics[2])));

        (, uint256[] memory amounts,) = recipeMarketHub.getLockedIncentiveParams(weirollWallet);
        assertEq(amounts[0], expectedIncentiveAmount);

        // Ensure there is a weirollWallet at the expected address
        assertGt(weirollWallet.code.length, 0);

        // Ensure that the deposit recipe was executed
        assertEq(WeirollWallet(payable(weirollWallet)).executed(), true);

        // Ensure the weiroll wallet got the liquidity
        assertEq(mockLiquidityToken.balanceOf(weirollWallet), fillAmount);

        // Check the frontend fee recipient received the correct fee
        assertEq(recipeMarketHub.feeClaimantToTokenToAmount(FRONTEND_FEE_RECIPIENT, address(mockIncentiveToken)), 0);

        // Check the protocol fee recipient received the correct fee
        assertEq(recipeMarketHub.feeClaimantToTokenToAmount(OWNER_ADDRESS, address(mockIncentiveToken)), 0);
    }

    function test_VaultFill_Arrear_IPOffer_ForPoints() external {
        uint256 frontendFee = recipeMarketHub.minimumFrontendFee();
        bytes32 marketHash = recipeMarketHub.createMarket(address(mockLiquidityToken), 30 days, frontendFee, NULL_RECIPE, NULL_RECIPE, RewardStyle.Arrear);

        uint256 offerAmount = 100_000e18; // Offer amount requested
        uint256 fillAmount = 1000e18; // Fill amount

        // Mint liquidity tokens to deposit into the vault
        mockLiquidityToken.mint(AP_ADDRESS, fillAmount);
        vm.startPrank(AP_ADDRESS);
        mockLiquidityToken.approve(address(mockVault), fillAmount);

        // Deposit tokens into the vault and approve recipeMarketHub to spend them
        mockVault.deposit(fillAmount, AP_ADDRESS);
        mockVault.approve(address(recipeMarketHub), fillAmount);

        vm.stopPrank();

        // Create a fillable IP offer
        (bytes32 offerHash, Points points) = createIPOffer_WithPoints(marketHash, offerAmount, IP_ADDRESS);

        (, uint256 expectedProtocolFeeAmount, uint256 expectedFrontendFeeAmount, uint256 expectedIncentiveAmount) =
            calculateIPOfferExpectedIncentiveAndFrontendFee(offerHash, offerAmount, fillAmount, address(points));

        // vm.expectEmit(true, true, false, true, address(points));
        // emit Points.Award(OWNER_ADDRESS, expectedProtocolFeeAmount);

        // vm.expectEmit(true, true, false, true, address(points));
        // emit Points.Award(FRONTEND_FEE_RECIPIENT, expectedFrontendFeeAmount);

        // burn shares
        vm.expectEmit(true, true, false, false, address(mockVault));
        emit ERC20.Transfer(AP_ADDRESS, address(0), 0);

        vm.expectEmit(true, false, true, false, address(mockVault));
        emit ERC4626.Withdraw(address(recipeMarketHub), address(0), AP_ADDRESS, fillAmount, 0);

        vm.expectEmit(true, false, false, true, address(mockLiquidityToken));
        emit ERC20.Transfer(address(mockVault), address(0), fillAmount);

        vm.expectEmit(false, false, false, false, address(recipeMarketHub));
        emit RecipeMarketHubBase.IPOfferFilled(0, 0, address(0), new uint256[](0), new uint256[](0), new uint256[](0));

        // Record the logs to capture Transfer events to get Weiroll wallet address
        vm.recordLogs();
        // Fill the offer
        vm.startPrank(AP_ADDRESS);
        recipeMarketHub.fillIPOffers(offerHash, fillAmount, address(mockVault), FRONTEND_FEE_RECIPIENT);
        vm.stopPrank();

        (,,,, uint256 resultingQuantity, uint256 resultingRemainingQuantity) = recipeMarketHub.offerHashToIPOffer(offerHash);
        assertEq(resultingRemainingQuantity, resultingQuantity - fillAmount);

        address weirollWallet = address(uint160(uint256(vm.getRecordedLogs()[2].topics[2])));

        (, uint256[] memory amounts,) = recipeMarketHub.getLockedIncentiveParams(weirollWallet);
        assertEq(amounts[0], expectedIncentiveAmount);

        // Ensure there is a weirollWallet at the expected address
        assertGt(weirollWallet.code.length, 0);

        // Ensure that the deposit recipe was executed
        assertEq(WeirollWallet(payable(weirollWallet)).executed(), true);

        // Ensure the weiroll wallet got the liquidity
        assertEq(mockLiquidityToken.balanceOf(weirollWallet), fillAmount);

        // Check the frontend fee recipient received the correct fee
        assertEq(recipeMarketHub.feeClaimantToTokenToAmount(FRONTEND_FEE_RECIPIENT, address(mockIncentiveToken)), 0);

        // Check the protocol fee recipient received the correct fee
        assertEq(recipeMarketHub.feeClaimantToTokenToAmount(OWNER_ADDRESS, address(mockIncentiveToken)), 0);
    }

    function test_RevertIf_OfferExpired() external {
        uint256 frontendFee = recipeMarketHub.minimumFrontendFee();
        bytes32 marketHash = recipeMarketHub.createMarket(address(mockLiquidityToken), 30 days, frontendFee, NULL_RECIPE, NULL_RECIPE, RewardStyle.Upfront);

        uint256 offerAmount = 100_000e18;
        uint256 fillAmount = 1000e18;

        // Create an offer with a past expiry date
        bytes32 offerHash = createIPOffer_WithTokens(marketHash, offerAmount, IP_ADDRESS);

        // Offer is now expired
        vm.warp(block.timestamp + 30 days + 1 seconds);

        // Attempt to fill the expired offer, expecting a revert
        vm.expectRevert(RecipeMarketHubBase.OfferExpired.selector);
        recipeMarketHub.fillIPOffers(offerHash, fillAmount, address(0), FRONTEND_FEE_RECIPIENT);
    }

    function test_RevertIf_NotEnoughRemainingQuantity() external {
        uint256 frontendFee = recipeMarketHub.minimumFrontendFee();
        bytes32 marketHash = recipeMarketHub.createMarket(address(mockLiquidityToken), 30 days, frontendFee, NULL_RECIPE, NULL_RECIPE, RewardStyle.Upfront);

        uint256 offerAmount = 100_000e18;
        uint256 fillAmount = 100_001e18; // Fill amount exceeds the offer amount

        // Create a fillable IP offer
        bytes32 offerHash = createIPOffer_WithTokens(marketHash, offerAmount, IP_ADDRESS);

        // Attempt to fill more than available, expecting a revert
        vm.expectRevert(RecipeMarketHubBase.NotEnoughRemainingQuantity.selector);
        recipeMarketHub.fillIPOffers(offerHash, fillAmount, address(0), FRONTEND_FEE_RECIPIENT);
    }

    function test_RevertIf_MismatchedBaseAsset() external {
        uint256 frontendFee = recipeMarketHub.minimumFrontendFee();
        bytes32 marketHash = recipeMarketHub.createMarket(address(mockLiquidityToken), 30 days, frontendFee, NULL_RECIPE, NULL_RECIPE, RewardStyle.Upfront);

        uint256 offerAmount = 100_000e18;
        uint256 fillAmount = 1000e18;

        // Create a fillable IP offer
        bytes32 offerHash = createIPOffer_WithTokens(marketHash, offerAmount, IP_ADDRESS);

        // Use a different vault with a mismatched base asset
        address incorrectVault = address(new MockERC4626(mockIncentiveToken)); // Mismatched asset

        // Attempt to fill with a mismatched base asset, expecting a revert
        vm.expectRevert(RecipeMarketHubBase.MismatchedBaseAsset.selector);
        recipeMarketHub.fillIPOffers(offerHash, fillAmount, incorrectVault, FRONTEND_FEE_RECIPIENT);
    }

    function test_RevertIf_ZeroQuantityFill() external {
        uint256 frontendFee = recipeMarketHub.minimumFrontendFee();
        bytes32 marketHash = recipeMarketHub.createMarket(address(mockLiquidityToken), 30 days, frontendFee, NULL_RECIPE, NULL_RECIPE, RewardStyle.Upfront);

        uint256 offerAmount = 100_000e18;

        // Create a fillable IP offer
        bytes32 offerHash = createIPOffer_WithTokens(marketHash, offerAmount, IP_ADDRESS);

        // Attempt to fill with a zero quantity, expecting a revert
        vm.expectRevert(RecipeMarketHubBase.CannotPlaceZeroQuantityOffer.selector);
        recipeMarketHub.fillIPOffers(offerHash, 0, address(0), FRONTEND_FEE_RECIPIENT);
    }
}
