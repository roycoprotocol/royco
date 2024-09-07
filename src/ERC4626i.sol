// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { SafeCast } from "src/libraries/SafeCast.sol";
import { Owned } from "lib/solmate/src/auth/Owned.sol";
import { ERC20 } from "lib/solmate/src/tokens/ERC20.sol";
import { ERC4626 } from "lib/solmate/src/tokens/ERC4626.sol";
import { IERC4626 } from "src/interfaces/IERC4626.sol";
import { LibString } from "lib/solady/src/utils/LibString.sol";
import { SafeTransferLib } from "lib/solmate/src/utils/SafeTransferLib.sol";
import { FixedPointMathLib } from "lib/solmate/src/utils/FixedPointMathLib.sol";
import { PointsFactory } from "src/PointsFactory.sol";
import { Points } from "src/Points.sol";

/// @title ERC4626i
/// @author CopyPaste, corddry
/// @dev Contract to wrap ERC4626 Vaults in an interface which allows the creation of incentive campaigns
contract ERC4626i is Owned(msg.sender), ERC20, IERC4626 {
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
    event UserRewardsUpdated(uint256 campaign, address token, address user, uint256 userRewards, uint256 paidRewardPerCampaign);

    /// @custom:field campaign    The unique campaignId identifier
    /// @custom:field token       The ERC20 token being given out as a reward
    /// @custom:field user        The user whose reward campaigns have been updated
    /// @custom:field receiver    The address which received the reward payout
    /// @custom:field claimed     The amount of rewards paid out
    event Claimed(uint256 campaign, address token, address user, address receiver, uint256 claimed);

    /// @custom:field sender     The user who selected the campaign
    /// @custom:field campaignId The campaignId selected by the user
    event RewardCampaignSelected(address indexed sender, uint256 indexed campaignId);
    /// @custom:field sender     The user who selected the campaign
    /// @custom:field campaignId The campaignId unselected by the user
    event RewardCampaignUnselected(address indexed sender, uint256 indexed campaignId);

    error CampaignTooShort();
    error CampaignNotStarted();
    error IncorrectInterval();
    error MaxCampaignsOptedInto();
    error NotReferrer();
    error OnlyProtocolFeeTo();
    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/
    /// @dev The underlying ERC4626 Vault deposits are routed to

    ERC4626 public underlyingVault;
    /// @dev The actual asset being deposited into the underlying vault
    ERC20 public immutable depositAsset;
    /// @dev The PointsFactory contract to create new Points contracts
    PointsFactory public pointsFactory;

    /// @dev The MakerDAO constant for
    uint256 constant WAD = 1e18;
    /// @dev The Minimum Duration a Rewards Campaign must run for
    uint256 constant MINIMUM_CAMPAIGN_DURATION = 7 days;

    /// @dev A counter number used to generate campaignIds
    uint256 public totalCampaigns;
    /// @dev The address which is allowed to claim protocol fees
    address public protocolFeesTo;
    /// @dev The protocol fee taken out of incentive campaigns out of 1e18
    uint256 public protocolFee;

    /// @dev The fee of incentives taken for referrals out of WAD
    uint256 public referralFee;

    /// @custom:field start The start time for the reward campaign schedule
    /// @custom:field end   End time for the reward campaign schedule
    /// @custom:field rate  Wei rewarded per second among all token holders
    /// @custom:field protocolFee The protocolFee taken out of the campaign rewards
    /// @custom:field referralFee The referralFee taken out of the campaign rewards
    /// @custom:field accumulated Accumulated rewards per token for the interval, scaled up by WAD
    /// @custom:field lastUpdate  Last time the rewards per token accumulator was updated
    struct CampaignData {
        uint32 start;
        uint32 end;
        uint96 rate;
        uint96 protocolFeeRate;
        uint96 referralFee;
        uint256 accumulated;
        uint64 lastUpdated;
    }

    /// @custom:field accumulated The accumulated rewards for the user until the checkpoint
    /// @custom:field checkpoint  RewardsPerCampagin the last time the user rewards were updated
    struct UserRewards {
        uint256 accumulated;
        uint256 checkpoint;
        uint64 lastUpdated;
    }

    /// @dev Campaign to Reward Tokens
    mapping(uint256 campaign => ERC20) public campaignToToken;
    /// @dev Tracks the token rewards distributed in a given campaign so far
    mapping(uint256 campaign => CampaignData) public campaignIdToData;
    /// @dev Tracks how much rewards a user has claimed from a given campaign, and when
    mapping(uint256 campaign => mapping(address user => UserRewards)) public campaignToUserRewards;

    /// @dev Mappiing to track how many fees have actually vested for a given campaign
    mapping(uint256 campaign => uint256 lastUpdated) public feeRewardsLastClaimed;

    /// @dev The user who referred someone for a given campaign
    mapping(uint256 campaign => mapping(address user => address referrer)) public referralsPerUser;
    /// @dev Tracks out how much of a user's incentives have been taken as fees to their referrer
    mapping(address user => mapping(uint256 campaignId => uint256 incentivesTaken)) public referralIncentives;

    /// @dev A mapping we use to keep track of which rewardCampaigns we should be tracking for a given user
    mapping(address user => uint256[5] campaignsOptedInto) public userSelectedCampaigns;
    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @param _underlyingVault The ERC4626 Vault to wrap
    /// @param _protocolFee     The protocol fee to take from incentives, out of WAD
    /// @param _referralFee     The fee taken out of incentives for the person who referred a given user
    /// @param _pointsFactory   The address of the PointsFactory contract
    constructor(
        ERC4626 _underlyingVault,
        uint256 _protocolFee,
        uint256 _referralFee,
        address _pointsFactory
    )
        ERC20(LibString.concat("Incentivied", _underlyingVault.name()), LibString.concat(_underlyingVault.name(), "i"), 18)
    {
        underlyingVault = _underlyingVault;
        totalCampaigns = 1;

        protocolFee = _protocolFee;
        referralFee = _referralFee;

        depositAsset = _underlyingVault.asset();
        depositAsset.approve(address(underlyingVault), type(uint256).max);

        pointsFactory = PointsFactory(_pointsFactory);
    }

    /*//////////////////////////////////////////////////////////////
                           FEE CONTROL LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @param newDefaultProtocolFee The new fee to set on default for the protocol
    function updateDefaultProtocolFee(uint256 newDefaultProtocolFee) external onlyOwner {
        protocolFee = newDefaultProtocolFee;
    }

    /// @param newDefaultReferralFee The new fee to set on default for referrals
    function updateDefaultReferralFee(uint256 newDefaultReferralFee) external onlyOwner {
        referralFee = newDefaultReferralFee;
    }

    /*//////////////////////////////////////////////////////////////
                              NEW CAMPAIGN
    //////////////////////////////////////////////////////////////*/

    /// @dev Create a rewards campaign for all users
    /// @param token       The token to give depositors
    /// @param start        When the rewards campaign should begin
    /// @param end          When the rewards campaign should end
    /// @param totalRewards The total amount of rewards tokens to give out
    ///
    /// @return campaignId The amount of token rewards to give out to depositors
    function createRewardsCampaign(ERC20 token, uint256 start, uint256 end, uint256 totalRewards) external returns (uint256 campaignId) {
        if (start < block.timestamp) {
            revert CampaignNotStarted();
        }

        if (start > end) {
            revert IncorrectInterval();
        }

        if (end - start < MINIMUM_CAMPAIGN_DURATION) {
            revert CampaignTooShort();
        }

        /// Set the initial IDs of the campaign
        campaignId = totalCampaigns++;

        /// Fund the Campaign
        if (!pointsFactory.isPointsProgram(address(token))) {
            token.safeTransferFrom(msg.sender, address(this), totalRewards);
        }

        uint256 protocolFeeTaken = totalRewards * protocolFee / WAD;
        uint256 referralFeeTaken = totalRewards * referralFee / WAD;

        totalRewards -= protocolFeeTaken + referralFeeTaken;

        uint256 rate = totalRewards / (end - start);

        CampaignData storage data = campaignIdToData[campaignId];
        campaignToToken[campaignId] = token;

        data.start = start.toUint32();
        data.end = end.toUint32();
        data.rate = rate.toUint96();
        data.protocolFeeRate = (protocolFeeTaken / (end - start)).toUint96();
        data.referralFee = referralFee.toUint96();
        data.lastUpdated = (block.timestamp).toUint64();

        emit RewardsSet(start.toUint32(), end.toUint32(), rate);
    }

    /// @param campaignId The campaign to opt out of
    function optIntoCampaign(uint256 campaignId, address referral) external {
        updateUserCampaigns(msg.sender);
        referralsPerUser[campaignId][msg.sender] = referral;

        for (uint256 i; i < 5; i++) {
            if (userSelectedCampaigns[msg.sender][i] == 0) {
                userSelectedCampaigns[msg.sender][i] = campaignId;
                break;
            }

            if (i == 4) {
                revert MaxCampaignsOptedInto();
            }
        }

        emit RewardCampaignSelected(msg.sender, campaignId);
    }

    /// @param campaignId The campaignId to opt out of
    /// @param index The index of the campaignId to remove
    function optOutOfCampaign(uint256 campaignId, uint256 index) external {
        updateUserCampaigns(msg.sender);

        if (index == 4) {
            delete userSelectedCampaigns[msg.sender][4];
            return;
        }

        for (uint256 i = index; i < userSelectedCampaigns[msg.sender].length - 1; i++) {
            userSelectedCampaigns[msg.sender][i] = userSelectedCampaigns[msg.sender][i + 1];
        }

        emit RewardCampaignUnselected(msg.sender, campaignId);
    }

    /*//////////////////////////////////////////////////////////////
                             CAMPAIGN MATH
    //////////////////////////////////////////////////////////////*/
    /// @param campaignId The campaign to update
    /// @param user The user to update rewards on beahlf of
    function updateUserRewards(uint256 campaignId, address user) public {
        updateRewardCampaign(campaignId);

        CampaignData storage _campaignData = campaignIdToData[campaignId];
        UserRewards storage userData = campaignToUserRewards[campaignId][user];

        uint256 _end = _campaignData.end;
        uint256 lastCheckpoint = block.timestamp;
        if (lastCheckpoint > _end) {
            lastCheckpoint = _end;
        }

        uint256 elapsed = lastCheckpoint - userData.lastUpdated;

        userData.accumulated = (balanceOf[user] * elapsed * _campaignData.rate) / WAD;
        userData.lastUpdated = lastCheckpoint.toUint64();
    }

    /// @param campaignId The campaignId to update
    function updateRewardCampaign(uint256 campaignId) public {
        CampaignData storage _campaignData = campaignIdToData[campaignId];

        uint256 _end = _campaignData.end;
        uint256 lastCheckpoint = block.timestamp;
        if (lastCheckpoint > _end) {
            lastCheckpoint = _end;
        }

        uint256 elapsed = lastCheckpoint - _campaignData.lastUpdated;

        _campaignData.accumulated += (elapsed * totalSupply * uint256(_campaignData.rate)) / WAD;
        _campaignData.lastUpdated = lastCheckpoint.toUint64();
    }

    /// @notice Claim all of one reward token for the caller
    /// @return claimed The amount of tokens awarded
    function claim(uint256 campaignId, address to) public returns (uint256 claimed) {
        updateUserRewards(campaignId, msg.sender);
        CampaignData storage _campaignData = campaignIdToData[campaignId];

        ERC20 token = campaignToToken[campaignId];

        UserRewards storage userData = campaignToUserRewards[campaignId][msg.sender];

        uint256 tokensVestedSoFar = (_campaignData.rate * (_campaignData.lastUpdated - _campaignData.start));
        if (tokensVestedSoFar == 0) return 0;

        claimed = userData.accumulated * tokensVestedSoFar / _campaignData.accumulated;

        address referrer = referralsPerUser[campaignId][msg.sender];
        uint256 referralClaimed = (claimed * referralFee) / (WAD - _campaignData.referralFee);

        if (pointsFactory.isPointsProgram(address(token))) {
            Points(address(token)).award(to, claimed, campaignId);
            Points(address(token)).award(referrer, referralClaimed, campaignId);
        } else {
            token.safeTransfer(to, claimed);
            token.safeTransfer(referrer, referralClaimed);
        }

        emit Claimed(campaignId, address(token), msg.sender, to, claimed);
    }

    /// @param campaignId The campaign you are depositing into
    /// @param amount The amount of tokens to deposit
    /// @return rate The rate of tokens being rewarded
    function previewRateAfterDeposit(uint256 campaignId, uint256 amount) public view returns (uint256 rate) {
        CampaignData storage _campaignData = campaignIdToData[campaignId];

        return _campaignData.rate * amount / WAD;
    }

    /*//////////////////////////////////////////////////////////////
                            FEE CLAIM LOGIC
    //////////////////////////////////////////////////////////////*/
    error FeeSetTooHigh();

    /// @dev newReferralFee The new referral fee to be charged
    function setReferralFee(uint256 newReferralFee) external onlyOwner {
        if (newReferralFee > WAD) {
            revert FeeSetTooHigh();
        }

        referralFee = newReferralFee;
    }

    /// @dev newProtocolFee The new protocol fee to be charged
    function setProtocolFee(uint256 newProtocolFee) external onlyOwner {
        if (newProtocolFee > WAD) {
            revert FeeSetTooHigh();
        }

        protocolFee = newProtocolFee;
    }

    /// @param newProtocolFeeTo The address to send protocol fees towards
    function changeProtocolFeeTo(address newProtocolFeeTo) external onlyOwner {
        protocolFeesTo = newProtocolFeeTo;
    }

    /// @param campaignId The campaign to claim rewardsFees for
    function claimProtocolFees(uint256 campaignId) external {
        if (msg.sender != protocolFeesTo) {
            revert OnlyProtocolFeeTo();
        }

        CampaignData storage _campaignData = campaignIdToData[campaignId];
        uint256 lastUpdated = feeRewardsLastClaimed[campaignId];

        uint256 elapsed = (_campaignData.end - lastUpdated);
        uint256 amountOwed = (elapsed * _campaignData.protocolFeeRate);

        if (block.timestamp > _campaignData.end) {
            feeRewardsLastClaimed[campaignId] = _campaignData.end;
        } else {
            feeRewardsLastClaimed[campaignId] = block.timestamp;
        }

        ERC20 token = campaignToToken[campaignId];
        if (pointsFactory.isPointsProgram(address(token))) {
            Points(address(token)).award(protocolFeesTo, amountOwed, campaignId);
        } else {
            token.safeTransfer(protocolFeesTo, amountOwed);
        }
    }

    /*//////////////////////////////////////////////////////////////
                               REFERRALS
    //////////////////////////////////////////////////////////////*/
    /// @param campaignId The campaignId which the user was referrred to
    /// @param referrer The address who referred the user
    function updateReferral(uint256 campaignId, address referrer) external {
        referralsPerUser[campaignId][msg.sender] = referrer;
    }

    /*//////////////////////////////////////////////////////////////
                          ERC4626I EXTENSION:
    //////////////////////////////////////////////////////////////*/

    /// @param amount The amount of ERC4626 tokens to deposit
    /// @param receiver The person to credit the deposits on behalf of
    function depositVaultTokens(uint256 amount, address receiver) external {
        underlyingVault.transferFrom(msg.sender, address(this), amount);
        _mint(receiver, amount);
    }

    /// @param amount The Amount of ERC4626 tokens to withdraw
    /// @param receiver The address to withdraw the ERC4626 tokens to
    function withdrawVaultTokens(uint256 amount, address receiver) external {
        underlyingVault.transfer(receiver, amount);
        _burn(msg.sender, amount);
    }

    /*//////////////////////////////////////////////////////////////
                            ERC4626 OVERRIDE
    //////////////////////////////////////////////////////////////*/

    /// @param user The user to update their campaigns
    function updateUserCampaigns(address user) public {
        for (uint8 i = 0; i < userSelectedCampaigns[user].length;) {
            uint256 campaignId = userSelectedCampaigns[user][i];
            if (campaignId == 0) {
                return;
            }
            updateUserRewards(campaignId, user);

            unchecked {
                ++i;
            }
        }
    }

    /// @inheritdoc IERC4626
    function asset() external view returns (address _asset) {
        return address(depositAsset);
    }

    /// @inheritdoc IERC4626
    function totalAssets() public view returns (uint256) {
        return underlyingVault.convertToAssets(underlyingVault.balanceOf(address(this)));
    }

    /// @inheritdoc IERC4626
    function deposit(uint256 assets, address receiver) public returns (uint256 shares) {
        depositAsset.transferFrom(msg.sender, address(this), assets);

        shares = underlyingVault.deposit(assets, address(this));
        _mint(receiver, shares);

        emit Deposit(msg.sender, receiver, assets, shares);
    }

    /// @inheritdoc IERC4626
    function mint(uint256 shares, address receiver) public returns (uint256 assets) {
        depositAsset.transferFrom(msg.sender, address(this), underlyingVault.convertToAssets(shares));

        assets = underlyingVault.mint(shares, address(this));
        _mint(receiver, shares);

        emit Deposit(msg.sender, receiver, assets, shares);
    }

    /// @inheritdoc IERC4626
    function withdraw(uint256 assets, address receiver, address owner) external returns (uint256 shares) {
        shares = underlyingVault.withdraw(assets, address(this), address(this));

        _burn(owner, shares);
        depositAsset.transfer(receiver, assets);

        emit Withdraw(msg.sender, receiver, owner, assets, shares);
    }

    /// @inheritdoc IERC4626
    function redeem(uint256 shares, address receiver, address owner) external returns (uint256 assets) {
        assets = underlyingVault.redeem(shares, address(this), address(this));

        _burn(owner, shares);
        depositAsset.transfer(receiver, assets);

        emit Withdraw(msg.sender, receiver, owner, assets, shares);
    }

    /// @inheritdoc IERC4626
    function convertToShares(uint256 assets) external view returns (uint256 shares) {
        shares = underlyingVault.convertToShares(assets);
    }

    /// @inheritdoc IERC4626
    function convertToAssets(uint256 shares) external view returns (uint256 assets) {
        assets = underlyingVault.convertToAssets(shares);
    }

    /// @inheritdoc IERC4626
    function maxDeposit(address) external view returns (uint256 maxAssets) {
        maxAssets = underlyingVault.maxDeposit(address(this));
    }

    /// @inheritdoc IERC4626
    function previewDeposit(uint256 assets) external view returns (uint256 shares) {
        shares = underlyingVault.previewDeposit(assets);
    }

    /// @inheritdoc IERC4626
    function maxMint(address) external view returns (uint256 maxShares) {
        maxShares = underlyingVault.maxMint(address(this));
    }

    /// @inheritdoc IERC4626
    function previewMint(uint256 shares) external view returns (uint256 assets) {
        assets = underlyingVault.previewMint(shares);
    }

    /// @inheritdoc IERC4626
    function maxWithdraw(address) external view returns (uint256 maxAssets) {
        maxAssets = underlyingVault.maxWithdraw(address(this));
    }

    /// @inheritdoc IERC4626
    function previewWithdraw(uint256 assets) external view virtual returns (uint256 shares) {
        shares = underlyingVault.previewWithdraw(assets);
    }

    /// @inheritdoc IERC4626
    function maxRedeem(address) external view returns (uint256 maxShares) {
        maxShares = underlyingVault.maxRedeem(address(this));
    }

    /// @inheritdoc IERC4626
    function previewRedeem(uint256 shares) external view returns (uint256 assets) {
        assets = underlyingVault.previewRedeem(shares);
    }

    /*////////////////////////////////////////////////////////
                       ERC20 Logic / Overrides
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
}
