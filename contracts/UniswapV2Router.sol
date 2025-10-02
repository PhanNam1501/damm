
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IUniswapV2Router} from './interfaces/IUniswapV2Router.sol';
import {IUniswapV2Factory} from './interfaces/IUniswapV2Factory.sol';
import {IUniswapV2Pair} from './interfaces/IUniswapV2Pair.sol';
import {IERC20} from './interfaces/IERC20.sol';
import {IWNATIVE} from './interfaces/IWNATIVE.sol';
import {LiquidityAmounts} from './libraries/LiquidityAmounts.sol';
import {IUniswapV3MintCallback} from './interfaces/IUniswapV3MintCallback.sol';
import {PoolAddress} from './libraries/PoolAddress.sol';
import {TransferHelper} from './libraries/TransferHelper.sol';

contract UniswapV2Router is IUniswapV2Router, IUniswapV3MintCallback {
    using LiquidityAmounts for uint160;

    IUniswapV2Factory public immutable override factory;
    IWNATIVE public immutable override wnative;

    constructor(IUniswapV2Factory _factory, IWNATIVE _wnative) {
        factory = _factory;
        wnative = _wnative;
    }

    receive() external payable {
        assert(msg.sender == address(wnative)); // only accept ETH via fallback from the WETH contract
    }

    function uniswapV3MintCallback(
        uint256 amount0Owed,
        uint256 amount1Owed,
        bytes calldata data
    ) external override {
        MintCallbackData memory decoded = abi.decode(data, (MintCallbackData));
        if (amount0Owed > 0) pay(decoded.poolKey.token0, decoded.payer, msg.sender, amount0Owed);
        if (amount1Owed > 0) pay(decoded.poolKey.token1, decoded.payer, msg.sender, amount1Owed);
    }

    function addLiquidity(AddLiquidityParams memory params) external returns (uint128 liquidity, uint256 amountA, uint256 amountB) {
        address tokenA = params.tokenA;
        address tokenB = params.tokenB;
        PoolKey memory poolKey =
            PoolKey({token0: tokenA, token1: params.tokenB});

        address pair = factory.getPair(tokenA, tokenB);

        uint160 sqrtMaxPrice = IUniswapV2Pair(pair).sqrtMaxPrice();
        uint160 sqrtMinPrice = IUniswapV2Pair(pair).sqrtMinPrice();
        uint160 sqrtPrice = IUniswapV2Pair(pair).sqrtPrice();

        liquidity = sqrtPrice.getLiquidityForAmounts(
            sqrtMinPrice,
            sqrtMaxPrice,
            params.amountADesired,
            params.amountBDesired
        );

        (amountA, amountB) = IUniswapV2Pair(pair).mint(
            params.recipient, 
            liquidity, 
            params.amountADesired, 
            params.amountBDesired,
            abi.encode(MintCallbackData({poolKey: poolKey, payer: msg.sender}))
        );

        require(amountA >= params.amountAMin && amountB >= params.amountBMin, "AmountIn slippage");



    }

    /// @param token The token to pay
    /// @param payer The entity that must pay
    /// @param recipient The entity that will receive payment
    /// @param value The amount to pay
    function pay(
        address token,
        address payer,
        address recipient,
        uint256 value
    ) internal {
        if (token == address(wnative) && address(this).balance >= value) {
            // pay with WETH9
            wnative.deposit{value: value}(); // wrap only what is needed to pay
            wnative.transfer(recipient, value);
        } else if (payer == address(this)) {
            // pay with tokens already in the contract (for the exact input multihop case)
            TransferHelper.safeTransfer(token, recipient, value);
        } else {
            // pull payment
            TransferHelper.safeTransferFrom(token, payer, recipient, value);
        }
    }



    
    
}