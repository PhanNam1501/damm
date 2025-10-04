// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title Vesting
 * @notice Library for managing vesting schedules with cliff and periodic unlocks
 * @dev Zero-copy inspired structure optimized for storage
 */
library VestingHelper {
    struct Vesting {
        uint64 cliffPoint;            // 8 bytes
        uint64 periodFrequency;       // 8 bytes
        uint128 cliffUnlockLiquidity; // 16 bytes
        uint128 liquidityPerPeriod;   // 16 bytes
        uint128 totalReleasedLiquidity; // 16 bytes
        uint16 numberOfPeriod;        // 2 bytes
        // padding: 14 bytes (Solidity handles this automatically)
        // Total: ~176 bytes aligned
    }

    // Custom errors for gas optimization
    error ArithmeticOverflow();
    error ArithmeticUnderflow();
    error DivisionByZero();
    error VestingNotComplete();
    error CliffNotReached();

    /**
     * @notice Initialize a new vesting schedule
     * @param self The vesting struct to initialize
     * @param cliffPoint Timestamp when cliff period ends
     * @param periodFrequency Duration of each vesting period
     * @param cliffUnlockLiquidity Amount unlocked at cliff
     * @param liquidityPerPeriod Amount unlocked per period
     * @param numberOfPeriod Total number of vesting periods
     */
    function initialize(
        Vesting storage self,
        uint64 cliffPoint,
        uint64 periodFrequency,
        uint128 cliffUnlockLiquidity,
        uint128 liquidityPerPeriod,
        uint16 numberOfPeriod
    ) internal {
        self.cliffPoint = cliffPoint;
        self.periodFrequency = periodFrequency;
        self.cliffUnlockLiquidity = cliffUnlockLiquidity;
        self.liquidityPerPeriod = liquidityPerPeriod;
        self.numberOfPeriod = numberOfPeriod;
        self.totalReleasedLiquidity = 0;
    }

    /**
     * @notice Calculate total locked amount
     * @param self The vesting struct
     * @return Total amount locked in vesting schedule
     */
    function getTotalLockAmount(Vesting storage self) 
        internal 
        view 
        returns (uint128) 
    {
        return safeAdd128(
            self.cliffUnlockLiquidity,
            safeMul128(self.liquidityPerPeriod, uint128(self.numberOfPeriod))
        );
    }

    /**
     * @notice Calculate maximum unlocked liquidity at current point
     * @param self The vesting struct
     * @param currentPoint Current timestamp
     * @return Maximum amount that can be unlocked
     */
    function getMaxUnlockedLiquidity(
        Vesting storage self,
        uint64 currentPoint
    ) internal view returns (uint128) {
        // Before cliff, nothing is unlocked
        if (currentPoint < self.cliffPoint) {
            return 0;
        }

        // If no periodic vesting, only cliff unlock
        if (self.periodFrequency == 0) {
            return self.cliffUnlockLiquidity;
        }

        // Calculate number of completed periods
        uint64 timeSinceCliff = safeSub64(currentPoint, self.cliffPoint);
        uint64 completedPeriods = timeSinceCliff / self.periodFrequency;
        
        // Cap at maximum number of periods
        if (completedPeriods > self.numberOfPeriod) {
            completedPeriods = self.numberOfPeriod;
        }

        // Calculate total unlocked
        uint128 periodicUnlock = safeMul128(
            self.liquidityPerPeriod,
            uint128(completedPeriods)
        );
        
        return safeAdd128(self.cliffUnlockLiquidity, periodicUnlock);
    }

    /**
     * @notice Calculate new releasable liquidity
     * @param self The vesting struct
     * @param currentPoint Current timestamp
     * @return Amount of new liquidity available to release
     */
    function getNewReleaseLiquidity(
        Vesting storage self,
        uint64 currentPoint
    ) internal view returns (uint128) {
        uint128 unlockedLiquidity = getMaxUnlockedLiquidity(self, currentPoint);
        return safeSub128(unlockedLiquidity, self.totalReleasedLiquidity);
    }

    /**
     * @notice Accumulate released liquidity
     * @param self The vesting struct
     * @param releasedLiquidity Amount being released
     */
    function accumulateReleasedLiquidity(
        Vesting storage self,
        uint128 releasedLiquidity
    ) internal {
        self.totalReleasedLiquidity = safeAdd128(
            self.totalReleasedLiquidity,
            releasedLiquidity
        );
    }

    /**
     * @notice Check if vesting is complete
     * @param self The vesting struct
     * @return true if all tokens have been released
     */
    function isDone(Vesting storage self) internal view returns (bool) {
        return self.totalReleasedLiquidity == getTotalLockAmount(self);
    }

    /**
     * @notice Get remaining locked liquidity
     * @param self The vesting struct
     * @return Amount still locked
     */
    function getRemainingLocked(Vesting storage self) 
        internal 
        view 
        returns (uint128) 
    {
        return safeSub128(getTotalLockAmount(self), self.totalReleasedLiquidity);
    }

    /**
     * @notice Get vesting progress percentage (in basis points, 10000 = 100%)
     * @param self The vesting struct
     * @return Progress in basis points
     */
    function getProgressBps(Vesting storage self) 
        internal 
        view 
        returns (uint256) 
    {
        uint128 total = getTotalLockAmount(self);
        if (total == 0) return 0;
        
        return (uint256(self.totalReleasedLiquidity) * 10000) / uint256(total);
    }

    // ========== Safe Math Functions ==========

    function safeAdd128(uint128 a, uint128 b) private pure returns (uint128) {
        uint128 c = a + b;
        if (c < a) revert ArithmeticOverflow();
        return c;
    }

    function safeSub128(uint128 a, uint128 b) private pure returns (uint128) {
        if (b > a) revert ArithmeticUnderflow();
        return a - b;
    }

    function safeMul128(uint128 a, uint128 b) private pure returns (uint128) {
        if (a == 0) return 0;
        uint256 c = uint256(a) * uint256(b);
        if (c > type(uint128).max) revert ArithmeticOverflow();
        return uint128(c);
    }

    function safeSub64(uint64 a, uint64 b) private pure returns (uint64) {
        if (b > a) revert ArithmeticUnderflow();
        return a - b;
    }
}