pragma solidity >=0.5.0;

interface IUniswapV2Pair {
    event Approval(address indexed owner, address indexed spender, uint value);
    event Transfer(address indexed from, address indexed to, uint value);

    enum CollectFeeMode {
        BothToken,
        OnlyB
    }

    enum TradeDirection {
        AtoB,
        BtoA
    }

    enum PoolStatus {
        Enable,
        Disable
    }

    enum PoolType {
        Permissionless,
        Customizable
    }

    struct InitializeParams {
        uint160 sqrtPrice;
        uint64 activationPoint;
        uint128 liquidity;
        bool collectBothToken;

    }

    struct AddLiquidityParams {
        address recipient;
        uint128 liquidityDelta;
        uint256 amount0Threshold;
        uint256 amount1Threshold;
        
    }

    struct RemoveLiquidityParams {
        address recipient;
        uint128 liquidityDelta;
        uint256 amount0Threshold;
        uint256 amount1Threshold;
    }

    struct FeeMode {
        bool feesOnInput;
        bool feesOnTokenA;
        bool hasReferral;
    }

    // struct PoolMetrics {
    //     uint128 totalLpAFee;
    //     uint128 totalLpBFee;
    //     uint64 totalProtocolAFee;
    //     uint64 totalProtocolBFee;
    //     uint64 totalPartnerAFee;
    //     uint64 totalPartnerBFee;
    //     uint64 totalPosition;
    // }

    // struct RewardInfo {
    //     bool initialized;
    //     uint8 rewardTokenFlag;
    //     address mint;
    //     address vault;
    //     address funder;
    //     uint64 rewardDuration;
    //     uint64 rewardDurationEnd;
    //     uint128 rewardRate;
    //     uint256 rewardPerTokenStored;
    //     uint64 lastUpdateTime;
    //     uint64 cumulativeSecondsWithEmptyLiquidityReward;
    // }

    // struct Position {
    //     address owner;
    //     uint128 liquidity;
    //     uint128 permanentLockedLiquidity;
    //     uint256 feeAPerLiquidity;
    //     uint256 feeBPerLiquidity;
    //     uint64 pendingFeeA;
    //     uint64 pendingFeeB;
    //     uint64[2] pendingRewards;
    //     uint256[2] rewardPerTokenPaid;
    // }

    struct SwapResult {
        uint256 actualAmountIn;
        uint256 outputAmount;
        uint160 nextSqrtPrice;
        uint128 lpFee;
        uint128 protocolFee;
        uint128 partnerFee;
        uint128 referralFee;
    }

    struct ModifyLiquidityResult {
        uint256 tokenAAmount;
        uint256 tokenBAmount;
    }

    struct SplitAmountInfo {
        uint128 permanentLockedLiquidity;
        uint128 unlockedLiquidity;
        uint64 feeA;
        uint64 feeB;
        uint64 reward0;
        uint64 reward1;
    }

    struct SwapAmount {
        uint128 outputAmount;
        uint160 nextSqrtPrice;
    }

    error PriceRangeViolation();

    function name() external pure returns (string memory);
    function symbol() external pure returns (string memory);
    function decimals() external pure returns (uint8);
    function totalSupply() external view returns (uint128);
    function balanceOf(address owner) external view returns (uint128);
    function allowance(address owner, address spender) external view returns (uint128);

    function approve(address spender, uint256 value) external returns (bool);
    function transfer(address to, uint256 value) external returns (bool);
    function transferFrom(address from, address to, uint256 value) external returns (bool);

    function DOMAIN_SEPARATOR() external view returns (bytes32);
    function PERMIT_TYPEHASH() external pure returns (bytes32);
    function nonces(address owner) external view returns (uint256);

    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;

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

    function MINIMUM_LIQUIDITY() external pure returns (uint);
    function factory() external view returns (address);
    function token0() external view returns (address);
    function token1() external view returns (address);
    function sqrtMinPrice() external view returns (uint160);
    function sqrtMaxPrice() external view returns (uint160);
    function sqrtPrice() external view returns (uint160);
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function price0CumulativeLast() external view returns (uint);
    function price1CumulativeLast() external view returns (uint);
    function kLast() external view returns (uint);

    function burn(address to) external returns (uint amount0, uint amount1);
    function swap(uint amount0Out, uint amount1Out, address to, bytes calldata data) external;
    function skim(address to) external;
    function sync() external;

    function mint(
        address recipient,
        uint128 liquidityDelta,
        uint256 amount0Threshold,
        uint256 amount1Threshold,
        bytes calldata data
    ) external returns (uint256 amount0, uint256 amount1);

    function initialize(address, address) external;
}
