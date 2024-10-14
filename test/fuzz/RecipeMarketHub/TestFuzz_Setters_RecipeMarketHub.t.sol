// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../../../src/RecipeMarketHub.sol";

import { RecipeMarketHubTestBase } from "../../utils/RecipeMarketHub/RecipeMarketHubTestBase.sol";

contract TestFuzz_Setters_RecipeMarketHub is RecipeMarketHubTestBase {
    function setUp() external {
        uint256 protocolFee = 0.01e18; // 1% protocol fee
        uint256 minimumFrontendFee = 0.001e18; // 0.1% minimum frontend fee
        setUpRecipeMarketHubTests(protocolFee, minimumFrontendFee);
    }

    function testFuzz_SetProtocolFeeClaimant(address _newClaimant) external prankModifier(OWNER_ADDRESS) {
        assertEq(recipeMarketHub.protocolFeeClaimant(), OWNER_ADDRESS);
        recipeMarketHub.setProtocolFeeClaimant(_newClaimant);
        assertEq(recipeMarketHub.protocolFeeClaimant(), _newClaimant);
    }

    function testFuzz_RevertIf_NonOwnerSetProtocolFeeClaimant(address _nonOwner, address _newClaimant) external prankModifier(_nonOwner) {
        vm.assume(_nonOwner != OWNER_ADDRESS);
        vm.expectRevert("UNAUTHORIZED");
        recipeMarketHub.setProtocolFeeClaimant(_newClaimant);
    }

    function testFuzz_SetProtocolFee(uint256 _newProtocolFee) external prankModifier(OWNER_ADDRESS) {
        recipeMarketHub.setProtocolFee(_newProtocolFee);
        assertEq(recipeMarketHub.protocolFee(), _newProtocolFee);
    }

    function testFuzz_RevertIf_NonOwnerSetProtocolFee(address _nonOwner, uint256 _newProtocolFee) external prankModifier(_nonOwner) {
        vm.assume(_nonOwner != OWNER_ADDRESS);
        vm.expectRevert("UNAUTHORIZED");
        recipeMarketHub.setProtocolFee(_newProtocolFee);
    }

    function testFuzz_SetMinimumFrontendFee(uint256 _newMinimumFrontendFee) external prankModifier(OWNER_ADDRESS) {
        recipeMarketHub.setMinimumFrontendFee(_newMinimumFrontendFee);
        assertEq(recipeMarketHub.minimumFrontendFee(), _newMinimumFrontendFee);
    }

    function testFuzz_RevertIf_NonOwnerSetMinimumFrontendFee(address _nonOwner, uint256 _newMinimumFrontendFee) external prankModifier(_nonOwner) {
        vm.assume(_nonOwner != OWNER_ADDRESS);
        vm.expectRevert("UNAUTHORIZED");
        recipeMarketHub.setMinimumFrontendFee(_newMinimumFrontendFee);
    }
}
