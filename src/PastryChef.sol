// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import { Owned } from "lib/solmate/src/auth/Owned.sol";
import { ERC20 } from "lib/solmate/src/tokens/ERC20.sol";
import { ERC4626 } from "lib/solmate/src/tokens/ERC4626.sol";
import { SafeTransferLib } from "lib/solmate/src/utils/SafeTransferLib.sol";

/// PastryChef is a bit like MasterChef, but he has more variety. He is a fair chef
/// who bakes multiple rewards at once, but uses only one timer. Each reward is tied its own
/// share based math system, however all rewards share the same base, which is user a users elastic value
/// in the overall share based system.
/*
                            ▓▓                        
                          ▓▓  ▓▓▓▓                    
                      ▓▓▓▓▓▓  ░░▓▓▓▓▓▓                
                    ▓▓      ▓▓▓▓      ▓▓              
                    ▓▓▓▓▓▓        ▓▓▓▓▓▓              
                ▓▓▓▓    ▓▓▓▓▓▓▓▓▓▓      ▓▓            
                ▓▓▓▓    ░░              ▓▓            
            ▓▓▓▓▒▒▒▒▓▓▓▓▓▓        ▓▓▓▓▓▓▒▒▓▓          
          ▓▓▒▒▒▒▒▒▒▒▒▒▒▒▒▒▓▓▓▓▓▓▓▓▒▒▒▒▒▒▒▒▒▒██        
          ▓▓▓▓▓▓▓▓▓▓▓▓▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▓▓▓▓▓▓▓▓        
            ▒▒▓▓░░░░▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓░░▓▓          
            ▒▒▓▓░░░░▓▓░░░░▓▓░░░░▓▓░░░░▓▓░░▓▓          
            ▒▒▓▓░░░░▓▓░░░░▓▓░░░░▓▓░░░░▓▓░░▓▓          
            ░░▓▓░░░░▓▓░░░░▓▓░░░░▓▓░░░░▓▓░░▓▓          
            ▒▒▓▓░░░░▓▓░░░░▓▓░░░░▓▓░░░░▓▓░░▓▓          
                ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓            
                    

*/
/// @title PastryChef
/// @notice One PastryChef is deployed per opportuntiy, limited by opportuntiy token
/// @author CopyPaste, corddry
contract PastryChef is Owned(msg.sender) {
    using SafeTransferLib for ERC20;
    using SafeTransferLib for ERC4626;

    /// @dev The ERC4626 Representing a deposit in the underlying yield opportuntiy
    ///     being incentivized
    ERC4626 public depositToken;

    error EpochNotStarted();
    error BalanceTooLow();
    error CampapignStartsTooLate();
    /*//////////////////////////////////////////////////////////////
                               STORAGE
    //////////////////////////////////////////////////////////////*/
    /// @dev MakerDAO Constant for a 1e18 Decimal Scale

    uint256 constant WAD = 1e18;

    /// @custom:field amount The amount of LP tokens deposited
    /// @custom:field lastEpoch The lastEpoch we've updated this users rewards at
    /// @custom:field epochDebt A mapping to how much has already been rewarded for each epoch
    ///   remember a users pending reward is equal to `(user.amount * pool.accRewardPerShare) - user.rewardDebt`
    struct UserInfo {
        uint128 amount;
        uint128 lastEpoch;
        mapping(uint256 epoch => uint256 rewardDebt) epochDebt;
    }

    /// @custom:field totalDeposited The total amount of LP tokens deposited within a given epoch
    /// @custom:field totalRewards The total amount of reward points awarded in a given epoch
    /// @custom:field accRewardsPerShare The amount of reward points that each share has earned
    /// @custom:field lastUpdated The last time we updated when the reward info for this epoch
    /// @custom:field epochEnds The timestamp when the epoch is over
    struct Epoch {
        uint128 totalDeposited;
        uint128 totalRewards;
        uint128 accRewardsPerShare;
        uint64 lastUpdated;
        uint64 epochEnds;
    }

    /// @dev the EpochId of the current epoch
    uint256 currentEpoch;
    /// @dev Tracks each epoch id to the assosiated reward info
    mapping(uint256 epochId => Epoch) public epochs;

    uint256 constant REWARDS_PER_EPOCH = EPOCH_DURATION * REWARD_POINTS_PER_SECOND;
    uint256 constant REWARD_POINTS_PER_SECOND = 50;
    uint256 constant EPOCH_DURATION = 2 weeks;

    mapping(address user => UserInfo info) public userInfo;
    mapping(address user => mapping(uint256 epoch => uint256 rewardPoints)) public epochRewardPoints;

    /// @custom:field token The token to be given out over the campaign
    /// @custom:field startEpoch The epoch at which the rewards campaign starts
    /// @custom:field endEpoch The epoch at which the rewards campaign ends
    /// @custom:field amount The amount of rewards to give out over the campaign
    struct Reward {
        ERC20 token;
        uint256 startEpoch;
        uint256 endEpoch;
        uint256 amount;
    }

    uint256 public maxRewardId;
    mapping(uint256 rewardId => Reward) public rewards;

    /*//////////////////////////////////////////////////////////////
                               KITCHEN
    //////////////////////////////////////////////////////////////*/

    /// @param epoch The epoch to update rewards info for
    function updateEpochRewards(uint256 epoch) public {
        if (epoch > currentEpoch) {
            revert EpochNotStarted();
        }
        Epoch storage _epoch = epochs[epoch];

        if (_epoch.lastUpdated >= _epoch.epochEnds) {
            return;
        }

        uint256 lastRewardedSecond = _epoch.epochEnds > block.timestamp ? _epoch.epochEnds : block.timestamp;
        uint256 newRewards = ((lastRewardedSecond - _epoch.lastUpdated) * REWARD_POINTS_PER_SECOND) / depositToken.balanceOf(address(this));
        _epoch.lastUpdated = uint64(block.timestamp);
        _epoch.accRewardsPerShare += uint128(newRewards * WAD / _epoch.totalDeposited);
    }

    /// @notice End the current Epoch and start the next one
    function rollOverEpoch() public {
        while (epochs[currentEpoch].epochEnds <= block.timestamp) {
            Epoch storage oldEpoch = epochs[currentEpoch];
            currentEpoch++;

            epochs[currentEpoch] = Epoch({
                totalDeposited: oldEpoch.totalDeposited,
                accRewardsPerShare: 0,
                totalRewards: 0,
                lastUpdated: oldEpoch.epochEnds,
                epochEnds: uint64(oldEpoch.epochEnds + EPOCH_DURATION)
            });

            updateEpochRewards(currentEpoch);
        }
    }

    /// @notice Update the rewards for a user
    /// @param _user The user to update rewards for
    function updateUserRewards(address _user) public {
        UserInfo storage user = userInfo[_user];

        for (uint256 i = user.lastEpoch; i < currentEpoch;) {
            updateEpochRewards(i);
            Epoch storage _epoch = epochs[i];

            uint256 rewardPointsAwarded = (user.amount * _epoch.accRewardsPerShare / WAD) - user.epochDebt[i];
            epochRewardPoints[_user][i] += rewardPointsAwarded;
            _epoch.totalRewards += uint128(rewardPointsAwarded);

            unchecked {
                ++i;
            }
        }
    }

    /// @param _amount The amount of principle opportunity tokens to deposit
    function deposit(uint256 _amount) public {
        UserInfo storage user = userInfo[msg.sender];
        rollOverEpoch();

        if (user.amount > 0) {
            updateUserRewards(msg.sender);
        }

        depositToken.safeTransferFrom(msg.sender, address(this), _amount);

        user.amount += uint128(_amount);
        user.lastEpoch = uint128(currentEpoch);
        user.epochDebt[currentEpoch] = (user.amount * epochs[currentEpoch].accRewardsPerShare) / WAD;

        epochs[currentEpoch].totalDeposited += uint128(_amount);
    }

    /// @param _amount The amount of principle opportunity tokens to withdraw
    function withdraw(uint256 _amount) public {
        UserInfo storage user = userInfo[msg.sender];
        if (_amount > user.amount) {
            revert BalanceTooLow();
        }

        rollOverEpoch();

        updateUserRewards(msg.sender);

        user.amount -= uint128(_amount);
        user.epochDebt[currentEpoch] = (user.amount * epochs[currentEpoch].accRewardsPerShare) / WAD;

        epochs[currentEpoch].totalDeposited -= uint128(_amount);

        depositToken.safeTransfer(msg.sender, _amount);
    }

    /*//////////////////////////////////////////////////////////////
                         REWARDS CAMPAIGNS
    //////////////////////////////////////////////////////////////*/

    /// @param _startEpoch The starting epoch of the rewards campaign, must be greater than currentEpoch
    /// @param _endEpoch The epoch at which the reward campaign ends
    /// @param _amount The amount of rewards given out over the course of the campaign
    /// @param _token The token to distributed as a part of the campaign
    function createRewardCampaign(uint256 _startEpoch, uint256 _endEpoch, uint256 _amount, ERC20 _token) public {
        rollOverEpoch();
        if (_startEpoch < currentEpoch) {
            revert CampapignStartsTooLate();
        }

        Reward memory newReward = Reward({ token: _token, amount: _amount, startEpoch: _startEpoch, endEpoch: _endEpoch });

        _token.safeTransferFrom(msg.sender, address(this), _amount);
        maxRewardId++;

        rewards[maxRewardId] = newReward;
    }

    /// @param rewardId The rewardId of the campaign to claim rewards for
    function claimRewards(uint256 rewardId) public {
        rollOverEpoch();
        Reward storage _reward = rewards[rewardId];

        uint256 endEpoch = currentEpoch > _reward.endEpoch ? _reward.endEpoch : currentEpoch;

        uint256 rewardsOwed = 0;
        for (uint256 i = _reward.startEpoch; i < endEpoch;) {
            Epoch memory _epoch = epochs[i];
            uint256 rewardPoints = epochRewardPoints[msg.sender][i];
            rewardsOwed += (_reward.amount * rewardPoints) / _epoch.totalRewards;
            epochRewardPoints[msg.sender][i] = 0;

            unchecked {
                ++i;
            }
        }

        _reward.token.safeTransfer(msg.sender, rewardsOwed);
    }
}
