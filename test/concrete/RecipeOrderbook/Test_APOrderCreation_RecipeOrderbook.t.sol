// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "src/base/RecipeOrderbookBase.sol";
import { MockERC4626 } from "../../mocks/MockERC4626.sol";
import { RecipeOrderbookTestBase } from "../../utils/RecipeOrderbook/RecipeOrderbookTestBase.sol";

contract Test_APOrderCreation_RecipeOrderbook is RecipeOrderbookTestBase {
    function setUp() external {
        uint256 protocolFee = 0.01e18; // 1% protocol fee
        uint256 minimumFrontendFee = 0.001e18; // 0.1% minimum frontend fee
        setUpRecipeOrderbookTests(protocolFee, minimumFrontendFee);
    }

    function test_CreateAPOrder() external prankModifier(ALICE_ADDRESS) {
        uint256 marketId = createMarket();

        address[] memory tokensRequested = new address[](1);
        tokensRequested[0] = address(mockIncentiveToken);
        uint256[] memory tokenAmountsRequested = new uint256[](1);
        tokenAmountsRequested[0] = 1000e18;

        uint256 quantity = 100_000e18; // The amount of input tokens to be deposited
        uint256 expiry = block.timestamp + 1 days; // Order expires in 1 day

        // Expect the APOfferCreated event to be emitted
        vm.expectEmit(true, true, true, false, address(orderbook));
        emit RecipeOrderbookBase.APOfferCreated(
            0, // Expected order ID (starts at 0)
            marketId, // Market ID
            address(0), // No funding vault
            quantity,
            tokensRequested, // Tokens requested
            tokenAmountsRequested, // Amounts requested,
            expiry // Expiry time
        );

        // Create the AP order
        uint256 orderId = orderbook.createAPOrder(
            marketId, // Referencing the created market
            address(0), // No funding vault
            quantity, // Total input token amount
            expiry, // Expiry time
            tokensRequested, // Incentive tokens requested
            tokenAmountsRequested // Incentive amounts requested
        );

        assertEq(orderId, 0); // First AP order should have ID 0
        assertEq(orderbook.numAPOrders(), 1); // AP order count should be 1
        assertEq(orderbook.numIPOrders(), 0); // IP orders should remain 0

        // Check hash is added correctly and quantity can be retrieved from mapping
        bytes32 orderHash = orderbook.getOrderHash(
            RecipeOrderbookBase.APOrder(0, marketId, ALICE_ADDRESS, address(0), quantity, expiry, tokensRequested, tokenAmountsRequested)
        );

        assertEq(orderbook.orderHashToRemainingQuantity(orderHash), quantity); // Ensure the correct quantity is stored
    }

    function test_RevertIf_CreateAPOrderWithNonExistentMarket() external {
        vm.expectRevert(abi.encodeWithSelector(RecipeOrderbookBase.MarketDoesNotExist.selector));
        orderbook.createAPOrder(
            0, // Non-existent market ID
            address(0),
            100_000e18,
            block.timestamp + 1 days,
            new address[](1),
            new uint256[](1)
        );
    }

    function test_RevertIf_CreateAPOrderWithExpiredOrder() external {
        vm.warp(1_231_006_505); // set block timestamp
        uint256 marketId = createMarket();
        vm.expectRevert(abi.encodeWithSelector(RecipeOrderbookBase.CannotPlaceExpiredOrder.selector));
        orderbook.createAPOrder(
            marketId,
            address(0),
            100_000e18,
            block.timestamp - 1 seconds, // Expired timestamp
            new address[](1),
            new uint256[](1)
        );
    }

    function test_RevertIf_CreateAPOrderWithZeroQuantity() external {
        uint256 marketId = createMarket();
        vm.expectRevert(abi.encodeWithSelector(RecipeOrderbookBase.CannotPlaceZeroQuantityOrder.selector));
        orderbook.createAPOrder(
            marketId,
            address(0),
            0, // Zero quantity
            block.timestamp + 1 days,
            new address[](1),
            new uint256[](1)
        );
    }

    function test_RevertIf_CreateAPOrderWithMismatchedTokenArrays() external {
        uint256 marketId = createMarket();

        address[] memory tokensRequested = new address[](1);
        uint256[] memory tokenAmountsRequested = new uint256[](2);

        vm.expectRevert(abi.encodeWithSelector(RecipeOrderbookBase.ArrayLengthMismatch.selector));
        orderbook.createAPOrder(marketId, address(0), 100_000e18, block.timestamp + 1 days, tokensRequested, tokenAmountsRequested);
    }

    function test_RevertIf_CreateAPOrderWithMismatchedBaseAsset() external {
        uint256 marketId = createMarket();

        address[] memory tokensRequested = new address[](1);
        tokensRequested[0] = address(mockIncentiveToken);
        uint256[] memory tokenAmountsRequested = new uint256[](1);
        tokenAmountsRequested[0] = 1000e18;

        MockERC4626 incentiveVault = new MockERC4626(mockIncentiveToken);

        vm.expectRevert(abi.encodeWithSelector(RecipeOrderbookBase.MismatchedBaseAsset.selector));
        orderbook.createAPOrder(
            marketId,
            address(incentiveVault), // Funding vault with mismatched base asset
            100_000e18,
            block.timestamp + 1 days,
            tokensRequested,
            tokenAmountsRequested
        );
    }
}
