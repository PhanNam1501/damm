// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IPositionManager
 * @notice Interface for managing user positions in liquidity pools
 */
interface IPositionManager {
    // ==================== Errors ====================
    error PositionNotInitialized();
    error InsufficientLiquidity();
    error InsufficientFees();
    error InvalidPercentage();
    error InvalidRewardIndex();
    error OnlyPoolAllowed();
    
    // ==================== Events ====================
    event PositionCreated(address indexed user, address indexed pool);
    event LiquidityModified(address indexed user, address indexed pool, int128 liquidityDelta);
    event FeesUpdated(address indexed user, address indexed pool, uint128 feeA, uint128 feeB);
    event FeesClaimed(address indexed user, address indexed pool, uint128 feeA, uint128 feeB);
    event RewardsClaimed(address indexed user, address indexed pool, uint256 rewardIndex, uint128 amount);
    
    // ==================== Structs ====================
    struct UserRewardInfo {
        uint256 rewardPerTokenCheckpoint;
        uint128 rewardPendings;
        uint128 totalClaimedRewards;
    }
    
    struct Position {
        uint256 feeAPerTokenCheckpoint;
        uint256 feeBPerTokenCheckpoint;
        uint128 feeAPending;
        uint128 feeBPending;
        uint128 unlockedLiquidity;
        uint128 vestedLiquidity;
        uint128 permanentLockedLiquidity;
        uint128 totalClaimedAFee;
        uint128 totalClaimedBFee;
        UserRewardInfo[2] rewardInfos;  // NUM_REWARDS = 2
        bool initialized;
    }
    
    // ==================== Position Management ====================
    
    /**
     * @notice Initialize a position for a user in a pool
     * @param user User address
     * @param pool Pool address
     * @return success True if successful
     */
    function initializePosition(
        address user,
        address pool
    ) external returns (bool success);
    
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
    ) external;
    
    /**
     * @notice Remove liquidity from user's position
     * @param user User address
     * @param pool Pool address
     * @param liquidityDelta Amount of liquidity to remove
     */
    function removeLiquidity(
        address user,
        address pool,
        uint128 liquidityDelta
    ) external;
    
    /**
     * @notice Get total liquidity for a user's position
     * @param user User address
     * @param pool Pool address
     * @return Total liquidity amount
     */
    function getTotalLiquidity(
        address user,
        address pool
    ) external view returns (uint128);
    
    /**
     * @notice Lock liquidity for vesting
     * @param user User address
     * @param pool Pool address
     * @param lockAmount Amount to lock
     */
    function lockLiquidity(
        address user,
        address pool,
        uint128 lockAmount
    ) external;
    
    /**
     * @notice Release vested liquidity
     * @param user User address
     * @param pool Pool address
     * @param releaseAmount Amount to release
     */
    function releaseVestedLiquidity(
        address user,
        address pool,
        uint128 releaseAmount
    ) external;
    
    // ==================== Fee Management ====================
    
    /**
     * @notice Update fees for a user's position
     * @param user User address
     * @param pool Pool address
     * @param feeAPerTokenStored Fee A per token stored
     * @param feeBPerTokenStored Fee B per token stored
     */
    function updateFees(
        address user,
        address pool,
        uint256 feeAPerTokenStored,
        uint256 feeBPerTokenStored
    ) external;
    
    /**
     * @notice Claim all pending fees
     * @param user User address
     * @param pool Pool address
     * @return feeA Amount of fee A claimed
     * @return feeB Amount of fee B claimed
     */
    function claimFees(
        address user,
        address pool
    ) external returns (uint128 feeA, uint128 feeB);
    
    /**
     * @notice Get claimable fees for a user
     * @param user User address
     * @param pool Pool address
     * @return feeA Claimable fee A
     * @return feeB Claimable fee B
     */
    function getClaimableFees(
        address user,
        address pool
    ) external view returns (uint128 feeA, uint128 feeB);
    
    // ==================== Reward Management ====================
    
    /**
     * @notice Update rewards for a user's position
     * @param user User address
     * @param pool Pool address
     * @param rewardIndex Index of the reward token (0 or 1)
     * @param rewardPerTokenStored Reward per token stored
     */
    function updateRewards(
        address user,
        address pool,
        uint256 rewardIndex,
        uint256 rewardPerTokenStored
    ) external;
    
    /**
     * @notice Claim rewards for a user
     * @param user User address
     * @param pool Pool address
     * @param rewardIndex Index of the reward token (0 or 1)
     * @return Amount of rewards claimed
     */
    function claimReward(
        address user,
        address pool,
        uint256 rewardIndex
    ) external returns (uint128);
    
    // ==================== View Functions ====================
    
    /**
     * @notice Get complete position data
     * @param user User address
     * @param pool Pool address
     * @return Position data
     */
    function getPosition(
        address user,
        address pool
    ) external view returns (Position memory);
    
    /**
     * @notice Check if position is empty
     * @param user User address
     * @param pool Pool address
     * @return True if position is empty
     */
    function isPositionEmpty(
        address user,
        address pool
    ) external view returns (bool);
    
    /**
     * @notice Check if user has position in pool
     * @param user User address
     * @param pool Pool address
     * @return True if user has position
     */
    function hasPosition(
        address user,
        address pool
    ) external view returns (bool);
    
    /**
     * @notice Access position mapping
     * @param user User address
     * @param pool Pool address
     * @return feeAPerTokenCheckpoint Fee A checkpoint
     * @return feeBPerTokenCheckpoint Fee B checkpoint
     * @return feeAPending Pending fee A
     * @return feeBPending Pending fee B
     * @return unlockedLiquidity Unlocked liquidity
     * @return vestedLiquidity Vested liquidity
     * @return permanentLockedLiquidity Permanent locked liquidity
     * @return totalClaimedAFee Total claimed fee A
     * @return totalClaimedBFee Total claimed fee B
     * @return initialized Position initialized flag
     */
    function positions(address user, address pool) external view returns (
        uint256 feeAPerTokenCheckpoint,
        uint256 feeBPerTokenCheckpoint,
        uint128 feeAPending,
        uint128 feeBPending,
        uint128 unlockedLiquidity,
        uint128 vestedLiquidity,
        uint128 permanentLockedLiquidity,
        uint128 totalClaimedAFee,
        uint128 totalClaimedBFee,
        bool initialized
    );
    
    // ==================== Batch Operations ====================
    
    /**
     * @notice Update fees for multiple users
     * @param users Array of user addresses
     * @param pool Pool address
     * @param feeAPerTokenStored Fee A per token stored
     * @param feeBPerTokenStored Fee B per token stored
     */
    function batchUpdateFees(
        address[] calldata users,
        address pool,
        uint256 feeAPerTokenStored,
        uint256 feeBPerTokenStored
    ) external;
}