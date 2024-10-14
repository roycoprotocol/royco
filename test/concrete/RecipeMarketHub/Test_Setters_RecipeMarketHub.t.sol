// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../../../src/RecipeMarketHub.sol";
import { RecipeMarketHubTestBase } from "../../utils/RecipeMarketHub/RecipeMarketHubTestBase.sol";

contract Test_Setters_RecipeMarketHub is RecipeMarketHubTestBase {
    function setUp() external {
        uint256 protocolFee = 0.01e18; // 1% protocol fee
        uint256 minimumFrontendFee = 0.001e18; // 0.1% minimum frontend fee
        setUpRecipeMarketHubTests(protocolFee, minimumFrontendFee);
    }

    function test_SetProtocolFeeClaimant() external prankModifier(OWNER_ADDRESS) {
        assertEq(recipeMarketHub.protocolFeeClaimant(), OWNER_ADDRESS);
        recipeMarketHub.setProtocolFeeClaimant(ALICE_ADDRESS);
        assertEq(recipeMarketHub.protocolFeeClaimant(), ALICE_ADDRESS);
    }

    function test_RevertIf_NonOwnerSetProtocolFeeClaimant() external prankModifier(ALICE_ADDRESS) {
        vm.expectRevert("UNAUTHORIZED");
        recipeMarketHub.setProtocolFeeClaimant(BOB_ADDRESS);
    }

    function test_SetProtocolFee() external prankModifier(OWNER_ADDRESS) {
        uint256 newProtocolFee = 0.02e18;
        assertEq(recipeMarketHub.protocolFee(), initialProtocolFee);
        recipeMarketHub.setProtocolFee(newProtocolFee);
        assertEq(recipeMarketHub.protocolFee(), newProtocolFee);
    }

    function test_RevertIf_NonOwnerSetProtocolFee() external prankModifier(ALICE_ADDRESS) {
        vm.expectRevert("UNAUTHORIZED");
        recipeMarketHub.setProtocolFee(0.02e18);
    }

    function test_SetMinimumFrontendFee() external prankModifier(OWNER_ADDRESS) {
        uint256 newMinimumFrontendFee = 0.002e18;
        assertEq(recipeMarketHub.minimumFrontendFee(), initialMinimumFrontendFee);
        recipeMarketHub.setMinimumFrontendFee(newMinimumFrontendFee);
        assertEq(recipeMarketHub.minimumFrontendFee(), newMinimumFrontendFee);
    }

    function test_RevertIf_NonOwnerSetMinimumFrontendFee() external prankModifier(ALICE_ADDRESS) {
        vm.expectRevert("UNAUTHORIZED");
        recipeMarketHub.setMinimumFrontendFee(0.002e18);
    }
}
