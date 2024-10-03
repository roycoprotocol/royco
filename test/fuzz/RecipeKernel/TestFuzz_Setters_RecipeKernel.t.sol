// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../../../src/RecipeKernel.sol";

import { RecipeKernelTestBase } from "../../utils/RecipeKernel/RecipeKernelTestBase.sol";

contract TestFuzz_Setters_RecipeKernel is RecipeKernelTestBase {
    function setUp() external {
        uint256 protocolFee = 0.01e18; // 1% protocol fee
        uint256 minimumFrontendFee = 0.001e18; // 0.1% minimum frontend fee
        setUpRecipeKernelTests(protocolFee, minimumFrontendFee);
    }

    function testFuzz_SetProtocolFeeClaimant(address _newClaimant) external prankModifier(OWNER_ADDRESS) {
        assertEq(recipeKernel.protocolFeeClaimant(), OWNER_ADDRESS);
        recipeKernel.setProtocolFeeClaimant(_newClaimant);
        assertEq(recipeKernel.protocolFeeClaimant(), _newClaimant);
    }

    function testFuzz_RevertIf_NonOwnerSetProtocolFeeClaimant(address _nonOwner, address _newClaimant) external prankModifier(_nonOwner) {
        vm.assume(_nonOwner != OWNER_ADDRESS);
        vm.expectRevert("UNAUTHORIZED");
        recipeKernel.setProtocolFeeClaimant(_newClaimant);
    }

    function testFuzz_SetProtocolFee(uint256 _newProtocolFee) external prankModifier(OWNER_ADDRESS) {
        recipeKernel.setProtocolFee(_newProtocolFee);
        assertEq(recipeKernel.protocolFee(), _newProtocolFee);
    }

    function testFuzz_RevertIf_NonOwnerSetProtocolFee(address _nonOwner, uint256 _newProtocolFee) external prankModifier(_nonOwner) {
        vm.assume(_nonOwner != OWNER_ADDRESS);
        vm.expectRevert("UNAUTHORIZED");
        recipeKernel.setProtocolFee(_newProtocolFee);
    }

    function testFuzz_SetMinimumFrontendFee(uint256 _newMinimumFrontendFee) external prankModifier(OWNER_ADDRESS) {
        recipeKernel.setMinimumFrontendFee(_newMinimumFrontendFee);
        assertEq(recipeKernel.minimumFrontendFee(), _newMinimumFrontendFee);
    }

    function testFuzz_RevertIf_NonOwnerSetMinimumFrontendFee(address _nonOwner, uint256 _newMinimumFrontendFee) external prankModifier(_nonOwner) {
        vm.assume(_nonOwner != OWNER_ADDRESS);
        vm.expectRevert("UNAUTHORIZED");
        recipeKernel.setMinimumFrontendFee(_newMinimumFrontendFee);
    }
}
