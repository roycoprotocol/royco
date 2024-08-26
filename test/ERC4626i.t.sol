// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import {MockERC20} from "test/mocks/MockERC20.sol";
import {MockERC4626} from "test/mocks/MockERC4626.sol";

import {ERC20} from "lib/solmate/src/tokens/ERC20.sol";
import {ERC4626} from "lib/solmate/src/tokens/ERC4626.sol";

import {ERC4626i} from "src/ERC4626i.sol";
import {ERC4626iFactory} from "src/ERC4626iFactory.sol";

import { PointsFactory } from "src/PointsFactory.sol";

import {Test} from "forge-std/Test.sol";

contract ERC4626iTest is Test {
    ERC20 token = ERC20(address(new MockERC20("Mock Token", "MOCK")));
    ERC4626 testVault = ERC4626(address(new MockERC4626(token)));
    ERC4626i testIncentivizedVault;

    PointsFactory pointsFactory = new PointsFactory();

    ERC4626iFactory testFactory;

    uint256 constant WAD = 1e18;

    uint256 constant DEFAULT_REFERRAL_FEE = 0.05e18;
    uint256 constant DEFAULT_PROTOCOL_FEE = 0.05e18;

    address public constant REGULAR_USER = address(0xbeef);
    address public constant REFERRAL_USER = address(0x33f123);


    function setUp() public {
        testFactory = new ERC4626iFactory(0.05e18, 0.05e18, address(pointsFactory));
    }

    function testConstructor(uint128 initialProtocolFee, uint128 initialReferralFee) public {
        ERC4626iFactory newTestFactory = new ERC4626iFactory(initialProtocolFee, initialReferralFee, address(0));

        assertEq(newTestFactory.defaultProtocolFee(), initialProtocolFee);
        assertEq(newTestFactory.defaultReferralFee(), initialReferralFee);
    }

    function testFactoryDeploysPair() public {
        ERC4626i iVault = testFactory.createIncentivizedVault(testVault);

        uint32 size;
        assembly {
            size := extcodesize(iVault)
        }

        assertGt(size, 0);
        assertEq(iVault.referralFee(), DEFAULT_REFERRAL_FEE);
        assertEq(iVault.protocolFee(), DEFAULT_PROTOCOL_FEE);

        vm.expectRevert(ERC4626iFactory.VaultAlreadyDeployed.selector);
        testFactory.createIncentivizedVault(testVault);
    }

    function testUpdateAPairsFee(uint128 newReferralFee, uint128 newProtocolFee) public {
        ERC4626i iVault = testFactory.createIncentivizedVault(testVault);

        vm.startPrank(REGULAR_USER);
        vm.expectRevert("UNAUTHORIZED");
        testFactory.updateReferralFee(testVault, newReferralFee);
        vm.expectRevert("UNAUTHORIZED");
        testFactory.updateProtocolFee(testVault, newProtocolFee);
        vm.stopPrank();

        vm.expectRevert(ERC4626iFactory.VaultNotDeployed.selector);
        testFactory.updateReferralFee(ERC4626(address(iVault)), newReferralFee);
        vm.expectRevert(ERC4626iFactory.VaultNotDeployed.selector);
        testFactory.updateProtocolFee(ERC4626(address(iVault)), newProtocolFee);

        if (newReferralFee > WAD) {
            vm.expectRevert(ERC4626i.FeeSetTooHigh.selector);
            testFactory.updateReferralFee(testVault, newReferralFee);
        } else {
            testFactory.updateReferralFee(testVault, newReferralFee);
            assertEq(iVault.referralFee(), newReferralFee);
        }

        if (newProtocolFee > WAD) {
            vm.expectRevert(ERC4626i.FeeSetTooHigh.selector);
            testFactory.updateProtocolFee(testVault, newProtocolFee);
        } else {
            testFactory.updateProtocolFee(testVault, newProtocolFee);
            assertEq(iVault.protocolFee(), newProtocolFee);
        }
    }

    function testCanCreateRewardsCampaign(uint96 _incentiveAmount) public {
      vm.assume(_incentiveAmount > 0);
      uint256 incentiveAmount = uint256(_incentiveAmount);
      ERC4626i iVault = testFactory.createIncentivizedVault(testVault);
    
      MockERC20 testMockToken = new MockERC20("Reward Token", "REWARD");

      testMockToken.mint(address(this), incentiveAmount);
      testMockToken.approve(address(iVault), incentiveAmount);

      uint256 startTime = block.timestamp;

      uint256 initialTokenBalance = testMockToken.balanceOf(address(this));

      uint256 campaignId = iVault.createRewardsCampaign(testMockToken, startTime, startTime + 100 days, incentiveAmount);
      assertEq(testMockToken.balanceOf(address(this)), initialTokenBalance - incentiveAmount);

      (uint32 start, uint32 end, uint96 rate, , , , ) = iVault.campaignIdToData(campaignId);

      assertEq(startTime, start);
      assertEq(end, startTime + 100 days);

      uint256 referralFeeAmount = incentiveAmount * uint256(iVault.referralFee()) / WAD;
      uint256 protocolFeeAmount = incentiveAmount * uint256(iVault.protocolFee()) / WAD;

      incentiveAmount -= referralFeeAmount;
      incentiveAmount -= protocolFeeAmount;

      assertEq(uint256(incentiveAmount) / (end - start), rate);
    }

    function testOptIntoCampaign() public {
      ERC4626i campaign = testFactory.createIncentivizedVault(testVault);
      vm.startPrank(REGULAR_USER);

      // Test opting into a campaign
      campaign.optIntoCampaign(1, address(0));
      assertEq(campaign.userSelectedCampaigns(REGULAR_USER, 0), 1);
      assertEq(campaign.referralsPerUser(1, REGULAR_USER), address(0));

      // Test opting into multiple campaigns
      campaign.optIntoCampaign(2, REFERRAL_USER);
      assertEq(campaign.userSelectedCampaigns(REGULAR_USER, 1), 2);
      assertEq(campaign.referralsPerUser(2, REGULAR_USER), REFERRAL_USER);

      // Test maximum campaigns limit
      campaign.optIntoCampaign(3, address(0));
      campaign.optIntoCampaign(4, address(0));
      campaign.optIntoCampaign(5, address(0));

      vm.expectRevert(ERC4626i.MaxCampaignsOptedInto.selector);
      campaign.optIntoCampaign(6, address(0));

      vm.stopPrank();
    }

    function testOptOutOfLastCampaign() public {
      ERC4626i iVault = testFactory.createIncentivizedVault(testVault);
      vm.startPrank(REGULAR_USER);

      // Setup: Opt into 5 campaigns
      for (uint256 i = 1; i <= 5; i++) {
        iVault.optIntoCampaign(i, REFERRAL_USER);
      }

      // Test opting out of the last campaign (index 4)
      iVault.optOutOfCampaign(5, 4);
      assertEq(iVault.userSelectedCampaigns(REGULAR_USER, 4), 0);

      // Verify that other campaigns are still intact
      for (uint256 i = 0; i < 4; i++) {
        assertEq(iVault.userSelectedCampaigns(REGULAR_USER, i), i + 1);
      }

      vm.stopPrank();
    }

    function testBasicRewardsCampaign(uint96 _incentiveAmount, uint112 depositAmount, uint16 _duration) public {
      vm.assume(_incentiveAmount > 0.0001 ether);
      vm.assume(depositAmount > 0.0001 ether);

      uint256 duration;
      uint256 incentiveAmount = uint256(_incentiveAmount);

      if (_duration < 7 days) {
        duration = 7 days + 1;
      } else {
        duration = uint256(_duration);
      }

      ERC4626i iVault = testFactory.createIncentivizedVault(testVault);

      MockERC20 testMockToken = new MockERC20("Reward Token", "REWARD");
      testMockToken.mint(address(this), incentiveAmount);
      testMockToken.approve(address(iVault), incentiveAmount);

      uint256 startTime = block.timestamp;
      
      uint256 campaignId = iVault.createRewardsCampaign(testMockToken, startTime, startTime + duration, incentiveAmount);
   
      vm.startPrank(REGULAR_USER);

      MockERC20(address(token)).mint(REGULAR_USER, depositAmount);
      token.approve(address(iVault), depositAmount);
      iVault.deposit(depositAmount, REGULAR_USER);

      iVault.optIntoCampaign(campaignId, REFERRAL_USER);

      iVault.claim(campaignId, REGULAR_USER);

      vm.warp(block.timestamp + startTime + duration);
      
      uint256 claimed = iVault.claim(campaignId, REGULAR_USER);
      assertEq(testMockToken.balanceOf(REGULAR_USER), claimed);
      assertGt(claimed, 0);
  }

  function createTestCampaign(uint256 incentiveAmount, uint256 depositAmount, uint256 duration) public returns (uint256 campaignId, ERC4626i iVault) {
      iVault = testFactory.createIncentivizedVault(testVault);

      MockERC20 testMockToken = new MockERC20("Reward Token", "REWARD");
      testMockToken.mint(address(this), incentiveAmount);
      testMockToken.approve(address(iVault), incentiveAmount);

      uint256 startTime = block.timestamp;
      
      campaignId = iVault.createRewardsCampaign(testMockToken, startTime, startTime + duration, incentiveAmount);
      
      vm.startPrank(REGULAR_USER);

      MockERC20(address(token)).mint(REGULAR_USER, depositAmount);
      token.approve(address(iVault), depositAmount);
      iVault.deposit(depositAmount, REGULAR_USER);

      iVault.optIntoCampaign(campaignId, REFERRAL_USER);

      vm.stopPrank();
  }

  function testPoolUpdate(uint96 _incentiveAmount, uint112 depositAmount, uint16 _duration) public {
      vm.assume(_incentiveAmount > 0.0001 ether);
      vm.assume(depositAmount > 0.0001 ether);

      uint256 duration;
      uint256 incentiveAmount = uint256(_incentiveAmount);

      if (_duration < 7 days) {
        duration = 7 days + 1;
      } else {
        duration = uint256(_duration);
      }

      (uint256 campaignId, ERC4626i iVault) = createTestCampaign(incentiveAmount, depositAmount, duration);
     
      (, , , , , uint256 accumulated, uint64 lastUpdated) = iVault.campaignIdToData(campaignId);

      vm.warp(duration / 3);
      iVault.updateRewardCampaign(campaignId);
  
      (, , , , , uint256 newAcc, uint64 mostRecentUpdate) = iVault.campaignIdToData(campaignId);

      assertGt(newAcc, accumulated);
      assertGt(mostRecentUpdate, lastUpdated);
  }

  function testRetroactiveOptIn(uint96 _incentiveAmount, uint112 depositAmount, uint16 _duration) public {
      vm.assume(_incentiveAmount > 0.0001 ether);
      vm.assume(depositAmount > 0.0001 ether);

      uint256 duration;
      uint256 incentiveAmount = uint256(_incentiveAmount);

      if (_duration < 7 days) {
        duration = 7 days + 1;
      } else {
        duration = uint256(_duration);
      }
      
      ERC4626i iVault = testFactory.createIncentivizedVault(testVault);

      MockERC20 testMockToken = new MockERC20("Reward Token", "REWARD");
      testMockToken.mint(address(this), incentiveAmount);
      testMockToken.approve(address(iVault), incentiveAmount);

      uint256 startTime = block.timestamp;
      
      uint256 campaignId = iVault.createRewardsCampaign(testMockToken, startTime, startTime + duration, incentiveAmount);
      
      vm.startPrank(REGULAR_USER);

      MockERC20(address(token)).mint(REGULAR_USER, depositAmount);
      token.approve(address(iVault), depositAmount);
      iVault.deposit(depositAmount, REGULAR_USER);

      vm.warp(duration / 2);
      iVault.updateRewardCampaign(campaignId);

      iVault.optIntoCampaign(campaignId, REFERRAL_USER);

      (uint256 accumulated, , ) = iVault.campaignToUserRewards(campaignId, REGULAR_USER);
      iVault.updateUserRewards(campaignId, REGULAR_USER);
      (uint256 newAccumulated, , ) = iVault.campaignToUserRewards(campaignId, REGULAR_USER);
  
      assertGt(newAccumulated, accumulated);
  }
}
