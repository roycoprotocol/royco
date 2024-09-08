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

    function setUp() external {
        setupBaseEnvironment();
        vault = new ERC4626i(ERC4626(address(mockVault)), 0.01e18, 0.001e18, address(pointsFactory));
        // Create a new Points contract through the factory
        pointsProgram = PointsFactory(vault.pointsFactory()).createPointsProgram(programName, programSymbol, decimals, programOwner, vault, orderbook);

        // Create a rewards campaign
        vm.startPrank(programOwner);
        campaignId = pointsProgram.createPointsRewardsCampaign(block.timestamp, block.timestamp + 30 days, 1000e18);
        pointsProgram.addAllowedIP(ipAddress);
        vm.stopPrank();
    }

    /// @dev Test the initialization of the Points contract
    function test_PointsCreation() external view {
        // Verify the Points contract is initialized correctly
        assertEq(pointsProgram.name(), programName);
        assertEq(pointsProgram.symbol(), programSymbol);
        assertEq(pointsProgram.decimals(), decimals);
        assertEq(pointsProgram.owner(), programOwner);
        assertEq(address(pointsProgram.allowedVault()), address(vault));
        assertEq(address(pointsProgram.orderbook()), address(orderbook));
    }

    function test_CreatePointsRewardsCampaign() external prankModifier(programOwner) {
        uint256 start = block.timestamp;
        uint256 end = start + 30 days;
        uint256 totalRewards = 1000e18;

        uint256 newCampaignId = pointsProgram.createPointsRewardsCampaign(start, end, totalRewards);

        // Check if the campaign is correctly added to allowedCampaigns
        assertTrue(pointsProgram.allowedCampaigns(newCampaignId));
    }

    function test_RevertIf_NonOwnerCreatesPointsRewardsCampaign() external prankModifier(BOB_ADDRESS) {
        uint256 start = block.timestamp;
        uint256 end = start + 30 days;
        uint256 totalRewards = 1000e18;

        vm.expectRevert(abi.encodeWithSelector(Ownable.Unauthorized.selector));
        pointsProgram.createPointsRewardsCampaign(start, end, totalRewards);
    }

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

    function test_AwardPoints_Campaign() external prankModifier(address(vault)) {
        // Check if the event was emitted (Points awarded)
        vm.expectEmit(true, true, false, true, address(pointsProgram));
        emit Points.Award(BOB_ADDRESS, 500e18);

        // Vault should call the award function
        pointsProgram.award(BOB_ADDRESS, 500e18, campaignId);
    }

    function test_RevertIf_NonVaultAwardsPoints_Campaign() external prankModifier(BOB_ADDRESS) {
        // Expect revert if a non-vault address tries to award points
        vm.expectRevert(abi.encodeWithSelector(Points.OnlyIncentivizedVault.selector));
        pointsProgram.award(BOB_ADDRESS, 500e18, campaignId);
    }

    function test_RevertIf_AwardPoints_NonAuthorizedCampaign() external prankModifier(address(vault)) {
        uint256 invalidCampaignId = 999; // Invalid campaignId

        // Expect revert due to non-authorized campaign
        vm.expectRevert(abi.encodeWithSelector(Points.CampaignNotAuthorized.selector));
        pointsProgram.award(BOB_ADDRESS, 500e18, invalidCampaignId);
    }

    function test_AwardPoints_AllowedIP() external prankModifier(address(orderbook)) {
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
