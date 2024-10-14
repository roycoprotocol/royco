// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../../utils/RecipeMarketHub/RecipeMarketHubTestBase.sol";

contract TestFuzz_RecipeMarketHubCreation_RecipeMarketHub is RecipeMarketHubTestBase {
    function setUp() external {
        uint256 protocolFee = 0.01e18; // 1% protocol fee
        uint256 minimumFrontendFee = 0.001e18; // 0.1% minimum frontend fee
        setUpRecipeMarketHubTests(protocolFee, minimumFrontendFee);
    }

    function testFuzz_CreateRecipeMarketHub(
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

        // Deploy recipeMarketHub and check for ownership transfer
        vm.expectEmit(true, false, false, true);
        emit Ownable.OwnershipTransferred(address(0), _ownerAddress);
        RecipeMarketHub newRecipeMarketHub = new RecipeMarketHub(
            _weirollImplementation,
            _protocolFee,
            _minimumFrontendFee,
            _ownerAddress, // fee claimant
            _pointsFactory
        );
        // Check constructor args being set correctly
        assertEq(newRecipeMarketHub.WEIROLL_WALLET_IMPLEMENTATION(), _weirollImplementation);
        assertEq(newRecipeMarketHub.POINTS_FACTORY(), _pointsFactory);
        assertEq(newRecipeMarketHub.protocolFee(), _protocolFee);
        assertEq(newRecipeMarketHub.protocolFeeClaimant(), _ownerAddress);
        assertEq(newRecipeMarketHub.minimumFrontendFee(), _minimumFrontendFee);

        // Check initial recipeMarketHub state
        assertEq(newRecipeMarketHub.numAPOffers(), 0);
        assertEq(newRecipeMarketHub.numIPOffers(), 0);
        assertEq(newRecipeMarketHub.numMarkets(), 0);
    }
}
