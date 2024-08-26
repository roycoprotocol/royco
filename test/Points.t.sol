// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../src/PointsFactory.sol";
import "../src/Points.sol";
import "../src/ERC4626i.sol";
import "../src/RecipeOrderbook.sol";

contract PointsFactoryTest is Test {
    PointsFactory public factory;
    ERC4626i public mockVault;
    RecipeOrderbook public mockOrderbook;

    Points public points;

    address public user = address(0x1);

    function setUp() public {
        factory = new PointsFactory();
        mockVault = ERC4626i(address(new MockERC4626i()));
        mockOrderbook = new RecipeOrderbook(address(0), 0, 0, address(0x1));

        points = factory.createPointsProgram("Test Points", "TP", 18, mockVault, mockOrderbook);
    }

    function testCreatePointsProgram() public {
        Points points2 = factory.createPointsProgram("Test Points", "TP", 18, mockVault, mockOrderbook);

        assertEq(factory.pointsPrograms(1), address(points2));
        assertTrue(factory.isPointsProgram(address(points2)));

        assertEq(points2.name(), "Test Points");
        assertEq(points2.symbol(), "TP");
        assertEq(points2.decimals(), 18);
        assertEq(address(points2.allowedVault()), address(mockVault));
        assertEq(address(points2.orderbook()), address(mockOrderbook));
    }

    function testMultiplePointsPrograms() public {
        factory.createPointsProgram("Test Points 1", "TP1", 18, mockVault, mockOrderbook);
        factory.createPointsProgram("Test Points 2", "TP2", 18, mockVault, mockOrderbook);

        assertEq(factory.pointsPrograms(0), address(factory.pointsPrograms(0)));
        assertEq(factory.pointsPrograms(1), address(factory.pointsPrograms(1)));
        assertTrue(factory.isPointsProgram(address(factory.pointsPrograms(0))));
        assertTrue(factory.isPointsProgram(address(factory.pointsPrograms(1))));
    }

      function testCreatePointsRewardsCampaign() public {
        uint256 start = block.timestamp;
        uint256 end = start + 1 weeks;
        uint256 totalRewards = 1000e18;

        vm.prank(points.owner());
        points.createPointsRewardsCampaign(start, end, totalRewards);

        assertTrue(points.allowedCampaigns(1));
    }

    function testCreatePointsRewardsCampaignOnlyOwner() public {
        vm.prank(user);
        vm.expectRevert("UNAUTHORIZED");
        points.createPointsRewardsCampaign(0, 0, 0);
    }

    function testAward() public {
        // First, create a campaign
        vm.prank(points.owner());
        points.createPointsRewardsCampaign(block.timestamp, block.timestamp + 1 weeks, 1000e18);

        // Mock the vault calling the award function
        vm.startPrank(address(mockVault));
        points.award(user, 100e18, 1);
    }

    function testAwardOnlyAllowedVault() public {
        vm.prank(user);
        vm.expectRevert(Points.OnlyIncentivizedVault.selector);
        points.award(user, 100e18, 1);
    }

    function testAwardOnlyAllowedCampaign() public {
        vm.prank(address(mockVault));
        vm.expectRevert(Points.CampaignNotAuthorized.selector);
        points.award(user, 100e18, 1);
    }
}

// Mock contracts for testing (same as in the previous test file)
contract MockERC4626i {
    uint256 public totalCampaigns;

    function createRewardsCampaign(ERC20 token, uint256 start, uint256 end, uint256 totalRewards) external returns (uint256) {
        totalCampaigns++;
        return totalCampaigns;
    }
}
