// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title PositionManager
 * @notice Manages user positions - one position per user per pool
 */

import { IPositionManager } from "./interfaces/IPositionManager.sol";

contract PositionManager is IPositionManager {
    // Constants
    uint256 constant LIQUIDITY_SCALE = 1e18;
    uint256 constant TOTAL_REWARD_SCALE = 1e18;
    uint256 constant NUM_REWARDS = 2;
    
    // State: user => pool => position
    mapping(address => mapping(address => Position)) public positions;
    
    // Modifiers
    modifier onlyInitialized(address user, address pool) {
        require(positions[user][pool].initialized, "Position not initialized");
        _;
    }
    
    // ==================== Position Creation ====================
    
    /**
     * @notice Create or get position for user in a pool
     * @param user User address
     * @param pool Pool address
     */
    function initializePosition(
        address user,
        address pool
    ) external returns (bool) {
        Position storage position = positions[user][pool];
        
        if (!position.initialized) {
            position.initialized = true;
            emit PositionCreated(user, pool);
        }
        
        return true;
    }
    
    // ==================== Liquidity Management ====================
    
    /**
     * @notice Add liquidity to user's position
     * @param user User address
     * @param pool Pool address
     * @param liquidityDelta Amount of liquidity to add
     */
    function addLiquidity(
        address user,
        address pool,
        uint128 liquidityDelta
    ) external {
        Position storage position = positions[user][pool];
        
        // Auto-initialize if needed
        if (!position.initialized) {
            position.initialized = true;
            emit PositionCreated(user, pool);
        }
        
        position.unlockedLiquidity += liquidityDelta;
        emit LiquidityModified(user, pool, int128(liquidityDelta));
    }
    
    /**
     * @notice Remove liquidity from user's position
     */
    function removeLiquidity(
        address user,
        address pool,
        uint128 liquidityDelta
    ) external onlyInitialized(user, pool) {
        Position storage position = positions[user][pool];
        
        require(position.unlockedLiquidity >= liquidityDelta, "Insufficient liquidity");
        
        position.unlockedLiquidity -= liquidityDelta;
        emit LiquidityModified(user, pool, -int128(liquidityDelta));
    }
    
    /**
     * @notice Get total liquidity for a user's position
     */
    function getTotalLiquidity(
        address user,
        address pool
    ) public view returns (uint128) {
        Position storage position = positions[user][pool];
        return position.unlockedLiquidity + 
               position.vestedLiquidity + 
               position.permanentLockedLiquidity;
    }
    
    /**
     * @notice Lock liquidity for vesting
     */
    function lockLiquidity(
        address user,
        address pool,
        uint128 lockAmount
    ) external onlyInitialized(user, pool) {
        Position storage position = positions[user][pool];
        
        require(position.unlockedLiquidity >= lockAmount, "Insufficient unlocked liquidity");
        
        position.unlockedLiquidity -= lockAmount;
        position.vestedLiquidity += lockAmount;
    }
    
    /**
     * @notice Release vested liquidity
     */
    function releaseVestedLiquidity(
        address user,
        address pool,
        uint128 releaseAmount
    ) external onlyInitialized(user, pool) {
        Position storage position = positions[user][pool];
        
        require(position.vestedLiquidity >= releaseAmount, "Insufficient vested liquidity");
        
        position.vestedLiquidity -= releaseAmount;
        position.unlockedLiquidity += releaseAmount;
    }
    
    // ==================== Fee Management ====================
    
    /**
     * @notice Update fees for a user's position (called by pool)
     */
    function updateFees(
        address user,
        address pool,
        uint256 feeAPerTokenStored,
        uint256 feeBPerTokenStored
    ) external {
        Position storage position = positions[user][pool];
        
        if (!position.initialized) return; // Skip if no position
        
        uint128 liquidity = getTotalLiquidity(user, pool);
        
        if (liquidity > 0) {
            // Calculate and accumulate fee A
            if (feeAPerTokenStored > position.feeAPerTokenCheckpoint) {
                uint256 deltaFeeA = feeAPerTokenStored - position.feeAPerTokenCheckpoint;
                uint128 newFeeA = uint128((uint256(liquidity) * deltaFeeA) / LIQUIDITY_SCALE);
                position.feeAPending += newFeeA;
            }
            
            // Calculate and accumulate fee B
            if (feeBPerTokenStored > position.feeBPerTokenCheckpoint) {
                uint256 deltaFeeB = feeBPerTokenStored - position.feeBPerTokenCheckpoint;
                uint128 newFeeB = uint128((uint256(liquidity) * deltaFeeB) / LIQUIDITY_SCALE);
                position.feeBPending += newFeeB;
            }
        }
        
        position.feeAPerTokenCheckpoint = feeAPerTokenStored;
        position.feeBPerTokenCheckpoint = feeBPerTokenStored;
        
        emit FeesUpdated(user, pool, position.feeAPending, position.feeBPending);
    }
    
    /**
     * @notice Claim all pending fees
     */
    function claimFees(
        address user,
        address pool
    ) external onlyInitialized(user, pool) returns (uint128 feeA, uint128 feeB) {
        Position storage position = positions[user][pool];
        
        feeA = position.feeAPending;
        feeB = position.feeBPending;
        
        if (feeA > 0 || feeB > 0) {
            position.totalClaimedAFee += feeA;
            position.totalClaimedBFee += feeB;
            
            position.feeAPending = 0;
            position.feeBPending = 0;
            
            emit FeesClaimed(user, pool, feeA, feeB);
        }
        
        return (feeA, feeB);
    }
    
    /**
     * @notice Get claimable fees for a user
     */
    function getClaimableFees(
        address user,
        address pool
    ) external view returns (uint128 feeA, uint128 feeB) {
        Position storage position = positions[user][pool];
        return (position.feeAPending, position.feeBPending);
    }
    
    // ==================== Reward Management ====================
    
    /**
     * @notice Update rewards for a user's position (called by pool)
     */
    function updateRewards(
        address user,
        address pool,
        uint256 rewardIndex,
        uint256 rewardPerTokenStored
    ) external {
        require(rewardIndex < NUM_REWARDS, "Invalid reward index");
        
        Position storage position = positions[user][pool];
        if (!position.initialized) return;
        
        uint128 liquidity = getTotalLiquidity(user, pool);
        if (liquidity == 0) return;
        
        UserRewardInfo storage rewardInfo = position.rewardInfos[rewardIndex];
        
        if (rewardPerTokenStored > rewardInfo.rewardPerTokenCheckpoint) {
            uint256 deltaReward = rewardPerTokenStored - rewardInfo.rewardPerTokenCheckpoint;
            uint128 newReward = uint128((uint256(liquidity) * deltaReward) / TOTAL_REWARD_SCALE);
            
            rewardInfo.rewardPendings += newReward;
            rewardInfo.rewardPerTokenCheckpoint = rewardPerTokenStored;
        }
    }
    
    /**
     * @notice Claim rewards for a user
     */
    function claimReward(
        address user,
        address pool,
        uint256 rewardIndex
    ) external onlyInitialized(user, pool) returns (uint128) {
        require(rewardIndex < NUM_REWARDS, "Invalid reward index");
        
        Position storage position = positions[user][pool];
        UserRewardInfo storage rewardInfo = position.rewardInfos[rewardIndex];
        
        uint128 reward = rewardInfo.rewardPendings;
        
        if (reward > 0) {
            rewardInfo.totalClaimedRewards += reward;
            rewardInfo.rewardPendings = 0;
            
            emit RewardsClaimed(user, pool, rewardIndex, reward);
        }
        
        return reward;
    }
    
    // ==================== View Functions ====================
    
    /**
     * @notice Get complete position data
     */
    function getPosition(
        address user,
        address pool
    ) external view returns (Position memory) {
        return positions[user][pool];
    }
    
    /**
     * @notice Check if position is empty
     */
    function isPositionEmpty(
        address user,
        address pool
    ) external view returns (bool) {
        Position storage position = positions[user][pool];
        
        if (!position.initialized) return true;
        
        // Check if has any liquidity
        if (getTotalLiquidity(user, pool) > 0) return false;
        
        // Check if has pending fees
        if (position.feeAPending > 0 || position.feeBPending > 0) return false;
        
        // Check if has pending rewards
        for (uint i = 0; i < NUM_REWARDS; i++) {
            if (position.rewardInfos[i].rewardPendings > 0) return false;
        }
        
        return true;
    }
    
    /**
     * @notice Check if user has position in pool
     */
    function hasPosition(
        address user,
        address pool
    ) external view returns (bool) {
        return positions[user][pool].initialized;
    }
    
    // ==================== Batch Operations ====================
    
    /**
     * @notice Update fees for multiple users (gas optimization)
     */
    function batchUpdateFees(
        address[] calldata users,
        address pool,
        uint256 feeAPerTokenStored,
        uint256 feeBPerTokenStored
    ) external {
        for (uint i = 0; i < users.length; i++) {
            Position storage position = positions[users[i]][pool];
            if (!position.initialized) continue;
            
            uint128 liquidity = getTotalLiquidity(users[i], pool);
            if (liquidity == 0) continue;
            
            // Update fee A
            if (feeAPerTokenStored > position.feeAPerTokenCheckpoint) {
                uint256 deltaFeeA = feeAPerTokenStored - position.feeAPerTokenCheckpoint;
                position.feeAPending += uint128((uint256(liquidity) * deltaFeeA) / LIQUIDITY_SCALE);
            }
            
            // Update fee B  
            if (feeBPerTokenStored > position.feeBPerTokenCheckpoint) {
                uint256 deltaFeeB = feeBPerTokenStored - position.feeBPerTokenCheckpoint;
                position.feeBPending += uint128((uint256(liquidity) * deltaFeeB) / LIQUIDITY_SCALE);
            }
            
            position.feeAPerTokenCheckpoint = feeAPerTokenStored;
            position.feeBPerTokenCheckpoint = feeBPerTokenStored;
        }
    }
}