// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../../../src/RecipeOrderbook.sol";
import "../../../src/ERC4626i.sol";

import { MockERC20 } from "../../mocks/MockERC20.sol";
import { RecipeOrderbookTestBase } from "../../utils/RecipeOrderbook/RecipeOrderbookTestBase.sol";
import { FixedPointMathLib } from "lib/solmate/src/utils/FixedPointMathLib.sol";

contract Test_IPOrderCreation_RecipeOrderbook is RecipeOrderbookTestBase {
    using FixedPointMathLib for uint256;

    function setUp() external {
        uint256 protocolFee = 0.01e18; // 1% protocol fee
        uint256 minimumFrontendFee = 0.001e18; // 0.1% minimum frontend fee
        setUpRecipeOrderbookTests(protocolFee, minimumFrontendFee);
    }

    function test_CreateIPOrder_ForTokens() external prankModifier(ALICE_ADDRESS) {
        uint256 marketId = createMarket();

        // Handle minting incentive token to the IP's address
        address[] memory tokensOffered = new address[](1);
        tokensOffered[0] = address(mockIncentiveToken);
        uint256[] memory tokenAmountsOffered = new uint256[](1);
        tokenAmountsOffered[0] = 100e18;
        mockIncentiveToken.mint(ALICE_ADDRESS, 100e18);
        mockIncentiveToken.approve(address(orderbook), 100e18);

        uint256 quantity = 1000e18; // The amount of input tokens to be deposited
        uint256 expiry = block.timestamp + 1 days; // Order expires in 1 day

        // Calculate expected fees
        uint256 protocolFeeAmount = tokenAmountsOffered[0].mulWadDown(orderbook.protocolFee());
        (,, uint256 frontendFee,,,) = orderbook.marketIDToWeirollMarket(marketId);
        uint256 frontendFeeAmount = tokenAmountsOffered[0].mulWadDown(frontendFee);
        uint256 incentiveAmount = tokenAmountsOffered[0] - protocolFeeAmount - frontendFeeAmount;

        // Expect the IPOrderCreated event to be emitted
        vm.expectEmit(true, true, true, true, address(orderbook));
        emit RecipeOrderbook.IPOrderCreated(
            0, // Expected order ID (starts at 0)
            marketId, // Market ID
            ALICE_ADDRESS, // IP address
            expiry, // Expiry time
            tokensOffered, // Tokens offered
            tokenAmountsOffered, // Amounts offered
            quantity // Total quantity
        );

        // MockERC20 should track calls to `transferFrom`
        vm.expectCall(
            address(mockIncentiveToken),
            abi.encodeWithSelector(ERC20.transferFrom.selector, ALICE_ADDRESS, address(orderbook), protocolFeeAmount + frontendFeeAmount + incentiveAmount)
        );

        // Create the IP order
        uint256 orderId = orderbook.createIPOrder(
            marketId, // Referencing the created market
            quantity, // Total input token amount
            expiry, // Expiry time
            tokensOffered, // Incentive tokens offered
            tokenAmountsOffered // Incentive amounts offered
        );

        // Assertions on the order
        assertEq(orderId, 0); // First IP order should have ID 0
        assertEq(orderbook.numIPOrders(), 1); // IP order count should be 1
        assertEq(orderbook.numLPOrders(), 0); // LP orders should remain 0

        // Use the helper function to retrieve values from storage
        uint256 frontendFeeStored = orderbook.getTokenToFrontendFeeAmountForIPOrder(orderId, tokensOffered[0]);
        uint256 incentiveAmountStored = orderbook.getTokenAmountsOfferedForIPOrder(orderId, tokensOffered[0]);

        // Assert that the values match expected values
        assertEq(frontendFeeStored, frontendFeeAmount);
        assertEq(incentiveAmountStored, incentiveAmount);

        // Check that the protocol fee is correctly accounted for
        assertEq(orderbook.feeClaimantToTokenToAmount(orderbook.protocolFeeClaimant(), address(mockIncentiveToken)), protocolFeeAmount);

        // Ensure the transfer was successful
        assertEq(MockERC20(address(mockIncentiveToken)).balanceOf(address(orderbook)), protocolFeeAmount + frontendFeeAmount + incentiveAmount);
    }

    function test_CreateIPOrder_ForPointsProgram() external {
        uint256 marketId = createMarket();

        Points points = pointsFactory.createPointsProgram("POINTS", "PTS", 18, BOB_ADDRESS, ERC4626i(address(mockVault)), orderbook);
        vm.startPrank(BOB_ADDRESS);
        points.addAllowedIP(ALICE_ADDRESS);
        vm.stopPrank();

        // Handle minting incentive token to the IP's address
        address[] memory tokensOffered = new address[](1);
        tokensOffered[0] = address(points);
        uint256[] memory tokenAmountsOffered = new uint256[](1);
        tokenAmountsOffered[0] = 100e18;

        uint256 quantity = 1000e18; // The amount of input tokens to be deposited
        uint256 expiry = block.timestamp + 1 days; // Order expires in 1 day

        // Calculate expected fees
        uint256 protocolFeeAmount = tokenAmountsOffered[0].mulWadDown(orderbook.protocolFee());
        (,, uint256 frontendFee,,,) = orderbook.marketIDToWeirollMarket(marketId);
        uint256 frontendFeeAmount = tokenAmountsOffered[0].mulWadDown(frontendFee);
        uint256 incentiveAmount = tokenAmountsOffered[0] - protocolFeeAmount - frontendFeeAmount;

        // Expect the IPOrderCreated event to be emitted
        vm.expectEmit(true, true, false, true, address(points));
        emit Points.Award(OWNER_ADDRESS, protocolFeeAmount);

        // Expect the IPOrderCreated event to be emitted
        vm.expectEmit(true, true, true, true, address(orderbook));
        emit RecipeOrderbook.IPOrderCreated(
            0, // Expected order ID (starts at 0)
            marketId, // Market ID
            ALICE_ADDRESS, // IP address
            expiry, // Expiry time
            tokensOffered, // Tokens offered
            tokenAmountsOffered, // Amounts offered
            quantity // Total quantity
        );

        // MockERC20 should track calls to `award` in points contract
        vm.expectCall(
            address(points), abi.encodeWithSignature("award(address,uint256,address)", OWNER_ADDRESS, protocolFeeAmount, ALICE_ADDRESS)
        );

        vm.startPrank(ALICE_ADDRESS);
        // Create the IP order
        uint256 orderId = orderbook.createIPOrder(
            marketId, // Referencing the created market
            quantity, // Total input token amount
            expiry, // Expiry time
            tokensOffered, // Incentive tokens offered
            tokenAmountsOffered // Incentive amounts offered
        );
        vm.stopPrank();

        // Assertions on the order
        assertEq(orderId, 0); // First IP order should have ID 0
        assertEq(orderbook.numIPOrders(), 1); // IP order count should be 1
        assertEq(orderbook.numLPOrders(), 0); // LP orders should remain 0

        // Use the helper function to retrieve values from storage
        uint256 frontendFeeStored = orderbook.getTokenToFrontendFeeAmountForIPOrder(orderId, tokensOffered[0]);
        uint256 incentiveAmountStored = orderbook.getTokenAmountsOfferedForIPOrder(orderId, tokensOffered[0]);

        // Assert that the values match expected values
        assertEq(frontendFeeStored, frontendFeeAmount);
        assertEq(incentiveAmountStored, incentiveAmount);
    }

    function test_RevertIf_CreateIPOrderWithNonExistentMarket() external {
        vm.expectRevert(abi.encodeWithSelector(RecipeOrderbook.MarketDoesNotExist.selector));
        orderbook.createIPOrder(
            0, // Non-existent market ID
            1000e18, // Quantity
            block.timestamp + 1 days, // Expiry time
            new address[](1), // Empty tokens offered array
            new uint256[](1) // Empty token amounts array
        );
    }

    function test_RevertIf_CreateIPOrderWithExpiredOrder() external {
        vm.warp(1_231_006_505); // set block timestamp
        uint256 marketId = createMarket();
        vm.expectRevert(abi.encodeWithSelector(RecipeOrderbook.CannotPlaceExpiredOrder.selector));
        orderbook.createIPOrder(
            marketId,
            1000e18, // Quantity
            block.timestamp - 1 seconds, // Expired timestamp
            new address[](1), // Empty tokens offered array
            new uint256[](1) // Empty token amounts array
        );
    }

    function test_RevertIf_CreateIPOrderWithZeroQuantity() external {
        uint256 marketId = createMarket();
        vm.expectRevert(abi.encodeWithSelector(RecipeOrderbook.CannotPlaceZeroQuantityOrder.selector));
        orderbook.createIPOrder(
            marketId,
            0, // Zero quantity
            block.timestamp + 1 days, // Expiry time
            new address[](1), // Empty tokens offered array
            new uint256[](1) // Empty token amounts array
        );
    }

    function test_RevertIf_CreateIPOrderWithMismatchedTokenArrays() external {
        uint256 marketId = createMarket();

        address[] memory tokensOffered = new address[](1);
        tokensOffered[0] = address(mockIncentiveToken);
        uint256[] memory tokenAmountsOffered = new uint256[](2);
        tokenAmountsOffered[0] = 100e18;

        vm.expectRevert(abi.encodeWithSelector(RecipeOrderbook.ArrayLengthMismatch.selector));
        orderbook.createIPOrder(
            marketId,
            1000e18, // Quantity
            block.timestamp + 1 days, // Expiry time
            tokensOffered, // Mismatched arrays
            tokenAmountsOffered
        );
    }
}
