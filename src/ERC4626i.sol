// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import { SafeCast } from "src/libraries/SafeCast.sol";
import { Owned } from "lib/solmate/src/auth/Owned.sol";
import { ERC20 } from "lib/solmate/src/tokens/ERC20.sol";
import { ERC4626 } from "lib/solmate/src/tokens/ERC4626.sol";
import { LibString } from "lib/solady/src/utils/LibString.sol";
import { SafeTransferLib } from "lib/solmate/src/utils/SafeTransferLib.sol";

/// @title is ERC4626i
contract ERC4626i is Owned(msg.sender), ERC20, ERC4626 {
    using SafeTransferLib for ERC20;
    using SafeCast for uint256;

    /*//////////////////////////////////////////////////////////////
                          EVENTS AND INTERFACE
    //////////////////////////////////////////////////////////////*/
    error CampaignTooShort();
    error CampaignNotStarted();
    error IncorrectInterval();

    event RewardsSet(uint32 start, uint32 end, uint256 rate);
    event RewardCampaignAdded(uint256 campaign, address token);
    event RewardsCampaignUpdated(uint256 campaign, address token, uint256 accumulated);
    event UserRewardsUpdated(uint256 campaign, address token, address user, uint256 userRewards, uint256 paidRewardPerCampaign);
    event Claimed(uint256 campaign, address token, address user, address receiver, uint256 claimed);

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/
    uint256 public totalCampaigns;
    ERC4626 public underlyingVault;

    uint256 constant MINIMUM_CAMPAIGN_DURATION = 7 days;

    struct RewardsInterval {
        uint32 start; // Start time for the current rewardsToken schedule
        uint32 end; // End time for the current rewardsToken schedule
        uint96 rate; // Wei rewarded per second among all token holders
    }

    struct RewardsPerCampaign {
        uint128 accumulated; // Accumulated rewards per token for the interval, scaled up by 1e18
        uint32 lastUpdated; // Last time the rewards per token accumulator was updated
    }

    struct UserRewards {
        uint128 accumulated; // Accumulated rewards for the user until the checkpoint
        uint128 checkpoint; // RewardsPerCampaign the last time the user rewards were updated
    }

    ERC20[] public rewardTokens; // Tokens used as rewards

    mapping(address user => uint256[5] campaignsOptedInto) public userSelectedCampaigns;

    mapping(uint256 campaign => address token) public campaignToToken;
    mapping(uint256 campaign => RewardsInterval) public tokenToRewardsInterval; // Interval in which rewards are accumulated by users
    mapping(uint256 campaign => RewardsPerCampaign) public tokenToRewardsPerCampaign; // Accumulator to track rewards per token
    mapping(uint256 campaign  => mapping(address user => UserRewards)) public tokenToAccumulatedRewards; // Rewards accumulated per user

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    constructor(ERC4626 _underlyingVault)
    ERC4626(_underlyingVault.asset(), LibString.concat("Incentivied", _underlyingVault.name()), LibString.concat(_underlyingVault.name(), "i"))
    {
        underlyingVault = _underlyingVault;
        totalCampaigns = 1;
    }

    /*//////////////////////////////////////////////////////////////
                              NEW CAMPAIGN
    //////////////////////////////////////////////////////////////*/

    /// @dev Set a rewards schedule
    function createRewardsCampaign(address token, uint256 start, uint256 end, uint256 totalRewards) external returns (uint256 campaignId) {
        if (start < block.timestamp) {
            revert CampaignNotStarted();
        }

        if (start > end) {
            revert IncorrectInterval();
        }

        if (end - start < MINIMUM_CAMPAIGN_DURATION) {
            revert CampaignTooShort();
        }

        campaignId = totalCampaigns++;        

        RewardsInterval memory rewardsInterval = tokenToRewardsInterval[campaignId];

        // A new rewards program can be set if one is not running

        // Update the rewards per token so that we don't lose any rewards
        _updateRewardsPerCampaign(campaignId);

        campaignToToken[campaignId] = token;
        ERC20(token).safeTransferFrom(msg.sender, address(this), totalRewards);

        uint256 rate = totalRewards / (end - start);

        rewardsInterval.start = start.toUint32();
        rewardsInterval.end = end.toUint32();
        rewardsInterval.rate = rate.toUint96();

        // If setting up a new rewards program, the rewardsPerCampaign.accumulated is used and built upon
        // New rewards start accumulating from the new rewards program start
        // Any unaccounted rewards from last program can still be added to the user rewards
        // Any unclaimed rewards can still be claimed
        tokenToRewardsPerCampaign[campaignId].lastUpdated = start.toUint32();

        emit RewardsSet(start.toUint32(), end.toUint32(), rate);
    }

    function optIntoCampaign(uint256 campaignId, uint256 index) external {
      updateUserCampaigns(msg.sender);

      userSelectedCampaigns[msg.sender][index] = campaignId;
    }

    /*//////////////////////////////////////////////////////////////
                             CAMPAIGN MATH
    //////////////////////////////////////////////////////////////*/

    /// @notice Update the rewards per token accumulator according to the rate, the time elapsed since the last update, and the current total staked amount.
    function _calculateRewardsPerCampaign(
        RewardsPerCampaign memory rewardsPerCampaignIn,
        RewardsInterval memory rewardsInterval_
    ) internal view returns (RewardsPerCampaign memory) {
        RewardsPerCampaign memory rewardsPerCampaignOut =
            RewardsPerCampaign(rewardsPerCampaignIn.accumulated, rewardsPerCampaignIn.lastUpdated);
        uint256 totalSupply_ = underlyingVault.totalSupply();

        // No changes if the program hasn't started
        if (block.timestamp < rewardsInterval_.start) return rewardsPerCampaignOut;

        // Stop accumulating at the end of the rewards interval
        uint256 updateTime = block.timestamp < rewardsInterval_.end ? block.timestamp : rewardsInterval_.end;
        uint256 elapsed = updateTime - rewardsPerCampaignIn.lastUpdated;

        // No changes if no time has passed
        if (elapsed == 0) return rewardsPerCampaignOut;
        rewardsPerCampaignOut.lastUpdated = updateTime.toUint32();

        // If there are no stakers we just change the last update time, the rewards for intervals without stakers are not accumulated
        if (totalSupply_ == 0) return rewardsPerCampaignOut;

        // Calculate and update the new value of the accumulator.
        rewardsPerCampaignOut.accumulated =
            (rewardsPerCampaignIn.accumulated + 1e18 * elapsed * rewardsInterval_.rate / totalSupply_).toUint128(); // The rewards per token are scaled up for precision
        return rewardsPerCampaignOut;
    }

    /// @notice Calculate the rewards accumulated by a stake between two checkpoints.
    function _calculateUserRewards(uint256 stake_, uint256 earlierCheckpoint, uint256 latterCheckpoint)
        internal
        pure
        returns (uint256)
    {
        return stake_ * (latterCheckpoint - earlierCheckpoint) / 1e18; // We must scale down the rewards by the precision factor
    }

    /// @notice Update and return the rewards per token accumulator according to the rate, the time elapsed since the last update, and the current total staked amount.
    function _updateRewardsPerCampaign(uint256 campaignId) internal returns (RewardsPerCampaign memory) {
        RewardsInterval memory rewardsInterval = tokenToRewardsInterval[campaignId];

        RewardsPerCampaign memory rewardsPerCampaignIn = tokenToRewardsPerCampaign[campaignId];
        RewardsPerCampaign memory rewardsPerCampaignOut = _calculateRewardsPerCampaign(rewardsPerCampaignIn, rewardsInterval);

        // We skip the storage changes if already updated in the same block, or if the program has ended and was updated at the end
        if (rewardsPerCampaignIn.lastUpdated == rewardsPerCampaignOut.lastUpdated) return rewardsPerCampaignOut;

        tokenToRewardsPerCampaign[campaignId] = rewardsPerCampaignOut;
        
        address token = campaignToToken[campaignId];
        emit RewardsCampaignUpdated(campaignId, token, rewardsPerCampaignOut.accumulated);

        return rewardsPerCampaignOut;
    }

    /// @notice Calculate and store current rewards for an user. Checkpoint the rewardsPerCampaign value with the user.
    function _updateUserRewards(uint256 campaignId, address user) internal returns (UserRewards memory) {
        RewardsPerCampaign memory rewardsPerCampaign_ = _updateRewardsPerCampaign(campaignId);
        UserRewards memory userRewards_ = tokenToAccumulatedRewards[campaignId][user];

        // We skip the storage changes if there are no changes to the rewards per token accumulator
        if (userRewards_.checkpoint == rewardsPerCampaign_.accumulated) return userRewards_;

        // Calculate and update the new value user reserves.
        userRewards_.accumulated +=
            _calculateUserRewards(underlyingVault.balanceOf(user), userRewards_.checkpoint, rewardsPerCampaign_.accumulated).toUint128();
        userRewards_.checkpoint = rewardsPerCampaign_.accumulated;

        tokenToAccumulatedRewards[campaignId][user] = userRewards_;

        address token = campaignToToken[campaignId];
        emit UserRewardsUpdated(campaignId, token, user, userRewards_.accumulated, userRewards_.checkpoint);

        return userRewards_;
    }

    /// @notice Claim rewards for an user
    function _claim(uint256 campaignId, address from, address to, uint256 amount) internal virtual {
        _updateUserRewards(campaignId, from);
        tokenToAccumulatedRewards[campaignId][from].accumulated -= amount.toUint128();
        
        address token = campaignToToken[campaignId];
        ERC20(token).safeTransfer(to, amount);

        emit Claimed(campaignId, token, from, to, amount);
    }

    /*//////////////////////////////////////////////////////////////
                            ERC4626 OVERRIDE
    //////////////////////////////////////////////////////////////*/
    function updateUserCampaigns(address user) internal {
        for (uint8 i = 0; i < userSelectedCampaigns[user].length; ) {
            uint256 campaignId = userSelectedCampaigns[user][i];
            _updateUserRewards(campaignId, user);

            unchecked {
              ++i;
            }
        }
    }

    /*////////////////////////////////////////////////////////
                      Vault properties
    ////////////////////////////////////////////////////////*/

    /// @notice Total amount of the underlying asset that
    /// is "managed" by Vault.
    function totalAssets() public view override returns (uint256) {
        return underlyingVault.convertToAssets(underlyingVault.balanceOf(address(this)));
    }

    /*////////////////////////////////////////////////////////
                      Deposit/Withdrawal Logic
    ////////////////////////////////////////////////////////*/

    /// @notice Mints `shares` Vault shares to `receiver` by
    /// depositing exactly `assets` of underlying tokens.
    function deposit(uint256 assets, address receiver) public override returns (uint256 shares) {

    }

    /// @notice Mints exactly `shares` Vault shares to `receiver`
    /// by depositing `assets` of underlying tokens.
    function mint(uint256 shares, address receiver) public override returns (uint256 assets) {

    }

    /// @notice Redeems `shares` from `owner` and sends `assets`
    /// of underlying tokens to `receiver`.
    function withdraw(
        uint256 assets,
        address receiver,
        address owner
    ) public override returns (uint256 shares) {

    }

    /// @notice Redeems `shares` from `owner` and sends `assets`
    /// of underlying tokens to `receiver`.
    function redeem(
        uint256 shares,
        address receiver,
        address owner
    ) public override returns (uint256 assets) {

    }

    /// @dev Mint tokens, after accumulating rewards for an user and update the rewards per token accumulator.
    function _mint(address to, uint256 amount) internal virtual override {
        updateUserCampaigns(to);
        super._mint(to, amount);
    }

    /// @dev Burn tokens, after accumulating rewards for an user and update the rewards per token accumulator.
    function _burn(address from, uint256 amount) internal virtual override {
        updateUserCampaigns(from);

        super._burn(from, amount);
    }

    /// @dev Transfer tokens, after updating rewards for source and destination.
    function transfer(address to, uint256 amount) public virtual override returns (bool) {
        updateUserCampaigns(msg.sender);
        updateUserCampaigns(to);

        return super.transfer(to, amount);
    }

    /// @dev Transfer tokens, after updating rewards for source and destination.
    function transferFrom(address from, address to, uint256 amount) public virtual override returns (bool) {
        updateUserCampaigns(from);
        updateUserCampaigns(to);

        return super.transferFrom(from, to, amount);
    }

    /// @notice Claim all of one reward token for the caller
    function claim(uint256 campaignId, address to) public virtual returns (uint256) {
        uint256 claimed = currentUserRewards(campaignId, msg.sender);

        _claim(campaignId, msg.sender, to, claimed);

        return claimed;
    }

    /// @notice Calculate and return current rewards per token.
    function currentRewardsPerCampaign(uint256 campaignId) public view returns (uint256) {
        return _calculateRewardsPerCampaign(tokenToRewardsPerCampaign[campaignId], tokenToRewardsInterval[campaignId]).accumulated;
    }

    /// @notice Calculate and return current rewards for a user.
    function currentUserRewards(uint256 campaignId, address user) public view returns (uint256) {
        /// @dev This repeats the logic used on transactions, but doesn't update the storage.
        UserRewards memory accumulatedRewards_ = tokenToAccumulatedRewards[campaignId][user];
        RewardsPerCampaign memory rewardsPerCampaign_ =
            _calculateRewardsPerCampaign(tokenToRewardsPerCampaign[campaignId], tokenToRewardsInterval[campaignId]);
        return accumulatedRewards_.accumulated
            + _calculateUserRewards(underlyingVault.balanceOf(user), accumulatedRewards_.checkpoint, rewardsPerCampaign_.accumulated);
    }

    function previewRewardsAfterDeposit(uint256 amount, uint256 campaignId, uint256 rate) public returns (uint256 incentiveRate) {
       RewardsInterval memory interval = tokenToRewardsInterval[campaignId];
       RewardsPerCampaign memory campaignRewards = tokenToRewardsPerCampaign[campaignId];
    }

    /*//////////////////////////////////////////////////////////////
                           ERC4626 OVERRIDES
    //////////////////////////////////////////////////////////////*/ 

    /// @notice The amount of shares that the vault would
    /// exchange for the amount of assets provided, in an
    /// ideal scenario where all the conditions are met.
    function convertToShares(uint256 assets) public view override returns (uint256 shares) {
      shares = underlyingVault.convertToShares(assets);
    }

    /// @notice The amount of assets that the vault would
    /// exchange for the amount of shares provided, in an
    /// ideal scenario where all the conditions are met.
    function convertToAssets(uint256 shares) public view override returns (uint256 assets) {
      assets = underlyingVault.convertToAssets(shares);
    }

    /// @notice Total number of underlying assets that can
    /// be deposited by `owner` into the Vault, where `owner`
    /// corresponds to the input parameter `receiver` of a
    /// `deposit` call.
    function maxDeposit(address) public view override returns (uint256 maxAssets) {
      maxAssets = underlyingVault.maxDeposit(address(this));
    }

    /// @notice Allows an on-chain or off-chain user to simulate
    /// the effects of their deposit at the current block, given
    /// current on-chain conditions.
    function previewDeposit(uint256 assets) public view override returns (uint256 shares) {
      shares = underlyingVault.previewDeposit(assets);
    }

    /// @notice Total number of underlying shares that can be minted
    /// for `owner`, where `owner` corresponds to the input
    /// parameter `receiver` of a `mint` call.
    function maxMint(address) public view override returns (uint256 maxShares) {
      maxShares = underlyingVault.maxMint(address(this));
    }

    /// @notice Allows an on-chain or off-chain user to simulate
    /// the effects of their mint at the current block, given
    /// current on-chain conditions.
    function previewMint(uint256 shares) public view override returns (uint256 assets) {
      assets = underlyingVault.previewMint(shares);
    }

    /// @notice Total number of underlying assets that can be
    /// withdrawn from the Vault by `owner`, where `owner`
    /// corresponds to the input parameter of a `withdraw` call.
    function maxWithdraw(address) public view override returns (uint256 maxAssets) {
      maxAssets = underlyingVault.maxWithdraw(address(this));
    }

    /// @notice Allows an on-chain or off-chain user to simulate
    /// the effects of their withdrawal at the current block,
    /// given current on-chain conditions.
    function previewWithdraw(uint256 assets) public view override returns (uint256 shares) {
      shares = underlyingVault.previewWithdraw(assets);
    }

    /// @notice Total number of underlying shares that can be
    /// redeemed from the Vault by `owner`, where `owner` corresponds
    /// to the input parameter of a `redeem` call.
    function maxRedeem(address ) public view override returns (uint256 maxShares) {
      maxShares = underlyingVault.maxRedeem(address(this));
    }

    /// @notice Allows an on-chain or off-chain user to simulate
    /// the effects of their redeemption at the current block,
    /// given current on-chain conditions.
    function previewRedeem(uint256 shares) public view override returns (uint256 assets) {
      assets = underlyingVault.previewRedeem(shares);
    }


}
