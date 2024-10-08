// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "src/base/RecipeKernelBase.sol";
import {ERC4626} from "src/RecipeKernel.sol";
import "src/WrappedVault.sol";

import { MockERC20, ERC20 } from "../../mocks/MockERC20.sol";
import { MockERC4626 } from "test/mocks/MockERC4626.sol";
import { RecipeKernelTestBase } from "../../utils/RecipeKernel/RecipeKernelTestBase.sol";
import { FixedPointMathLib } from "lib/solmate/src/utils/FixedPointMathLib.sol";

contract Test_Fill_APOffer_RecipeKernel is RecipeKernelTestBase {
    using FixedPointMathLib for uint256;

    address AP_ADDRESS;
    address IP_ADDRESS;
    address FRONTEND_FEE_RECIPIENT;

    function setUp() external {
        uint256 protocolFee = 0.01e18; // 1% protocol fee
        uint256 minimumFrontendFee = 0.001e18; // 0.1% minimum frontend fee
        setUpRecipeKernelTests(protocolFee, minimumFrontendFee);

        AP_ADDRESS = ALICE_ADDRESS;
        IP_ADDRESS = DAN_ADDRESS;
        FRONTEND_FEE_RECIPIENT = CHARLIE_ADDRESS;
    }

    function test_DirectFill_Upfront_APOffer_ForTokens() external {
        uint256 frontendFee = recipeKernel.minimumFrontendFee();
        uint256 marketId = recipeKernel.createMarket(address(mockLiquidityToken), 30 days, frontendFee, NULL_RECIPE, NULL_RECIPE, RewardStyle.Upfront);

        uint256 offerAmount = 100_000e18; // Offer amount requested
        uint256 fillAmount = 25_000e18; // Fill amount

        (, RecipeKernelBase.APOffer memory offer) = createAPOffer_ForTokens(marketId, address(0), offerAmount, AP_ADDRESS);

        (, uint256 expectedFrontendFeeAmount, uint256 expectedProtocolFeeAmount, uint256 expectedIncentiveAmount) =
            calculateAPOfferExpectedIncentiveAndFrontendFee(recipeKernel.protocolFee(), frontendFee, offerAmount, fillAmount, 1000e18);

        // Mint liquidity tokens to the AP to be able to pay IP who fills it
        mockLiquidityToken.mint(AP_ADDRESS, offerAmount);
        vm.startPrank(AP_ADDRESS);
        mockLiquidityToken.approve(address(recipeKernel), fillAmount);
        vm.stopPrank();

        // Mint incentive tokens to IP
        mockIncentiveToken.mint(IP_ADDRESS, fillAmount);
        vm.startPrank(IP_ADDRESS);
        mockIncentiveToken.approve(address(recipeKernel), fillAmount);

        // Expect events for transfers
        vm.expectEmit(true, false, false, true, address(mockIncentiveToken));
        emit ERC20.Transfer(IP_ADDRESS, address(recipeKernel), expectedFrontendFeeAmount + expectedProtocolFeeAmount);

        vm.expectEmit(true, true, false, true, address(mockIncentiveToken));
        emit ERC20.Transfer(IP_ADDRESS, AP_ADDRESS, expectedIncentiveAmount);

        vm.expectEmit(true, false, false, true, address(mockLiquidityToken));
        emit ERC20.Transfer(AP_ADDRESS, address(0), fillAmount);

        // Expect events for offer fill
        vm.expectEmit(false, false, false, false);
        emit RecipeKernelBase.APOfferFilled(0, 0, address(0), new uint256[](0), new uint256[](0), new uint256[](0));

        vm.recordLogs();

        recipeKernel.fillAPOffers(offer, fillAmount, FRONTEND_FEE_RECIPIENT);
        vm.stopPrank();

        uint256 resultingRemainingQuantity = recipeKernel.offerHashToRemainingQuantity(recipeKernel.getOfferHash(offer));
        assertEq(resultingRemainingQuantity, offerAmount - fillAmount);

        // Ensure the ap got the incentives upfront
        assertEq(mockIncentiveToken.balanceOf(AP_ADDRESS), expectedIncentiveAmount);

        // Extract the Weiroll wallet address (the 'to' address from the Transfer event - third event in logs)
        address weirollWallet = address(uint160(uint256(vm.getRecordedLogs()[2].topics[2])));

        // Ensure there is a weirollWallet at the expected address
        assertGt(weirollWallet.code.length, 0);

        // Ensure that the deposit recipe was executed
        assertEq(WeirollWallet(payable(weirollWallet)).executed(), true);

        // Ensure the weiroll wallet got the liquidity
        assertEq(mockLiquidityToken.balanceOf(weirollWallet), fillAmount);

        // Check the frontend fee recipient received the correct fee
        assertEq(recipeKernel.feeClaimantToTokenToAmount(FRONTEND_FEE_RECIPIENT, address(mockIncentiveToken)), expectedFrontendFeeAmount);

        // Check the protocol fee claimant received the correct fee
        assertEq(recipeKernel.feeClaimantToTokenToAmount(OWNER_ADDRESS, address(mockIncentiveToken)), expectedProtocolFeeAmount);
    }

    function test_DirectFullFill_Upfront_APOffer_ForTokens() external {
        uint256 frontendFee = recipeKernel.minimumFrontendFee();
        uint256 marketId = recipeKernel.createMarket(address(mockLiquidityToken), 30 days, frontendFee, NULL_RECIPE, NULL_RECIPE, RewardStyle.Upfront);

        uint256 offerAmount = 100_000e18; // Offer amount requested
        uint256 fillAmount = 100_000e18; // Fill amount

        (, RecipeKernelBase.APOffer memory offer) = createAPOffer_ForTokens(marketId, address(0), offerAmount, AP_ADDRESS);

        (, uint256 expectedFrontendFeeAmount, uint256 expectedProtocolFeeAmount, uint256 expectedIncentiveAmount) =
            calculateAPOfferExpectedIncentiveAndFrontendFee(recipeKernel.protocolFee(), frontendFee, offerAmount, fillAmount, 1000e18);

        // Mint liquidity tokens to the AP to be able to pay IP who fills it
        mockLiquidityToken.mint(AP_ADDRESS, offerAmount);
        vm.startPrank(AP_ADDRESS);
        mockLiquidityToken.approve(address(recipeKernel), fillAmount);
        vm.stopPrank();

        // Mint incentive tokens to IP
        mockIncentiveToken.mint(IP_ADDRESS, fillAmount);
        vm.startPrank(IP_ADDRESS);
        mockIncentiveToken.approve(address(recipeKernel), fillAmount);

        // Expect events for transfers
        vm.expectEmit(true, false, false, true, address(mockIncentiveToken));
        emit ERC20.Transfer(IP_ADDRESS, address(recipeKernel), expectedFrontendFeeAmount + expectedProtocolFeeAmount);

        vm.expectEmit(true, true, false, true, address(mockIncentiveToken));
        emit ERC20.Transfer(IP_ADDRESS, AP_ADDRESS, expectedIncentiveAmount);

        vm.expectEmit(true, false, false, true, address(mockLiquidityToken));
        emit ERC20.Transfer(AP_ADDRESS, address(0), fillAmount);

        // Expect events for offer fill
        vm.expectEmit(false, false, false, false);
        emit RecipeKernelBase.APOfferFilled(0, 0, address(0), new uint256[](0), new uint256[](0), new uint256[](0));

        vm.recordLogs();

        recipeKernel.fillAPOffers(offer, type(uint256).max, FRONTEND_FEE_RECIPIENT);
        vm.stopPrank();

        uint256 resultingRemainingQuantity = recipeKernel.offerHashToRemainingQuantity(recipeKernel.getOfferHash(offer));
        assertEq(resultingRemainingQuantity, offerAmount - fillAmount);

        // Ensure the ap got the incentives upfront
        assertEq(mockIncentiveToken.balanceOf(AP_ADDRESS), expectedIncentiveAmount);

        // Extract the Weiroll wallet address (the 'to' address from the Transfer event - third event in logs)
        address weirollWallet = address(uint160(uint256(vm.getRecordedLogs()[2].topics[2])));

        // Ensure there is a weirollWallet at the expected address
        assertGt(weirollWallet.code.length, 0);

        // Ensure that the deposit recipe was executed
        assertEq(WeirollWallet(payable(weirollWallet)).executed(), true);

        // Ensure the weiroll wallet got the liquidity
        assertEq(mockLiquidityToken.balanceOf(weirollWallet), fillAmount);

        // Check the frontend fee recipient received the correct fee
        assertEq(recipeKernel.feeClaimantToTokenToAmount(FRONTEND_FEE_RECIPIENT, address(mockIncentiveToken)), expectedFrontendFeeAmount);

        // Check the protocol fee claimant received the correct fee
        assertEq(recipeKernel.feeClaimantToTokenToAmount(OWNER_ADDRESS, address(mockIncentiveToken)), expectedProtocolFeeAmount);
    }

    function test_DirectFill_Upfront_APOffer_ForPoints() external {
        uint256 frontendFee = recipeKernel.minimumFrontendFee();
        uint256 marketId = recipeKernel.createMarket(address(mockLiquidityToken), 30 days, frontendFee, NULL_RECIPE, NULL_RECIPE, RewardStyle.Upfront);

        uint256 offerAmount = 100_000e18; // Offer amount requested
        uint256 fillAmount = 25_000e18; // Fill amount

        // Create a fillable IP offer
        (, RecipeKernelBase.APOffer memory offer, Points points) = createAPOffer_ForPoints(marketId, address(0), offerAmount, AP_ADDRESS, IP_ADDRESS);

        (, uint256 expectedFrontendFeeAmount, uint256 expectedProtocolFeeAmount, uint256 expectedIncentiveAmount) =
            calculateAPOfferExpectedIncentiveAndFrontendFee(recipeKernel.protocolFee(), frontendFee, offerAmount, fillAmount, 1000e18);

        // Mint liquidity tokens to the AP to be able to pay IP who fills it
        mockLiquidityToken.mint(AP_ADDRESS, offerAmount);
        vm.startPrank(AP_ADDRESS);
        mockLiquidityToken.approve(address(recipeKernel), fillAmount);
        vm.stopPrank();

        // Mint incentive tokens to IP
        mockIncentiveToken.mint(IP_ADDRESS, fillAmount);
        vm.startPrank(IP_ADDRESS);
        mockIncentiveToken.approve(address(recipeKernel), fillAmount);

        // Expect events for awards and transfer
        vm.expectEmit(true, true, false, true, address(points));
        emit Points.Award(OWNER_ADDRESS, expectedProtocolFeeAmount);

        vm.expectEmit(true, true, false, true, address(points));
        emit Points.Award(FRONTEND_FEE_RECIPIENT, expectedFrontendFeeAmount);

        vm.expectEmit(true, true, false, true, address(points));
        emit Points.Award(AP_ADDRESS, expectedIncentiveAmount);

        vm.expectEmit(true, false, false, true, address(mockLiquidityToken));
        emit ERC20.Transfer(AP_ADDRESS, address(0), fillAmount);

        vm.expectEmit(false, false, false, false, address(recipeKernel));
        emit RecipeKernelBase.APOfferFilled(0, 0, address(0), new uint256[](0), new uint256[](0), new uint256[](0));

        // Record the logs to capture Transfer events to get Weiroll wallet address
        vm.recordLogs();

        recipeKernel.fillAPOffers(offer, fillAmount, FRONTEND_FEE_RECIPIENT);
        vm.stopPrank();

        uint256 resultingRemainingQuantity = recipeKernel.offerHashToRemainingQuantity(recipeKernel.getOfferHash(offer));
        assertEq(resultingRemainingQuantity, offerAmount - fillAmount);

        // Extract the Weiroll wallet address (the 'to' address from the Transfer event - third event in logs)
        address weirollWallet = address(uint160(uint256(vm.getRecordedLogs()[3].topics[2])));

        // Ensure there is a weirollWallet at the expected address
        assertGt(weirollWallet.code.length, 0);

        // Ensure that the deposit recipe was executed
        assertEq(WeirollWallet(payable(weirollWallet)).executed(), true);

        // Ensure the weiroll wallet got the liquidity
        assertEq(mockLiquidityToken.balanceOf(weirollWallet), fillAmount);
    }

    function test_VaultFill_Upfront_APOffer_ForTokens() external {
        uint256 frontendFee = recipeKernel.minimumFrontendFee();
        uint256 marketId = recipeKernel.createMarket(address(mockLiquidityToken), 30 days, frontendFee, NULL_RECIPE, NULL_RECIPE, RewardStyle.Upfront);

        uint256 offerAmount = 100_000e18; // Offer amount requested
        uint256 fillAmount = 25_000e18; // Fill amount

        (, RecipeKernelBase.APOffer memory offer) = createAPOffer_ForTokens(marketId, address(mockVault), offerAmount, AP_ADDRESS);

        (, uint256 expectedFrontendFeeAmount, uint256 expectedProtocolFeeAmount, uint256 expectedIncentiveAmount) =
            calculateAPOfferExpectedIncentiveAndFrontendFee(recipeKernel.protocolFee(), frontendFee, offerAmount, fillAmount, 1000e18);

        // Mint liquidity tokens to deposit into the vault
        mockLiquidityToken.mint(AP_ADDRESS, fillAmount);
        vm.startPrank(AP_ADDRESS);
        mockLiquidityToken.approve(address(mockVault), fillAmount);

        // Deposit tokens into the vault and approve recipeKernel to spend them
        mockVault.deposit(fillAmount, AP_ADDRESS);
        mockVault.approve(address(recipeKernel), fillAmount);
        vm.stopPrank();

        // Mint incentive tokens to IP
        mockIncentiveToken.mint(IP_ADDRESS, fillAmount);
        vm.startPrank(IP_ADDRESS);
        mockIncentiveToken.approve(address(recipeKernel), fillAmount);

        // Expect events for transfers
        vm.expectEmit(true, false, false, true, address(mockIncentiveToken));
        emit ERC20.Transfer(IP_ADDRESS, address(recipeKernel), expectedFrontendFeeAmount + expectedProtocolFeeAmount);

        vm.expectEmit(true, true, false, true, address(mockIncentiveToken));
        emit ERC20.Transfer(IP_ADDRESS, AP_ADDRESS, expectedIncentiveAmount);

        vm.expectEmit(true, false, true, false, address(mockVault));
        emit ERC4626.Withdraw(address(recipeKernel), address(0), AP_ADDRESS, fillAmount, 0);

        vm.expectEmit(true, false, false, true, address(mockLiquidityToken));
        emit ERC20.Transfer(address(mockVault), address(0), fillAmount);

        // Expect events for offer fill
        vm.expectEmit(false, false, false, false);
        emit RecipeKernelBase.APOfferFilled(0, 0, address(0), new uint256[](0), new uint256[](0), new uint256[](0));

        vm.recordLogs();

        recipeKernel.fillAPOffers(offer, fillAmount, FRONTEND_FEE_RECIPIENT);
        vm.stopPrank();

        uint256 resultingRemainingQuantity = recipeKernel.offerHashToRemainingQuantity(recipeKernel.getOfferHash(offer));
        assertEq(resultingRemainingQuantity, offerAmount - fillAmount);

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
        assertEq(recipeKernel.feeClaimantToTokenToAmount(FRONTEND_FEE_RECIPIENT, address(mockIncentiveToken)), expectedFrontendFeeAmount);

        // Check the protocol fee claimant received the correct fee
        assertEq(recipeKernel.feeClaimantToTokenToAmount(OWNER_ADDRESS, address(mockIncentiveToken)), expectedProtocolFeeAmount);
    }

    function test_VaultFill_Upfront_IPOffer_ForPoints() external {
        uint256 frontendFee = recipeKernel.minimumFrontendFee();
        uint256 marketId = recipeKernel.createMarket(address(mockLiquidityToken), 30 days, frontendFee, NULL_RECIPE, NULL_RECIPE, RewardStyle.Upfront);

        uint256 offerAmount = 100_000e18; // Offer amount requested
        uint256 fillAmount = 25_000e18; // Fill amount

        // Create a fillable IP offer
        (, RecipeKernelBase.APOffer memory offer, Points points) = createAPOffer_ForPoints(marketId, address(mockVault), offerAmount, AP_ADDRESS, IP_ADDRESS);

        (, uint256 expectedFrontendFeeAmount, uint256 expectedProtocolFeeAmount, uint256 expectedIncentiveAmount) =
            calculateAPOfferExpectedIncentiveAndFrontendFee(recipeKernel.protocolFee(), frontendFee, offerAmount, fillAmount, 1000e18);

        // Mint liquidity tokens to deposit into the vault
        mockLiquidityToken.mint(AP_ADDRESS, fillAmount);
        vm.startPrank(AP_ADDRESS);
        mockLiquidityToken.approve(address(mockVault), fillAmount);

        // Deposit tokens into the vault and approve recipeKernel to spend them
        mockVault.deposit(fillAmount, AP_ADDRESS);
        mockVault.approve(address(recipeKernel), fillAmount);

        vm.stopPrank();

        // Expect events for awards and transfer
        vm.expectEmit(true, true, false, true, address(points));
        emit Points.Award(OWNER_ADDRESS, expectedProtocolFeeAmount);

        vm.expectEmit(true, true, false, true, address(points));
        emit Points.Award(FRONTEND_FEE_RECIPIENT, expectedFrontendFeeAmount);

        vm.expectEmit(true, true, false, true, address(points));
        emit Points.Award(AP_ADDRESS, expectedIncentiveAmount);

        vm.expectEmit(true, false, true, false, address(mockVault));
        emit ERC4626.Withdraw(address(recipeKernel), address(0), AP_ADDRESS, fillAmount, 0);

        vm.expectEmit(true, false, false, true, address(mockLiquidityToken));
        emit ERC20.Transfer(address(mockVault), address(0), fillAmount);

        vm.expectEmit(false, false, false, false, address(recipeKernel));
        emit RecipeKernelBase.APOfferFilled(0, 0, address(0), new uint256[](0), new uint256[](0), new uint256[](0));

        // Record the logs to capture Transfer events to get Weiroll wallet address
        vm.recordLogs();

        vm.startPrank(IP_ADDRESS);
        recipeKernel.fillAPOffers(offer, fillAmount, FRONTEND_FEE_RECIPIENT);
        vm.stopPrank();

        uint256 resultingRemainingQuantity = recipeKernel.offerHashToRemainingQuantity(recipeKernel.getOfferHash(offer));
        assertEq(resultingRemainingQuantity, offerAmount - fillAmount);

        // Extract the Weiroll wallet address (the 'to' address from the Transfer event - third event in logs)
        address weirollWallet = address(uint160(uint256(vm.getRecordedLogs()[4].topics[2])));

        // Ensure there is a weirollWallet at the expected address
        assertGt(weirollWallet.code.length, 0);

        // Ensure that the deposit recipe was executed
        assertEq(WeirollWallet(payable(weirollWallet)).executed(), true);

        // Ensure the weiroll wallet got the liquidity
        assertEq(mockLiquidityToken.balanceOf(weirollWallet), fillAmount);
    }

    function test_DirectFill_Forfeitable_APOffer_ForTokens() external {
        uint256 frontendFee = recipeKernel.minimumFrontendFee();
        uint256 marketId = recipeKernel.createMarket(address(mockLiquidityToken), 30 days, frontendFee, NULL_RECIPE, NULL_RECIPE, RewardStyle.Forfeitable);

        uint256 offerAmount = 100_000e18; // Offer amount requested
        uint256 fillAmount = 25_000e18; // Fill amount

        (, RecipeKernelBase.APOffer memory offer) = createAPOffer_ForTokens(marketId, address(0), offerAmount, AP_ADDRESS);

        (, uint256 expectedFrontendFeeAmount, uint256 expectedProtocolFeeAmount, uint256 expectedIncentiveAmount) =
            calculateAPOfferExpectedIncentiveAndFrontendFee(recipeKernel.protocolFee(), frontendFee, offerAmount, fillAmount, 1000e18);

        // Mint liquidity tokens to the AP to be able to pay IP who fills it
        mockLiquidityToken.mint(AP_ADDRESS, offerAmount);
        vm.startPrank(AP_ADDRESS);
        mockLiquidityToken.approve(address(recipeKernel), fillAmount);
        vm.stopPrank();

        // Mint incentive tokens to IP
        mockIncentiveToken.mint(IP_ADDRESS, fillAmount);
        vm.startPrank(IP_ADDRESS);
        mockIncentiveToken.approve(address(recipeKernel), fillAmount);

        // Expect events for transfers
        vm.expectEmit(true, false, false, true, address(mockIncentiveToken));
        emit ERC20.Transfer(IP_ADDRESS, address(recipeKernel), expectedFrontendFeeAmount + expectedProtocolFeeAmount + expectedIncentiveAmount);

        vm.expectEmit(true, false, false, true, address(mockLiquidityToken));
        emit ERC20.Transfer(AP_ADDRESS, address(0), fillAmount);

        // Expect events for offer fill
        vm.expectEmit(false, false, false, false);
        emit RecipeKernelBase.APOfferFilled(0, 0, address(0), new uint256[](0), new uint256[](0), new uint256[](0));

        vm.recordLogs();

        recipeKernel.fillAPOffers(offer, fillAmount, FRONTEND_FEE_RECIPIENT);
        vm.stopPrank();

        uint256 resultingRemainingQuantity = recipeKernel.offerHashToRemainingQuantity(recipeKernel.getOfferHash(offer));
        assertEq(resultingRemainingQuantity, offerAmount - fillAmount);

        // Extract the Weiroll wallet address (the 'to' address from the Transfer event - third event in logs)
        address weirollWallet = address(uint160(uint256(vm.getRecordedLogs()[1].topics[2])));

        (, uint256[] memory amounts,) = recipeKernel.getLockedIncentiveParams(weirollWallet);
        assertEq(amounts[0], expectedIncentiveAmount);

        // Ensure there is a weirollWallet at the expected address
        assertGt(weirollWallet.code.length, 0);

        // Ensure that the deposit recipe was executed
        assertEq(WeirollWallet(payable(weirollWallet)).executed(), true);

        // Ensure the weiroll wallet got the liquidity
        assertEq(mockLiquidityToken.balanceOf(weirollWallet), fillAmount);

        // Check the frontend fee recipient received the correct fee
        assertEq(recipeKernel.feeClaimantToTokenToAmount(FRONTEND_FEE_RECIPIENT, address(mockIncentiveToken)), 0);

        // Check the protocol fee claimant received the correct fee
        assertEq(recipeKernel.feeClaimantToTokenToAmount(OWNER_ADDRESS, address(mockIncentiveToken)), 0);
    }

    function test_DirectFill_Forfeitable_APOffer_ForPoints() external {
        uint256 frontendFee = recipeKernel.minimumFrontendFee();
        uint256 marketId = recipeKernel.createMarket(address(mockLiquidityToken), 30 days, frontendFee, NULL_RECIPE, NULL_RECIPE, RewardStyle.Forfeitable);

        uint256 offerAmount = 100_000e18; // Offer amount requested
        uint256 fillAmount = 25_000e18; // Fill amount

        // Create a fillable IP offer
        (, RecipeKernelBase.APOffer memory offer, Points points) = createAPOffer_ForPoints(marketId, address(0), offerAmount, AP_ADDRESS, IP_ADDRESS);

        (, uint256 expectedFrontendFeeAmount, uint256 expectedProtocolFeeAmount, uint256 expectedIncentiveAmount) =
            calculateAPOfferExpectedIncentiveAndFrontendFee(recipeKernel.protocolFee(), frontendFee, offerAmount, fillAmount, 1000e18);

        // Mint liquidity tokens to the AP to be able to pay IP who fills it
        mockLiquidityToken.mint(AP_ADDRESS, offerAmount);
        vm.startPrank(AP_ADDRESS);
        mockLiquidityToken.approve(address(recipeKernel), fillAmount);
        vm.stopPrank();

        // Mint incentive tokens to IP
        mockIncentiveToken.mint(IP_ADDRESS, fillAmount);
        vm.startPrank(IP_ADDRESS);
        mockIncentiveToken.approve(address(recipeKernel), fillAmount);

        vm.expectEmit(true, false, false, true, address(mockLiquidityToken));
        emit ERC20.Transfer(AP_ADDRESS, address(0), fillAmount);

        vm.expectEmit(false, false, false, false, address(recipeKernel));
        emit RecipeKernelBase.APOfferFilled(0, 0, address(0), new uint256[](0), new uint256[](0), new uint256[](0));

        // Record the logs to capture Transfer events to get Weiroll wallet address
        vm.recordLogs();

        recipeKernel.fillAPOffers(offer, fillAmount, FRONTEND_FEE_RECIPIENT);
        vm.stopPrank();

        uint256 resultingRemainingQuantity = recipeKernel.offerHashToRemainingQuantity(recipeKernel.getOfferHash(offer));
        assertEq(resultingRemainingQuantity, offerAmount - fillAmount);

        // Extract the Weiroll wallet address (the 'to' address from the Transfer event - third event in logs)
        address weirollWallet = address(uint160(uint256(vm.getRecordedLogs()[0].topics[2])));

        (, uint256[] memory amounts,) = recipeKernel.getLockedIncentiveParams(weirollWallet);
        assertEq(amounts[0], expectedIncentiveAmount);

        // Ensure there is a weirollWallet at the expected address
        assertGt(weirollWallet.code.length, 0);

        // Ensure that the deposit recipe was executed
        assertEq(WeirollWallet(payable(weirollWallet)).executed(), true);

        // Ensure the weiroll wallet got the liquidity
        assertEq(mockLiquidityToken.balanceOf(weirollWallet), fillAmount);
    }

    function test_VaultFill_Forfeitable_APOffer_ForTokens() external {
        uint256 frontendFee = recipeKernel.minimumFrontendFee();
        uint256 marketId = recipeKernel.createMarket(address(mockLiquidityToken), 30 days, frontendFee, NULL_RECIPE, NULL_RECIPE, RewardStyle.Forfeitable);

        uint256 offerAmount = 100_000e18; // Offer amount requested
        uint256 fillAmount = 25_000e18; // Fill amount

        (, RecipeKernelBase.APOffer memory offer) = createAPOffer_ForTokens(marketId, address(mockVault), offerAmount, AP_ADDRESS);

        (, uint256 expectedFrontendFeeAmount, uint256 expectedProtocolFeeAmount, uint256 expectedIncentiveAmount) =
            calculateAPOfferExpectedIncentiveAndFrontendFee(recipeKernel.protocolFee(), frontendFee, offerAmount, fillAmount, 1000e18);

        // Mint liquidity tokens to deposit into the vault
        mockLiquidityToken.mint(AP_ADDRESS, fillAmount);
        vm.startPrank(AP_ADDRESS);
        mockLiquidityToken.approve(address(mockVault), fillAmount);

        // Deposit tokens into the vault and approve recipeKernel to spend them
        mockVault.deposit(fillAmount, AP_ADDRESS);
        mockVault.approve(address(recipeKernel), fillAmount);
        vm.stopPrank();

        // Mint incentive tokens to IP
        mockIncentiveToken.mint(IP_ADDRESS, fillAmount);
        vm.startPrank(IP_ADDRESS);
        mockIncentiveToken.approve(address(recipeKernel), fillAmount);

        // Expect events for transfers
        vm.expectEmit(true, false, false, true, address(mockIncentiveToken));
        emit ERC20.Transfer(IP_ADDRESS, address(recipeKernel), expectedFrontendFeeAmount + expectedProtocolFeeAmount + expectedIncentiveAmount);

        vm.expectEmit(true, false, true, false, address(mockVault));
        emit ERC4626.Withdraw(address(recipeKernel), address(0), AP_ADDRESS, fillAmount, 0);

        vm.expectEmit(true, false, false, true, address(mockLiquidityToken));
        emit ERC20.Transfer(address(mockVault), address(0), fillAmount);

        // Expect events for offer fill
        vm.expectEmit(false, false, false, false);
        emit RecipeKernelBase.APOfferFilled(0, 0, address(0), new uint256[](0), new uint256[](0), new uint256[](0));

        vm.recordLogs();

        recipeKernel.fillAPOffers(offer, fillAmount, FRONTEND_FEE_RECIPIENT);
        vm.stopPrank();

        uint256 resultingRemainingQuantity = recipeKernel.offerHashToRemainingQuantity(recipeKernel.getOfferHash(offer));
        assertEq(resultingRemainingQuantity, offerAmount - fillAmount);

        // Extract the Weiroll wallet address (the 'to' address from the third Transfer event)
        address weirollWallet = address(uint160(uint256(vm.getRecordedLogs()[2].topics[2])));

        (, uint256[] memory amounts,) = recipeKernel.getLockedIncentiveParams(weirollWallet);
        assertEq(amounts[0], expectedIncentiveAmount);

        // Ensure there is a weirollWallet at the expected address
        assertGt(weirollWallet.code.length, 0);

        // Ensure that the deposit recipe was executed
        assertEq(WeirollWallet(payable(weirollWallet)).executed(), true);

        // Ensure the weiroll wallet got the liquidity
        assertEq(mockLiquidityToken.balanceOf(weirollWallet), fillAmount);

        // Check the frontend fee recipient received the correct fee
        assertEq(recipeKernel.feeClaimantToTokenToAmount(FRONTEND_FEE_RECIPIENT, address(mockIncentiveToken)), 0);

        // Check the protocol fee claimant received the correct fee
        assertEq(recipeKernel.feeClaimantToTokenToAmount(OWNER_ADDRESS, address(mockIncentiveToken)), 0);
    }

    function test_VaultFill_Forfeitable_IPOffer_ForPoints() external {
        uint256 frontendFee = recipeKernel.minimumFrontendFee();
        uint256 marketId = recipeKernel.createMarket(address(mockLiquidityToken), 30 days, frontendFee, NULL_RECIPE, NULL_RECIPE, RewardStyle.Forfeitable);

        uint256 offerAmount = 100_000e18; // Offer amount requested
        uint256 fillAmount = 25_000e18; // Fill amount

        // Create a fillable IP offer
        (, RecipeKernelBase.APOffer memory offer, Points points) = createAPOffer_ForPoints(marketId, address(mockVault), offerAmount, AP_ADDRESS, IP_ADDRESS);

        (, uint256 expectedFrontendFeeAmount, uint256 expectedProtocolFeeAmount, uint256 expectedIncentiveAmount) =
            calculateAPOfferExpectedIncentiveAndFrontendFee(recipeKernel.protocolFee(), frontendFee, offerAmount, fillAmount, 1000e18);

        // Mint liquidity tokens to deposit into the vault
        mockLiquidityToken.mint(AP_ADDRESS, fillAmount);
        vm.startPrank(AP_ADDRESS);
        mockLiquidityToken.approve(address(mockVault), fillAmount);

        // Deposit tokens into the vault and approve recipeKernel to spend them
        mockVault.deposit(fillAmount, AP_ADDRESS);
        mockVault.approve(address(recipeKernel), fillAmount);

        vm.stopPrank();

        vm.expectEmit(true, false, true, false, address(mockVault));
        emit ERC4626.Withdraw(address(recipeKernel), address(0), AP_ADDRESS, fillAmount, 0);

        vm.expectEmit(true, false, false, true, address(mockLiquidityToken));
        emit ERC20.Transfer(address(mockVault), address(0), fillAmount);

        vm.expectEmit(false, false, false, false, address(recipeKernel));
        emit RecipeKernelBase.APOfferFilled(0, 0, address(0), new uint256[](0), new uint256[](0), new uint256[](0));

        // Record the logs to capture Transfer events to get Weiroll wallet address
        vm.recordLogs();

        vm.startPrank(IP_ADDRESS);
        recipeKernel.fillAPOffers(offer, fillAmount, FRONTEND_FEE_RECIPIENT);
        vm.stopPrank();

        uint256 resultingRemainingQuantity = recipeKernel.offerHashToRemainingQuantity(recipeKernel.getOfferHash(offer));
        assertEq(resultingRemainingQuantity, offerAmount - fillAmount);

        // Extract the Weiroll wallet address (the 'to' address from the Transfer event - third event in logs)
        address weirollWallet = address(uint160(uint256(vm.getRecordedLogs()[1].topics[2])));

        (, uint256[] memory amounts,) = recipeKernel.getLockedIncentiveParams(weirollWallet);
        assertEq(amounts[0], expectedIncentiveAmount);

        // Ensure there is a weirollWallet at the expected address
        assertGt(weirollWallet.code.length, 0);

        // Ensure that the deposit recipe was executed
        assertEq(WeirollWallet(payable(weirollWallet)).executed(), true);

        // Ensure the weiroll wallet got the liquidity
        assertEq(mockLiquidityToken.balanceOf(weirollWallet), fillAmount);
    }

    function test_DirectFill_Arrear_APOffer_ForTokens() external {
        uint256 frontendFee = recipeKernel.minimumFrontendFee();
        uint256 marketId = recipeKernel.createMarket(address(mockLiquidityToken), 30 days, frontendFee, NULL_RECIPE, NULL_RECIPE, RewardStyle.Arrear);

        uint256 offerAmount = 100_000e18; // Offer amount requested
        uint256 fillAmount = 25_000e18; // Fill amount

        (, RecipeKernelBase.APOffer memory offer) = createAPOffer_ForTokens(marketId, address(0), offerAmount, AP_ADDRESS);

        (, uint256 expectedFrontendFeeAmount, uint256 expectedProtocolFeeAmount, uint256 expectedIncentiveAmount) =
            calculateAPOfferExpectedIncentiveAndFrontendFee(recipeKernel.protocolFee(), frontendFee, offerAmount, fillAmount, 1000e18);

        // Mint liquidity tokens to the AP to be able to pay IP who fills it
        mockLiquidityToken.mint(AP_ADDRESS, offerAmount);
        vm.startPrank(AP_ADDRESS);
        mockLiquidityToken.approve(address(recipeKernel), fillAmount);
        vm.stopPrank();

        // Mint incentive tokens to IP
        mockIncentiveToken.mint(IP_ADDRESS, fillAmount);
        vm.startPrank(IP_ADDRESS);
        mockIncentiveToken.approve(address(recipeKernel), fillAmount);

        // Expect events for transfers
        vm.expectEmit(true, false, false, true, address(mockIncentiveToken));
        emit ERC20.Transfer(IP_ADDRESS, address(recipeKernel), expectedFrontendFeeAmount + expectedProtocolFeeAmount + expectedIncentiveAmount);

        vm.expectEmit(true, false, false, true, address(mockLiquidityToken));
        emit ERC20.Transfer(AP_ADDRESS, address(0), fillAmount);

        // Expect events for offer fill
        vm.expectEmit(false, false, false, false);
        emit RecipeKernelBase.APOfferFilled(0, 0, address(0), new uint256[](0), new uint256[](0), new uint256[](0));

        vm.recordLogs();

        recipeKernel.fillAPOffers(offer, fillAmount, FRONTEND_FEE_RECIPIENT);
        vm.stopPrank();

        uint256 resultingRemainingQuantity = recipeKernel.offerHashToRemainingQuantity(recipeKernel.getOfferHash(offer));
        assertEq(resultingRemainingQuantity, offerAmount - fillAmount);

        // Extract the Weiroll wallet address (the 'to' address from the Transfer event - third event in logs)
        address weirollWallet = address(uint160(uint256(vm.getRecordedLogs()[1].topics[2])));

        (, uint256[] memory amounts,) = recipeKernel.getLockedIncentiveParams(weirollWallet);
        assertEq(amounts[0], expectedIncentiveAmount);

        // Ensure there is a weirollWallet at the expected address
        assertGt(weirollWallet.code.length, 0);

        // Ensure that the deposit recipe was executed
        assertEq(WeirollWallet(payable(weirollWallet)).executed(), true);

        // Ensure the weiroll wallet got the liquidity
        assertEq(mockLiquidityToken.balanceOf(weirollWallet), fillAmount);

        // Check the frontend fee recipient received the correct fee
        assertEq(recipeKernel.feeClaimantToTokenToAmount(FRONTEND_FEE_RECIPIENT, address(mockIncentiveToken)), 0);

        // Check the protocol fee claimant received the correct fee
        assertEq(recipeKernel.feeClaimantToTokenToAmount(OWNER_ADDRESS, address(mockIncentiveToken)), 0);
    }

    function test_DirectFill_Arrear_APOffer_ForPoints() external {
        uint256 frontendFee = recipeKernel.minimumFrontendFee();
        uint256 marketId = recipeKernel.createMarket(address(mockLiquidityToken), 30 days, frontendFee, NULL_RECIPE, NULL_RECIPE, RewardStyle.Arrear);

        uint256 offerAmount = 100_000e18; // Offer amount requested
        uint256 fillAmount = 25_000e18; // Fill amount

        // Create a fillable IP offer
        (, RecipeKernelBase.APOffer memory offer, Points points) = createAPOffer_ForPoints(marketId, address(0), offerAmount, AP_ADDRESS, IP_ADDRESS);

        (, uint256 expectedFrontendFeeAmount, uint256 expectedProtocolFeeAmount, uint256 expectedIncentiveAmount) =
            calculateAPOfferExpectedIncentiveAndFrontendFee(recipeKernel.protocolFee(), frontendFee, offerAmount, fillAmount, 1000e18);

        // Mint liquidity tokens to the AP to be able to pay IP who fills it
        mockLiquidityToken.mint(AP_ADDRESS, offerAmount);
        vm.startPrank(AP_ADDRESS);
        mockLiquidityToken.approve(address(recipeKernel), fillAmount);
        vm.stopPrank();

        // Mint incentive tokens to IP
        mockIncentiveToken.mint(IP_ADDRESS, fillAmount);
        vm.startPrank(IP_ADDRESS);
        mockIncentiveToken.approve(address(recipeKernel), fillAmount);

        vm.expectEmit(true, false, false, true, address(mockLiquidityToken));
        emit ERC20.Transfer(AP_ADDRESS, address(0), fillAmount);

        vm.expectEmit(false, false, false, false, address(recipeKernel));
        emit RecipeKernelBase.APOfferFilled(0, 0, address(0), new uint256[](0), new uint256[](0), new uint256[](0));

        // Record the logs to capture Transfer events to get Weiroll wallet address
        vm.recordLogs();

        recipeKernel.fillAPOffers(offer, fillAmount, FRONTEND_FEE_RECIPIENT);
        vm.stopPrank();

        uint256 resultingRemainingQuantity = recipeKernel.offerHashToRemainingQuantity(recipeKernel.getOfferHash(offer));
        assertEq(resultingRemainingQuantity, offerAmount - fillAmount);

        // Extract the Weiroll wallet address (the 'to' address from the Transfer event - third event in logs)
        address weirollWallet = address(uint160(uint256(vm.getRecordedLogs()[0].topics[2])));

        (, uint256[] memory amounts,) = recipeKernel.getLockedIncentiveParams(weirollWallet);
        assertEq(amounts[0], expectedIncentiveAmount);

        // Ensure there is a weirollWallet at the expected address
        assertGt(weirollWallet.code.length, 0);

        // Ensure that the deposit recipe was executed
        assertEq(WeirollWallet(payable(weirollWallet)).executed(), true);

        // Ensure the weiroll wallet got the liquidity
        assertEq(mockLiquidityToken.balanceOf(weirollWallet), fillAmount);
    }

    function test_VaultFill_Arrear_APOffer_ForTokens() external {
        uint256 frontendFee = recipeKernel.minimumFrontendFee();
        uint256 marketId = recipeKernel.createMarket(address(mockLiquidityToken), 30 days, frontendFee, NULL_RECIPE, NULL_RECIPE, RewardStyle.Arrear);

        uint256 offerAmount = 100_000e18; // Offer amount requested
        uint256 fillAmount = 25_000e18; // Fill amount

        (, RecipeKernelBase.APOffer memory offer) = createAPOffer_ForTokens(marketId, address(mockVault), offerAmount, AP_ADDRESS);

        (, uint256 expectedFrontendFeeAmount, uint256 expectedProtocolFeeAmount, uint256 expectedIncentiveAmount) =
            calculateAPOfferExpectedIncentiveAndFrontendFee(recipeKernel.protocolFee(), frontendFee, offerAmount, fillAmount, 1000e18);

        // Mint liquidity tokens to deposit into the vault
        mockLiquidityToken.mint(AP_ADDRESS, fillAmount);
        vm.startPrank(AP_ADDRESS);
        mockLiquidityToken.approve(address(mockVault), fillAmount);

        // Deposit tokens into the vault and approve recipeKernel to spend them
        mockVault.deposit(fillAmount, AP_ADDRESS);
        mockVault.approve(address(recipeKernel), fillAmount);
        vm.stopPrank();

        // Mint incentive tokens to IP
        mockIncentiveToken.mint(IP_ADDRESS, fillAmount);
        vm.startPrank(IP_ADDRESS);
        mockIncentiveToken.approve(address(recipeKernel), fillAmount);

        // Expect events for transfers
        vm.expectEmit(true, false, false, true, address(mockIncentiveToken));
        emit ERC20.Transfer(IP_ADDRESS, address(recipeKernel), expectedFrontendFeeAmount + expectedProtocolFeeAmount + expectedIncentiveAmount);

        vm.expectEmit(true, false, true, false, address(mockVault));
        emit ERC4626.Withdraw(address(recipeKernel), address(0), AP_ADDRESS, fillAmount, 0);

        vm.expectEmit(true, false, false, true, address(mockLiquidityToken));
        emit ERC20.Transfer(address(mockVault), address(0), fillAmount);

        // Expect events for offer fill
        vm.expectEmit(false, false, false, false);
        emit RecipeKernelBase.APOfferFilled(0, 0, address(0), new uint256[](0), new uint256[](0), new uint256[](0));

        vm.recordLogs();

        recipeKernel.fillAPOffers(offer, fillAmount, FRONTEND_FEE_RECIPIENT);
        vm.stopPrank();

        uint256 resultingRemainingQuantity = recipeKernel.offerHashToRemainingQuantity(recipeKernel.getOfferHash(offer));
        assertEq(resultingRemainingQuantity, offerAmount - fillAmount);

        // Extract the Weiroll wallet address (the 'to' address from the third Transfer event)
        address weirollWallet = address(uint160(uint256(vm.getRecordedLogs()[2].topics[2])));

        (, uint256[] memory amounts,) = recipeKernel.getLockedIncentiveParams(weirollWallet);
        assertEq(amounts[0], expectedIncentiveAmount);

        // Ensure there is a weirollWallet at the expected address
        assertGt(weirollWallet.code.length, 0);

        // Ensure that the deposit recipe was executed
        assertEq(WeirollWallet(payable(weirollWallet)).executed(), true);

        // Ensure the weiroll wallet got the liquidity
        assertEq(mockLiquidityToken.balanceOf(weirollWallet), fillAmount);

        // Check the frontend fee recipient received the correct fee
        assertEq(recipeKernel.feeClaimantToTokenToAmount(FRONTEND_FEE_RECIPIENT, address(mockIncentiveToken)), 0);

        // Check the protocol fee claimant received the correct fee
        assertEq(recipeKernel.feeClaimantToTokenToAmount(OWNER_ADDRESS, address(mockIncentiveToken)), 0);
    }

    function test_VaultFill_Arrear_IPOffer_ForPoints() external {
        uint256 frontendFee = recipeKernel.minimumFrontendFee();
        uint256 marketId = recipeKernel.createMarket(address(mockLiquidityToken), 30 days, frontendFee, NULL_RECIPE, NULL_RECIPE, RewardStyle.Arrear);

        uint256 offerAmount = 100_000e18; // Offer amount requested
        uint256 fillAmount = 25_000e18; // Fill amount

        // Create a fillable IP offer
        (, RecipeKernelBase.APOffer memory offer, Points points) = createAPOffer_ForPoints(marketId, address(mockVault), offerAmount, AP_ADDRESS, IP_ADDRESS);

        (, uint256 expectedFrontendFeeAmount, uint256 expectedProtocolFeeAmount, uint256 expectedIncentiveAmount) =
            calculateAPOfferExpectedIncentiveAndFrontendFee(recipeKernel.protocolFee(), frontendFee, offerAmount, fillAmount, 1000e18);

        // Mint liquidity tokens to deposit into the vault
        mockLiquidityToken.mint(AP_ADDRESS, fillAmount);
        vm.startPrank(AP_ADDRESS);
        mockLiquidityToken.approve(address(mockVault), fillAmount);

        // Deposit tokens into the vault and approve recipeKernel to spend them
        mockVault.deposit(fillAmount, AP_ADDRESS);
        mockVault.approve(address(recipeKernel), fillAmount);

        vm.stopPrank();


        vm.expectEmit(true, false, true, false, address(mockVault));
        emit ERC4626.Withdraw(address(recipeKernel), address(0), AP_ADDRESS, fillAmount, 0);

        vm.expectEmit(true, false, false, true, address(mockLiquidityToken));
        emit ERC20.Transfer(address(mockVault), address(0), fillAmount);

        vm.expectEmit(false, false, false, false, address(recipeKernel));
        emit RecipeKernelBase.APOfferFilled(0, 0, address(0), new uint256[](0), new uint256[](0), new uint256[](0));

        // Record the logs to capture Transfer events to get Weiroll wallet address
        vm.recordLogs();

        vm.startPrank(IP_ADDRESS);
        recipeKernel.fillAPOffers(offer, fillAmount, FRONTEND_FEE_RECIPIENT);
        vm.stopPrank();

        uint256 resultingRemainingQuantity = recipeKernel.offerHashToRemainingQuantity(recipeKernel.getOfferHash(offer));
        assertEq(resultingRemainingQuantity, offerAmount - fillAmount);

        // Extract the Weiroll wallet address (the 'to' address from the Transfer event - third event in logs)
        address weirollWallet = address(uint160(uint256(vm.getRecordedLogs()[1].topics[2])));

        (, uint256[] memory amounts,) = recipeKernel.getLockedIncentiveParams(weirollWallet);
        assertEq(amounts[0], expectedIncentiveAmount);

        // Ensure there is a weirollWallet at the expected address
        assertGt(weirollWallet.code.length, 0);

        // Ensure that the deposit recipe was executed
        assertEq(WeirollWallet(payable(weirollWallet)).executed(), true);

        // Ensure the weiroll wallet got the liquidity
        assertEq(mockLiquidityToken.balanceOf(weirollWallet), fillAmount);
    }

    function test_RevertIf_NotEnoughRemainingQuantity_FillAPOffer() external {
        uint256 marketId = createMarket();

        uint256 offerAmount = 100_000e18;
        uint256 fillAmount = 100_001e18; // Fill amount exceeds the offer amount

        // Create a fillable AP offer
        (, RecipeKernelBase.APOffer memory offer) = createAPOffer_ForTokens(marketId, address(0), offerAmount, AP_ADDRESS);

        // Attempt to fill more than available, expecting a revert
        vm.expectRevert(RecipeKernelBase.NotEnoughRemainingQuantity.selector);
        recipeKernel.fillAPOffers(offer, fillAmount, FRONTEND_FEE_RECIPIENT);
    }

    function test_RevertIf_ZeroQuantityFill_FillAPOffer() external {
        uint256 marketId = createMarket();

        uint256 offerAmount = 100_000e18;

        // Create a fillable AP offer
        (, RecipeKernelBase.APOffer memory offer) = createAPOffer_ForTokens(marketId, address(0), offerAmount, AP_ADDRESS);

        // Attempt to fill with zero quantity, expecting a revert
        vm.expectRevert(RecipeKernelBase.CannotFillZeroQuantityOffer.selector);
        recipeKernel.fillAPOffers(offer, 0, FRONTEND_FEE_RECIPIENT);
    }

    function test_RevertIf_OfferExpired_FillAPOffer() external {
        uint256 marketId = createMarket();

        uint256 offerAmount = 100_000e18;

        // Create a fillable AP offer with a short expiry time
        (, RecipeKernelBase.APOffer memory offer) = createAPOffer_ForTokens(marketId, address(0), offerAmount, AP_ADDRESS);

        // Simulate the passage of time beyond the expiry
        vm.warp(block.timestamp + 31 days);

        // Attempt to fill an expired offer, expecting a revert
        vm.expectRevert(RecipeKernelBase.OfferExpired.selector);
        recipeKernel.fillAPOffers(offer, offerAmount, FRONTEND_FEE_RECIPIENT);
    }
}
