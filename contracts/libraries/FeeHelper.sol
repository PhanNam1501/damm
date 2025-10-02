// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title FeeHelper
 * @notice Fee management library compatible with Uniswap V3 data types
 * @dev Uses X96 for prices, raw uint128 for liquidity, 1e18 for fee rates
 */

import {SafeCast} from "./SafeCast.sol";

library FeeHelper {
    // Constants
    using SafeCast for uint256 ;
    uint256 internal constant FEE_PRECISION = 1e18;  // 1e18 = 100%
    uint256 internal constant MAX_FEE_RATE = 1e17;   // 10% max fee
    uint256 internal constant BASIS_POINT_MAX = 10_000;
    uint256 internal constant Q96 = 2**96;
    uint256 internal constant Q128 = 2**128;

    // Errors
    error InvalidFeeSchedulerMode();
    error InvalidCollectFeeMode();
    error FeeTooHigh();

    // Enums
    enum FeeSchedulerMode {
        Linear,
        Exponential
    }

    enum CollectFeeMode {
        BothToken,
        OnlyB
    }

    enum TradeDirection {
        AtoB,
        BtoA
    }

    // Structs
    struct FeeOnAmountResult {
        uint256 amount;       // Amount after fees
        uint128 lpFee;        // LP fee amount
        uint128 protocolFee;  // Protocol fee amount
        uint128 partnerFee;   // Partner fee amount
        uint128 referralFee;  // Referral fee amount
    }

    struct PoolFeesStruct {
        BaseFeeStruct baseFee;
        uint8 protocolFeePercent;
        uint8 partnerFeePercent;
        uint8 referralFeePercent;
        DynamicFeeStruct dynamicFee;
    }

    struct BaseFeeStruct {
        uint24 cliffFeeRate;              // Fee rate in units of 1e-6 (like Uniswap V3)
        FeeSchedulerMode feeSchedulerMode;
        uint16 numberOfPeriod;
        uint64 periodFrequency;
        uint24 reductionFactor;           // In units of 1e-6
    }

    struct DynamicFeeStruct {
        bool initialized;
        uint32 maxVolatilityAccumulator;
        uint32 variableFeeControl;
        uint16 binStep;
        uint16 filterPeriod;
        uint16 decayPeriod;
        uint16 reductionFactor;
        uint64 lastUpdateTimestamp;
        uint160 sqrtPriceReferenceX96;   // X96 format
        uint128 volatilityAccumulator;
        uint128 volatilityReference;
    }

    /**
     * @notice Get total trading fee rate
     * @return Fee rate in 1e18 precision (1e18 = 100%)
     */
    function getTotalTradingFee(
        PoolFeesStruct memory fees,
        uint64 currentTimestamp,
        uint64 activationTimestamp
    ) internal pure returns (uint256) {
        uint256 baseFeeRate = getCurrentBaseFeeRate(
            fees.baseFee,
            currentTimestamp,
            activationTimestamp
        );
        
        uint256 variableFeeRate = getVariableFeeRate(fees.dynamicFee);
        
        uint256 totalFeeRate = baseFeeRate + variableFeeRate;
        
        // Cap at max fee
        if (totalFeeRate > MAX_FEE_RATE) {
            return MAX_FEE_RATE;
        }
        
        return totalFeeRate;
    }

    /**
     * @notice Get current base fee rate
     * @return Fee rate in 1e18 precision
     */
    function getCurrentBaseFeeRate(
        BaseFeeStruct memory baseFee,
        uint64 currentTimestamp,
        uint64 activationTimestamp
    ) internal pure returns (uint256) {
        // Convert from 1e-6 to 1e18 precision
        uint256 cliffFeeRate = uint256(baseFee.cliffFeeRate) * 1e12;
        
        if (baseFee.periodFrequency == 0) {
            return cliffFeeRate;
        }
        
        uint64 period;
        if (currentTimestamp < activationTimestamp) {
            period = baseFee.numberOfPeriod;
        } else {
            period = (currentTimestamp - activationTimestamp) / baseFee.periodFrequency;
            if (period > baseFee.numberOfPeriod) {
                period = baseFee.numberOfPeriod;
            }
        }
        
        if (baseFee.feeSchedulerMode == FeeSchedulerMode.Linear) {
            uint256 reduction = uint256(period) * uint256(baseFee.reductionFactor) * 1e12;
            if (reduction >= cliffFeeRate) {
                return 0;
            }
            return cliffFeeRate - reduction;
        } else {
            return calculateExponentialFeeRate(
                baseFee.cliffFeeRate,
                baseFee.reductionFactor,
                uint16(period)
            );
        }
    }

    /**
     * @notice Calculate exponential fee rate
     */
    function calculateExponentialFeeRate(
        uint24 cliffFeeRate,
        uint24 reductionFactor,
        uint16 periods
    ) internal pure returns (uint256) {
        if (periods == 0) {
            return uint256(cliffFeeRate) * 1e12;
        }
        
        uint256 fee = uint256(cliffFeeRate);
        uint256 multiplier = 1e6 - uint256(reductionFactor);
        
        for (uint16 i = 0; i < periods; i++) {
            fee = (fee * multiplier) / 1e6;
        }
        
        return fee * 1e12; // Convert to 1e18 precision
    }

    /**
     * @notice Get variable fee rate based on volatility
     * @return Fee rate in 1e18 precision
     */
    function getVariableFeeRate(DynamicFeeStruct memory dynamicFee) internal pure returns (uint256) {
        if (!dynamicFee.initialized) {
            return 0;
        }
        
        // Calculate variable fee based on volatility
        uint256 squareVfa = uint256(dynamicFee.volatilityAccumulator) * uint256(dynamicFee.binStep);
        squareVfa = squareVfa * squareVfa;
        
        uint256 vFee = squareVfa * uint256(dynamicFee.variableFeeControl);
        
        // Scale to 1e18 precision
        return (vFee * 1e18) / (BASIS_POINT_MAX * BASIS_POINT_MAX * BASIS_POINT_MAX);
    }

    /**
     * @notice Calculate fees on amount
     */
    function getFeeOnAmount(
        PoolFeesStruct memory fees,
        uint256 amount,
        bool hasReferral,
        uint64 currentTimestamp,
        uint64 activationTimestamp,
        bool hasPartner
    ) internal pure returns (FeeOnAmountResult memory result) {
        uint256 feeRate = getTotalTradingFee(fees, currentTimestamp, activationTimestamp);
        
        // Calculate LP fee
        uint128 lpFee = ((amount * feeRate) / FEE_PRECISION).safe128();
        
        result.amount = amount - lpFee;
        
        // Calculate protocol fee
        uint128 protocolFee = (lpFee * fees.protocolFeePercent) / 100;
        
        result.lpFee = lpFee - protocolFee;
        
        // Calculate referral fee
        if (hasReferral) {
            result.referralFee = (protocolFee * fees.referralFeePercent) / 100;
        }
        
        uint128 protocolFeeAfterReferral = protocolFee - result.referralFee;
        
        // Calculate partner fee
        if (hasPartner && fees.partnerFeePercent > 0) {
            result.partnerFee = (protocolFeeAfterReferral * fees.partnerFeePercent) / 100;
        }
        
        result.protocolFee = protocolFeeAfterReferral - result.partnerFee;
        
        return result;
    }

    /**
     * @notice Update volatility accumulator based on price movement
     */
    function updateVolatilityAccumulator(
        DynamicFeeStruct memory dynamicFee,
        uint16 binStep,
        uint160 sqrtPriceX96
    ) internal pure returns (uint128) {
        uint256 priceDelta = getDeltaBinIdComplete(
            binStep,
            sqrtPriceX96,
            dynamicFee.sqrtPriceReferenceX96
        );
        
        uint256 volatilityAccumulator = uint256(dynamicFee.volatilityReference) + 
                                        (priceDelta * BASIS_POINT_MAX) / Q96;
        
        if (volatilityAccumulator > dynamicFee.maxVolatilityAccumulator) {
            return dynamicFee.maxVolatilityAccumulator;
        }
        
        return uint128(volatilityAccumulator);
    }

    /**
    * @notice Calculate delta bin ID between two sqrt prices
    * @dev Matches Rust's get_delta_bin_id logic
    * @param binStepX96 Bin step in X96 format (similar to bin_step_u128 but for X96)
    * @param sqrtPriceAX96 First sqrt price in X96
    * @param sqrtPriceBX96 Second sqrt price in X96
    * @return deltaBinId The delta bin ID
    */
    function getDeltaBinId(
        uint256 binStepX96,
        uint160 sqrtPriceAX96,
        uint160 sqrtPriceBX96
    ) internal pure returns (uint256) {
        // Get upper and lower prices
        uint256 upperSqrtPrice = sqrtPriceAX96 > sqrtPriceBX96 ? sqrtPriceAX96 : sqrtPriceBX96;
        uint256 lowerSqrtPrice = sqrtPriceAX96 > sqrtPriceBX96 ? sqrtPriceBX96 : sqrtPriceAX96;
        
        if (lowerSqrtPrice == 0) return 0;
        
        // Calculate price ratio with X96 precision
        // Rust uses Q64, we use Q96, so formula is:
        // priceRatio = (upperSqrtPrice * 2^96) / lowerSqrtPrice
        uint256 priceRatio = (upperSqrtPrice << 96) / lowerSqrtPrice;
        
        // Subtract 1 (in Q96 format)
        if (priceRatio <= Q96) return 0;
        
        uint256 priceDelta = priceRatio - Q96;
        
        // Divide by bin step to get bin count
        uint256 deltaBinId = priceDelta / binStepX96;
        
        // Multiply by 2 (matching Rust logic)
        return deltaBinId * 2;
    }

    /**
    * @notice Alternative: If you need to convert bin step from basis points to X96
    * @param binStep Bin step in basis points (e.g., 1 = 0.01%)
    * @return binStepX96 Bin step in X96 format
    */
    function binStepToX96(uint16 binStep) internal pure returns (uint256) {
        // binStep is in basis points (1 = 0.01% = 0.0001)
        // Convert to X96: (1 + binStep/10000) * 2^96
        // Approximation for small values: 2^96 * (1 + binStep/10000) ≈ 2^96 + (2^96 * binStep / 10000)
        return Q96 + (Q96 * binStep / 10000);
    }

    /**
    * @notice Complete implementation matching Rust logic
    */
    function getDeltaBinIdComplete(
        uint16 binStep, // Bin step in basis points
        uint160 sqrtPriceAX96,
        uint160 sqrtPriceBX96
    ) internal pure returns (uint256) {
        uint256 binStepX96 = binStepToX96(binStep);
        return getDeltaBinId(binStepX96, sqrtPriceAX96, sqrtPriceBX96);
    }

    /**
     * @notice Update volatility references
     */
    function updateReferences(
        DynamicFeeStruct memory dynamicFee,
        uint160 sqrtPriceX96,
        uint64 currentTimestamp
    ) internal pure returns (DynamicFeeStruct memory) {
        uint64 elapsed = currentTimestamp - dynamicFee.lastUpdateTimestamp;
        
        if (elapsed >= dynamicFee.filterPeriod) {
            dynamicFee.sqrtPriceReferenceX96 = sqrtPriceX96;
            
            if (elapsed < dynamicFee.decayPeriod) {
                dynamicFee.volatilityReference = uint128(
                    (uint256(dynamicFee.volatilityAccumulator) * uint256(dynamicFee.reductionFactor)) / 
                    BASIS_POINT_MAX
                );
            } else {
                dynamicFee.volatilityReference = 0;
            }
            
            dynamicFee.lastUpdateTimestamp = currentTimestamp;
        }
        
        return dynamicFee;
    }
}