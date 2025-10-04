// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import './interfaces/IUniswapV2Pair.sol';
import './UniswapV2ERC20.sol';
import './libraries/math/Math.sol';
import './libraries/math/UQ112x112.sol';
import { Curve } from './libraries/Curve.sol';
import { FeeHelper } from './libraries/FeeHelper.sol';
import { VestingHelper } from './libraries/VestingHelper.sol';
import { Constants} from './libraries/Constants.sol';
import { SafeCast } from './libraries/SafeCast.sol';
import { IERC20 } from './interfaces/IERC20.sol';
import './interfaces/IUniswapV2Factory.sol';
import './interfaces/IUniswapV2Callee.sol';
import { IActivationHandler } from './interfaces/IActivationHandler.sol';
import { IPositionManager } from './interfaces/IPositionManager.sol';
import { IUniswapV3MintCallback } from './interfaces/IUniswapV3MintCallback.sol';
import { IUniswapV3SwapCallback } from './interfaces/IUniswapV3SwapCallback.sol';

contract UniswapV2Pair is IUniswapV2Pair, UniswapV2ERC20 {
    using SafeMath for uint256;
    using SafeCast for uint256;
    using UQ112x112 for uint224;
    using Curve for uint160;  
    using FeeHelper for FeeHelper.PoolFeesStruct;
    using FeeHelper for FeeHelper.BaseFeeStruct;
    using FeeHelper for FeeHelper.DynamicFeeStruct;
    using VestingHelper for VestingHelper.Vesting;
    using FeeHelper for uint16;

    // uint public constant MINIMUM_LIQUIDITY = 10**3;
    bytes4 private constant SELECTOR = bytes4(keccak256(bytes('transfer(address,uint256)')));

    address public factory;
    address public token0;
    address public token1;

    // Reserves using uint128 for concentrated liquidity consistency
    uint128 private reserve0;
    uint128 private reserve1;
    uint32 private blockTimestampLast;

    // Concentrated liquidity state using Q64.96 (uint256)
    uint160 public sqrtMinPrice;    
    uint160 public sqrtMaxPrice;     
    uint160 public sqrtPrice;       
    
    // Fee accumulation
    uint256 private feeGrowthGlobal0;
    uint256 private feeGrowthGlobal1;
    uint128 private protocolFeeA;
    uint128 private protocolFeeB;
    uint128 private partnerAFee;
    uint128 private partnerBFee;
    uint256 private feeAPerLiquidity; //Q128
    uint256 private feeBPerLiquidity; //Q128
    uint128 private lpAFee; 
    uint128 private lpBFee;
    uint64 activationPoint;
    
    // Oracle
    uint public price0CumulativeLast;
    uint public price1CumulativeLast;
    uint public kLast;

    uint private unlocked = 1;

    FeeHelper.PoolFeesStruct private poolFees;
    // VestingHelper.Vesting private vesting;
    mapping(address => VestingHelper.Vesting) private vesting;
    // FeeHelper.BaseFeeStruct private baseFees;
    // FeeHelper.DynamicFeeStruct private dynamicFees;

    IActivationHandler private activationHandler;
    IPositionManager private positionManager;

    address partner;

    
    modifier lock() {
        require(unlocked == 1, 'UniswapV2: LOCKED');
        unlocked = 0;
        _;
        unlocked = 1;
    }

    event Mint(address indexed sender, uint amount0, uint amount1);
    event Burn(address indexed sender, uint amount0, uint amount1, address indexed to);
    event Swap(
        address indexed sender,
        uint amount0In,
        uint amount1In,
        uint amount0Out,
        uint amount1Out,
        address indexed to
    );
    event Sync(uint112 reserve0, uint112 reserve1);

    constructor(IActivationHandler _activation, IPositionManager _positionManager, address _token0, address _token1) {
        factory = msg.sender;
        positionManager = _positionManager;
        activationHandler = _activation;
        token0 = _token0;
        token1 = _token1;
    }

    // Initialize with concentrated liquidity
    function initialize(
        uint160 _sqrtPriceMin, 
        uint160 _sqrtPriceMax,    
        uint160 _sqrtPrice,
        uint128 _liquidity,
        address recipient,
        FeeHelper.PoolFeesStruct memory feeConfigs    
    ) external {
        require(msg.sender == factory, 'UniswapV2: FORBIDDEN');
        // Initialize concentrated liquidity parameters in Q128.128
        require(_sqrtPrice >= _sqrtMinPrice && _sqrtPrice <= _sqrtMaxPrice, "InvalidPriceRange");
        sqrtMaxPrice = _sqrtPriceMax;
        sqrtMinPrice = _sqrtPriceMin;
        sqrtPrice = _sqrtPrice;        
        totalSupply = _liquidity;
        (uint256 amountA, uint256 amountB) = getInitializedAmount(_sqrtMinPrice, _sqrtMaxPrice, _sqrtPrice, _liquidity);
        require(amountA > 0 || amountB > 0, "AmountIsZero");

        if (amountA > 0) {
            _safeTransfer(token0, address(this), amountA);
            reserve0 += amountA.safe128();
        }
        if (amountB > 0) {
            _safeTransfer(token1, address(this), amountB);
            reserve1 += amountB.safe128();
        }

        poolFees = feeConfigs;

        addLiquidity(recipient, _liquidity);
    }

    function getInitializedAmount(
        uint160 sqrtMinPrice,
        uint160 sqrtMaxPrice,
        uint160 sqrtPrice,
        uint128 liquidity
    ) private view returns (uint256 amountA, uint256 amountB) {
        amountA = sqrtPrice.getAmount0Delta(sqrtMaxPrice, liquidity, true);
        amountB = sqrtMinPrice.getAmount1Delta(sqrtPrice, liquidity, true);
    }

    function getReserves() public view returns (uint128 _reserve0, uint128 _reserve1, uint32 _blockTimestampLast) {
        (_reserve0, _reserve1) = (reserve0, reserve1);
        _blockTimestampLast = blockTimestampLast;
    }

    function updatePreSwap() private {
        if (poolFees.dynamicFees.initialized) {
            poolFees.dynamicFees = poolFees.dynamicFees.updateReferences(sqrtPrice, block.timestamp);
        }
    }

    function getFeeMode(
        CollectFeeMode collectFeeMode,
        TradeDirection tradeDirection,
        bool hasReferral
    ) private pure returns (FeeMode memory) {
        FeeMode memory feeMode;
        
        if (collectFeeMode == CollectFeeMode.BothToken) {
            feeMode.feesOnInput = false;
            feeMode.feesOnTokenA = (tradeDirection == TradeDirection.BtoA);
        } else { // CollectFeeMode.OnlyB
            feeMode.feesOnInput = (tradeDirection == TradeDirection.BtoA);
            feeMode.feesOnTokenA = false;
        }
        
        feeMode.hasReferral = hasReferral;
        return feeMode;
    }

    function getSwapAmount(
        uint256 amountIn,
        bool zeroForOne
    ) private view returns (SwapAmount memory swapAmount) {
        uint128 liquidity = totalSupply;
        if (zeroForOne == true) {
            uint160 nextSqrtPrice = sqrtPrice.getNextSqrtPriceFromInput(
                liquidity,
                amountIn,
                true
            );

            if (nextSqrtPrice < sqrtMinPrice) {
                revert PriceRangeViolation();
            }

            uint256 outputAmount = nextSqrtPrice.getAmount1Delta(
                sqrtPrice,
                liquidity,
                false
            );

            swapAmount.outputAmount = outputAmount;
            swapAmount.nextSqrtPrice = nextSqrtPrice;
        } else {
            uint160 nextSqrtPrice = sqrtPrice.getNextSqrtPriceFromInput(
                liquidity,
                amountIn,
                false
            );

            if (nextSqrtPrice >  sqrtMaxPrice) {
                revert PriceRangeViolation();
            }

            uint256 outputAmount = sqrtPrice.getAmount0Delta(
                nextSqrtPrice,
                liquidity,
                false
            );

            swapAmount.outputAmount = outputAmount;
            swapAmount.nextSqrtPrice = nextSqrtPrice;
        }
    }

    function getSwapResult(
        uint256 amountIn,
        FeeMode memory feeMode,
        TradeDirection tradeDirection,
        uint64 currentPoint
    ) internal returns (SwapResult memory result) {
        uint128 actualProtocolFee;
        uint128 actualLpFee;
        uint128 actualReferralFee;
        uint128 actualPartnerFee;
        uint256 actualAmountIn;
        uint256 actualAmountOut;

        if (feeMode.feesOnInput) {
            FeeOnAmountResult memory feeResult
                = poolFees.getFeeOnAmount(
                    amountIn, 
                    feeMode.hasReferral, 
                    currentPoint, 
                    activationPoint, 
                    partner != address(0)
                );

            actualProtocolFee = feeResult.protocolFee;
            actualLpFee = feeResult.lpFee;
            actualReferralFee = feeResult.referralFee;
            actualPartnerFee = feeResult.partnerFee;
            actualAmountIn = feeResult.amount;
        } else {
            actualAmountIn = amountIn;
        }

        SwapAmount memory swapAmount;
        if (tradeDirection == TradeDirection.AtoB) {
            swapAmount = getSwapAmount(
                actualAmountIn,
                true
            );
        } else {
            swapAmount = getSwapAmount(
                actualAmountIn, 
                false
            );
        }

        if (feeMode.feesOnInput) {
            actualAmountOut = swapAmount.outputAmount;
        } else {
            FeeOnAmountResult memory feeResult
                = poolFees.getFeeOnAmount(
                    swapAmount.outputAmount, 
                    feeMode.hasReferral, 
                    currentPoint, 
                    activationPoint, 
                    partner != address(0)
                );
            actualProtocolFee = feeResult.protocolFee;
            actualLpFee = feeResult.lpFee;
            actualReferralFee = feeResult.referralFee;
            actualPartnerFee = feeResult.partnerFee;
            actualAmountOut = feeResult.amount;
        }

        result.actualAmountIn = actualAmountIn;
        result.outputAmount = actualAmountOut;
        result.nextSqrtPrice = swapAmount.nextSqrtPrice;
        result.lpFee = actualLpFee;
        result.protocolFee = actualProtocolFee;
        result.partnerFee = actualPartnerFee;
        result.referralFee = actualReferralFee;
    }

    function calculateFeePerLiquidity(
        uint256 fee,
        uint128 _liquidity
    ) private pure returns (uint256) {
        if (_liquidity == 0) return 0;
        
        // Shift left by 128 bits for precision, then divide by liquidity
        // This maintains precision for small fees
        return fee.mul(Constants.SCALE).div(uint256(_liquidity));
    }

    function applySwapResult(
        SwapResult memory swapResult,
        FeeMode memory feeMode,
        uint64 currentTimestamp
    ) private {
        uint160 oldSqrtPrice = sqrtPrice;
        sqrtPrice = swapResult.nextSqrtPrice;
        uint128 liquidity = totalSupply;

        //Q128.128
        uint256 feePerTokenStored = calculateFeePerLiquidity(
            uint256(swapResult.lpFee),
            liquidity
        );

        if (feeMode.feesOnTokenA) {
            partnerAFee += swapResult.partnerFee;
            protocolFeeA += swapResult.protocolFee;
            feeAPerLiquidity += feePerTokenStored;
            lpAFee += swapResult.lpFee;
        } else {
            partnerBFee += swapResult.partnerFee;
            protocolFeeB += swapResult.protocolFee;
            feeBPerLiquidity += feePerTokenStored;
            lpBFee += swapResult.lpFee;
        }

        updatePostSwap(oldSqrtPrice, currentTimestamp);
    }

    function updatePostSwap(uint160 oldSqrtPrice, uint64 currentTimestamp) private {
        poolFees.dynamicFees = poolFees.dynamicFees.updateVolatilityAccumulator(poolFees.dynamicFees.binStep, sqrtPrice);
        uint160 deltaPrice = poolFees.dynamicFees.binStep.getDeltaBinIdComplete(old_sqrt_price, sqrtPrice);

        if (deltaPrice > 0) {
            poolFees.dynamicFees.lastUpdateTimestamp = currentTimestamp;
        }
    }

    /**
    * @notice Swap function that takes amountIn as parameter and calculates amountOut internally
    * @param amount0In Amount of token0 to swap (0 if swapping token1)
    * @param amount1In Amount of token1 to swap (0 if swapping token0)
    * @param to Recipient address
    * @param data Callback data
    */
    function swap(
        uint256 amount0In, 
        uint256 amount1In, 
        address to, 
        bytes calldata data
    ) external lock returns (uint256 amount0Out, uint256 amount1Out) {
        // Validate inputs
        require(amount0In > 0 || amount1In > 0, 'UniswapV2: INSUFFICIENT_INPUT_AMOUNT');
        require((amount0In == 0) != (amount1In == 0), 'UniswapV2: ONLY_ONE_INPUT'); // XOR - only one can be non-zero
        
        uint128 liquidity = totalSupply;
        require(liquidity > 0, 'UniswapV2: INSUFFICIENT_LIQUIDITY');

        address _token0 = token0;
        address _token1 = token1;
        require(to != _token0 && to != _token1, 'UniswapV2: INVALID_TO');
        
        // Determine trade direction
        bool zeroForOne = amount0In > 0; // true if swapping token0 for token1
        uint256 amountIn = zeroForOne ? amount0In : amount1In;
        TradeDirection tradeDirection = zeroForOne ? TradeDirection.AtoB : TradeDirection.BtoA;
        
        // Update pre-swap state for dynamic fees
        updatePreSwap();
        
        // Get current timestamp for fee calculation
        uint64 currentTimestamp = uint64(block.timestamp);
        uint64 currentPoint = activationHandler.getCurrentPoint();
        
        // Determine fee mode (can be passed as parameter or stored)
        FeeMode memory feeMode = getFeeMode(
            CollectFeeMode.BothToken,
            tradeDirection,
            false // hasReferral - could be passed as parameter
        );
        
        // Calculate output amount with fees
        SwapResult memory swapResult = getSwapResult(
            amountIn,
            feeMode,
            tradeDirection,
            currentPoint
        );
        
        // Set output amounts
        if (zeroForOne) {
            amount0Out = 0;
            amount1Out = uint128(swapResult.outputAmount);
        } else {
            amount0Out = uint128(swapResult.outputAmount);
            amount1Out = 0;
        }
        
        // Check output is not zero
        require(swapResult.outputAmount > 0, 'UniswapV2: INSUFFICIENT_OUTPUT_AMOUNT');
        
        // Transfer input tokens from sender
        if (amount0In > 0) {
            //IERC20(_token0).transferFrom(msg.sender, address(this), amount0In);
            reserve0 += swapResult.actualAmountIn.safe128();
        }
        if (amount1In > 0) {
            //IERC20(_token1).transferFrom(msg.sender, address(this), amount1In);
            reserve1 += swapResult.actualAmountIn.safe128();
        } // Should fix by check balance
        
        // Apply swap result - update price and fees
        applySwapResult(swapResult, feeMode, currentTimestamp);
        
        if (poolFees.dynamicFees.initialized) {
            poolFees.dynamicFees.updateVolatilityAccumulator(sqrtPrice);
        }

        uint256 balance0Before;
        uint256 balance1Before;
        if (amount0In > 0) balance0Before = balance0();
        if (amount1In > 0) balance1Before = balance1();
        IUniswapV3SwapCallback(msg.sender).uniswapV3SwapCallback(amount0In, amount1In, data);
        if (amount0In > 0) require(balance0Before.add(amount0In) <= balance0(), 'M0');
        if (amount1In > 0) require(balance1Before.add(amount1In) <= balance1(), 'M1');

        // Transfer output tokens to recipient
        if (amount0Out > 0) {
            _safeTransfer(_token0, to, amount0Out);
            reserve0 -= amount0Out.safe128();
        }
        if (amount1Out > 0) {
            _safeTransfer(_token1, to, amount1Out);
            reserve1 -= amount1Out.safe128();
        }
        
        emit Swap(msg.sender, amount0In, amount1In, amount0Out, amount1Out, to);
        
        return (amount0Out, amount1Out);
    }

    function getAmountsForModifyLiquidity(
        uint256 liquidityDelta
    ) private returns (ModifyLiquidityResult memory result) {
        uint256 amountA = sqrtPrice.getAmount0Delta(
            sqrtMaxPrice,
            liquidityDelta,
            true
        );

        uint256 amountB = sqrtMinPrice.getAmount1Delta(
            sqrtPrice,
            liquidityDelta,
            true
        );

        result.tokenAAmount = amountA.safe128();
        result.tokenBAmount = amountB.safe128();
    }

    function mint(
        address recipient,
        uint128 liquidityDelta,
        uint256 amount0Threshold,
        uint256 amount1Threshold,
        bytes calldata data
    ) external lock returns (uint256 amount0, uint256 amount1) {            
        // Calculate liquidity based on current state
        address _token0 = token0;
        address _token1 = token1;
        ModifyLiquidityResult memory result = getAmountsForModifyLiquidity(liquidityDelta);
        amount0 = result.tokenAAmount;
        amount1 = result.tokenBAmount;
        require(amount0 > 0 || amount1 > 0, "AmountIsZero");
        applyAddLiquidity(liquidityDelta, recipient);
        // if (amount0 > 0) {
        //     IERC20(_token0).transferFrom(msg.sender, address(this), amount0);
        //     reserve0 += amount0.safe128();
        // }
        // if (amount1 > 0) {
        //     IERC20(_token1).transferFrom(msg.sender, address(this), amount1);
        //     reserve1 += amount1.safe128();
        // } 

        uint256 balance0Before;
        uint256 balance1Before;
        if (amount0 > 0) balance0Before = balance0();
        if (amount1 > 0) balance1Before = balance1();
        IUniswapV3MintCallback(msg.sender).uniswapV3MintCallback(amount0, amount1, data);
        if (amount0 > 0) require(balance0Before.add(amount0) <= balance0(), 'M0');
        if (amount1 > 0) require(balance1Before.add(amount1) <= balance1(), 'M1');

        reserve0 += amount0.safe128();
        reserve1 += amount1.safe128();

        require(amount0 <= amount0Threshold && amount1 <= amount1Threshold, "ExceededSlippage");
    }

    function applyAddLiquidity(
        uint128 liquidityDelta,
        address recipient
    ) private {
        updateFees(recipient, feeAPerLiquidity, feeBPerLiquidity);
        totalSupply += liquidityDelta;
        addLiquidity(recipient, liquidityDelta);
    }

    function applyRemoveLiquidity(
        uint218 liquidityDelta,
        address recipient
    ) private { 
        updateFees(recipient, feeAPerLiquidity, feeBPerLiquidity);
        totalSupply -= liquidityDelta;
        removeLiquidity(recipient, liquidityDelta);
    }


    function burn(
        uint128 liquidityDelta,
        address recipient
    ) external lock returns (uint256 amount0, uint256 amount1) {
        address _token0 = token0;
        address _token1 = token1;
        ModifyLiquidityResult memory result = getAmountsForModifyLiquidity(liquidityDelta);
        amount0 = result.tokenAAmount;
        amount1 = result.tokenBAmount;
        require(amount0 > 0 || amount1 > 0, "AmountIsZero");
        require(amount0 <= reserve0 && amount1 <= reserve1, "Insufficient amount");
        applyRemoveLiquidity(liquidityDelta, recipient);
        if (amount0 > 0) {
            IERC20(_token0).transfer(recipient, amount0);
            reserve0 -= amount0.safe128();
        }
        if (amount1 > 0) {
            IERC20(_token1).transfer(recipient, amount1);
            reserve1 -= amount1.safe128();
        } 
        // uint256 balance0 = IERC20(_token0).balanceOf(address(this));
        // uint256 balance1 = IERC20(_token1).balanceOf(address(this));
        
        // // // Update reserves with new balances
        // _update(balance0, balance1);
    }

    function claimFee(
        address recipient
    ) external returns (uint128 feeA, uint128 feeB) {
        address _token0 = token0;
        address _token1 = token1;
        updateFees(recipient, feeAPerLiquidity, feeBPerLiquidity);
        require(recipient != address(0), "Address is zero");
        (feeA, feeB) = claimFees(recipient);

        if (feeA > 0) {
            IERC20(_token0).transfer(recipient, feeA);
            lpAFee -= feeA;
        }
        if (feeB > 0) {
            IERC20(_token0).transfer(recipient, feeB);
            lpAFee -= feeA;
        }
    }

    function claimProtocolFee(
        address recipient
    ) external returns (uint128 feeA, uint128 feeB) {
        address _token0 = token0;
        address _token1 = token1;

        require(recipient != address(0), "Address is zero");
        feeA = protocolFeeA;
        feeB = protocolFeeB;

        if (feeA > 0) {
            IERC20(_token0).transfer(recipient, feeA);
            protocolFeeA = 0;
        }
        if (feeB > 0) {
            IERC20(_token0).transfer(recipient, feeA);
            protocolFeeB = 0;
        }
    }

    function getCliffPoint(uint64 currentPoint, address user) private view returns (uint64) {
        VestingHelper.Vesting memory _vesting = vesting[user];
        if (_vesting.cliffPoint != 0) {
            return _vesting.cliffPoint;
        } else {
            return currentPoint;
        }
    }

    function getTotalLockAmount(address user) private returns(uint128 totalAmount) {
        VestingHelper.Vesting memory _vesting = vesting[user];
        totalAmount = _vesting.cliffUnlockLiquidity + _vesting.liquidityPerPeriod * _vesting.numberOfPeriod.safe128();
    }

    function validateVesting(uint64 currentPoint, uint64 maxVestingDuration, address user) private view {
        VestingHelper.Vesting memory _vesting = vesting[user];
        
        uint64 cliffPoint = getCliffPoint(currentPoint, user);
        require(cliffPoint >= currentPoint, "Invalid Vesting Info1");
        require(_vesting.numberOfPeriod > 0, "Invalid Vesting Info2");
        require(_vesting.periodFrequency > 0 && _vesting.liquidityPerPeriod > 0, "Invalid Vesting Info3");

        uint64 vestingDuration = (cliffPoint - currentPoint) + (_vesting.periodFrequency * _vesting.numberOfPeriod);
        require(vestingDuration <= maxVestingDuration, "Invalid Vesting Info4");

        require(getTotalLockAmount(user) > 0, "Invalid Vesting Info5");
    }


    function lockPosition(
        uint64 cliffPoint,
        uint64 periodFrequency,
        uint128 cliffUnlockLiquidity,
        uint128 liquidityPerPeriod,
        uint16 numberOfPeriod,
        address recipient
    ) external {
        (uint64 currentPoint, uint64 maxVestingDuration) = activationHandler.getCurrentPointAndMaxVestingDuration();
        validateVesting(currentPoint, maxVestingDuration, recipient);

        uint128 totalLockLiquidity = getTotalLockAmount(recipient);
        uint64 cliffPoint = getCliffPoint(currentPoint, recipient);

        vesting[recipient].initialize(
            cliffPoint,
            periodFrequency,
            cliffUnlockLiquidity,
            liquidityPerPeriod,
            numberOfPeriod
        );

        lockLiquidity(recipient, totalLockLiquidity);
    }

    function permanentLockPosition(
        uint128 permanentLockLiquidity,
        address recipient
    ) external {
        permanentLockLiquidity(recipient, permanentLockLiquidity);
        permanentTotalSupply += permanentLockLiquidity;
    }

    function refreshVesting(
        address recipient
    ) external returns (uint128 releasedLiquidity) {
        uint64 currentPoint = activationHandler.getCurrentPoint();
        releasedLiquidity = vesting[user].getNewReleaseLiquidity(currentPoint);
        if (releasedLiquidity > 0) {
            releaseVestedLiquidity(recipient, releasedLiquidity);
            vesting[user].accumulateReleasedLiquidity(releasedLiquidity);
        }

        if (vesting[user].isDone()) {
            delete vesting[user];
        }
    }

    function splitPosition(
        SplitPositionParameters memory params,
        address from,
        address to
    ) external returns (
        uint128 unlockedLiquiditySplit,
        uint128 permanentLockedLiquiditySplit,
        uint128 feeASplit,
        uint128 feeBSplit,
        uint128 reward0Split,
        uint128 reward1Split
    ) {
        require(
            params.unlockedLiquidityPercentage <= 100 &&
            params.permanentLockedLiquidityPercentage <= 100 &&
            params.feeAPercentage <= 100 &&
            params.feeBPercentage <= 100 &&
            params.reward0Percentage <= 100 &&
            params.reward1Percentage <= 100, 
            "InvalidSplitPositionParametersMax"
        );

        require(
            params.unlockedLiquidityPercentage > 0 &&
            params.permanentLockedLiquidityPercentage > 0 &&
            params.feeAPercentage > 0 &&
            params.feeBPercentage > 0 &&
            params.reward0Percentage > 0 &&
            params.reward1Percentage > 0, 
            "InvalidSplitPositionParametersMin"
        );

        require(vesting[from] == 0, "UnsupportPositionHasVestingLock");

        require(from != to, "FromIsTo");

        updateFees(from, feeAPerLiquidity, feeBPerLiquidity);
        updateFees(to, feeAPerLiquidity, feeBPerLiquidity);

        unlockedLiquiditySplit = getUnlockedLiquiditybyPercentage(from, params.unlockedLiquidityPercentage);
        removeLiquidity(from, unlockedLiquidityDelta);
        addLiquidity(to, unlockedLiquidityDelta);

        permanentLockedLiquiditySplit = getPermanentLockedLiquidityByPercentage(from, params.permanentLockedLiquidityPercentage);
        removePermanentLiquidity(from, permanentLockedLiquiditySplit);
        addPermanentLiquidity(to, permanentLockedLiquiditySplit);

        (feeASplit, feeBSplit) = getPendingFeeByPercentage(from, params.feeAPercentage, params.feeBPercentage);
        removeFeePending(from, feeASplit, feeBSplit);
        addFeePending(to, feeASplit, feeBSplit);
    }

    
    function _update(uint balance0, uint balance1) private {
        require(balance0 <= type(uint128).max && balance1 <= type(uint128).max, 'UniswapV2: BALANCE_OVERFLOW');
        
        uint128 _reserve0 = uint128(balance0);
        uint128 _reserve1 = uint128(balance1);
        
        uint32 blockTimestamp = uint32(block.timestamp % 2**32);
        // uint32 timeElapsed = blockTimestamp - blockTimestampLast;
        
        // if (timeElapsed > 0 && reserve0 != 0 && reserve1 != 0) {
        //     // Use UQ112x112 for price oracle (need to fit in uint112 for compatibility)
        //     if (reserve0 <= type(uint112).max && reserve1 <= type(uint112).max) {
        //         price0CumulativeLast += uint(UQ112x112.encode(uint112(reserve1)).uqdiv(uint112(reserve0))) * timeElapsed;
        //         price1CumulativeLast += uint(UQ112x112.encode(uint112(reserve0)).uqdiv(uint112(reserve1))) * timeElapsed;
        //     }
        // }
        
        reserve0 = _reserve0;
        reserve1 = _reserve1;
        blockTimestampLast = blockTimestamp;
        emit Sync(uint112(_reserve0), uint112(_reserve1));
    }

    function _safeTransfer(address token, address to, uint value) private {
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(SELECTOR, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'UniswapV2: TRANSFER_FAILED');
    }

    function balance0() private view returns (uint256) {
        (bool success, bytes memory data) =
            token0.staticcall(abi.encodeWithSelector(IERC20.balanceOf.selector, address(this)));
        require(success && data.length >= 32);
        return abi.decode(data, (uint256));
    }

    /// @dev Get the pool's balance of token1
    /// @dev This function is gas optimized to avoid a redundant extcodesize check in addition to the returndatasize
    /// check
    function balance1() private view returns (uint256) {
        (bool success, bytes memory data) =
            token1.staticcall(abi.encodeWithSelector(IERC20.balanceOf.selector, address(this)));
        require(success && data.length >= 32);
        return abi.decode(data, (uint256));
    }


    function skim(address to) external lock {
        address _token0 = token0;
        address _token1 = token1;
        uint128 _reserve0 = reserve0;
        uint128 _reserve1 = reserve1;
        
        uint balance0 = IERC20(_token0).balanceOf(address(this));
        uint balance1 = IERC20(_token1).balanceOf(address(this));
        
        if (balance0 > _reserve0) {
            _safeTransfer(_token0, to, balance0 - _reserve0);
        }
        if (balance1 > _reserve1) {
            _safeTransfer(_token1, to, balance1 - _reserve1);
        }
    }

    function sync() external lock {
        _update(IERC20(token0).balanceOf(address(this)), IERC20(token1).balanceOf(address(this)));
    }
}