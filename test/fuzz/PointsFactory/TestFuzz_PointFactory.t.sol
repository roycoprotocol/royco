// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../../../src/PointsFactory.sol";
import { RoycoTestBase } from "../../utils/RoycoTestBase.sol";

contract TestFuzz_PointFactory is RoycoTestBase {
    function setUp() external {
        setupBaseEnvironment();
    }

    function testFuzz_AddRecipeKernel(address _recipeKernel) external prankModifier(POINTS_FACTORY_OWNER_ADDRESS) {
        // Expect the NewPointsProgram event to be emitted
        vm.expectEmit(true, false, false, true, address(pointsFactory));
        // Emit the expected event
        emit PointsFactory.RecipeKernelAdded(address(_recipeKernel));

        assertFalse(pointsFactory.isRecipeKernel(address(_recipeKernel)));
        pointsFactory.addRecipeKernel(address(_recipeKernel));
        assertTrue(pointsFactory.isRecipeKernel(address(_recipeKernel)));
    }

    function testFuzz_RevertIf_NonOwnerAddsRecipeKernel(address _nonOwner) external prankModifier(_nonOwner) {
        vm.assume(POINTS_FACTORY_OWNER_ADDRESS != _nonOwner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, _nonOwner));
        pointsFactory.addRecipeKernel(address(recipeKernel));
    }

    function testFuzz_CreatePointsProgram(string memory _programName, string memory _programSymbol, uint256 _decimals, address _programOwner) external {
        vm.assume(_programOwner != address(0));
        
        // Expect the NewPointsProgram event to be emitted before creation
        vm.expectEmit(false, true, true, true, address(pointsFactory));
        // Emit the expected event (don't know Points program address before hand)
        emit PointsFactory.NewPointsProgram(Points(address(0)), _programName, _programSymbol);

        // Call PointsFactory to create a new Points program
        Points pointsProgram = pointsFactory.createPointsProgram(_programName, _programSymbol, _decimals, _programOwner);

        // Assertions on the created Points program
        assertEq(pointsProgram.name(), _programName); // Check the name
        assertEq(pointsProgram.symbol(), _programSymbol); // Check the symbol
        assertEq(pointsProgram.decimals(), _decimals); // Check the decimals
        assertEq(pointsProgram.owner(), _programOwner); // Check the owner

        assertFalse(pointsProgram.isAllowedVault(address(mockVault))); // Check the allowed vault

        // Verify that the Points program is correctly tracked by the factory
        assertTrue(pointsFactory.isPointsProgram(address(pointsProgram)));
    }
}
