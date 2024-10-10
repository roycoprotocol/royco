// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "src/Points.sol";
import { WrappedVault } from "../../../src/WrappedVault.sol";
import { ERC4626 } from "../../../lib/solmate/src/tokens/ERC4626.sol";
import { RoycoTestBase } from "../../utils/RoycoTestBase.sol";

contract Test_Points is RoycoTestBase {
    string programName = "TestPoints";
    string programSymbol = "TP";
    uint256 decimals = 18;
    address programOwner = ALICE_ADDRESS;
    address ipAddress = CHARLIE_ADDRESS;
    WrappedVault vault;
    Points pointsProgram;
    uint256 campaignId;

    uint256 public constant PROTOCOL_FEE = 0.01e18;

    function setUp() external {
        setupBaseEnvironment();
        programOwner = ALICE_ADDRESS;
        vault = erc4626iFactory.wrapVault(mockVault, programOwner, "Test Vault", ERC4626I_FACTORY_MIN_FRONTEND_FEE);
        pointsProgram = PointsFactory(vault.POINTS_FACTORY()).createPointsProgram(programName, programSymbol, decimals, programOwner);
        ipAddress = CHARLIE_ADDRESS;

        vm.startPrank(POINTS_FACTORY_OWNER_ADDRESS);
        pointsFactory.addRecipeKernel(address(recipeKernel));
        vm.stopPrank();

        vm.startPrank(programOwner);
        // Create a rewards campaign
        pointsProgram.addAllowedVault(address(vault));
        vm.stopPrank();
    }

    /// @dev Test the initialization of the Points contract
    function test_PointsCreation() external view {
        // Verify the Points contract is initialized correctly
        assertEq(pointsProgram.name(), programName);
        assertEq(pointsProgram.symbol(), programSymbol);
        assertEq(pointsProgram.decimals(), decimals);
        assertEq(pointsProgram.owner(), programOwner);
        assertEq(address(pointsProgram.pointsFactory()), address(vault.POINTS_FACTORY()));
        assertTrue(pointsProgram.isAllowedVault(address(vault)));
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
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, BOB_ADDRESS));
        pointsProgram.addAllowedIP(ipAddress);
    }

    function test_AwardPoints() external prankModifier(address(vault)) {
        // Check if the event was emitted (Points awarded)
        vm.expectEmit(true, true, false, true, address(pointsProgram));
        emit Points.Award(BOB_ADDRESS, 500e18, address(this));

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
        vm.startPrank(address(recipeKernel));

        // Check if the event was emitted (Points awarded)
        vm.expectEmit(true, true, false, true, address(pointsProgram));
        emit Points.Award(BOB_ADDRESS, 300e18, ipAddress);

        // IP should call the award function
        pointsProgram.award(BOB_ADDRESS, 300e18, ipAddress);
    }

    function test_RevertIf_NonAllowedIPAwardsPoints() external {
        vm.startPrank(POINTS_FACTORY_OWNER_ADDRESS);
        pointsFactory.addRecipeKernel(address(recipeKernel));
        vm.stopPrank();

        vm.startPrank(address(recipeKernel));
        // Expect revert if a non-allowed IP tries to award points
        vm.expectRevert(abi.encodeWithSelector(Points.NotAllowedIP.selector));
        pointsProgram.award(BOB_ADDRESS, 300e18, BOB_ADDRESS);
        vm.stopPrank();
    }

    function test_RevertIf_NonOrderbookCallsAwardForIP() external prankModifier(BOB_ADDRESS) {
        // Expect revert if a non-recipeKernel address calls award for IPs
        vm.expectRevert(abi.encodeWithSelector(Points.OnlyRecipeKernel.selector));
        pointsProgram.award(BOB_ADDRESS, 300e18, ipAddress);
    }
}
