// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../../utils/RecipeKernel/RecipeKernelTestBase.sol";

contract TestFuzz_RecipeKernelCreation_RecipeKernel is RecipeKernelTestBase {
    function setUp() external {
        uint256 protocolFee = 0.01e18; // 1% protocol fee
        uint256 minimumFrontendFee = 0.001e18; // 0.1% minimum frontend fee
        setUpRecipeKernelTests(protocolFee, minimumFrontendFee);
    }

    function testFuzz_CreateRecipekernel(
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

        // Deploy recipeKernel and check for ownership transfer
        vm.expectEmit(true, false, false, true);
        emit Ownable.OwnershipTransferred(address(0), _ownerAddress);
        RecipeKernel newRecipekernel = new RecipeKernel(
            _weirollImplementation,
            _protocolFee,
            _minimumFrontendFee,
            _ownerAddress, // fee claimant
            _pointsFactory
        );
        // Check constructor args being set correctly
        assertEq(newRecipekernel.WEIROLL_WALLET_IMPLEMENTATION(), _weirollImplementation);
        assertEq(newRecipekernel.POINTS_FACTORY(), _pointsFactory);
        assertEq(newRecipekernel.protocolFee(), _protocolFee);
        assertEq(newRecipekernel.protocolFeeClaimant(), _ownerAddress);
        assertEq(newRecipekernel.minimumFrontendFee(), _minimumFrontendFee);

        // Check initial recipeKernel state
        assertEq(newRecipekernel.numAPOffers(), 0);
        assertEq(newRecipekernel.numIPOffers(), 0);
        assertEq(newRecipekernel.numMarkets(), 0);
    }
}
