// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../../../src/PointsFactory.sol";
import { RoycoTestBase } from "../../utils/RoycoTestBase.sol";

contract Test_PointFactory is RoycoTestBase {
    function setUp() external {
        setupBaseEnvironment();
    }

    function test_AddOrderbook() external prankModifier(POINTS_FACTORY_OWNER_ADDRESS) {
        assertFalse(pointsFactory.isRecipeOrderbook(address(0xbeef)));
        // Expect the NewPointsProgram event to be emitted
        vm.expectEmit(true, false, false, true, address(pointsFactory));
        // Emit the expected event
        emit PointsFactory.RecipeOrderbookAdded(address(0xbeef));
        pointsFactory.addRecipeOrderbook(address(0xbeef));
        assertTrue(pointsFactory.isRecipeOrderbook(address(0xbeef)));
    }

    function test_RevertIf_NonOwnerAddsOrderbook() external prankModifier(ALICE_ADDRESS) {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, ALICE_ADDRESS));        
        pointsFactory.addRecipeOrderbook(address(orderbook));
    }

    function test_CreatePointsProgram() external {
        string memory programName = "POINTS_PROGRAM";
        string memory programSymbol = "PTS";
        uint256 decimals = 18;
        address programOwner = ALICE_ADDRESS;

        // Expect the NewPointsProgram event to be emitted
        vm.expectEmit(false, true, true, true, address(pointsFactory));
        // Emit the expected event (don't know Points program address before hand)
        emit PointsFactory.NewPointsProgram(Points(address(0)), programName, programSymbol);
        
        // Call the PointsFactory to create a new Points program
        Points pointsProgram = pointsFactory.createPointsProgram(programName, programSymbol, decimals, programOwner);

        // Assert that the Points program has been created correctly
        assertEq(pointsProgram.name(), programName); // Check the name
        assertEq(pointsProgram.symbol(), programSymbol); // Check the symbol
        assertEq(pointsProgram.decimals(), decimals); // Check the decimals
        assertEq(pointsProgram.owner(), programOwner); // Check the owner
        assertEq(address(pointsProgram.pointsFactory()), address(pointsFactory)); // Check the points factory

        // Verify that the Points program is correctly tracked by the factory
        assertTrue(pointsFactory.isPointsProgram(address(pointsProgram)));
    }
}
