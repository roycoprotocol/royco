// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../../../src/RecipeOrderbook.sol";

import { RecipeOrderbookTestBase } from "../../utils/RecipeOrderbook/RecipeOrderbookTestBase.sol";

contract TestFuzz_OrderbookCreation_RecipeOrderbook is RecipeOrderbookTestBase {
    function setUp() external {
        uint256 protocolFee = 0.01e18; // 1% protocol fee
        uint256 minimumFrontendFee = 0.001e18; // 0.1% minimum frontend fee
        setUpRecipeOrderbookTests(protocolFee, minimumFrontendFee);
    }

    function testFuzz_CreateOrderbook(
        uint256 _protocolFee,
        uint256 _minimumFrontendFee,
        address _weirollImplementation,
        address _ownerAddress,
        address _pointsFactory
    )
        external
    {
        vm.assume(_ownerAddress != address(0));
        vm.assume(_protocolFee <= 1e18);
        vm.assume(_minimumFrontendFee <= 1e18);
        vm.assume((_protocolFee + _minimumFrontendFee) <= 1e18);

        // Deploy orderbook and check for ownership transfer
        vm.expectEmit(true, false, false, true);
        emit Ownable.OwnershipTransferred(address(0), _ownerAddress);
        RecipeOrderbook newOrderbook = new RecipeOrderbook(
            _weirollImplementation,
            _protocolFee,
            _minimumFrontendFee,
            _ownerAddress, // fee claimant
            _pointsFactory
        );
        // Check constructor args being set correctly
        assertEq(newOrderbook.WEIROLL_WALLET_IMPLEMENTATION(), _weirollImplementation);
        assertEq(newOrderbook.POINTS_FACTORY(), _pointsFactory);
        assertEq(newOrderbook.protocolFee(), _protocolFee);
        assertEq(newOrderbook.protocolFeeClaimant(), _ownerAddress);
        assertEq(newOrderbook.minimumFrontendFee(), _minimumFrontendFee);

        // Check initial orderbook state
        assertEq(newOrderbook.numAPOrders(), 0);
        assertEq(newOrderbook.numIPOrders(), 0);
        assertEq(newOrderbook.numMarkets(), 0);
    }
}
