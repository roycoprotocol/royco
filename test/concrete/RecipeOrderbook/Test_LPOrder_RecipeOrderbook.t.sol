// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../../../src/RecipeOrderbook.sol";
import { MockERC4626 } from "../../mocks/MockERC4626.sol";
import { RecipeOrderbookTestBase } from "../../utils/RecipeOrderbook/RecipeOrderbookTestBase.sol";

contract Test_LPOrder_RecipeOrderbook is RecipeOrderbookTestBase {
    function setUp() external {
        uint256 protocolFee = 0.01e18; // 1% protocol fee
        uint256 minimumFrontendFee = 0.001e18; // 0.1% minimum frontend fee
        setUpRecipeOrderbookTests(protocolFee, minimumFrontendFee);
    }

    function test_CreateLPOrder() external prankModifier(ALICE_ADDRESS) {
        uint256 marketId = createMarket();

        address[] memory tokensRequested = new address[](1);
        tokensRequested[0] = address(mockIncentiveToken);
        uint256[] memory tokenAmountsRequested = new uint256[](1);
        tokenAmountsRequested[0] = 100e18;

        uint256 quantity = 1000e18; // The amount of input tokens to be deposited
        uint256 expiry = block.timestamp + 1 days; // Order expires in 1 day

        // Expect the LPOrderCreated event to be emitted
        vm.expectEmit(true, true, true, true, address(orderbook));
        emit RecipeOrderbook.LPOrderCreated(
            0, // Expected order ID (starts at 0)
            marketId, // Market ID
            ALICE_ADDRESS, // LP address
            address(0), // No funding vault
            quantity,
            expiry, // Expiry time
            tokensRequested, // Tokens requested
            tokenAmountsRequested // Amounts requested
        );

        // Create the LP order
        uint256 orderId = orderbook.createLPOrder(
            marketId, // Referencing the created market
            address(0), // No funding vault
            quantity, // Total input token amount
            expiry, // Expiry time
            tokensRequested, // Incentive tokens requested
            tokenAmountsRequested // Incentive amounts requested
        );

        assertEq(orderId, 0); // First LP order should have ID 0
        assertEq(orderbook.numLPOrders(), 1); // LP order count should be 1
        assertEq(orderbook.numIPOrders(), 0); // IP orders should remain 0

        // Check hash is added correctly and quantity can be retrieved from mapping
        bytes32 orderHash =
            orderbook.getOrderHash(RecipeOrderbook.LPOrder(0, marketId, ALICE_ADDRESS, address(0), quantity, expiry, tokensRequested, tokenAmountsRequested));

        assertEq(orderbook.orderHashToRemainingQuantity(orderHash), quantity); // Ensure the correct quantity is stored
    }

    function test_RevertIf_CreateLPOrderWithNonExistentMarket() external {
        vm.expectRevert(abi.encodeWithSelector(RecipeOrderbook.MarketDoesNotExist.selector));
        orderbook.createLPOrder(
            0, // Non-existent market ID
            address(0),
            1000e18,
            block.timestamp + 1 days,
            new address[](1),
            new uint256[](1)
        );
    }

    function test_RevertIf_CreateLPOrderWithExpiredOrder() external {
        vm.warp(1_231_006_505); // set block timestamp
        uint256 marketId = createMarket();
        vm.expectRevert(abi.encodeWithSelector(RecipeOrderbook.CannotPlaceExpiredOrder.selector));
        orderbook.createLPOrder(
            marketId,
            address(0),
            1000e18,
            block.timestamp - 1 seconds, // Expired timestamp
            new address[](1),
            new uint256[](1)
        );
    }

    function test_RevertIf_CreateLPOrderWithZeroQuantity() external {
        uint256 marketId = createMarket();
        vm.expectRevert(abi.encodeWithSelector(RecipeOrderbook.CannotPlaceZeroQuantityOrder.selector));
        orderbook.createLPOrder(
            marketId,
            address(0),
            0, // Zero quantity
            block.timestamp + 1 days,
            new address[](1),
            new uint256[](1)
        );
    }

    function test_RevertIf_CreateLPOrderWithMismatchedTokenArrays() external {
        uint256 marketId = createMarket();

        address[] memory tokensRequested = new address[](1);
        uint256[] memory tokenAmountsRequested = new uint256[](2);

        vm.expectRevert(abi.encodeWithSelector(RecipeOrderbook.ArrayLengthMismatch.selector));
        orderbook.createLPOrder(marketId, address(0), 1000e18, block.timestamp + 1 days, tokensRequested, tokenAmountsRequested);
    }

    function test_RevertIf_CreateLPOrderWithMismatchedBaseAsset() external {
        uint256 marketId = createMarket();

        address[] memory tokensRequested = new address[](1);
        tokensRequested[0] = address(mockIncentiveToken);
        uint256[] memory tokenAmountsRequested = new uint256[](1);
        tokenAmountsRequested[0] = 100e18;

        MockERC4626 incentiveVault = new MockERC4626(mockIncentiveToken);

        vm.expectRevert(abi.encodeWithSelector(RecipeOrderbook.MismatchedBaseAsset.selector));
        orderbook.createLPOrder(
            marketId,
            address(incentiveVault), // Funding vault with mismatched base asset
            1000e18,
            block.timestamp + 1 days,
            tokensRequested,
            tokenAmountsRequested
        );
    }
}
