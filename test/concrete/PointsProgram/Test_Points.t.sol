// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../../../src/Points.sol";
import "../../../src/PointsFactory.sol";
import { ERC4626i } from "../../../src/ERC4626i.sol";
import { ERC4626 } from "../../../lib/solmate/src/tokens/ERC4626.sol";
import { Ownable } from "lib/solady/src/auth/Ownable.sol";
import { RoycoTestBase } from "../../utils/RoycoTestBase.sol";

contract Test_Points is RoycoTestBase {
    string programName = "TestPoints";
    string programSymbol = "TP";
    uint256 decimals = 18;
    address programOwner = ALICE_ADDRESS;
    address ipAddress = CHARLIE_ADDRESS;
    ERC4626i vault;
    Points pointsProgram;
    uint256 campaignId;

    uint256 public constant PROTOCOL_FEE = 0.01e18;

    function setUp() external {
        setupBaseEnvironment();
        vault = erc4626iFactory.createIncentivizedVault(mockVault, programOwner, "Test Vault", ERC4626I_FACTORY_MIN_FRONTEND_FEE);
        // Create a new Points contract through the factory
        pointsProgram = PointsFactory(vault.POINTS_FACTORY()).createPointsProgram(programName, programSymbol, decimals, programOwner, orderbook);

        // Authorize mockVault to award points
        vm.prank(programOwner);
        pointsProgram.addAllowedVault(address(vault));
    }

    /// @dev Test the initialization of the Points contract
    function test_PointsCreation() external view {
        // Verify the Points contract is initialized correctly
        assertEq(pointsProgram.name(), programName);
        assertEq(pointsProgram.symbol(), programSymbol);
        assertEq(pointsProgram.decimals(), decimals);
        assertEq(pointsProgram.owner(), programOwner);
        assertTrue(pointsProgram.isAllowedVault(address(vault)));
        assertEq(address(pointsProgram.orderbook()), address(orderbook));
    }

    // TODO: replace with a test that checks that a non-owner cannot create a campaign
    // function test_RevertIf_NonOwnerCreatesPointsRewardsCampaign() external prankModifier(BOB_ADDRESS) {
    //     uint256 start = block.timestamp;
    //     uint256 end = start + 30 days;
    //     uint256 totalRewards = 100000e18;

    //     vm.expectRevert(abi.encodeWithSelector(Ownable.Unauthorized.selector));
    //     pointsProgram.createPointsRewardsCampaign(start, end, totalRewards);
    // }

    function test_AddAllowedIP() external prankModifier(programOwner) {
        // Add CHARLIE_ADDRESS as an allowed IP
        pointsProgram.addAllowedIP(ipAddress);

        // Verify that CHARLIE_ADDRESS is added to allowed IPs
        assertTrue(pointsProgram.allowedIPs(ipAddress));
    }

    function test_RevertIf_NonOwnerAddsAllowedIP() external prankModifier(BOB_ADDRESS) {
        // Expect revert when a non-owner tries to add an allowed IP
        vm.expectRevert(abi.encodeWithSelector(Ownable.Unauthorized.selector));
        pointsProgram.addAllowedIP(ipAddress);
    }

    function test_RemoveAllowedIP() external prankModifier(programOwner) {
        // Add CHARLIE_ADDRESS first as an allowed IP
        pointsProgram.addAllowedIP(ipAddress);
        assertTrue(pointsProgram.allowedIPs(ipAddress));

        // Remove CHARLIE_ADDRESS from allowed IPs
        pointsProgram.removeAllowedIP(ipAddress);

        // Verify that CHARLIE_ADDRESS is removed from allowed IPs
        assertFalse(pointsProgram.allowedIPs(ipAddress));
    }

    function test_RevertIf_NonOwnerRemovesAllowedIP() external prankModifier(BOB_ADDRESS) {
        // Expect revert when a non-owner tries to remove an allowed IP
        vm.expectRevert(abi.encodeWithSelector(Ownable.Unauthorized.selector));
        pointsProgram.removeAllowedIP(ipAddress);
    }

    function test_AwardPoints() external prankModifier(address(vault)) {
        // Check if the event was emitted (Points awarded)
        vm.expectEmit(true, true, false, true, address(pointsProgram));
        emit Points.Award(BOB_ADDRESS, 500e18);

        // Vault should call the award function
        pointsProgram.award(BOB_ADDRESS, 500e18);
    }

    //TODO: replace with a test that checks that a non whitelist vault cannot award points
    // function test_RevertIf_NonVaultAwardsPoints_Campaign() external prankModifier(BOB_ADDRESS) {
    //     // Expect revert if a non-vault address tries to award points
    //     vm.expectRevert(abi.encodeWithSelector(Points.OnlyAllowedVaults.selector));
    //     pointsProgram.award(BOB_ADDRESS, 500e18);
    // }

    function test_AwardPoints_AllowedIP() external {
        vm.startPrank(pointsProgram.owner());
        pointsProgram.addAllowedIP(ipAddress);
        vm.stopPrank();
        vm.startPrank(address(orderbook));

        // Check if the event was emitted (Points awarded)
        vm.expectEmit(true, true, false, true, address(pointsProgram));
        emit Points.Award(BOB_ADDRESS, 300e18);

        // IP should call the award function
        pointsProgram.award(BOB_ADDRESS, 300e18, ipAddress);
    }

    function test_RevertIf_NonAllowedIPAwardsPoints() external prankModifier(address(orderbook)) {
        // Expect revert if a non-allowed IP tries to award points
        vm.expectRevert(abi.encodeWithSelector(Points.NotAllowedIP.selector));
        pointsProgram.award(BOB_ADDRESS, 300e18, BOB_ADDRESS);
    }

    function test_RevertIf_NonOrderbookCallsAwardForIP() external prankModifier(BOB_ADDRESS) {
        // Expect revert if a non-orderbook address calls award for IPs
        vm.expectRevert(abi.encodeWithSelector(Points.OnlyRecipeOrderbook.selector));
        pointsProgram.award(BOB_ADDRESS, 300e18, ipAddress);
    }
}
