// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../../../src/RecipeOrderbook.sol";
import "../../../src/ERC4626i.sol";

import { MockERC20, ERC20 } from "../../mocks/MockERC20.sol";
import { MockERC4626 } from "test/mocks/MockERC4626.sol";
import { RecipeOrderbookTestBase } from "../../utils/RecipeOrderbook/RecipeOrderbookTestBase.sol";
import { FixedPointMathLib } from "lib/solmate/src/utils/FixedPointMathLib.sol";

contract Test_Fill_APOrder_RecipeOrderbook is RecipeOrderbookTestBase {
    using FixedPointMathLib for uint256;

    address AP_ADDRESS;
    address IP_ADDRESS;
    address FRONTEND_FEE_RECIPIENT;

    function setUp() external {
        uint256 protocolFee = 0.01e18; // 1% protocol fee
        uint256 minimumFrontendFee = 0.001e18; // 0.1% minimum frontend fee
        setUpRecipeOrderbookTests(protocolFee, minimumFrontendFee);

        AP_ADDRESS = ALICE_ADDRESS;
        IP_ADDRESS = DAN_ADDRESS;
        FRONTEND_FEE_RECIPIENT = CHARLIE_ADDRESS;
    }

    function test_DirectFill_Upfront_APOrder_ForTokens() external {
        uint256 frontendFee = orderbook.minimumFrontendFee();
        uint256 marketId = orderbook.createMarket(address(mockLiquidityToken), 30 days, frontendFee, NULL_RECIPE, NULL_RECIPE, RewardStyle.Upfront);

        uint256 orderAmount = 100_000e18; // Order amount requested
        uint256 fillAmount = 1000e18; // Fill amount

        (, RecipeOrderbook.APOrder memory order) = createAPOrder_ForTokens(marketId, address(0), orderAmount, AP_ADDRESS);

        (, uint256 expectedFrontendFeeAmount, uint256 expectedProtocolFeeAmount, uint256 expectedIncentiveAmount) =
            calculateAPOrderExpectedIncentiveAndFrontendFee(orderbook.protocolFee(), frontendFee, orderAmount, fillAmount, 1000e18);

        // Mint liquidity tokens to the AP to be able to pay IP who fills it
        mockLiquidityToken.mint(AP_ADDRESS, orderAmount);
        vm.startPrank(AP_ADDRESS);
        mockLiquidityToken.approve(address(orderbook), fillAmount);
        vm.stopPrank();

        // Mint incentive tokens to IP
        mockIncentiveToken.mint(IP_ADDRESS, fillAmount);
        vm.startPrank(IP_ADDRESS);
        mockIncentiveToken.approve(address(orderbook), fillAmount);

        // Expect events for transfers
        vm.expectEmit(true, false, false, true, address(mockIncentiveToken));
        emit ERC20.Transfer(IP_ADDRESS, address(orderbook), expectedFrontendFeeAmount + expectedProtocolFeeAmount);

        vm.expectEmit(true, true, false, true, address(mockIncentiveToken));
        emit ERC20.Transfer(IP_ADDRESS, AP_ADDRESS, expectedIncentiveAmount);

        vm.expectEmit(true, false, false, true, address(mockLiquidityToken));
        emit ERC20.Transfer(AP_ADDRESS, address(0), fillAmount);

        // Expect events for order fill
        vm.expectEmit(false, false, false, false);
        emit RecipeOrderbook.APOrderFilled(0, 0, address(0), 0, 0, address(0));

        vm.recordLogs();

        orderbook.fillAPOrder(order, fillAmount, FRONTEND_FEE_RECIPIENT);
        vm.stopPrank();

        uint256 resultingRemainingQuantity = orderbook.orderHashToRemainingQuantity(orderbook.getOrderHash(order));
        assertEq(resultingRemainingQuantity, orderAmount - fillAmount);

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
        assertEq(orderbook.feeClaimantToTokenToAmount(FRONTEND_FEE_RECIPIENT, address(mockIncentiveToken)), expectedFrontendFeeAmount);

        // Check the protocol fee claimant received the correct fee
        assertEq(orderbook.feeClaimantToTokenToAmount(OWNER_ADDRESS, address(mockIncentiveToken)), expectedProtocolFeeAmount);
    }

    function test_DirectFullFill_Upfront_APOrder_ForTokens() external {
        uint256 frontendFee = orderbook.minimumFrontendFee();
        uint256 marketId = orderbook.createMarket(address(mockLiquidityToken), 30 days, frontendFee, NULL_RECIPE, NULL_RECIPE, RewardStyle.Upfront);

        uint256 orderAmount = 100_000e18; // Order amount requested
        uint256 fillAmount = 100_000e18; // Fill amount

        (, RecipeOrderbook.APOrder memory order) = createAPOrder_ForTokens(marketId, address(0), orderAmount, AP_ADDRESS);

        (, uint256 expectedFrontendFeeAmount, uint256 expectedProtocolFeeAmount, uint256 expectedIncentiveAmount) =
            calculateAPOrderExpectedIncentiveAndFrontendFee(orderbook.protocolFee(), frontendFee, orderAmount, fillAmount, 1000e18);

        // Mint liquidity tokens to the AP to be able to pay IP who fills it
        mockLiquidityToken.mint(AP_ADDRESS, orderAmount);
        vm.startPrank(AP_ADDRESS);
        mockLiquidityToken.approve(address(orderbook), fillAmount);
        vm.stopPrank();

        // Mint incentive tokens to IP
        mockIncentiveToken.mint(IP_ADDRESS, fillAmount);
        vm.startPrank(IP_ADDRESS);
        mockIncentiveToken.approve(address(orderbook), fillAmount);

        // Expect events for transfers
        vm.expectEmit(true, false, false, true, address(mockIncentiveToken));
        emit ERC20.Transfer(IP_ADDRESS, address(orderbook), expectedFrontendFeeAmount + expectedProtocolFeeAmount);

        vm.expectEmit(true, true, false, true, address(mockIncentiveToken));
        emit ERC20.Transfer(IP_ADDRESS, AP_ADDRESS, expectedIncentiveAmount);

        vm.expectEmit(true, false, false, true, address(mockLiquidityToken));
        emit ERC20.Transfer(AP_ADDRESS, address(0), fillAmount);

        // Expect events for order fill
        vm.expectEmit(false, false, false, false);
        emit RecipeOrderbook.APOrderFilled(0, 0, address(0), 0, 0, address(0));

        vm.recordLogs();

        orderbook.fillAPOrder(order, type(uint256).max, FRONTEND_FEE_RECIPIENT);
        vm.stopPrank();

        uint256 resultingRemainingQuantity = orderbook.orderHashToRemainingQuantity(orderbook.getOrderHash(order));
        assertEq(resultingRemainingQuantity, orderAmount - fillAmount);

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
        assertEq(orderbook.feeClaimantToTokenToAmount(FRONTEND_FEE_RECIPIENT, address(mockIncentiveToken)), expectedFrontendFeeAmount);

        // Check the protocol fee claimant received the correct fee
        assertEq(orderbook.feeClaimantToTokenToAmount(OWNER_ADDRESS, address(mockIncentiveToken)), expectedProtocolFeeAmount);
    }

    function test_DirectFill_Upfront_APOrder_ForPoints() external {
        uint256 frontendFee = orderbook.minimumFrontendFee();
        uint256 marketId = orderbook.createMarket(address(mockLiquidityToken), 30 days, frontendFee, NULL_RECIPE, NULL_RECIPE, RewardStyle.Upfront);

        uint256 orderAmount = 100_000e18; // Order amount requested
        uint256 fillAmount = 1000e18; // Fill amount

        // Create a fillable IP order
        (, RecipeOrderbook.APOrder memory order, Points points) = createAPOrder_ForPoints(marketId, address(0), orderAmount, AP_ADDRESS, IP_ADDRESS);

        (, uint256 expectedFrontendFeeAmount, uint256 expectedProtocolFeeAmount, uint256 expectedIncentiveAmount) =
            calculateAPOrderExpectedIncentiveAndFrontendFee(orderbook.protocolFee(), frontendFee, orderAmount, fillAmount, 1000e18);

        // Mint liquidity tokens to the AP to be able to pay IP who fills it
        mockLiquidityToken.mint(AP_ADDRESS, orderAmount);
        vm.startPrank(AP_ADDRESS);
        mockLiquidityToken.approve(address(orderbook), fillAmount);
        vm.stopPrank();

        // Mint incentive tokens to IP
        mockIncentiveToken.mint(IP_ADDRESS, fillAmount);
        vm.startPrank(IP_ADDRESS);
        mockIncentiveToken.approve(address(orderbook), fillAmount);

        // Expect events for awards and transfer
        vm.expectEmit(true, true, false, true, address(points));
        emit Points.Award(OWNER_ADDRESS, expectedProtocolFeeAmount);

        vm.expectEmit(true, true, false, true, address(points));
        emit Points.Award(FRONTEND_FEE_RECIPIENT, expectedFrontendFeeAmount);

        vm.expectEmit(true, true, false, true, address(points));
        emit Points.Award(AP_ADDRESS, expectedIncentiveAmount);

        vm.expectEmit(true, false, false, true, address(mockLiquidityToken));
        emit ERC20.Transfer(AP_ADDRESS, address(0), fillAmount);

        vm.expectEmit(false, false, false, false, address(orderbook));
        emit RecipeOrderbook.APOrderFilled(0, 0, address(0), 0, 0, address(0));

        // Record the logs to capture Transfer events to get Weiroll wallet address
        vm.recordLogs();

        orderbook.fillAPOrder(order, fillAmount, FRONTEND_FEE_RECIPIENT);
        vm.stopPrank();

        uint256 resultingRemainingQuantity = orderbook.orderHashToRemainingQuantity(orderbook.getOrderHash(order));
        assertEq(resultingRemainingQuantity, orderAmount - fillAmount);

        // Extract the Weiroll wallet address (the 'to' address from the Transfer event - third event in logs)
        address weirollWallet = address(uint160(uint256(vm.getRecordedLogs()[3].topics[2])));

        // Ensure there is a weirollWallet at the expected address
        assertGt(weirollWallet.code.length, 0);

        // Ensure that the deposit recipe was executed
        assertEq(WeirollWallet(payable(weirollWallet)).executed(), true);

        // Ensure the weiroll wallet got the liquidity
        assertEq(mockLiquidityToken.balanceOf(weirollWallet), fillAmount);
    }

    function test_VaultFill_Upfront_APOrder_ForTokens() external {
        uint256 frontendFee = orderbook.minimumFrontendFee();
        uint256 marketId = orderbook.createMarket(address(mockLiquidityToken), 30 days, frontendFee, NULL_RECIPE, NULL_RECIPE, RewardStyle.Upfront);

        uint256 orderAmount = 100_000e18; // Order amount requested
        uint256 fillAmount = 1000e18; // Fill amount

        (, RecipeOrderbook.APOrder memory order) = createAPOrder_ForTokens(marketId, address(mockVault), orderAmount, AP_ADDRESS);

        (, uint256 expectedFrontendFeeAmount, uint256 expectedProtocolFeeAmount, uint256 expectedIncentiveAmount) =
            calculateAPOrderExpectedIncentiveAndFrontendFee(orderbook.protocolFee(), frontendFee, orderAmount, fillAmount, 1000e18);

        // Mint liquidity tokens to deposit into the vault
        mockLiquidityToken.mint(AP_ADDRESS, fillAmount);
        vm.startPrank(AP_ADDRESS);
        mockLiquidityToken.approve(address(mockVault), fillAmount);

        // Deposit tokens into the vault and approve orderbook to spend them
        mockVault.deposit(fillAmount, AP_ADDRESS);
        mockVault.approve(address(orderbook), fillAmount);
        vm.stopPrank();

        // Mint incentive tokens to IP
        mockIncentiveToken.mint(IP_ADDRESS, fillAmount);
        vm.startPrank(IP_ADDRESS);
        mockIncentiveToken.approve(address(orderbook), fillAmount);

        // Expect events for transfers
        vm.expectEmit(true, false, false, true, address(mockIncentiveToken));
        emit ERC20.Transfer(IP_ADDRESS, address(orderbook), expectedFrontendFeeAmount + expectedProtocolFeeAmount);

        vm.expectEmit(true, true, false, true, address(mockIncentiveToken));
        emit ERC20.Transfer(IP_ADDRESS, AP_ADDRESS, expectedIncentiveAmount);

        vm.expectEmit(true, false, true, false, address(mockVault));
        emit ERC4626.Withdraw(address(orderbook), address(0), AP_ADDRESS, fillAmount, 0);

        vm.expectEmit(true, false, false, true, address(mockLiquidityToken));
        emit ERC20.Transfer(address(mockVault), address(0), fillAmount);

        // Expect events for order fill
        vm.expectEmit(false, false, false, false);
        emit RecipeOrderbook.APOrderFilled(0, 0, address(0), 0, 0, address(0));

        vm.recordLogs();

        orderbook.fillAPOrder(order, fillAmount, FRONTEND_FEE_RECIPIENT);
        vm.stopPrank();

        uint256 resultingRemainingQuantity = orderbook.orderHashToRemainingQuantity(orderbook.getOrderHash(order));
        assertEq(resultingRemainingQuantity, orderAmount - fillAmount);

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
        assertEq(orderbook.feeClaimantToTokenToAmount(FRONTEND_FEE_RECIPIENT, address(mockIncentiveToken)), expectedFrontendFeeAmount);

        // Check the protocol fee claimant received the correct fee
        assertEq(orderbook.feeClaimantToTokenToAmount(OWNER_ADDRESS, address(mockIncentiveToken)), expectedProtocolFeeAmount);
    }

    function test_VaultFill_Upfront_IPOrder_ForPoints() external {
        uint256 frontendFee = orderbook.minimumFrontendFee();
        uint256 marketId = orderbook.createMarket(address(mockLiquidityToken), 30 days, frontendFee, NULL_RECIPE, NULL_RECIPE, RewardStyle.Upfront);

        uint256 orderAmount = 100_000e18; // Order amount requested
        uint256 fillAmount = 1000e18; // Fill amount

        // Create a fillable IP order
        (, RecipeOrderbook.APOrder memory order, Points points) = createAPOrder_ForPoints(marketId, address(mockVault), orderAmount, AP_ADDRESS, IP_ADDRESS);

        (, uint256 expectedFrontendFeeAmount, uint256 expectedProtocolFeeAmount, uint256 expectedIncentiveAmount) =
            calculateAPOrderExpectedIncentiveAndFrontendFee(orderbook.protocolFee(), frontendFee, orderAmount, fillAmount, 1000e18);

        // Mint liquidity tokens to deposit into the vault
        mockLiquidityToken.mint(AP_ADDRESS, fillAmount);
        vm.startPrank(AP_ADDRESS);
        mockLiquidityToken.approve(address(mockVault), fillAmount);

        // Deposit tokens into the vault and approve orderbook to spend them
        mockVault.deposit(fillAmount, AP_ADDRESS);
        mockVault.approve(address(orderbook), fillAmount);

        vm.stopPrank();

        // Expect events for awards and transfer
        vm.expectEmit(true, true, false, true, address(points));
        emit Points.Award(OWNER_ADDRESS, expectedProtocolFeeAmount);

        vm.expectEmit(true, true, false, true, address(points));
        emit Points.Award(FRONTEND_FEE_RECIPIENT, expectedFrontendFeeAmount);

        vm.expectEmit(true, true, false, true, address(points));
        emit Points.Award(AP_ADDRESS, expectedIncentiveAmount);

        vm.expectEmit(true, false, true, false, address(mockVault));
        emit ERC4626.Withdraw(address(orderbook), address(0), AP_ADDRESS, fillAmount, 0);

        vm.expectEmit(true, false, false, true, address(mockLiquidityToken));
        emit ERC20.Transfer(address(mockVault), address(0), fillAmount);

        vm.expectEmit(false, false, false, false, address(orderbook));
        emit RecipeOrderbook.APOrderFilled(0, 0, address(0), 0, 0, address(0));

        // Record the logs to capture Transfer events to get Weiroll wallet address
        vm.recordLogs();

        vm.startPrank(IP_ADDRESS);
        orderbook.fillAPOrder(order, fillAmount, FRONTEND_FEE_RECIPIENT);
        vm.stopPrank();

        uint256 resultingRemainingQuantity = orderbook.orderHashToRemainingQuantity(orderbook.getOrderHash(order));
        assertEq(resultingRemainingQuantity, orderAmount - fillAmount);

        // Extract the Weiroll wallet address (the 'to' address from the Transfer event - third event in logs)
        address weirollWallet = address(uint160(uint256(vm.getRecordedLogs()[4].topics[2])));

        // Ensure there is a weirollWallet at the expected address
        assertGt(weirollWallet.code.length, 0);

        // Ensure that the deposit recipe was executed
        assertEq(WeirollWallet(payable(weirollWallet)).executed(), true);

        // Ensure the weiroll wallet got the liquidity
        assertEq(mockLiquidityToken.balanceOf(weirollWallet), fillAmount);
    }

    function test_DirectFill_Forfeitable_APOrder_ForTokens() external {
        uint256 frontendFee = orderbook.minimumFrontendFee();
        uint256 marketId = orderbook.createMarket(address(mockLiquidityToken), 30 days, frontendFee, NULL_RECIPE, NULL_RECIPE, RewardStyle.Forfeitable);

        uint256 orderAmount = 100_000e18; // Order amount requested
        uint256 fillAmount = 1000e18; // Fill amount

        (, RecipeOrderbook.APOrder memory order) = createAPOrder_ForTokens(marketId, address(0), orderAmount, AP_ADDRESS);

        (, uint256 expectedFrontendFeeAmount, uint256 expectedProtocolFeeAmount, uint256 expectedIncentiveAmount) =
            calculateAPOrderExpectedIncentiveAndFrontendFee(orderbook.protocolFee(), frontendFee, orderAmount, fillAmount, 1000e18);

        // Mint liquidity tokens to the AP to be able to pay IP who fills it
        mockLiquidityToken.mint(AP_ADDRESS, orderAmount);
        vm.startPrank(AP_ADDRESS);
        mockLiquidityToken.approve(address(orderbook), fillAmount);
        vm.stopPrank();

        // Mint incentive tokens to IP
        mockIncentiveToken.mint(IP_ADDRESS, fillAmount);
        vm.startPrank(IP_ADDRESS);
        mockIncentiveToken.approve(address(orderbook), fillAmount);

        // Expect events for transfers
        vm.expectEmit(true, false, false, true, address(mockIncentiveToken));
        emit ERC20.Transfer(IP_ADDRESS, address(orderbook), expectedFrontendFeeAmount + expectedProtocolFeeAmount + expectedIncentiveAmount);

        vm.expectEmit(true, false, false, true, address(mockLiquidityToken));
        emit ERC20.Transfer(AP_ADDRESS, address(0), fillAmount);

        // Expect events for order fill
        vm.expectEmit(false, false, false, false);
        emit RecipeOrderbook.APOrderFilled(0, 0, address(0), 0, 0, address(0));

        vm.recordLogs();

        orderbook.fillAPOrder(order, fillAmount, FRONTEND_FEE_RECIPIENT);
        vm.stopPrank();

        uint256 resultingRemainingQuantity = orderbook.orderHashToRemainingQuantity(orderbook.getOrderHash(order));
        assertEq(resultingRemainingQuantity, orderAmount - fillAmount);

        // Extract the Weiroll wallet address (the 'to' address from the Transfer event - third event in logs)
        address weirollWallet = address(uint160(uint256(vm.getRecordedLogs()[1].topics[2])));

        (, uint256[] memory amounts,) = orderbook.getLockedRewardParams(weirollWallet);
        assertEq(amounts[0], expectedIncentiveAmount);

        // Ensure there is a weirollWallet at the expected address
        assertGt(weirollWallet.code.length, 0);

        // Ensure that the deposit recipe was executed
        assertEq(WeirollWallet(payable(weirollWallet)).executed(), true);

        // Ensure the weiroll wallet got the liquidity
        assertEq(mockLiquidityToken.balanceOf(weirollWallet), fillAmount);

        // Check the frontend fee recipient received the correct fee
        assertEq(orderbook.feeClaimantToTokenToAmount(FRONTEND_FEE_RECIPIENT, address(mockIncentiveToken)), expectedFrontendFeeAmount);

        // Check the protocol fee claimant received the correct fee
        assertEq(orderbook.feeClaimantToTokenToAmount(OWNER_ADDRESS, address(mockIncentiveToken)), expectedProtocolFeeAmount);
    }

    function test_DirectFill_Forfeitable_APOrder_ForPoints() external {
        uint256 frontendFee = orderbook.minimumFrontendFee();
        uint256 marketId = orderbook.createMarket(address(mockLiquidityToken), 30 days, frontendFee, NULL_RECIPE, NULL_RECIPE, RewardStyle.Forfeitable);

        uint256 orderAmount = 100_000e18; // Order amount requested
        uint256 fillAmount = 1000e18; // Fill amount

        // Create a fillable IP order
        (, RecipeOrderbook.APOrder memory order, Points points) = createAPOrder_ForPoints(marketId, address(0), orderAmount, AP_ADDRESS, IP_ADDRESS);

        (, uint256 expectedFrontendFeeAmount, uint256 expectedProtocolFeeAmount, uint256 expectedIncentiveAmount) =
            calculateAPOrderExpectedIncentiveAndFrontendFee(orderbook.protocolFee(), frontendFee, orderAmount, fillAmount, 1000e18);

        // Mint liquidity tokens to the AP to be able to pay IP who fills it
        mockLiquidityToken.mint(AP_ADDRESS, orderAmount);
        vm.startPrank(AP_ADDRESS);
        mockLiquidityToken.approve(address(orderbook), fillAmount);
        vm.stopPrank();

        // Mint incentive tokens to IP
        mockIncentiveToken.mint(IP_ADDRESS, fillAmount);
        vm.startPrank(IP_ADDRESS);
        mockIncentiveToken.approve(address(orderbook), fillAmount);

        // Expect events for awards and transfer
        vm.expectEmit(true, true, false, true, address(points));
        emit Points.Award(OWNER_ADDRESS, expectedProtocolFeeAmount);

        vm.expectEmit(true, true, false, true, address(points));
        emit Points.Award(FRONTEND_FEE_RECIPIENT, expectedFrontendFeeAmount);

        vm.expectEmit(true, false, false, true, address(mockLiquidityToken));
        emit ERC20.Transfer(AP_ADDRESS, address(0), fillAmount);

        vm.expectEmit(false, false, false, false, address(orderbook));
        emit RecipeOrderbook.APOrderFilled(0, 0, address(0), 0, 0, address(0));

        // Record the logs to capture Transfer events to get Weiroll wallet address
        vm.recordLogs();

        orderbook.fillAPOrder(order, fillAmount, FRONTEND_FEE_RECIPIENT);
        vm.stopPrank();

        uint256 resultingRemainingQuantity = orderbook.orderHashToRemainingQuantity(orderbook.getOrderHash(order));
        assertEq(resultingRemainingQuantity, orderAmount - fillAmount);

        // Extract the Weiroll wallet address (the 'to' address from the Transfer event - third event in logs)
        address weirollWallet = address(uint160(uint256(vm.getRecordedLogs()[2].topics[2])));

        (, uint256[] memory amounts,) = orderbook.getLockedRewardParams(weirollWallet);
        assertEq(amounts[0], expectedIncentiveAmount);

        // Ensure there is a weirollWallet at the expected address
        assertGt(weirollWallet.code.length, 0);

        // Ensure that the deposit recipe was executed
        assertEq(WeirollWallet(payable(weirollWallet)).executed(), true);

        // Ensure the weiroll wallet got the liquidity
        assertEq(mockLiquidityToken.balanceOf(weirollWallet), fillAmount);
    }

    function test_VaultFill_Forfeitable_APOrder_ForTokens() external {
        uint256 frontendFee = orderbook.minimumFrontendFee();
        uint256 marketId = orderbook.createMarket(address(mockLiquidityToken), 30 days, frontendFee, NULL_RECIPE, NULL_RECIPE, RewardStyle.Forfeitable);

        uint256 orderAmount = 100_000e18; // Order amount requested
        uint256 fillAmount = 1000e18; // Fill amount

        (, RecipeOrderbook.APOrder memory order) = createAPOrder_ForTokens(marketId, address(mockVault), orderAmount, AP_ADDRESS);

        (, uint256 expectedFrontendFeeAmount, uint256 expectedProtocolFeeAmount, uint256 expectedIncentiveAmount) =
            calculateAPOrderExpectedIncentiveAndFrontendFee(orderbook.protocolFee(), frontendFee, orderAmount, fillAmount, 1000e18);

        // Mint liquidity tokens to deposit into the vault
        mockLiquidityToken.mint(AP_ADDRESS, fillAmount);
        vm.startPrank(AP_ADDRESS);
        mockLiquidityToken.approve(address(mockVault), fillAmount);

        // Deposit tokens into the vault and approve orderbook to spend them
        mockVault.deposit(fillAmount, AP_ADDRESS);
        mockVault.approve(address(orderbook), fillAmount);
        vm.stopPrank();

        // Mint incentive tokens to IP
        mockIncentiveToken.mint(IP_ADDRESS, fillAmount);
        vm.startPrank(IP_ADDRESS);
        mockIncentiveToken.approve(address(orderbook), fillAmount);

        // Expect events for transfers
        vm.expectEmit(true, false, false, true, address(mockIncentiveToken));
        emit ERC20.Transfer(IP_ADDRESS, address(orderbook), expectedFrontendFeeAmount + expectedProtocolFeeAmount + expectedIncentiveAmount);

        vm.expectEmit(true, false, true, false, address(mockVault));
        emit ERC4626.Withdraw(address(orderbook), address(0), AP_ADDRESS, fillAmount, 0);

        vm.expectEmit(true, false, false, true, address(mockLiquidityToken));
        emit ERC20.Transfer(address(mockVault), address(0), fillAmount);

        // Expect events for order fill
        vm.expectEmit(false, false, false, false);
        emit RecipeOrderbook.APOrderFilled(0, 0, address(0), 0, 0, address(0));

        vm.recordLogs();

        orderbook.fillAPOrder(order, fillAmount, FRONTEND_FEE_RECIPIENT);
        vm.stopPrank();

        uint256 resultingRemainingQuantity = orderbook.orderHashToRemainingQuantity(orderbook.getOrderHash(order));
        assertEq(resultingRemainingQuantity, orderAmount - fillAmount);

        // Extract the Weiroll wallet address (the 'to' address from the third Transfer event)
        address weirollWallet = address(uint160(uint256(vm.getRecordedLogs()[2].topics[2])));

        (, uint256[] memory amounts,) = orderbook.getLockedRewardParams(weirollWallet);
        assertEq(amounts[0], expectedIncentiveAmount);

        // Ensure there is a weirollWallet at the expected address
        assertGt(weirollWallet.code.length, 0);

        // Ensure that the deposit recipe was executed
        assertEq(WeirollWallet(payable(weirollWallet)).executed(), true);

        // Ensure the weiroll wallet got the liquidity
        assertEq(mockLiquidityToken.balanceOf(weirollWallet), fillAmount);

        // Check the frontend fee recipient received the correct fee
        assertEq(orderbook.feeClaimantToTokenToAmount(FRONTEND_FEE_RECIPIENT, address(mockIncentiveToken)), expectedFrontendFeeAmount);

        // Check the protocol fee claimant received the correct fee
        assertEq(orderbook.feeClaimantToTokenToAmount(OWNER_ADDRESS, address(mockIncentiveToken)), expectedProtocolFeeAmount);
    }

    function test_VaultFill_Forfeitable_IPOrder_ForPoints() external {
        uint256 frontendFee = orderbook.minimumFrontendFee();
        uint256 marketId = orderbook.createMarket(address(mockLiquidityToken), 30 days, frontendFee, NULL_RECIPE, NULL_RECIPE, RewardStyle.Forfeitable);

        uint256 orderAmount = 100_000e18; // Order amount requested
        uint256 fillAmount = 1000e18; // Fill amount

        // Create a fillable IP order
        (, RecipeOrderbook.APOrder memory order, Points points) = createAPOrder_ForPoints(marketId, address(mockVault), orderAmount, AP_ADDRESS, IP_ADDRESS);

        (, uint256 expectedFrontendFeeAmount, uint256 expectedProtocolFeeAmount, uint256 expectedIncentiveAmount) =
            calculateAPOrderExpectedIncentiveAndFrontendFee(orderbook.protocolFee(), frontendFee, orderAmount, fillAmount, 1000e18);

        // Mint liquidity tokens to deposit into the vault
        mockLiquidityToken.mint(AP_ADDRESS, fillAmount);
        vm.startPrank(AP_ADDRESS);
        mockLiquidityToken.approve(address(mockVault), fillAmount);

        // Deposit tokens into the vault and approve orderbook to spend them
        mockVault.deposit(fillAmount, AP_ADDRESS);
        mockVault.approve(address(orderbook), fillAmount);

        vm.stopPrank();

        // Expect events for awards and transfer
        vm.expectEmit(true, true, false, true, address(points));
        emit Points.Award(OWNER_ADDRESS, expectedProtocolFeeAmount);

        vm.expectEmit(true, true, false, true, address(points));
        emit Points.Award(FRONTEND_FEE_RECIPIENT, expectedFrontendFeeAmount);

        vm.expectEmit(true, false, true, false, address(mockVault));
        emit ERC4626.Withdraw(address(orderbook), address(0), AP_ADDRESS, fillAmount, 0);

        vm.expectEmit(true, false, false, true, address(mockLiquidityToken));
        emit ERC20.Transfer(address(mockVault), address(0), fillAmount);

        vm.expectEmit(false, false, false, false, address(orderbook));
        emit RecipeOrderbook.APOrderFilled(0, 0, address(0), 0, 0, address(0));

        // Record the logs to capture Transfer events to get Weiroll wallet address
        vm.recordLogs();

        vm.startPrank(IP_ADDRESS);
        orderbook.fillAPOrder(order, fillAmount, FRONTEND_FEE_RECIPIENT);
        vm.stopPrank();

        uint256 resultingRemainingQuantity = orderbook.orderHashToRemainingQuantity(orderbook.getOrderHash(order));
        assertEq(resultingRemainingQuantity, orderAmount - fillAmount);

        // Extract the Weiroll wallet address (the 'to' address from the Transfer event - third event in logs)
        address weirollWallet = address(uint160(uint256(vm.getRecordedLogs()[3].topics[2])));

        (, uint256[] memory amounts,) = orderbook.getLockedRewardParams(weirollWallet);
        assertEq(amounts[0], expectedIncentiveAmount);

        // Ensure there is a weirollWallet at the expected address
        assertGt(weirollWallet.code.length, 0);

        // Ensure that the deposit recipe was executed
        assertEq(WeirollWallet(payable(weirollWallet)).executed(), true);

        // Ensure the weiroll wallet got the liquidity
        assertEq(mockLiquidityToken.balanceOf(weirollWallet), fillAmount);
    }

    function test_DirectFill_Arrear_APOrder_ForTokens() external {
        uint256 frontendFee = orderbook.minimumFrontendFee();
        uint256 marketId = orderbook.createMarket(address(mockLiquidityToken), 30 days, frontendFee, NULL_RECIPE, NULL_RECIPE, RewardStyle.Arrear);

        uint256 orderAmount = 100_000e18; // Order amount requested
        uint256 fillAmount = 1000e18; // Fill amount

        (, RecipeOrderbook.APOrder memory order) = createAPOrder_ForTokens(marketId, address(0), orderAmount, AP_ADDRESS);

        (, uint256 expectedFrontendFeeAmount, uint256 expectedProtocolFeeAmount, uint256 expectedIncentiveAmount) =
            calculateAPOrderExpectedIncentiveAndFrontendFee(orderbook.protocolFee(), frontendFee, orderAmount, fillAmount, 1000e18);

        // Mint liquidity tokens to the AP to be able to pay IP who fills it
        mockLiquidityToken.mint(AP_ADDRESS, orderAmount);
        vm.startPrank(AP_ADDRESS);
        mockLiquidityToken.approve(address(orderbook), fillAmount);
        vm.stopPrank();

        // Mint incentive tokens to IP
        mockIncentiveToken.mint(IP_ADDRESS, fillAmount);
        vm.startPrank(IP_ADDRESS);
        mockIncentiveToken.approve(address(orderbook), fillAmount);

        // Expect events for transfers
        vm.expectEmit(true, false, false, true, address(mockIncentiveToken));
        emit ERC20.Transfer(IP_ADDRESS, address(orderbook), expectedFrontendFeeAmount + expectedProtocolFeeAmount + expectedIncentiveAmount);

        vm.expectEmit(true, false, false, true, address(mockLiquidityToken));
        emit ERC20.Transfer(AP_ADDRESS, address(0), fillAmount);

        // Expect events for order fill
        vm.expectEmit(false, false, false, false);
        emit RecipeOrderbook.APOrderFilled(0, 0, address(0), 0, 0, address(0));

        vm.recordLogs();

        orderbook.fillAPOrder(order, fillAmount, FRONTEND_FEE_RECIPIENT);
        vm.stopPrank();

        uint256 resultingRemainingQuantity = orderbook.orderHashToRemainingQuantity(orderbook.getOrderHash(order));
        assertEq(resultingRemainingQuantity, orderAmount - fillAmount);

        // Extract the Weiroll wallet address (the 'to' address from the Transfer event - third event in logs)
        address weirollWallet = address(uint160(uint256(vm.getRecordedLogs()[1].topics[2])));

        (, uint256[] memory amounts,) = orderbook.getLockedRewardParams(weirollWallet);
        assertEq(amounts[0], expectedIncentiveAmount);

        // Ensure there is a weirollWallet at the expected address
        assertGt(weirollWallet.code.length, 0);

        // Ensure that the deposit recipe was executed
        assertEq(WeirollWallet(payable(weirollWallet)).executed(), true);

        // Ensure the weiroll wallet got the liquidity
        assertEq(mockLiquidityToken.balanceOf(weirollWallet), fillAmount);

        // Check the frontend fee recipient received the correct fee
        assertEq(orderbook.feeClaimantToTokenToAmount(FRONTEND_FEE_RECIPIENT, address(mockIncentiveToken)), expectedFrontendFeeAmount);

        // Check the protocol fee claimant received the correct fee
        assertEq(orderbook.feeClaimantToTokenToAmount(OWNER_ADDRESS, address(mockIncentiveToken)), expectedProtocolFeeAmount);
    }

    function test_DirectFill_Arrear_APOrder_ForPoints() external {
        uint256 frontendFee = orderbook.minimumFrontendFee();
        uint256 marketId = orderbook.createMarket(address(mockLiquidityToken), 30 days, frontendFee, NULL_RECIPE, NULL_RECIPE, RewardStyle.Arrear);

        uint256 orderAmount = 100_000e18; // Order amount requested
        uint256 fillAmount = 1000e18; // Fill amount

        // Create a fillable IP order
        (, RecipeOrderbook.APOrder memory order, Points points) = createAPOrder_ForPoints(marketId, address(0), orderAmount, AP_ADDRESS, IP_ADDRESS);

        (, uint256 expectedFrontendFeeAmount, uint256 expectedProtocolFeeAmount, uint256 expectedIncentiveAmount) =
            calculateAPOrderExpectedIncentiveAndFrontendFee(orderbook.protocolFee(), frontendFee, orderAmount, fillAmount, 1000e18);

        // Mint liquidity tokens to the AP to be able to pay IP who fills it
        mockLiquidityToken.mint(AP_ADDRESS, orderAmount);
        vm.startPrank(AP_ADDRESS);
        mockLiquidityToken.approve(address(orderbook), fillAmount);
        vm.stopPrank();

        // Mint incentive tokens to IP
        mockIncentiveToken.mint(IP_ADDRESS, fillAmount);
        vm.startPrank(IP_ADDRESS);
        mockIncentiveToken.approve(address(orderbook), fillAmount);

        // Expect events for awards and transfer
        vm.expectEmit(true, true, false, true, address(points));
        emit Points.Award(OWNER_ADDRESS, expectedProtocolFeeAmount);

        vm.expectEmit(true, true, false, true, address(points));
        emit Points.Award(FRONTEND_FEE_RECIPIENT, expectedFrontendFeeAmount);

        vm.expectEmit(true, false, false, true, address(mockLiquidityToken));
        emit ERC20.Transfer(AP_ADDRESS, address(0), fillAmount);

        vm.expectEmit(false, false, false, false, address(orderbook));
        emit RecipeOrderbook.APOrderFilled(0, 0, address(0), 0, 0, address(0));

        // Record the logs to capture Transfer events to get Weiroll wallet address
        vm.recordLogs();

        orderbook.fillAPOrder(order, fillAmount, FRONTEND_FEE_RECIPIENT);
        vm.stopPrank();

        uint256 resultingRemainingQuantity = orderbook.orderHashToRemainingQuantity(orderbook.getOrderHash(order));
        assertEq(resultingRemainingQuantity, orderAmount - fillAmount);

        // Extract the Weiroll wallet address (the 'to' address from the Transfer event - third event in logs)
        address weirollWallet = address(uint160(uint256(vm.getRecordedLogs()[2].topics[2])));

        (, uint256[] memory amounts,) = orderbook.getLockedRewardParams(weirollWallet);
        assertEq(amounts[0], expectedIncentiveAmount);

        // Ensure there is a weirollWallet at the expected address
        assertGt(weirollWallet.code.length, 0);

        // Ensure that the deposit recipe was executed
        assertEq(WeirollWallet(payable(weirollWallet)).executed(), true);

        // Ensure the weiroll wallet got the liquidity
        assertEq(mockLiquidityToken.balanceOf(weirollWallet), fillAmount);
    }

    function test_VaultFill_Arrear_APOrder_ForTokens() external {
        uint256 frontendFee = orderbook.minimumFrontendFee();
        uint256 marketId = orderbook.createMarket(address(mockLiquidityToken), 30 days, frontendFee, NULL_RECIPE, NULL_RECIPE, RewardStyle.Arrear);

        uint256 orderAmount = 100_000e18; // Order amount requested
        uint256 fillAmount = 1000e18; // Fill amount

        (, RecipeOrderbook.APOrder memory order) = createAPOrder_ForTokens(marketId, address(mockVault), orderAmount, AP_ADDRESS);

        (, uint256 expectedFrontendFeeAmount, uint256 expectedProtocolFeeAmount, uint256 expectedIncentiveAmount) =
            calculateAPOrderExpectedIncentiveAndFrontendFee(orderbook.protocolFee(), frontendFee, orderAmount, fillAmount, 1000e18);

        // Mint liquidity tokens to deposit into the vault
        mockLiquidityToken.mint(AP_ADDRESS, fillAmount);
        vm.startPrank(AP_ADDRESS);
        mockLiquidityToken.approve(address(mockVault), fillAmount);

        // Deposit tokens into the vault and approve orderbook to spend them
        mockVault.deposit(fillAmount, AP_ADDRESS);
        mockVault.approve(address(orderbook), fillAmount);
        vm.stopPrank();

        // Mint incentive tokens to IP
        mockIncentiveToken.mint(IP_ADDRESS, fillAmount);
        vm.startPrank(IP_ADDRESS);
        mockIncentiveToken.approve(address(orderbook), fillAmount);

        // Expect events for transfers
        vm.expectEmit(true, false, false, true, address(mockIncentiveToken));
        emit ERC20.Transfer(IP_ADDRESS, address(orderbook), expectedFrontendFeeAmount + expectedProtocolFeeAmount + expectedIncentiveAmount);

        vm.expectEmit(true, false, true, false, address(mockVault));
        emit ERC4626.Withdraw(address(orderbook), address(0), AP_ADDRESS, fillAmount, 0);

        vm.expectEmit(true, false, false, true, address(mockLiquidityToken));
        emit ERC20.Transfer(address(mockVault), address(0), fillAmount);

        // Expect events for order fill
        vm.expectEmit(false, false, false, false);
        emit RecipeOrderbook.APOrderFilled(0, 0, address(0), 0, 0, address(0));

        vm.recordLogs();

        orderbook.fillAPOrder(order, fillAmount, FRONTEND_FEE_RECIPIENT);
        vm.stopPrank();

        uint256 resultingRemainingQuantity = orderbook.orderHashToRemainingQuantity(orderbook.getOrderHash(order));
        assertEq(resultingRemainingQuantity, orderAmount - fillAmount);

        // Extract the Weiroll wallet address (the 'to' address from the third Transfer event)
        address weirollWallet = address(uint160(uint256(vm.getRecordedLogs()[2].topics[2])));

        (, uint256[] memory amounts,) = orderbook.getLockedRewardParams(weirollWallet);
        assertEq(amounts[0], expectedIncentiveAmount);

        // Ensure there is a weirollWallet at the expected address
        assertGt(weirollWallet.code.length, 0);

        // Ensure that the deposit recipe was executed
        assertEq(WeirollWallet(payable(weirollWallet)).executed(), true);

        // Ensure the weiroll wallet got the liquidity
        assertEq(mockLiquidityToken.balanceOf(weirollWallet), fillAmount);

        // Check the frontend fee recipient received the correct fee
        assertEq(orderbook.feeClaimantToTokenToAmount(FRONTEND_FEE_RECIPIENT, address(mockIncentiveToken)), expectedFrontendFeeAmount);

        // Check the protocol fee claimant received the correct fee
        assertEq(orderbook.feeClaimantToTokenToAmount(OWNER_ADDRESS, address(mockIncentiveToken)), expectedProtocolFeeAmount);
    }

    function test_VaultFill_Arrear_IPOrder_ForPoints() external {
        uint256 frontendFee = orderbook.minimumFrontendFee();
        uint256 marketId = orderbook.createMarket(address(mockLiquidityToken), 30 days, frontendFee, NULL_RECIPE, NULL_RECIPE, RewardStyle.Arrear);

        uint256 orderAmount = 100_000e18; // Order amount requested
        uint256 fillAmount = 1000e18; // Fill amount

        // Create a fillable IP order
        (, RecipeOrderbook.APOrder memory order, Points points) = createAPOrder_ForPoints(marketId, address(mockVault), orderAmount, AP_ADDRESS, IP_ADDRESS);

        (, uint256 expectedFrontendFeeAmount, uint256 expectedProtocolFeeAmount, uint256 expectedIncentiveAmount) =
            calculateAPOrderExpectedIncentiveAndFrontendFee(orderbook.protocolFee(), frontendFee, orderAmount, fillAmount, 1000e18);

        // Mint liquidity tokens to deposit into the vault
        mockLiquidityToken.mint(AP_ADDRESS, fillAmount);
        vm.startPrank(AP_ADDRESS);
        mockLiquidityToken.approve(address(mockVault), fillAmount);

        // Deposit tokens into the vault and approve orderbook to spend them
        mockVault.deposit(fillAmount, AP_ADDRESS);
        mockVault.approve(address(orderbook), fillAmount);

        vm.stopPrank();

        // Expect events for awards and transfer
        vm.expectEmit(true, true, false, true, address(points));
        emit Points.Award(OWNER_ADDRESS, expectedProtocolFeeAmount);

        vm.expectEmit(true, true, false, true, address(points));
        emit Points.Award(FRONTEND_FEE_RECIPIENT, expectedFrontendFeeAmount);

        vm.expectEmit(true, false, true, false, address(mockVault));
        emit ERC4626.Withdraw(address(orderbook), address(0), AP_ADDRESS, fillAmount, 0);

        vm.expectEmit(true, false, false, true, address(mockLiquidityToken));
        emit ERC20.Transfer(address(mockVault), address(0), fillAmount);

        vm.expectEmit(false, false, false, false, address(orderbook));
        emit RecipeOrderbook.APOrderFilled(0, 0, address(0), 0, 0, address(0));

        // Record the logs to capture Transfer events to get Weiroll wallet address
        vm.recordLogs();

        vm.startPrank(IP_ADDRESS);
        orderbook.fillAPOrder(order, fillAmount, FRONTEND_FEE_RECIPIENT);
        vm.stopPrank();

        uint256 resultingRemainingQuantity = orderbook.orderHashToRemainingQuantity(orderbook.getOrderHash(order));
        assertEq(resultingRemainingQuantity, orderAmount - fillAmount);

        // Extract the Weiroll wallet address (the 'to' address from the Transfer event - third event in logs)
        address weirollWallet = address(uint160(uint256(vm.getRecordedLogs()[3].topics[2])));

        (, uint256[] memory amounts,) = orderbook.getLockedRewardParams(weirollWallet);
        assertEq(amounts[0], expectedIncentiveAmount);

        // Ensure there is a weirollWallet at the expected address
        assertGt(weirollWallet.code.length, 0);

        // Ensure that the deposit recipe was executed
        assertEq(WeirollWallet(payable(weirollWallet)).executed(), true);

        // Ensure the weiroll wallet got the liquidity
        assertEq(mockLiquidityToken.balanceOf(weirollWallet), fillAmount);
    }

    function test_RevertIf_NotEnoughRemainingQuantity_FillAPOrder() external {
        uint256 marketId = createMarket();

        uint256 orderAmount = 100_000e18;
        uint256 fillAmount = 100_001e18; // Fill amount exceeds the order amount

        // Create a fillable AP order
        (, RecipeOrderbook.APOrder memory order) = createAPOrder_ForTokens(marketId, address(0), orderAmount, AP_ADDRESS);

        // Attempt to fill more than available, expecting a revert
        vm.expectRevert(RecipeOrderbook.NotEnoughRemainingQuantity.selector);
        orderbook.fillAPOrder(order, fillAmount, FRONTEND_FEE_RECIPIENT);
    }

    function test_RevertIf_ZeroQuantityFill_FillAPOrder() external {
        uint256 marketId = createMarket();

        uint256 orderAmount = 100_000e18;

        // Create a fillable AP order
        (, RecipeOrderbook.APOrder memory order) = createAPOrder_ForTokens(marketId, address(0), orderAmount, AP_ADDRESS);

        // Attempt to fill with zero quantity, expecting a revert
        vm.expectRevert(RecipeOrderbook.CannotFillZeroQuantityOrder.selector);
        orderbook.fillAPOrder(order, 0, FRONTEND_FEE_RECIPIENT);
    }

    function test_RevertIf_OrderExpired_FillAPOrder() external {
        uint256 marketId = createMarket();

        uint256 orderAmount = 100_000e18;

        // Create a fillable AP order with a short expiry time
        (, RecipeOrderbook.APOrder memory order) = createAPOrder_ForTokens(marketId, address(0), orderAmount, AP_ADDRESS);

        // Simulate the passage of time beyond the expiry
        vm.warp(block.timestamp + 31 days);

        // Attempt to fill an expired order, expecting a revert
        vm.expectRevert(RecipeOrderbook.OrderExpired.selector);
        orderbook.fillAPOrder(order, orderAmount, FRONTEND_FEE_RECIPIENT);
    }
}
