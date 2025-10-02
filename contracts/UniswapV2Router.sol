
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IUniswapV2Router} from './interfaces/IUniswapV2Router.sol';
import {IUniswapV2Factory} from './interfaces/IUniswapV2Factory.sol';
import {IUniswapV2Pair} from './interfaces/IUniswapV2Pair.sol';
import {IERC20} from './interfaces/IERC20.sol';
import {IWNATIVE} from './interfaces/IWNATIVE.sol';
import {LiquidityAmounts} from './libraries/LiquidityAmounts.sol';

contract UniswapV2Router is IUniswapV2Router {
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

    function addLiquidity(AddLiquidityParams memory params) external returns (uint128 liquidity, uint256 amountA, uint256 amountB) {
        address tokenA = params.tokenA;
        address tokenB = params.tokenB;
        address pair = factory.getPair(tokenA, tokenB);

    }



    
    
}