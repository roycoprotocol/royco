// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../../../src/RecipeOrderbook.sol";

import { RecipeOrderbookTestBase } from "../../utils/RecipeOrderbook/RecipeOrderbookTestBase.sol";

contract TestFuzz_Setters_RecipeOrderbook is RecipeOrderbookTestBase {
    function setUp() external {
        uint256 protocolFee = 0.01e18; // 1% protocol fee
        uint256 minimumFrontendFee = 0.001e18; // 0.1% minimum frontend fee
        setUpRecipeOrderbookTests(protocolFee, minimumFrontendFee);
    }

    function testFuzz_SetProtocolFeeClaimant(address _newClaimant) external prankModifier(OWNER_ADDRESS) {
        assertEq(orderbook.protocolFeeClaimant(), OWNER_ADDRESS);
        orderbook.setProtocolFeeClaimant(_newClaimant);
        assertEq(orderbook.protocolFeeClaimant(), _newClaimant);
    }

    function testFuzz_RevertIf_NonOwnerSetProtocolFeeClaimant(address _nonOwner, address _newClaimant) external prankModifier(_nonOwner) {
        vm.assume(_nonOwner != OWNER_ADDRESS);
        vm.expectRevert("UNAUTHORIZED");
        orderbook.setProtocolFeeClaimant(_newClaimant);
    }

    function testFuzz_SetProtocolFee(uint256 _newProtocolFee) external prankModifier(OWNER_ADDRESS) {
        orderbook.setProtocolFee(_newProtocolFee);
        assertEq(orderbook.protocolFee(), _newProtocolFee);
    }

    function testFuzz_RevertIf_NonOwnerSetProtocolFee(address _nonOwner, uint256 _newProtocolFee) external prankModifier(_nonOwner) {
        vm.assume(_nonOwner != OWNER_ADDRESS);
        vm.expectRevert("UNAUTHORIZED");
        orderbook.setProtocolFee(_newProtocolFee);
    }

    function testFuzz_SetMinimumFrontendFee(uint256 _newMinimumFrontendFee) external prankModifier(OWNER_ADDRESS) {
        orderbook.setMinimumFrontendFee(_newMinimumFrontendFee);
        assertEq(orderbook.minimumFrontendFee(), _newMinimumFrontendFee);
    }

    function testFuzz_RevertIf_NonOwnerSetMinimumFrontendFee(address _nonOwner, uint256 _newMinimumFrontendFee) external prankModifier(_nonOwner) {
        vm.assume(_nonOwner != OWNER_ADDRESS);
        vm.expectRevert("UNAUTHORIZED");
        orderbook.setMinimumFrontendFee(_newMinimumFrontendFee);
    }
}
