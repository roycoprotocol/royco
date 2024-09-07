// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import { ERC20 } from "lib/solmate/src/tokens/ERC20.sol";
import { SafeTransferLib } from "lib/solmate/src/utils/SafeTransferLib.sol";
import { Owned } from "lib/solmate/src/auth/Owned.sol";
import { PointsFactory } from "src/PointsFactory.sol";

/// @dev A token inheriting from ERC20Rewards will reward token holders with a rewards token.
/// The rewarded amount will be a fixed wei per second, distributed proportionally to token holders
/// by the size of their holdings.
contract ERC20Rewards is Owned, ERC20 {
    using SafeTransferLib for ERC20;
    using Cast for uint256;

    event RewardsSet(uint32 start, uint32 end, uint256 rate);
    event RewardsPerTokenUpdated(uint256 accumulated);
    event UserRewardsUpdated(address user, uint256 userRewards, uint256 paidRewardPerToken);
    event Claimed(address reward, address user, address receiver, uint256 claimed);

    error MaxRewardsReached();

    struct RewardsInterval {
        uint32 start; // Start time for the current rewardsToken schedule
        uint32 end; // End time for the current rewardsToken schedule
        uint96 rate; // Wei rewarded per second among all token holders
    }

    struct RewardsPerToken {
        uint128 accumulated; // Accumulated rewards per token for the interval, scaled up by 1e18
        uint32 lastUpdated; // Last time the rewards per token accumulator was updated
    }

    struct UserRewards {
        uint128 accumulated; // Accumulated rewards for the user until the checkpoint
        uint128 checkpoint; // RewardsPerToken the last time the user rewards were updated
    }

    // ERC20 public immutable rewardsToken;                            
    // RewardsInterval public rewardsInterval;                         // Interval in which rewards are accumulated by users
    // RewardsPerToken public rewardsPerToken;                         // Accumulator to track rewards per token
    // mapping (address => UserRewards) public accumulatedRewards;     // Rewards accumulated per user

    uint256 public constant MAX_REWARDS = 5;
    uint256 public constant MIN_CAMPAIGN_DURATION = 1 weeks;

    PointsFactory public immutable POINTS_FACTORY;

    address[] public rewards;                                                                   // Tokens or points programs used as rewards
    mapping(address => RewardsInterval) public rewardToInterval;                                // Maps a reward to its interval in which rewards are accumulated by users
    mapping(address => RewardsPerToken) public rewardToRPT;                                     // Maps a reward to its accumulator to track rewards per token
    mapping(address => mapping(address => UserRewards)) public rewardToUserToAR;                // Maps a reward to a user to their accumulated rewards

    constructor(address _owner, string memory name, string memory symbol, uint8 decimals, address pointsFactory) ERC20(name, symbol, decimals) Owned(_owner) {
        POINTS_FACTORY = PointsFactory(pointsFactory);
    }

    function addRewardsToken(address rewardsToken) public onlyOwner {
        if (rewards.length == MAX_REWARDS) revert MaxRewardsReached();
        rewards.push(rewardsToken);
    }

    function pullReward(address reward, address from, uint256 amount) internal {
        if (POINTS_FACTORY.isPointsProgram(reward)) {
            // TODO: check permissioned awarder then do nothing
        } else {
            ERC20(reward).safeTransfer(from, amount);
        }
    }

    function pushRewardAndTakeFee(address reward, address to, uint256 amount) internal {
        // TODO: take fee
        if (POINTS_FACTORY.isPointsProgram(reward)) {
            // TODO: call points.award (needs modification to points contrcact)
        } else {
            ERC20(reward).safeTransfer(to, amount);
        }
    }

    function extendRewardsInterval(uint256 totalRewardsAdded, uint256 newEnd) public onlyOwner {
        require(
            newEnd > rewardsInterval.end,
            "New end must be after the current end"
        );
        require(
            block.timestamp.u32() < rewardsInterval.end,
            "Rewards already ended"
        );
        _updateRewardsPerToken();

        uint256 remainingRewards = rewardsInterval.end < block.timestamp ? 0 : rewardsInterval.rate * (rewardsInterval.end - block.timestamp.u32());

        uint256 rate = totalRewardsAdded / (newEnd - block.timestamp);

        require(rate >= rewardsInterval.rate, "New rate must be greater than or equal to the current rate");
        
        rewardsInterval.end = newEnd.u32();
        rewardsInterval.rate = rate.u96();
    }

    /// @dev Set a rewards schedule
    function setRewardsInterval(address reward, uint256 start, uint256 end, uint256 totalRewards) external onlyOwner {
        require(start < end, "Incorrect interval");

        RewardsInterval storage rewardsInterval = rewardToInterval[reward];
        RewardsPerToken storage rewardsPerToken = rewardToRPT[reward];

        // A new rewards program can be set if one is not running
        require(block.timestamp.u32() < rewardsInterval.start || block.timestamp.u32() > rewardsInterval.end, "Rewards still ongoing");

        // Update the rewards per token so that we don't lose any rewards
        _updateRewardsPerToken(reward);

        uint256 rate = totalRewards / (end - start);
        rewardsInterval.start = start.u32();
        rewardsInterval.end = end.u32();
        rewardsInterval.rate = rate.u96();

        // If setting up a new rewards program, the rewardsPerToken.accumulated is used and built upon
        // New rewards start accumulating from the new rewards program start
        // Any unaccounted rewards from last program can still be added to the user rewards
        // Any unclaimed rewards can still be claimed
        rewardsPerToken.lastUpdated = start.u32();

        emit RewardsSet(start.u32(), end.u32(), rate);
    }

    /// @notice Update the rewards per token accumulator according to the rate, the time elapsed since the last update, and the current total staked amount.
    function _calculateRewardsPerToken(
        RewardsPerToken memory rewardsPerTokenIn,
        RewardsInterval memory rewardsInterval_
    )
        internal
        view
        returns (RewardsPerToken memory)
    {
        RewardsPerToken memory rewardsPerTokenOut = RewardsPerToken(rewardsPerTokenIn.accumulated, rewardsPerTokenIn.lastUpdated);
        uint256 totalSupply_ = totalSupply;

        // No changes if the program hasn't started
        if (block.timestamp < rewardsInterval_.start) return rewardsPerTokenOut;

        // Stop accumulating at the end of the rewards interval
        uint256 updateTime = block.timestamp < rewardsInterval_.end ? block.timestamp : rewardsInterval_.end;
        uint256 elapsed = updateTime - rewardsPerTokenIn.lastUpdated;

        // No changes if no time has passed
        if (elapsed == 0) return rewardsPerTokenOut;
        rewardsPerTokenOut.lastUpdated = updateTime.u32();

        // If there are no stakers we just change the last update time, the rewards for intervals without stakers are not accumulated
        if (totalSupply_ == 0) return rewardsPerTokenOut;

        // Calculate and update the new value of the accumulator.
        rewardsPerTokenOut.accumulated = (rewardsPerTokenIn.accumulated + 1e18 * elapsed * rewardsInterval_.rate / totalSupply_).u128(); // The rewards per
            // token are scaled up for precision
        return rewardsPerTokenOut;
    }

    /// @notice Calculate the rewards accumulated by a stake between two checkpoints.
    function _calculateUserRewards(uint256 stake_, uint256 earlierCheckpoint, uint256 latterCheckpoint) internal pure returns (uint256) {
        return stake_ * (latterCheckpoint - earlierCheckpoint) / 1e18; // We must scale down the rewards by the precision factor
    }

    /// @notice Update and return the rewards per token accumulator according to the rate, the time elapsed since the last update, and the current total staked
    /// amount.
    function _updateRewardsPerToken(address reward) internal returns (RewardsPerToken memory) {
        RewardsInterval storage rewardsInterval = rewardToInterval[reward];
        RewardsPerToken memory rewardsPerTokenIn = rewardToRPT[reward];
        RewardsPerToken memory rewardsPerTokenOut = _calculateRewardsPerToken(rewardsPerTokenIn, rewardsInterval);

        // We skip the storage changes if already updated in the same block, or if the program has ended and was updated at the end
        if (rewardsPerTokenIn.lastUpdated == rewardsPerTokenOut.lastUpdated) return rewardsPerTokenOut;

        rewardToRPT[reward] = rewardsPerTokenOut;
        emit RewardsPerTokenUpdated(rewardsPerTokenOut.accumulated);

        return rewardsPerTokenOut;
    }

    function _updateUserRewards(address user) internal {
        for (uint256 i = 0; i < rewards.length; i++) {
            address reward = rewards[i];
            _updateUserRewards(reward, user);
        }
    }

    /// @notice Calculate and store current rewards for an user. Checkpoint the rewardsPerToken value with the user.
    function _updateUserRewards(address reward, address user) internal returns (UserRewards memory) {
        RewardsPerToken memory rewardsPerToken_ = _updateRewardsPerToken(reward);
        UserRewards memory userRewards_ = rewardToUserToAR[reward][user];

        // We skip the storage changes if there are no changes to the rewards per token accumulator
        if (userRewards_.checkpoint == rewardsPerToken_.accumulated) return userRewards_;

        // Calculate and update the new value user reserves.
        userRewards_.accumulated += _calculateUserRewards(balanceOf[user], userRewards_.checkpoint, rewardsPerToken_.accumulated).u128();
        userRewards_.checkpoint = rewardsPerToken_.accumulated;

        rewardToUserToAR[reward][user] = userRewards_;
        emit UserRewardsUpdated(user, userRewards_.accumulated, userRewards_.checkpoint);

        return userRewards_;
    }

    /// @dev Mint tokens, after accumulating rewards for an user and update the rewards per token accumulator.
    function _mint(address to, uint256 amount) internal virtual override {
        _updateUserRewards(to);
        super._mint(to, amount);
    }

    /// @dev Burn tokens, after accumulating rewards for an user and update the rewards per token accumulator.
    function _burn(address from, uint256 amount) internal virtual override {
        _updateUserRewards(from);
        super._burn(from, amount);
    }

    /// @notice Claim rewards for an user
    function _claim(address reward, address from, address to, uint256 amount) internal virtual {
        _updateUserRewards(reward, from);
        rewardToUserToAR[reward][from].accumulated -= amount.u128();
        pushRewardAndTakeFee(reward, to, amount);
        emit Claimed(reward, from, to, amount);
    }

    /// @dev Transfer tokens, after updating rewards for source and destination.
    function transfer(address to, uint256 amount) public virtual override returns (bool) {
        _updateUserRewards(msg.sender);
        _updateUserRewards(to);
        return super.transfer(to, amount);
    }

    /// @dev Transfer tokens, after updating rewards for source and destination.
    function transferFrom(address from, address to, uint256 amount) public virtual override returns (bool) {
        _updateUserRewards(from);
        _updateUserRewards(to);
        return super.transferFrom(from, to, amount);
    }

    /// @notice Claim all rewards for the caller
    function claim(address to) public virtual {
        for (uint256 i = 0; i < rewards.length; i++) {
            address reward = rewards[i];
            _claim(reward, msg.sender, to, currentUserRewards(reward, msg.sender));
        }
    }

    /// @notice Calculate and return current rewards per token.
    function currentRewardsPerToken(address reward) public view returns (uint256) {
        return _calculateRewardsPerToken(rewardToRPT[reward], rewardToInterval[reward]).accumulated;
    }

    /// @notice Calculate and return current rewards for a user.
    /// @dev This repeats the logic used on transactions, but doesn't update the storage.
    function currentUserRewards(address reward, address user) public view returns (uint256) {
        UserRewards memory accumulatedRewards_ = rewardToUserToAR[reward][user];
        RewardsPerToken memory rewardsPerToken_ = _calculateRewardsPerToken(rewardToRPT[reward], rewardToInterval[reward]);
        return accumulatedRewards_.accumulated + _calculateUserRewards(balanceOf[user], accumulatedRewards_.checkpoint, rewardsPerToken_.accumulated);
    }
}

library Cast {
    function u128(uint256 x) internal pure returns (uint128 y) {
        require(x <= type(uint128).max, "Cast overflow");
        y = uint128(x);
    }

    function u96(uint256 x) internal pure returns (uint96 y) {
        require(x <= type(uint96).max, "Cast overflow");
        y = uint96(x);
    }

    function u32(uint256 x) internal pure returns (uint32 y) {
        require(x <= type(uint32).max, "Cast overflow");
        y = uint32(x);
    }
}