// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../../../src/RecipeKernel.sol";
import { RecipeKernelTestBase } from "../../utils/RecipeKernel/RecipeKernelTestBase.sol";

contract Test_Setters_RecipeKernel is RecipeKernelTestBase {
    function setUp() external {
        uint256 protocolFee = 0.01e18; // 1% protocol fee
        uint256 minimumFrontendFee = 0.001e18; // 0.1% minimum frontend fee
        setUpRecipeKernelTests(protocolFee, minimumFrontendFee);
    }

    function test_SetProtocolFeeClaimant() external prankModifier(OWNER_ADDRESS) {
        assertEq(recipeKernel.protocolFeeClaimant(), OWNER_ADDRESS);
        recipeKernel.setProtocolFeeClaimant(ALICE_ADDRESS);
        assertEq(recipeKernel.protocolFeeClaimant(), ALICE_ADDRESS);
    }

    function test_RevertIf_NonOwnerSetProtocolFeeClaimant() external prankModifier(ALICE_ADDRESS) {
        vm.expectRevert("UNAUTHORIZED");
        recipeKernel.setProtocolFeeClaimant(BOB_ADDRESS);
    }

    function test_SetProtocolFee() external prankModifier(OWNER_ADDRESS) {
        uint256 newProtocolFee = 0.02e18;
        assertEq(recipeKernel.protocolFee(), initialProtocolFee);
        recipeKernel.setProtocolFee(newProtocolFee);
        assertEq(recipeKernel.protocolFee(), newProtocolFee);
    }

    function test_RevertIf_NonOwnerSetProtocolFee() external prankModifier(ALICE_ADDRESS) {
        vm.expectRevert("UNAUTHORIZED");
        recipeKernel.setProtocolFee(0.02e18);
    }

    function test_SetMinimumFrontendFee() external prankModifier(OWNER_ADDRESS) {
        uint256 newMinimumFrontendFee = 0.002e18;
        assertEq(recipeKernel.minimumFrontendFee(), initialMinimumFrontendFee);
        recipeKernel.setMinimumFrontendFee(newMinimumFrontendFee);
        assertEq(recipeKernel.minimumFrontendFee(), newMinimumFrontendFee);
    }

    function test_RevertIf_NonOwnerSetMinimumFrontendFee() external prankModifier(ALICE_ADDRESS) {
        vm.expectRevert("UNAUTHORIZED");
        recipeKernel.setMinimumFrontendFee(0.002e18);
    }
}
