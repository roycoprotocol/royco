// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../../../src/PointsFactory.sol";

import { RoycoTestBase } from "../../utils/RoycoTestBase.sol";

contract Test_PointFactory is RoycoTestBase {
    function setUp() external {
        setupBaseEnvironment();
    }

    function test_CreatePointsProgram() external {
        string memory programName = "POINTS_PROGRAM";
        string memory programSymbol = "PTS";
        uint256 decimals = 18;
        address programOwner = ALICE_ADDRESS;

        // Expect the NewPointsProgram event to be emitted
        vm.expectEmit(false, true, true, true, address(pointsFactory));
        // Emit the expected event (don't know Points program address before hand)
        emit PointsFactory.NewPointsProgram(Points(address(0)), programName, programSymbol, address(mockVault), address(orderbook));

        // Call the PointsFactory to create a new Points program
        Points pointsProgram = pointsFactory.createPointsProgram(programName, programSymbol, decimals, programOwner, ERC4626i(address(mockVault)), orderbook);

        // Assert that the Points program has been created correctly
        assertEq(pointsProgram.name(), programName); // Check the name
        assertEq(pointsProgram.symbol(), programSymbol); // Check the symbol
        assertEq(pointsProgram.decimals(), decimals); // Check the decimals
        assertEq(pointsProgram.owner(), programOwner); // Check the owner
        assertEq(address(pointsProgram.allowedVault()), address(mockVault)); // Check the allowed vault
        assertEq(address(pointsProgram.orderbook()), address(orderbook)); // Check the orderbook

        // Verify that the Points program is correctly tracked by the factory
        assertTrue(pointsFactory.isPointsProgram(address(pointsProgram)));
    }
}
