// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../../../src/RecipeOrderbook.sol";
import { RecipeOrderbookTestBase } from "../../utils/RecipeOrderbook/RecipeOrderbookTestBase.sol";

contract Test_Setters_RecipeOrderbook is RecipeOrderbookTestBase {
    function setUp() external {
        uint256 protocolFee = 0.01e18; // 1% protocol fee
        uint256 minimumFrontendFee = 0.001e18; // 0.1% minimum frontend fee
        setUpRecipeOrderbookTests(protocolFee, minimumFrontendFee);
    }

    function test_SetProtocolFeeClaimant() external prankModifier(OWNER_ADDRESS) {
        assertEq(orderbook.protocolFeeClaimant(), OWNER_ADDRESS);
        orderbook.setProtocolFeeClaimant(ALICE_ADDRESS);
        assertEq(orderbook.protocolFeeClaimant(), ALICE_ADDRESS);
    }

    function test_RevertIf_NonOwnerSetProtocolFeeClaimant() external prankModifier(ALICE_ADDRESS) {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, ALICE_ADDRESS));
        orderbook.setProtocolFeeClaimant(BOB_ADDRESS);
    }

    function test_SetProtocolFee() external prankModifier(OWNER_ADDRESS) {
        uint256 newProtocolFee = 0.02e18;
        assertEq(orderbook.protocolFee(), initialProtocolFee);
        orderbook.setProtocolFee(newProtocolFee);
        assertEq(orderbook.protocolFee(), newProtocolFee);
    }

    function test_RevertIf_NonOwnerSetProtocolFee() external prankModifier(ALICE_ADDRESS) {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, ALICE_ADDRESS));
        orderbook.setProtocolFee(0.02e18);
    }

    function test_SetMinimumFrontendFee() external prankModifier(OWNER_ADDRESS) {
        uint256 newMinimumFrontendFee = 0.002e18;
        assertEq(orderbook.minimumFrontendFee(), initialMinimumFrontendFee);
        orderbook.setMinimumFrontendFee(newMinimumFrontendFee);
        assertEq(orderbook.minimumFrontendFee(), newMinimumFrontendFee);
    }

    function test_RevertIf_NonOwnerSetMinimumFrontendFee() external prankModifier(ALICE_ADDRESS) {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, ALICE_ADDRESS));
        orderbook.setMinimumFrontendFee(0.002e18);
    }
}
