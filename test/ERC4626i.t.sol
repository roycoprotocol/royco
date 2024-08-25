// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import {MockERC20} from "test/mocks/MockERC20.sol";
import {MockERC4626} from "test/mocks/MockERC4626.sol";

import {ERC20} from "lib/solmate/src/tokens/ERC20.sol";
import {ERC4626} from "lib/solmate/src/tokens/ERC4626.sol";

import {ERC4626i} from "src/ERC4626i.sol";
import {ERC4626iFactory} from "src/ERC4626iFactory.sol";

import {Test} from "forge-std/Test.sol";

contract ERC4626iTest is Test {
    ERC20 token = ERC20(address(new MockERC20("Mock Token", "MOCK")));
    ERC4626 testVault = ERC4626(address(new MockERC4626(token)));
    ERC4626i testIncentivizedVault;

    ERC4626iFactory testFactory;

    uint256 constant WAD = 1e18;

    uint256 constant DEFAULT_REFERRAL_FEE = 0.05e18;
    uint256 constant DEFAULT_PROTOCOL_FEE = 0.05e18;

    address public constant REGULAR_USER = address(0xbeef);

    function setUp() public {
        testFactory = new ERC4626iFactory(0.05e18, 0.05e18);
    }

    function testConstructor(uint128 initialProtocolFee, uint128 initialReferralFee) public {
        ERC4626iFactory newTestFactory = new ERC4626iFactory(initialProtocolFee, initialReferralFee);

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

    function testCanCreateRewardsCampaign(uint96 incentiveAmount) public {
      vm.assume(incentiveAmount > 0);
      ERC4626i iVault = testFactory.createIncentivizedVault(testVault);
    
      MockERC20 testMockToken = new MockERC20("Reward Token", "REWARD");

      testMockToken.mint(address(this), incentiveAmount);
      testMockToken.approve(address(iVault), incentiveAmount);

      uint256 startTime = block.timestamp;

      uint256 campaignId = iVault.createRewardsCampaign(testMockToken, startTime, startTime + 100 days, incentiveAmount);
      (uint32 start, uint32 end, uint96 rate, , ) = iVault.tokenToRewardsInterval(campaignId);

      assertEq(startTime, start);
      assertEq(end, startTime + 100 days);

      //assertEq(uint256(incentiveAmount) / (end - start), rate);
    }
}
