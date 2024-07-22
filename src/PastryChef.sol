// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import { Owned } from "lib/solmate/src/auth/Owned.sol";
import { ERC20 } from "lib/solmate/src/tokens/ERC20.sol";
import { ERC4626 } from "lib/solmate/src/tokens/ERC4626.sol";
import { EnumerableSetLib } from "lib/solady/src/utils/EnumerableSetLib.sol";
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
contract PastryChef is Owned(msg.sender) {
    using SafeTransferLib for ERC20;
    using SafeTransferLib for ERC4626;

    ERC4626 public depositToken;

    error BalanceTooLow();
    error CampapignStartsTooLate();
    /*//////////////////////////////////////////////////////////////
                               STORAGE
    //////////////////////////////////////////////////////////////*/

    uint256 constant WAD = 1e18;

    struct UserInfo {
        uint256 amount; // How many LP tokens the user has provided.
        uint256 lastEpoch;
        mapping(uint256 epoch => uint256 rewardDebt) epochDebt; // Reward debt. See explanation below.
    }

    struct Epoch {
        uint256 totalDeposited;
        uint256 totalRewards;
        uint256 accRewardsPerShare;
        uint256 lastUpdated;
        uint256 epochEnds;
    }

    mapping(uint256 => Epoch) public epochs;
    uint256 currentEpoch;

    uint256 constant REWARDS_PER_EPOCH = EPOCH_DURATION * REWARD_POINTS_PER_SECOND;
    uint256 constant REWARD_POINTS_PER_SECOND = 50;
    uint256 constant EPOCH_DURATION = 2 weeks;

    mapping(address user => UserInfo info) public userInfo;
    mapping(address user => mapping(uint256 epoch => uint256 rewardPoints)) public epochRewardPoints;

    uint256 public maxRewardId;

    struct Reward {
        ERC20 token;
        uint256 startEpoch;
        uint256 endEpoch;
        uint256 amount;
    }

    mapping(uint256 rewardId => Reward) public rewards;

    /*//////////////////////////////////////////////////////////////
                               KITCHEN
    //////////////////////////////////////////////////////////////*/

    function updateEpochRewards(uint256 epoch) public {
        Epoch storage _epoch = epochs[epoch];

        if (_epoch.lastUpdated >= _epoch.epochEnds) {
            return;
        }

        uint256 lastRewardedSecond = _epoch.epochEnds > block.timestamp ? _epoch.epochEnds : block.timestamp;
        uint256 newRewards = (lastRewardedSecond * REWARD_POINTS_PER_SECOND) / depositToken.balanceOf(address(this));
        _epoch.accRewardsPerShare += newRewards * WAD / _epoch.totalDeposited;
    }

    function rollOverEpoch() public {
        while (epochs[currentEpoch].epochEnds <= block.timestamp) {
            Epoch storage oldEpoch = epochs[currentEpoch];
            currentEpoch++;

            epochs[currentEpoch] = Epoch({
                totalDeposited: oldEpoch.totalDeposited,
                accRewardsPerShare: 0,
                totalRewards: 0,
                lastUpdated: oldEpoch.epochEnds,
                epochEnds: oldEpoch.epochEnds + EPOCH_DURATION
            });

            updateEpochRewards(currentEpoch);
        }
    }

    function deposit(uint256 _amount) public {
        UserInfo storage user = userInfo[msg.sender];
        rollOverEpoch();

        if (user.amount > 0) {
            for (uint256 i = user.lastEpoch; i < currentEpoch; ++i) {
                updateEpochRewards(i);
                Epoch storage _epoch = epochs[i];

                uint256 rewardPointsAwarded = (user.amount * _epoch.accRewardsPerShare / WAD) - user.epochDebt[i];
                epochRewardPoints[msg.sender][i] += rewardPointsAwarded;
                _epoch.totalRewards += rewardPointsAwarded;
            }
        }

        depositToken.safeTransferFrom(msg.sender, address(this), _amount);

        user.amount += _amount;
        user.lastEpoch = currentEpoch;
        user.epochDebt[currentEpoch] = (user.amount * epochs[currentEpoch].accRewardsPerShare) / WAD;

        epochs[currentEpoch].totalDeposited += _amount;
    }

    function withdraw(uint256 _amount) public {
        UserInfo storage user = userInfo[msg.sender];
        if (_amount > user.amount) {
            revert BalanceTooLow();
        }

        rollOverEpoch();

        for (uint256 i = user.lastEpoch; i < currentEpoch; ++i) {
            updateEpochRewards(i);
            Epoch storage _epoch = epochs[i];

            uint256 rewardPointsAwarded = (user.amount * _epoch.accRewardsPerShare / WAD) - user.epochDebt[i];
            epochRewardPoints[msg.sender][i] += rewardPointsAwarded;
            _epoch.totalRewards += rewardPointsAwarded;
        }

        user.amount -= _amount;
        user.epochDebt[currentEpoch] = (user.amount * epochs[currentEpoch].accRewardsPerShare) / WAD;

        epochs[currentEpoch].totalDeposited -= _amount;

        depositToken.safeTransfer(msg.sender, _amount);
    }

    /*//////////////////////////////////////////////////////////////
                         REWARDS CAMPAIGNS
    //////////////////////////////////////////////////////////////*/
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

    function claimRewards(uint256 rewardId) public {
        rollOverEpoch();
        Reward storage _reward = rewards[rewardId];

        uint256 endEpoch = currentEpoch > _reward.endEpoch ? _reward.endEpoch : currentEpoch;

        uint256 rewardsOwed;
        for (uint256 i = _reward.startEpoch; i < endEpoch; i++) {
            Epoch memory _epoch = epochs[i];
            uint256 rewardPoints = epochRewardPoints[msg.sender][i];
            rewardsOwed += (_reward.amount * rewardPoints) / _epoch.totalRewards;
            epochRewardPoints[msg.sender][i] = 0;
        }

        _reward.token.safeTransfer(msg.sender, rewardsOwed);
    }
}
