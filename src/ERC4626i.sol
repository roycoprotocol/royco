// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import {SafeCast} from "src/libraries/SafeCast.sol";
import {Owned} from "lib/solmate/src/auth/Owned.sol";
import {ERC20} from "lib/solmate/src/tokens/ERC20.sol";
import {ERC4626} from "lib/solmate/src/tokens/ERC4626.sol";
import {LibString} from "lib/solady/src/utils/LibString.sol";
import {SafeTransferLib} from "lib/solmate/src/utils/SafeTransferLib.sol";

/// @title is ERC4626i
/// @title ERC4626i 
/// @author CopyPaste, corddry 
/// @dev Contract to wrap ERC4626 Vaults in an interface which allows the creation of incentive campaigns
contract ERC4626i is Owned(msg.sender), ERC20 {
    using SafeTransferLib for ERC20;
    using SafeCast for uint256;

    /*//////////////////////////////////////////////////////////////
                          EVENTS AND INTERFACE
    //////////////////////////////////////////////////////////////*/

    /// @custom:field start The start timestamp of the rewards campaign
    /// @custom:field end   The end timestamp of the rewards campaign 
    /// @custom:field rate  The rate in wei per second split among all depositors for rewards
    event RewardsSet(uint32 start, uint32 end, uint256 rate);

    /// @custom:field campaign The unique campaignId identifier 
    /// @custom:field token    The ERC20 token being given out as a reward
    event RewardCampaignAdded(uint256 campaign, address token);

    /// @custom:field campaign     The unique campaignId identifier 
    /// @custom:field token        The ERC20 token being given out as a reward
    /// @custom:field accumulated  The amount of rewards which have been accumulated so far
    event RewardsCampaignUpdated(uint256 campaign, address token, uint256 accumulated);

    /// @custom:field campaign              The unique campaignId identifier 
    /// @custom:field token                 The ERC20 token being given out as a reward
    /// @custom:field user                  The user whose reward campaigns have been updated 
    /// @custom:field paidRewardPerCampaign The amount of paid rewards for the campagin the user has been paid
    event UserRewardsUpdated(
        uint256 campaign, address token, address user, uint256 userRewards, uint256 paidRewardPerCampaign
    );

    /// @custom:field campaign    The unique campaignId identifier 
    /// @custom:field token       The ERC20 token being given out as a reward
    /// @custom:field user        The user whose reward campaigns have been updated 
    /// @custom:field receiver    The address which received the reward payout
    /// @custom:field claimed     The amount of rewards paid out
    event Claimed(uint256 campaign, address token, address user, address receiver, uint256 claimed);

    /// @custom:field sender   The caller of the contract 
    /// @custom:field receiver The receiver with who the deposit is credited to 
    /// @custom:field assets   The amount of assets (equivalent) deposited
    /// @custom:field shares   The amount of shares (equivalent) minted
    event Deposit(address indexed sender, address indexed receiver, uint256 assets, uint256 shares);

    /// @custom:field sender   The caller of the contract 
    /// @custom:field receiver The receiver with who the deposit is credited to 
    /// @custom:field assets   The amount of assets (equivalent) withdrawn 
    /// @custom:field shares   The amount of shares (equivalent) redeemed
    event Withdraw(address indexed sender, address indexed receiver, uint256 assets, uint256 shares);
    
    error CampaignTooShort();
    error CampaignNotStarted();
    error IncorrectInterval();
    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/
    /// @dev The underlying ERC4626 Vault deposits are routed to
    ERC4626 public underlyingVault;
    /// @dev The actual asset being deposited into the underlying vault
    ERC20 public immutable depositAsset;

    /// @dev The MakerDAO constant for 
    uint256 constant WAD = 1e18;
    /// @dev The Minimum Duration a Rewards Campaign must run for
    uint256 constant MINIMUM_CAMPAIGN_DURATION = 7 days;

    /// @dev A counter number used to generate campaignIds 
    uint256 internal totalCampaigns;
    /// @dev The protocol fee taken out of incentive campaigns out of 1e18
    uint256 public protocolFee;

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

    mapping(address user => uint256[5] campaignsOptedInto) public userSelectedCampaigns;

    mapping(uint256 campaign => address token) public campaignToToken;
    mapping(uint256 campaign => RewardsInterval) public tokenToRewardsInterval; // Interval in which rewards are accumulated by users
    mapping(uint256 campaign => RewardsPerCampaign) public tokenToRewardsPerCampaign; // Accumulator to track rewards per token
    mapping(uint256 campaign => mapping(address user => UserRewards)) public tokenToAccumulatedRewards; // Rewards accumulated per user

    mapping(uint256 campaign => RewardsInterval) public feeEarningInterval;
    mapping(uint256 campaign => RewardsPerCampaign) public feeRewardCampaign;
    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(ERC4626 _underlyingVault, uint256 _protocolFee)
        ERC20(LibString.concat("Incentivied", _underlyingVault.name()), LibString.concat(_underlyingVault.name(), "i"), 18)
    {
        underlyingVault = _underlyingVault;
        totalCampaigns = 1;

        depositAsset = _underlyingVault.asset();
        depositAsset.approve(address(underlyingVault), type(uint256).max);
    }

    /*//////////////////////////////////////////////////////////////
                              NEW CAMPAIGN
    //////////////////////////////////////////////////////////////*/

    /// @dev Set a rewards schedule
    function createRewardsCampaign(address token, uint256 start, uint256 end, uint256 totalRewards)
        external
        returns (uint256 campaignId)
    {
        if (start < block.timestamp) {
            revert CampaignNotStarted();
        }

        if (start > end) {
            revert IncorrectInterval();
        }

        if (end - start < MINIMUM_CAMPAIGN_DURATION) {
            revert CampaignTooShort();
        }

        uint256 feeTaken = totalRewards * protocolFee / WAD;
        totalRewards -= feeTaken;

        campaignId = totalCampaigns++;
        
        campaignToToken[campaignId] = token;
        ERC20(token).safeTransferFrom(msg.sender, address(this), totalRewards);

        RewardsInterval memory rewardsInterval = tokenToRewardsInterval[campaignId];

        // A new rewards program can be set if one is not running
        // Update the rewards per token so that we don't lose any rewards
        _updateRewardsPerCampaign(campaignId);

        uint256 rate = totalRewards / (end - start);

        rewardsInterval.start = start.toUint32();
        rewardsInterval.end = end.toUint32();
        rewardsInterval.rate = rate.toUint96();

        tokenToRewardsPerCampaign[campaignId].lastUpdated = start.toUint32();

        emit RewardsSet(start.toUint32(), end.toUint32(), rate);
    }

    function optIntoCampaign(uint256 campaignId, uint256 index) external {
        updateUserCampaigns(msg.sender);

        userSelectedCampaigns[msg.sender][index] = campaignId;
    }

    function optOutOfCampaign(uint256 campaignId) external {

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
        RewardsPerCampaign memory rewardsPerCampaignOut =
            _calculateRewardsPerCampaign(rewardsPerCampaignIn, rewardsInterval);

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
        userRewards_.accumulated += _calculateUserRewards(
            underlyingVault.balanceOf(user), userRewards_.checkpoint, rewardsPerCampaign_.accumulated
        ).toUint128();
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

    /// @notice Calculate and return current rewards per token.
    function currentRewardsPerCampaign(uint256 campaignId) public view returns (uint256) {
        return _calculateRewardsPerCampaign(tokenToRewardsPerCampaign[campaignId], tokenToRewardsInterval[campaignId])
            .accumulated;
    }

    /// @notice Calculate and return current rewards for a user.
    function currentUserRewards(uint256 campaignId, address user) public view returns (uint256) {
        /// @dev This repeats the logic used on transactions, but doesn't update the storage.
        UserRewards memory accumulatedRewards_ = tokenToAccumulatedRewards[campaignId][user];
        RewardsPerCampaign memory rewardsPerCampaign_ =
            _calculateRewardsPerCampaign(tokenToRewardsPerCampaign[campaignId], tokenToRewardsInterval[campaignId]);
        return accumulatedRewards_.accumulated
            + _calculateUserRewards(
                underlyingVault.balanceOf(user), accumulatedRewards_.checkpoint, rewardsPerCampaign_.accumulated
            );
    }

    ///
    function previewRewardsAfterDeposit(uint256 amount, uint256 campaignId)
        public
        view
        returns (uint256 incentiveRate)
    {
        RewardsInterval memory interval = tokenToRewardsInterval[campaignId];
        RewardsPerCampaign memory campaignRewards = tokenToRewardsPerCampaign[campaignId];

        return interval.rate * (campaignRewards.accumulated * amount) / WAD;
    }

    /*//////////////////////////////////////////////////////////////
                            ERC4626 OVERRIDE
    //////////////////////////////////////////////////////////////*/
    function updateUserCampaigns(address user) internal {
        for (uint8 i = 0; i < userSelectedCampaigns[user].length;) {
            uint256 campaignId = userSelectedCampaigns[user][i];
            _updateUserRewards(campaignId, user);

            unchecked {
                ++i;
            }
        }
    }

    /// @notice The address of the underlying ERC20 token used for
    /// the Vault for accounting, depositing, and withdrawing.
    function asset() external view returns (address _asset) {
        return address(depositAsset);
    }

    /// @notice Total amount of the underlying asset that
    /// is "managed" by Vault.
    function totalAssets() public view returns (uint256) {
        return underlyingVault.convertToAssets(underlyingVault.balanceOf(address(this)));
    }

    /// @notice Mints `shares` Vault shares to `receiver` by
    /// depositing exactly `assets` of underlying tokens.
    function deposit(uint256 assets, address receiver) external returns (uint256 shares) {
        depositAsset.transferFrom(msg.sender, address(this), assets);

        shares = underlyingVault.deposit(assets, address(this));
        _mint(receiver, shares);
        
        emit Deposit(msg.sender, receiver, assets, shares);
    }

    /// @notice Mints exactly `shares` Vault shares to `receiver`
    /// by depositing `assets` of underlying tokens.
    function mint(uint256 shares, address receiver) external returns (uint256 assets) {
        depositAsset.transferFrom(msg.sender, address(this), underlyingVault.convertToAssets(shares));

        assets = underlyingVault.mint(shares, address(this));
        _mint(receiver, shares);
    
        emit Deposit(msg.sender, receiver, assets, shares);
    }

    /// @notice Redeems `shares` from `owner` and sends `assets`
    /// of underlying tokens to `receiver`.
    function withdraw(uint256 assets, address receiver, address owner) external returns (uint256 shares) {
        shares = underlyingVault.withdraw(assets, address(this), address(this));

        _burn(owner, shares);
        depositAsset.transfer(receiver, assets);
    
        emit Withdraw(msg.sender, receiver, assets, shares);
    }

    /// @notice Redeems `shares` from `owner` and sends `assets`
    /// of underlying tokens to `receiver`.
    function redeem(uint256 shares, address receiver, address owner) external returns (uint256 assets) {
        assets = underlyingVault.redeem(shares, address(this), address(this));

        _burn(owner, shares);
        depositAsset.transfer(receiver, assets);
        
        emit Withdraw(msg.sender, receiver, assets, shares);
    }

    function convertToShares(uint256 assets) external view returns (uint256 shares) {
        shares = underlyingVault.convertToShares(assets);
    }

    function convertToAssets(uint256 shares) external view returns (uint256 assets) {
        assets = underlyingVault.convertToAssets(shares);
    }

    function maxDeposit(address) external view returns (uint256 maxAssets) {
        maxAssets = underlyingVault.maxDeposit(address(this));
    }

    function previewDeposit(uint256 assets) external view returns (uint256 shares) {
        shares = underlyingVault.previewDeposit(assets);
    }

    function maxMint(address) external view returns (uint256 maxShares) {
        maxShares = underlyingVault.maxMint(address(this));
    }

    function previewMint(uint256 shares) external view returns (uint256 assets) {
        assets = underlyingVault.previewMint(shares);
    }

    function maxWithdraw(address) external view returns (uint256 maxAssets) {
        maxAssets = underlyingVault.maxWithdraw(address(this));
    }

    function previewWithdraw(uint256 assets) external view virtual returns (uint256 shares) {
        shares = underlyingVault.previewWithdraw(assets);
    }

    function maxRedeem(address) external view returns (uint256 maxShares) {
        maxShares = underlyingVault.maxRedeem(address(this));
    }

    function previewRedeem(uint256 shares) external view returns (uint256 assets) {
        assets = underlyingVault.previewRedeem(shares);
    }

    /*////////////////////////////////////////////////////////
                      Deposit/Withdrawal Logic
    ////////////////////////////////////////////////////////*/

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
    function claim(uint256 campaignId, address to) public virtual returns (uint256 claimed) {
        claimed = currentUserRewards(campaignId, msg.sender);

        _claim(campaignId, msg.sender, to, claimed);
    }
}
