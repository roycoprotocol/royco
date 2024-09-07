// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../../../src/PointsFactory.sol";
import { RoycoTestBase } from "../../utils/RoycoTestBase.sol";

contract TestFuzz_PointFactory is RoycoTestBase {
    function setUp() external {
        setupBaseEnvironment();
    }

    function testFuzz_CreatePointsProgram(string memory _programName, string memory _programSymbol, uint256 _decimals, address _programOwner) external {
        // Expect the NewPointsProgram event to be emitted before creation
        vm.expectEmit(false, true, true, true, address(pointsFactory));
        // Emit the expected event (don't know Points program address before hand)
        emit PointsFactory.NewPointsProgram(Points(address(0)), _programName, _programSymbol, address(mockVault), address(orderbook));

        // Call PointsFactory to create a new Points program
        Points pointsProgram =
            pointsFactory.createPointsProgram(_programName, _programSymbol, _decimals, _programOwner, ERC4626i(address(mockVault)), orderbook);

        // Assertions on the created Points program
        assertEq(pointsProgram.name(), _programName); // Check the name
        assertEq(pointsProgram.symbol(), _programSymbol); // Check the symbol
        assertEq(pointsProgram.decimals(), _decimals); // Check the decimals
        assertEq(pointsProgram.owner(), _programOwner); // Check the owner
        assertEq(address(pointsProgram.allowedVault()), address(mockVault)); // Check the allowed vault
        assertEq(address(pointsProgram.orderbook()), address(orderbook)); // Check the orderbook

        // Verify that the Points program is correctly tracked by the factory
        assertTrue(pointsFactory.isPointsProgram(address(pointsProgram)));
    }
}
