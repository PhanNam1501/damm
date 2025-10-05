// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {SafeCast} from './libraries/SafeCast.sol';
import {SafeMath} from './libraries/math/SafeMath.sol';
import {Uint256x256Math} from './libraries/math/Uint256x256Math.sol';
contract Rewarder {
    using SafeCast for uint256;
    using SafeMath for uint256;
    using Uint256x256Math for uint256; 

    struct RewardInfo {
        bool initialized;
        address funder;
        address token;
        address vault;
        uint64 rewardDuration;
        uint64 rewardDurationEnd;
        uint256 rewardRate; //Q128.128
        uint256 rewardPerTokenStored;
        uint64 lastUpdateTime;
        uint64 cummulativeSecondsWithEmptyLiquidityReward;
    }
    uint256 public constant NUM_REWARDS = 2;
    RewardInfo[] public rewardInfos;

    function initialized(
        uint256 index
    ) internal view returns (bool) {
        if (index >= rewardInfos.length) {
            return false;
        }
        return rewardInfos[index].initialized;
    }

    function isValidFunder(
        uint256 index,
        address funder
    ) internal view returns (bool) {
        if (index >= rewardInfos.length) {
            return false;
        }
        return funder == rewardInfos[index].funder;
    }

    function addReward(
        address token,
        address funder,
        address vault,
        uint64 rewardDuration
    ) internal {
        require(rewardInfos.length < NUM_REWARDS, "Rewards are full");
        rewardInfos[rewardInfos.length].initialized = true;
        rewardInfos[rewardInfos.length].token = token;
        rewardInfos[rewardInfos.length].funder = funder;
        rewardInfos[rewardInfos.length].vault = vault;
        rewardInfos[rewardInfos.length].rewardDuration = rewardDuration;
    }

    function updateLastUpdateTime(
        uint256 index,
        uint64 currentTime
    ) internal {
        require(index < rewardInfos.length, "Index is over");
        rewardInfos[index].lastUpdateTime = currentTime < rewardInfos[index].rewardDurationEnd ? currentTime : rewardInfos[index].rewardDurationEnd;
    }

    function getSecondsElapsedSinceLastUpdate(
        uint256 index,
        uint64 currentTime
    ) internal view returns (uint64 timePeriod) {
        require(index < rewardInfos.length, "Index is over");
        uint64 lastTimeRewardApplicable = currentTime < rewardInfos[index].rewardDurationEnd ? currentTime : rewardInfos[index].rewardDurationEnd;
        timePeriod = lastTimeRewardApplicable - rewardInfos[index].lastUpdateTime;
    }

    function calculateRewardPerTokenStoredSinceLastUpdate(
        uint256 index,
        uint64 currentTime,
        uint128 liquiditySupply
    ) internal view returns (uint256 rewardPerTokenStored) {
        require(index < rewardInfos.length, "Index is over");
        uint128 timePeriod = uint128(getSecondsElapsedSinceLastUpdate(index, currentTime));
        uint256 totalReward = uint256(timePeriod).mul(rewardInfos[index].rewardRate);

        rewardPerTokenStored = totalReward.div(uint256(liquiditySupply));
    }

    function accumulateRewardPerTokenStored(
        uint256 index,
        uint256 delta
    ) internal {
        require(index < rewardInfos.length, "Index is over");
        rewardInfos[index].rewardPerTokenStored += delta;
    }

    function updateRewards(
        uint64 currentTime,
        uint128 liquiditySupply
    ) internal {
        for (uint256 i = 0; i < rewardInfos.length; i++) {
            updateReward(i, liquiditySupply, currentTime);
        }
    }

    function updateReward(
        uint256 index,
        uint128 liquiditySupply,
        uint64 currentTime
    ) private {
        require(index < rewardInfos.length, "Index is over");
        if (rewardInfos[index].initialized) {
            if (liquiditySupply > 0) {
                uint256 rewardPerTokenStoredDelta = calculateRewardPerTokenStoredSinceLastUpdate(index, currentTime, liquiditySupply);
                accumulateRewardPerTokenStored(index, rewardPerTokenStoredDelta);
            } else {
                uint64 timePeriod = getSecondsElapsedSinceLastUpdate(index, currentTime);

                rewardInfos[index].cummulativeSecondsWithEmptyLiquidityReward += timePeriod;
            }

            updateLastUpdateTime(index, currentTime);
        }
    }

    function updateRateAfterFunding(
        uint256 index,
        uint64 currentTime,
        uint128 fundingAmount
    ) internal {
        require(index < rewardInfos.length, "Index is over");
        uint64 rewardDurationEnd = rewardInfos[index].rewardDurationEnd;
        uint128 totalAmount;

        if (currentTime >= rewardDurationEnd) {
            totalAmount = fundingAmount;
        } else {
            uint64 remainingSeconds = rewardDurationEnd - currentTime;
            uint128 leftOver = (rewardInfos[index].rewardRate.mul(uint256(remainingSeconds)) >> 128).safe128();

            totalAmount = fundingAmount + leftOver;
        }

        rewardInfos[index].rewardRate = uint256(totalAmount).mulShiftRoundDown(uint256(rewardInfos[index].rewardDuration), 128);
        rewardInfos[index].lastUpdateTime = currentTime;
        rewardInfos[index].rewardDurationEnd = currentTime + rewardInfos[index].rewardDuration;
    }
    
}