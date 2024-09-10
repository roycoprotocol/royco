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
        // campaignId = pointsProgram.createPointsRewardsCampaign(block.timestamp, block.timestamp + 30 days, 1000e18);
        // pointsProgram.addAllowedIP(ipAddress);
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
        assertTrue(fuzzPoints.isAllowedVault(address(newVault)));
        assertEq(address(fuzzPoints.orderbook()), address(newOrderbook));
    }

    // TODO: Change to the campaignless paradigm
    // function testFuzz_CreatePointsRewardsCampaign(uint256 _start, uint256 _end, uint256 _totalRewards) external prankModifier(owner) {
    //     // Ensure valid time intervals and duration
    //     _start = block.timestamp + (_start % 365 days); // Start within the next year
    //     _end = _start + MINIMUM_CAMPAIGN_DURATION + (_end % 365 days); // Ensure the end is valid and respects the minimum campaign duration

    //     // Bound the total rewards to avoid overflow and revert
    //     _totalRewards = _totalRewards % 1e30; // Cap total rewards to a reasonable value to avoid overflow

    //     // Create the rewards campaign
    //     uint256 newCampaignId = pointsProgram.createPointsRewardsCampaign(_start, _end, _totalRewards);

    //     // Verify the campaign was successfully added
    //     assertTrue(pointsProgram.allowedCampaigns(newCampaignId));
    // }

    // function testFuzz_RevertIf_CampaignNotStarted(uint256 _blockTimestamp, uint256 _start, uint256 _end, uint256 _totalRewards) external prankModifier(owner) {
    //     // Set _start in the past
    //     vm.warp(_blockTimestamp);
    //     vm.assume(_start < _blockTimestamp);

    //     vm.expectRevert(abi.encodeWithSelector(ERC4626i.CampaignNotStarted.selector));
    //     pointsProgram.createPointsRewardsCampaign(_start, _end, _totalRewards);
    // }

    // function testFuzz_RevertIf_IncorrectInterval(uint256 _blockTimestamp, uint256 _start, uint256 _end, uint256 _totalRewards) external prankModifier(owner) {
    //     vm.assume(_start > _blockTimestamp);
    //     vm.assume(_end > _blockTimestamp);
    //     vm.assume(_end < _start);

    //     vm.expectRevert(abi.encodeWithSelector(ERC4626i.IncorrectInterval.selector));
    //     pointsProgram.createPointsRewardsCampaign(_start, _end, _totalRewards);
    // }

    // function testFuzz_RevertIf_CampaignTooShort(uint256 _start, uint256 _end, uint256 _totalRewards) external prankModifier(owner) {
    //     _start = block.timestamp + (_start % 365 days);
    //     _end = _start + (MINIMUM_CAMPAIGN_DURATION - 1);

    //     vm.expectRevert(abi.encodeWithSelector(ERC4626i.CampaignTooShort.selector));
    //     pointsProgram.createPointsRewardsCampaign(_start, _end, _totalRewards);
    // }

    function testFuzz_AddAllowedIP(address _ip) external prankModifier(owner) {
        pointsProgram.addAllowedIP(_ip);
        assertTrue(pointsProgram.allowedIPs(_ip));
    }

    function testFuzz_RevertIf_NonOwnerAddsAllowedIP(address _ip, address _nonOwner) external prankModifier(_nonOwner) {
        vm.assume(_nonOwner != owner);

        vm.expectRevert(abi.encodeWithSelector(Ownable.Unauthorized.selector));
        pointsProgram.addAllowedIP(_ip);
    }

    function testFuzz_RemoveAllowedIP(address _ip) external prankModifier(owner) {
        pointsProgram.addAllowedIP(_ip);
        assertTrue(pointsProgram.allowedIPs(_ip));

        pointsProgram.removeAllowedIP(_ip);
        assertFalse(pointsProgram.allowedIPs(_ip));
    }

    function testFuzz_RevertIf_NonOwnerRemovesAllowedIP(address _ip, address _nonOwner) external prankModifier(_nonOwner) {
        vm.assume(_nonOwner != owner);

        vm.expectRevert(abi.encodeWithSelector(Ownable.Unauthorized.selector));
        pointsProgram.removeAllowedIP(_ip);
    }

    // TODO: Refactor as necessary
    // function testFuzz_AwardPoints_Campaign(address _to, uint256 _amount) external prankModifier(address(vault)) {
    //     vm.expectEmit(true, true, false, true, address(pointsProgram));
    //     emit Points.Award(_to, _amount);

    //     pointsProgram.award(_to, _amount, campaignId);
    // }

    // function testFuzz_RevertIf_NonVaultAwardsPoints_Campaign(address _to, uint256 _amount, address _nonVault) external prankModifier(_nonVault) {
    //     vm.assume(_nonVault != address(vault));

    //     vm.expectRevert(abi.encodeWithSelector(Points.OnlyIncentivizedVault.selector));
    //     pointsProgram.award(_to, _amount, campaignId);
    // }

    // function testFuzz_RevertIf_AwardPoints_NonAuthorizedCampaign(
    //     uint256 _invalidCampaignId,
    //     address _to,
    //     uint256 _amount
    // )
    //     external
    //     prankModifier(address(vault))
    // {
    //     vm.assume(campaignId != _invalidCampaignId);

    //     vm.expectRevert(abi.encodeWithSelector(Points.CampaignNotAuthorized.selector));
    //     pointsProgram.award(_to, _amount, _invalidCampaignId);
    // }

    function testFuzz_AwardPoints_AllowedIP(address _to, uint256 _amount, address _ip) external prankModifier(address(orderbook)) {
        pointsProgram.addAllowedIP(_ip);

        vm.expectEmit(true, true, false, true, address(pointsProgram));
        emit Points.Award(_to, _amount);

        pointsProgram.award(_to, _amount, _ip);
    }

    // Fuzz test reverting when a non-allowed IP tries to award points
    function testFuzz_RevertIf_NonAllowedIPAwardsPoints(address _to, uint256 _amount, address _nonAllowedIP) external prankModifier(address(orderbook)) {
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
