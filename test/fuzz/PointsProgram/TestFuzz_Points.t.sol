// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "src/Points.sol";
import { VaultWrapper } from "../../../src/VaultWrapper.sol";
import { RoycoTestBase } from "../../utils/RoycoTestBase.sol";

contract TestFuzz_Points is RoycoTestBase {
    string programName = "TestPoints";
    string programSymbol = "TP";
    uint256 decimals = 18;
    VaultWrapper vault;
    Points pointsProgram;
    address owner;
    uint256 constant MINIMUM_CAMPAIGN_DURATION = 7 days;
    uint256 campaignId;
    address ipAddress;

    function setUp() external {
        setupBaseEnvironment();
        owner = ALICE_ADDRESS;
        vault = erc4626iFactory.createIncentivizedVault(mockVault, owner, "Test Vault", ERC4626I_FACTORY_MIN_FRONTEND_FEE);
        pointsProgram = PointsFactory(vault.POINTS_FACTORY()).createPointsProgram(programName, programSymbol, decimals, owner);
        ipAddress = CHARLIE_ADDRESS;

        vm.startPrank(POINTS_FACTORY_OWNER_ADDRESS);
        pointsFactory.addRecipeKernel(address(recipeKernel));
        vm.stopPrank();

        vm.startPrank(owner);
        // Create a rewards campaign
        pointsProgram.addAllowedVault(address(vault));
        vm.stopPrank();
    }

    function testFuzz_PointsCreation(address _owner, string memory _name, string memory _symbol, uint256 _decimals) external {
        vm.assume(_owner != address(0));

        VaultWrapper newVault = erc4626iFactory.createIncentivizedVault(mockVault, _owner, "Test Vault", ERC4626I_FACTORY_MIN_FRONTEND_FEE);
        Points fuzzPoints = PointsFactory(vault.POINTS_FACTORY()).createPointsProgram(_name, _symbol, _decimals, _owner);

        assertEq(fuzzPoints.name(), _name);
        assertEq(fuzzPoints.symbol(), _symbol);
        assertEq(fuzzPoints.decimals(), _decimals);
        assertEq(fuzzPoints.owner(), _owner);
        assertEq(address(pointsProgram.pointsFactory()), address(vault.POINTS_FACTORY()));
        assertFalse(fuzzPoints.isAllowedVault(address(newVault)));
    }

    function testFuzz_AddAllowedIP(address _ip) external prankModifier(owner) {
        pointsProgram.addAllowedIP(_ip);
        assertTrue(pointsProgram.allowedIPs(_ip));
    }

    function testFuzz_RevertIf_NonOwnerAddsAllowedIP(address _ip, address _nonOwner) external prankModifier(_nonOwner) {
        vm.assume(_nonOwner != owner);

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, _nonOwner));
        pointsProgram.addAllowedIP(_ip);
    }

    function testFuzz_AwardPoints_AllowedIP(address _to, uint256 _amount, address _ip) external {
        vm.startPrank(owner);
        pointsProgram.addAllowedIP(_ip);
        vm.stopPrank();

        vm.expectEmit(true, true, false, true, address(pointsProgram));
        emit Points.Award(_to, _amount);

        vm.startPrank(address(recipeKernel));
        pointsProgram.award(_to, _amount, _ip);
        vm.stopPrank();
    }

    // Fuzz test reverting when a non-allowed IP tries to award points
    function testFuzz_RevertIf_NonAllowedIPAwardsPoints(address _to, uint256 _amount, address _nonAllowedIP) external prankModifier(address(recipeKernel)) {
        vm.assume(_nonAllowedIP != ipAddress);

        vm.expectRevert(abi.encodeWithSelector(Points.NotAllowedIP.selector));
        pointsProgram.award(_to, _amount, _nonAllowedIP);
    }

    // Fuzz test reverting when a non-recipeKernel address calls award for IPs
    function testFuzz_RevertIf_NonRecipekernelCallsAwardForIP(address _to, uint256 _amount, address _nonRecipekernel) external prankModifier(_nonRecipekernel) {
        vm.assume(_nonRecipekernel != address(recipeKernel));

        vm.expectRevert(abi.encodeWithSelector(Points.OnlyRecipeKernel.selector));
        pointsProgram.award(_to, _amount, ipAddress);
    }
}
