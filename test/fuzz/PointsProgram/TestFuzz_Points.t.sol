// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../../../src/Points.sol";
import "../../../src/PointsFactory.sol";
import { ERC4626i } from "../../../src/ERC4626i.sol";
import { ERC4626 } from "../../../lib/solmate/src/tokens/ERC4626.sol";
import { Ownable } from "lib/solady/src/auth/Ownable.sol";
import { RoycoTestBase } from "../../utils/RoycoTestBase.sol";

contract TestFuzz_Points is RoycoTestBase {
    string programName = "TestPoints";
    string programSymbol = "TP";
    uint256 decimals = 18;
    ERC4626i vault;
    Points pointsProgram;
    address owner = ALICE_ADDRESS;
    uint256 constant MINIMUM_CAMPAIGN_DURATION = 7 days;
    uint256 campaignId;
    address ipAddress;

    function setUp() external {
        setupBaseEnvironment();
        vault = erc4626iFactory.createIncentivizedVault(mockVault, owner, "Test Vault", ERC4626I_FACTORY_MIN_FRONTEND_FEE);
        pointsProgram = PointsFactory(vault.POINTS_FACTORY()).createPointsProgram(programName, programSymbol, decimals, owner, orderbook);
        ipAddress = CHARLIE_ADDRESS;

        // Create a rewards campaign
        vm.startPrank(owner);
        pointsProgram.addAllowedVault(address(vault));
        
        vm.stopPrank();
    }

    function testFuzz_PointsCreation(address _owner, string memory _name, string memory _symbol, uint256 _decimals) external {
        ERC4626i newVault = erc4626iFactory.createIncentivizedVault(mockVault, _owner, "Test Vault", ERC4626I_FACTORY_MIN_FRONTEND_FEE);
        RecipeOrderbook newOrderbook = new RecipeOrderbook(address(weirollImplementation), 0.01e18, 0.001e18, OWNER_ADDRESS, address(pointsFactory));

        Points fuzzPoints = PointsFactory(vault.POINTS_FACTORY()).createPointsProgram(_name, _symbol, _decimals, _owner, newOrderbook);
        
        assertEq(fuzzPoints.name(), _name);
        assertEq(fuzzPoints.symbol(), _symbol);
        assertEq(fuzzPoints.decimals(), _decimals);
        assertEq(fuzzPoints.owner(), _owner);
        assertFalse(fuzzPoints.isAllowedVault(address(newVault)));
        assertEq(address(fuzzPoints.orderbook()), address(newOrderbook));
    }

    function testFuzz_AddAllowedIP(address _ip) external prankModifier(owner) {
        pointsProgram.addAllowedIP(_ip);
        assertTrue(pointsProgram.allowedIPs(_ip));
    }

    function testFuzz_RevertIf_NonOwnerAddsAllowedIP(address _ip, address _nonOwner) external prankModifier(_nonOwner) {
        vm.assume(_nonOwner != owner);

        vm.expectRevert(abi.encodeWithSelector(Ownable.Unauthorized.selector));
        pointsProgram.addAllowedIP(_ip);
    }

    function testFuzz_AwardPoints_AllowedIP(address _to, uint256 _amount, address _ip) external prankModifier(address(orderbook)) {
        pointsProgram.addAllowedIP(_ip);

        vm.expectEmit(true, true, false, true, address(pointsProgram));
        emit Points.Award(_to, _amount);

        pointsProgram.award(_to, _amount, _ip);
    }

    // Fuzz test reverting when a non-allowed IP tries to award points
    function testFuzz_RevertIf_NonAllowedIPAwardsPoints(address _to, uint256 _amount, address _nonAllowedIP) external prankModifier(address(orderbook)) {
        vm.assume(_nonAllowedIP != ipAddress);
        
        vm.expectRevert(abi.encodeWithSelector(Points.NotAllowedIP.selector));
        pointsProgram.award(_to, _amount, _nonAllowedIP);
    }

    // Fuzz test reverting when a non-orderbook address calls award for IPs
    function testFuzz_RevertIf_NonOrderbookCallsAwardForIP(address _to, uint256 _amount, address _nonOrderbook) external prankModifier(_nonOrderbook) {
        vm.assume(_nonOrderbook != address(orderbook));

        vm.expectRevert(abi.encodeWithSelector(Points.OnlyRecipeOrderbook.selector));
        pointsProgram.award(_to, _amount, ipAddress);
    }
}
