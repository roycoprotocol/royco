// SPDX-Liense-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import { MockERC20 } from "test/mocks/MockERC20.sol";
import { MockERC4626 } from "test/mocks/MockERC4626.sol";

import { ERC20 } from "lib/solmate/src/tokens/ERC20.sol";
import { ERC4626 } from "lib/solmate/src/tokens/ERC4626.sol";

import { WrappedVault } from "src/WrappedVault.sol";
import { WrappedVaultFactory } from "src/WrappedVaultFactory.sol";

import { FixedPointMathLib } from "lib/solmate/src/utils/FixedPointMathLib.sol";
import { Owned } from "lib/solmate/src/auth/Owned.sol";

import { PointsFactory } from "src/PointsFactory.sol";

import { Test, console } from "forge-std/Test.sol";

contract WrappedVaultTest is Test {
    using FixedPointMathLib for *;

    ERC20 token = ERC20(address(new MockERC20("Mock Token", "MOCK")));
    ERC4626 testVault = ERC4626(address(new MockERC4626(token)));
    WrappedVault testIncentivizedVault;

    PointsFactory pointsFactory = new PointsFactory(POINTS_FACTORY_OWNER);
    WrappedVaultFactory testFactory;
    uint256 constant WAD = 1e18;

    uint256 constant DEFAULT_REFERRAL_FEE = 0.025e18;
    uint256 constant DEFAULT_FRONTEND_FEE = 0.025e18;
    uint256 constant DEFAULT_PROTOCOL_FEE = 0.05e18;

    address constant DEFAULT_FEE_RECIPIENT = address(0xdead);

    address public constant POINTS_FACTORY_OWNER = address(0x1);
    address public constant REGULAR_USER = address(0xbeef);
    address public constant REFERRAL_USER = address(0x33f123);

    MockERC20 rewardToken1;
    MockERC20 rewardToken2;

    function setUp() public {
        testFactory = new WrappedVaultFactory(DEFAULT_FEE_RECIPIENT, DEFAULT_PROTOCOL_FEE, DEFAULT_FRONTEND_FEE, address(this), address(pointsFactory));
        testIncentivizedVault = testFactory.wrapVault(testVault, address(this), "Incentivized Vault", DEFAULT_FRONTEND_FEE);

        rewardToken1 = new MockERC20("Reward Token 1", "RWD1");
        rewardToken2 = new MockERC20("Reward Token 2", "RWD2");

        vm.label(address(testIncentivizedVault), "IncentivizedVault");
        vm.label(address(rewardToken1), "RewardToken1");
        vm.label(address(rewardToken2), "RewardToken2");
        vm.label(REGULAR_USER, "RegularUser");
        vm.label(REFERRAL_USER, "ReferralUser");
    }

    function testFactoryUpdateProtocolFees() public {
        vm.startPrank(address(0x8482));
        vm.expectRevert("UNAUTHORIZED");
        testFactory.updateProtocolFee(0.01e18);
        vm.stopPrank();

        vm.startPrank(testFactory.owner());
        uint256 maxProtocolFee = /*testFactory.MAX_PROTOCOL_FEE()*/ 0.3e18;
        vm.expectRevert(WrappedVaultFactory.ProtocolFeeTooHigh.selector);
        testFactory.updateProtocolFee(maxProtocolFee + 1);

        testFactory.updateProtocolFee(0.075e18);
        assertEq(testFactory.protocolFee(), 0.075e18);
    }

    function testFactoryUpdateReferralFee() public {
        vm.startPrank(address(0x8482));
        vm.expectRevert("UNAUTHORIZED");
        testFactory.updateMinimumReferralFee(0.01e18);
        vm.stopPrank();

        vm.startPrank(testFactory.owner());
        uint256 maxMinFee = /*testFactory.MAX_MIN_REFERRAL_FEE()*/ 0.3e18;
        vm.expectRevert(WrappedVaultFactory.ReferralFeeTooHigh.selector);
        testFactory.updateMinimumReferralFee(maxMinFee + 1);

        testFactory.updateMinimumReferralFee(0.075e18);
        assertEq(testFactory.minimumFrontendFee(), 0.075e18);
    }

    function testDeployment() public view {
        assertEq(address(testIncentivizedVault.VAULT()), address(testVault));
        assertEq(address(testIncentivizedVault.asset()), address(token));
        assertEq(testIncentivizedVault.owner(), address(this));
        assertEq(testIncentivizedVault.frontendFee(), DEFAULT_FRONTEND_FEE);
    }

    function testVaultPassThroughFunctions() public {
        testIncentivizedVault = testFactory.wrapVault(testVault, address(this), "Incentivized Vault", DEFAULT_FRONTEND_FEE);

        assertEq(address(testIncentivizedVault.asset()), address(testVault.asset()));
        assertEq(testIncentivizedVault.maxDeposit(address(this)), testVault.maxDeposit(address(this)));
        assertEq(testIncentivizedVault.maxMint(address(this)), testVault.maxMint(address(this)));
        assertEq(testIncentivizedVault.previewMint(100e18), testVault.previewMint(100e18));
        assertEq(testIncentivizedVault.previewDeposit(100e18), testVault.previewDeposit(100e18));

        assertEq(testIncentivizedVault.convertToShares(100e18), testVault.convertToShares(100e18));
        assertEq(testIncentivizedVault.convertToAssets(100e18), testVault.convertToAssets(100e18));
    }

    function testAddRewardToken(address newRewardToken) public {
        vm.assume(newRewardToken != address(0));
        vm.assume(newRewardToken != address(testIncentivizedVault.VAULT()));
        vm.assume(newRewardToken != address(testIncentivizedVault));

        testIncentivizedVault.addRewardsToken(newRewardToken);
        assertEq(testIncentivizedVault.rewards(0), newRewardToken);

        // Test we cannot add the second reward token twice
        vm.expectRevert(WrappedVault.DuplicateRewardToken.selector);
        testIncentivizedVault.addRewardsToken(newRewardToken);
    }

    function testAddRewardTokenUnauthorized(address unauthorized) public {
        vm.assume(unauthorized != address(this));
        vm.expectRevert("UNAUTHORIZED");
        vm.prank(unauthorized);
        testIncentivizedVault.addRewardsToken(address(rewardToken1));
    }

    function testAddRewardTokenMaxReached() public {
        for (uint256 i = 0; i < 20 /*testIncentivizedVault.MAX_REWARDS()*/; i++) {
            testIncentivizedVault.addRewardsToken(address(new MockERC20("", "")));
        }

        address mockToken = address(new MockERC20("", ""));
        vm.expectRevert(WrappedVault.MaxRewardsReached.selector);
        testIncentivizedVault.addRewardsToken(mockToken);
    }

    function testSetFrontendFee(uint256 newFee) public {
        vm.assume(newFee >= testFactory.minimumFrontendFee() && newFee <= WAD);
        testIncentivizedVault.setFrontendFee(newFee);
        assertEq(testIncentivizedVault.frontendFee(), newFee);
    }

    function testSetFrontendFeeBelowMinimum(uint256 newFee) public {
        vm.assume(newFee < testFactory.minimumFrontendFee());
        vm.expectRevert(WrappedVault.FrontendFeeBelowMinimum.selector);
        testIncentivizedVault.setFrontendFee(newFee);
    }

    function testSetRewardsInterval(uint32 start, uint32 duration, uint256 totalRewards) public {
        vm.assume(duration >= /*testIncentivizedVault.MIN_CAMPAIGN_DURATION_OR_EXTENSION()*/1 weeks);
        vm.assume(duration <= type(uint32).max - start); //If this is not here, then 'end' variable will overflow
        vm.assume(totalRewards > 0 && totalRewards < type(uint96).max);
        vm.assume(totalRewards / duration > 1e6);

        uint32 end = start + duration;
        testIncentivizedVault.addRewardsToken(address(rewardToken1));

        rewardToken1.mint(address(this), totalRewards);
        rewardToken1.approve(address(testIncentivizedVault), totalRewards);
        testIncentivizedVault.setRewardsInterval(address(rewardToken1), start, end, totalRewards, DEFAULT_FEE_RECIPIENT);

        uint256 frontendFee = totalRewards.mulWadDown(testIncentivizedVault.frontendFee());
        uint256 protocolFee = totalRewards.mulWadDown(testFactory.protocolFee());
        totalRewards -= frontendFee + protocolFee;

        (uint32 actualStart, uint32 actualEnd, uint96 actualRate) = testIncentivizedVault.rewardToInterval(address(rewardToken1));

        assertEq(actualStart, start);
        assertEq(actualEnd, end);
        assertEq(actualRate, totalRewards / duration);
    }

    function testExtendRewardsInterval(uint256 start, uint256 initialDuration, uint256 extension, uint256 initialRewards, uint256 additionalRewards) public {
        // Bound start to uint32 range
        start = bound(start, 0, type(uint32).max);

        // Calculate the remaining space in uint32 after accounting for start
        uint256 remainingSpace = type(uint32).max - start;

        // Get the minimum campaign duration
        uint256 minCampaignDuration = /*testIncentivizedVault.MIN_CAMPAIGN_DURATION_OR_EXTENSION()*/ 1 weeks;

        // Ensure there is enough remaining space for the initial duration
        if (remainingSpace < minCampaignDuration) {
            return;
        }

        // Bound initialDuration between minCampaignDuration and remainingSpace
        initialDuration = bound(initialDuration, minCampaignDuration, remainingSpace);

        // Calculate initialEnd and ensure it doesn't overflow
        uint256 initialEnd = start + initialDuration;

        // Calculate the remaining space after initialEnd
        uint256 remainingSpaceAfterInitialEnd = type(uint32).max - initialEnd;

        // Ensure there is enough remaining space for the extension
        if (remainingSpaceAfterInitialEnd < 1 days + 1) {
            return;
        }

        // Bound extension between 1 day + 1 and the remaining space after initialEnd
        extension = bound(extension, 1 days + 1, remainingSpaceAfterInitialEnd);

        // Calculate newEnd and ensure it doesn't overflow
        uint256 newEnd = initialEnd + extension;

        // Ensure that start, initialEnd, and newEnd fit within uint32
        if (start > type(uint32).max || initialEnd > type(uint32).max || newEnd > type(uint32).max) {
            return;
        }

        // Cast to uint32 after ensuring values are within uint32 range
        uint32 _start = uint32(start);
        uint32 _initialEnd = uint32(initialEnd);
        uint32 _newEnd = uint32(newEnd);

        // Ensure initialRewards is within specified bounds and satisfies the rate condition
        uint256 minInitialRewards = (initialDuration * 1e6) + 1;
        uint256 maxInitialRewards = type(uint96).max - 1;

        if (maxInitialRewards < minInitialRewards) {
            return; // Cannot proceed if maxInitialRewards is less than minInitialRewards
        }

        initialRewards = bound(initialRewards, minInitialRewards, maxInitialRewards);

        // Ensure additionalRewards is within specified bounds
        uint256 minAdditionalRewards = 1e6 + 1;
        uint256 maxAdditionalRewards = type(uint96).max - 1;

        if (maxAdditionalRewards < minAdditionalRewards) {
            return; // Cannot proceed if maxAdditionalRewards is less than minAdditionalRewards
        }

        additionalRewards = bound(additionalRewards, minAdditionalRewards, maxAdditionalRewards);

        // Ensure initialRewards / initialDuration > 1e6
        if (initialRewards / initialDuration <= 1e6) {
            // Adjust initialRewards to satisfy the condition
            initialRewards = (initialDuration * 1e6) + 1e18;
        }

        // Adjust additionalRewards if the rate condition is not met
        if (additionalRewards / extension <= initialRewards / initialDuration) {
            additionalRewards = ((initialRewards / initialDuration) * extension) + 1e18;
        }

        testIncentivizedVault.addRewardsToken(address(rewardToken1));

        rewardToken1.mint(address(this), initialRewards + additionalRewards);
        rewardToken1.approve(address(testIncentivizedVault), initialRewards + additionalRewards);

        testIncentivizedVault.setRewardsInterval(address(rewardToken1), _start, _initialEnd, initialRewards, DEFAULT_FEE_RECIPIENT);

        uint256 frontendFee = initialRewards.mulWadDown(testIncentivizedVault.frontendFee());
        uint256 protocolFee = initialRewards.mulWadDown(testFactory.protocolFee());
        initialRewards -= frontendFee + protocolFee;

        vm.warp(start + (initialDuration / 2)); // Warp to middle of interval

        // Ensure the new campaign duration meets the minimum requirement
        if (newEnd - block.timestamp < minCampaignDuration) {
            return;
        }

        testIncentivizedVault.extendRewardsInterval(address(rewardToken1), additionalRewards, _newEnd, address(this));

        frontendFee = additionalRewards.mulWadDown(testIncentivizedVault.frontendFee());
        protocolFee = additionalRewards.mulWadDown(testFactory.protocolFee());
        additionalRewards -= frontendFee + protocolFee;

        (uint32 actualStart, uint32 actualEnd, uint96 actualRate) = testIncentivizedVault.rewardToInterval(address(rewardToken1));
        assertEq(actualStart, block.timestamp);
        assertEq(actualEnd, _newEnd);

        uint256 remainingInitialRewards = (initialRewards / initialDuration) * (_initialEnd - block.timestamp);
        uint256 expectedRate = (remainingInitialRewards + additionalRewards) / (_newEnd - block.timestamp);
        assertEq(actualRate, expectedRate);
    }

    function testDeposit(uint256 amount) public {
        vm.assume(amount > 0 && amount <= type(uint96).max);
        MockERC20(address(token)).mint(REGULAR_USER, amount);

        vm.startPrank(REGULAR_USER);
        token.approve(address(testIncentivizedVault), amount);
        uint256 shares = testIncentivizedVault.deposit(amount, REGULAR_USER);
        vm.stopPrank();

        assertEq(testIncentivizedVault.balanceOf(REGULAR_USER), shares);
        assertEq(testIncentivizedVault.totalAssets(), amount);
    }

    function testRefundInterval(uint32 start, uint32 duration, uint256 totalRewards) public {
        if (start < block.timestamp + 10_000) {
            start = uint32(block.timestamp + 10_000);
        }

        vm.assume(duration >= /*testIncentivizedVault.MIN_CAMPAIGN_DURATION_OR_EXTENSION()*/ 1 weeks);
        vm.assume(duration <= type(uint32).max - start); //If this is not here, then 'end' variable will overflow
        vm.assume(totalRewards > 0 && totalRewards < type(uint96).max);
        vm.assume(totalRewards / duration > 1e6);

        uint32 end = start + duration;
        testIncentivizedVault.addRewardsToken(address(rewardToken1));

        rewardToken1.mint(address(this), totalRewards);
        rewardToken1.approve(address(testIncentivizedVault), totalRewards);
        testIncentivizedVault.setRewardsInterval(address(rewardToken1), start, end, totalRewards, DEFAULT_FEE_RECIPIENT);

        vm.startPrank(REGULAR_USER);
        vm.expectRevert("UNAUTHORIZED");
        testIncentivizedVault.refundRewardsInterval(address(rewardToken1));
        vm.stopPrank();

        uint256 initialBalance = rewardToken1.balanceOf(address(this));

        testIncentivizedVault.refundRewardsInterval(address(rewardToken1));
    }

    function testWithdraw(uint256 depositAmount, uint256 withdrawAmount) public {
        vm.assume(depositAmount > 0 && depositAmount <= type(uint96).max);
        vm.assume(withdrawAmount > 0 && withdrawAmount <= depositAmount);

        MockERC20(address(token)).mint(REGULAR_USER, depositAmount);

        vm.startPrank(REGULAR_USER);
        token.approve(address(testIncentivizedVault), depositAmount);
        testIncentivizedVault.deposit(depositAmount, REGULAR_USER);

        testIncentivizedVault.withdraw(withdrawAmount, REGULAR_USER, REGULAR_USER);
        vm.stopPrank();

        assertEq(token.balanceOf(REGULAR_USER), withdrawAmount);
        assertEq(testIncentivizedVault.totalAssets(), depositAmount - withdrawAmount);
    }

    function testRewardsAccrual(uint256 depositAmount, uint32 timeElapsed) public {
        vm.assume(depositAmount > 1e6 && depositAmount <= type(uint96).max);
        vm.assume(timeElapsed > 7 days && timeElapsed <= 30 days);

        uint256 rewardAmount = 1000 * WAD;
        uint32 start = uint32(block.timestamp);
        uint32 duration = 30 days;

        testIncentivizedVault.addRewardsToken(address(rewardToken1));
        rewardToken1.mint(address(this), rewardAmount);
        rewardToken1.approve(address(testIncentivizedVault), rewardAmount);
        testIncentivizedVault.setRewardsInterval(address(rewardToken1), start, start + duration, rewardAmount, DEFAULT_FEE_RECIPIENT);

        uint256 frontendFee = rewardAmount.mulWadDown(testIncentivizedVault.frontendFee());
        uint256 protocolFee = rewardAmount.mulWadDown(testFactory.protocolFee());
        rewardAmount -= frontendFee + protocolFee;

        MockERC20(address(token)).mint(REGULAR_USER, depositAmount);

        vm.startPrank(REGULAR_USER);
        token.approve(address(testIncentivizedVault), depositAmount);
        uint256 shares = testIncentivizedVault.deposit(depositAmount, REGULAR_USER);
        vm.stopPrank();

        vm.warp(start + timeElapsed);

        uint256 expectedRewards = (rewardAmount * timeElapsed) * shares / testIncentivizedVault.totalSupply() / duration;
        uint256 actualRewards = testIncentivizedVault.currentUserRewards(address(rewardToken1), REGULAR_USER);

        assertApproxEqRel(actualRewards, expectedRewards, 1e15); // Allow 0.1% deviation
    }

    function testClaim(uint96 _depositAmount, uint32 timeElapsed) public {
        uint256 depositAmount = _depositAmount;

        vm.assume(depositAmount > 1e6);
        vm.assume(depositAmount <= type(uint96).max);
        vm.assume(timeElapsed > 1e6);
        vm.assume(timeElapsed <= 30 days);

        uint256 rewardAmount = 1000 * WAD;
        uint32 start = uint32(block.timestamp);
        uint32 duration = 30 days;

        testIncentivizedVault.addRewardsToken(address(rewardToken1));
        rewardToken1.mint(address(this), rewardAmount);
        rewardToken1.approve(address(testIncentivizedVault), rewardAmount);
        testIncentivizedVault.setRewardsInterval(address(rewardToken1), start, start + duration, rewardAmount, DEFAULT_FEE_RECIPIENT);

        uint256 frontendFee = rewardAmount.mulWadDown(testIncentivizedVault.frontendFee());
        uint256 protocolFee = rewardAmount.mulWadDown(testFactory.protocolFee());

        rewardAmount -= frontendFee + protocolFee;

        MockERC20(address(token)).mint(REGULAR_USER, depositAmount);

        vm.startPrank(REGULAR_USER);
        token.approve(address(testIncentivizedVault), depositAmount);
        uint256 shares = testIncentivizedVault.deposit(depositAmount, REGULAR_USER);
        vm.warp(timeElapsed);

        uint256 expectedRewards = (rewardAmount / duration) * shares / testIncentivizedVault.totalSupply() * timeElapsed;
        testIncentivizedVault.rewardToInterval(address(rewardToken1));

        testIncentivizedVault.claim(REGULAR_USER);
        vm.stopPrank();

        assertApproxEqRel(rewardToken1.balanceOf(REGULAR_USER), expectedRewards, 2e15); // Allow 0.2% deviation
    }

    function testMultipleRewardTokens(uint256 depositAmount, uint32 timeElapsed) public {
        vm.assume(depositAmount > 1e6 && depositAmount <= type(uint96).max);
        vm.assume(timeElapsed > 1e6 && timeElapsed <= 30 days);

        uint256 rewardAmount1 = 1000 * WAD;
        uint256 rewardAmount2 = 500 * WAD;
        uint32 start = uint32(block.timestamp);
        uint32 duration = 30 days;

        testIncentivizedVault.addRewardsToken(address(rewardToken1));
        testIncentivizedVault.addRewardsToken(address(rewardToken2));

        rewardToken1.mint(address(this), rewardAmount1);
        rewardToken2.mint(address(this), rewardAmount2);
        rewardToken1.approve(address(testIncentivizedVault), rewardAmount1);
        rewardToken2.approve(address(testIncentivizedVault), rewardAmount2);

        testIncentivizedVault.setRewardsInterval(address(rewardToken1), start, start + duration, rewardAmount1, DEFAULT_FEE_RECIPIENT);
        testIncentivizedVault.setRewardsInterval(address(rewardToken2), start, start + duration, rewardAmount2, DEFAULT_FEE_RECIPIENT);

        uint256 frontendFee = rewardAmount1.mulWadDown(testIncentivizedVault.frontendFee());
        uint256 protocolFee = rewardAmount1.mulWadDown(testFactory.protocolFee());
        rewardAmount1 -= frontendFee + protocolFee;

        frontendFee = rewardAmount2.mulWadDown(testIncentivizedVault.frontendFee());
        protocolFee = rewardAmount2.mulWadDown(testFactory.protocolFee());
        rewardAmount2 -= frontendFee + protocolFee;

        MockERC20(address(token)).mint(REGULAR_USER, depositAmount);

        vm.startPrank(REGULAR_USER);
        token.approve(address(testIncentivizedVault), depositAmount);
        uint256 shares = testIncentivizedVault.deposit(depositAmount, REGULAR_USER);
        vm.warp(start + timeElapsed);

        testIncentivizedVault.claim(REGULAR_USER);
        vm.stopPrank();

        uint256 expectedRewards1 = (rewardAmount1 / duration) * shares / testIncentivizedVault.totalSupply() * timeElapsed;
        uint256 expectedRewards2 = (rewardAmount2 / duration) * shares / testIncentivizedVault.totalSupply() * timeElapsed;

        assertApproxEqRel(rewardToken1.balanceOf(REGULAR_USER), expectedRewards1, 1e15);
        assertApproxEqRel(rewardToken2.balanceOf(REGULAR_USER), expectedRewards2, 1e15);
    }

    function testRewardsAfterWithdraw(uint256 depositAmount, uint32 timeElapsed, uint256 withdrawAmount) public {
        vm.assume(depositAmount > 1e6 && depositAmount <= type(uint96).max);
        vm.assume(timeElapsed > 0 && timeElapsed < 30 days);
        vm.assume(withdrawAmount > 0 && withdrawAmount < depositAmount);

        uint256 rewardAmount = 1000 * WAD;
        uint32 start = uint32(block.timestamp);
        uint32 duration = 30 days;

        testIncentivizedVault.addRewardsToken(address(rewardToken1));
        rewardToken1.mint(address(this), rewardAmount);
        rewardToken1.approve(address(testIncentivizedVault), rewardAmount);
        testIncentivizedVault.setRewardsInterval(address(rewardToken1), start, start + duration, rewardAmount, DEFAULT_FEE_RECIPIENT);

        uint256 frontendFee = rewardAmount.mulWadDown(testIncentivizedVault.frontendFee());
        uint256 protocolFee = rewardAmount.mulWadDown(testFactory.protocolFee());
        rewardAmount -= frontendFee + protocolFee;

        MockERC20(address(token)).mint(REGULAR_USER, depositAmount);

        vm.startPrank(REGULAR_USER);
        token.approve(address(testIncentivizedVault), depositAmount);
        uint256 shares = testIncentivizedVault.deposit(depositAmount, REGULAR_USER);
        vm.warp(start + timeElapsed);

        uint256 supply = testIncentivizedVault.totalSupply();

        testIncentivizedVault.withdraw(withdrawAmount, REGULAR_USER, REGULAR_USER);
        vm.stopPrank();

        uint256 expectedRewards = rewardAmount * timeElapsed / duration * shares / supply;
        assertApproxEqRel(testIncentivizedVault.currentUserRewards(address(rewardToken1), REGULAR_USER), expectedRewards, 5e15);
    }

    function testFeeClaiming(uint256 depositAmount, uint32 timeElapsed) public {
        vm.assume(depositAmount > 0 && depositAmount <= type(uint96).max);
        vm.assume(timeElapsed > 0 && timeElapsed <= 30 days);

        uint256 rewardAmount = 1000 * WAD;
        uint32 start = uint32(block.timestamp);
        uint32 duration = 30 days;

        address FRONTEND_FEE_RECIPIENT = address(0x08989);

        testIncentivizedVault.addRewardsToken(address(rewardToken1));
        rewardToken1.mint(address(this), rewardAmount);
        rewardToken1.approve(address(testIncentivizedVault), rewardAmount);
        testIncentivizedVault.setRewardsInterval(address(rewardToken1), start, start + duration, rewardAmount, FRONTEND_FEE_RECIPIENT);

        MockERC20(address(token)).mint(REGULAR_USER, depositAmount);

        vm.startPrank(REGULAR_USER);
        token.approve(address(testIncentivizedVault), depositAmount);
        testIncentivizedVault.deposit(depositAmount, REGULAR_USER);
        vm.warp(start + timeElapsed);
        vm.stopPrank();

        uint256 expectedFrontendFee = (rewardAmount * DEFAULT_FRONTEND_FEE) / WAD;
        uint256 expectedProtocolFee = (rewardAmount * DEFAULT_PROTOCOL_FEE) / WAD;

        vm.prank(FRONTEND_FEE_RECIPIENT);
        testIncentivizedVault.claimFees(FRONTEND_FEE_RECIPIENT);
        assertApproxEqRel(rewardToken1.balanceOf(FRONTEND_FEE_RECIPIENT), expectedFrontendFee, 1e15);

        vm.prank(DEFAULT_FEE_RECIPIENT);
        testIncentivizedVault.claimFees(DEFAULT_FEE_RECIPIENT);
        assertApproxEqRel(rewardToken1.balanceOf(DEFAULT_FEE_RECIPIENT), expectedProtocolFee, 1e15);
    }

    function testRewardsRateAfterDeposit() public {
        uint256 initialDeposit = 100e18;
        uint256 additionalDeposit = initialDeposit * 2;

        uint256 rewardAmount = 1000 * WAD;
        uint32 start = uint32(block.timestamp);
        uint32 duration = 30 days;

        testIncentivizedVault.addRewardsToken(address(rewardToken1));
        rewardToken1.mint(address(this), rewardAmount);
        rewardToken1.approve(address(testIncentivizedVault), rewardAmount);
        testIncentivizedVault.setRewardsInterval(address(rewardToken1), start, start + duration, rewardAmount, DEFAULT_FEE_RECIPIENT);

        MockERC20(address(token)).mint(REGULAR_USER, initialDeposit + additionalDeposit);

        vm.startPrank(REGULAR_USER);
        token.approve(address(testIncentivizedVault), initialDeposit + additionalDeposit);
        testIncentivizedVault.deposit(initialDeposit, REGULAR_USER);

        uint256 initialRate = testIncentivizedVault.previewRateAfterDeposit(address(rewardToken1), 1e18);
        testIncentivizedVault.deposit(additionalDeposit, REGULAR_USER);
        uint256 finalRate = testIncentivizedVault.previewRateAfterDeposit(address(rewardToken1), 1e18);

        vm.stopPrank();

        assertLt(finalRate, initialRate, "Rate should decrease after additional deposit");
    }

    function testExtremeValues(uint256 depositAmount) public {
        vm.assume(depositAmount > 1e18 && depositAmount <= type(uint96).max);

        uint256 rewardAmount = type(uint96).max;
        uint32 start = uint32(block.timestamp);
        uint32 duration = 365 days;

        testIncentivizedVault.addRewardsToken(address(rewardToken1));
        rewardToken1.mint(address(this), rewardAmount);
        rewardToken1.approve(address(testIncentivizedVault), rewardAmount);
        testIncentivizedVault.setRewardsInterval(address(rewardToken1), start, start + duration, rewardAmount, DEFAULT_FEE_RECIPIENT);

        MockERC20(address(token)).mint(REGULAR_USER, depositAmount);

        vm.startPrank(REGULAR_USER);
        token.approve(address(testIncentivizedVault), depositAmount);
        testIncentivizedVault.deposit(depositAmount, REGULAR_USER);
        vm.warp(start + duration);

        uint256 rewards = testIncentivizedVault.currentUserRewards(address(rewardToken1), REGULAR_USER);
        assertLe(rewards, rewardAmount, "Rewards should not exceed total reward amount");

        testIncentivizedVault.claim(REGULAR_USER);
        vm.stopPrank();

        assertEq(rewardToken1.balanceOf(REGULAR_USER), rewards, "User should receive all accrued rewards");
    }

    function testRewardsAccrualWithMultipleUsers(uint256[] memory deposits, uint32 timeElapsed) public {
        vm.assume(deposits.length > 1 && deposits.length <= 10);
        vm.assume(timeElapsed > 0 && timeElapsed <= 30 days);

        uint256 totalDeposit;
        for (uint256 i = 0; i < deposits.length; i++) {
            deposits[i] = bound(deposits[i], 1e7, type(uint96).max / deposits.length);
            totalDeposit += deposits[i];
        }

        uint256 rewardAmount = 1000 * WAD;
        uint32 start = uint32(block.timestamp);
        uint32 duration = 30 days;

        testIncentivizedVault.addRewardsToken(address(rewardToken1));
        rewardToken1.mint(address(this), rewardAmount);
        rewardToken1.approve(address(testIncentivizedVault), rewardAmount);
        testIncentivizedVault.setRewardsInterval(address(rewardToken1), start, start + duration, rewardAmount, DEFAULT_FEE_RECIPIENT);

        uint256 frontendFee = rewardAmount.mulWadDown(testIncentivizedVault.frontendFee());
        uint256 protocolFee = rewardAmount.mulWadDown(testFactory.protocolFee());
        rewardAmount -= frontendFee + protocolFee;

        uint256[] memory shares = new uint256[](deposits.length);

        for (uint256 i = 0; i < deposits.length; i++) {
            address user = address(uint160(i + 1));
            MockERC20(address(token)).mint(user, deposits[i]);
            vm.startPrank(user);
            token.approve(address(testIncentivizedVault), deposits[i]);
            uint256 share = testIncentivizedVault.deposit(deposits[i], user);
            shares[i] = share;
            vm.stopPrank();
        }

        vm.warp(start + timeElapsed);

        uint256 totalRewards;
        uint256 totalShares;
        for (uint256 i = 0; i < deposits.length; i++) {
            address user = address(uint160(i + 1));
            uint256 userRewards = testIncentivizedVault.currentUserRewards(address(rewardToken1), user);
            totalRewards += userRewards;
            totalShares += shares[i];

            uint256 expectedRewards = rewardAmount * timeElapsed / duration * shares[i] / testIncentivizedVault.totalSupply();
            assertApproxEqRel(userRewards, expectedRewards, 0.005e18, "Incorrect rewards for user");
        }

        assertApproxEqRel(
            totalRewards, (rewardAmount * timeElapsed) * totalShares / testIncentivizedVault.totalSupply() / duration, 1e15, "Total rewards mismatch"
        );
    }
}
