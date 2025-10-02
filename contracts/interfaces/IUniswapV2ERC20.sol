// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/** 
 * @title IUniswapV2ERC20
 * @notice Interface for Uniswap V2 LP token with ERC20 and EIP-2612 permit functionality
 * @dev This version maintains ERC20 compatibility while using uint128 internally for optimization
 */
interface IUniswapV2ERC20 {
    // ==================== Events ====================
    
    /**
     * @notice Emitted when tokens are transferred
     * @param from The sender address (address(0) for minting)
     * @param to The recipient address (address(0) for burning)
     * @param value The amount transferred
     */
    event Transfer(address indexed from, address indexed to, uint256 value);
    
    /**
     * @notice Emitted when approval is set
     * @param owner The token owner
     * @param spender The approved spender
     * @param value The approved amount
     */
    event Approval(address indexed owner, address indexed spender, uint256 value);

    event PositionCreated(address indexed user);
    event LiquidityModified(address indexed user, int128 liquidityDelta);
    event FeesUpdated(address indexed user, uint128 feeA, uint128 feeB);
    event FeesClaimed(address indexed user, uint128 feeA, uint128 feeB);
    event RewardsClaimed(address indexed user, uint256 rewardIndex, uint128 amount);

    // ==================== Custom Errors ====================
    
    error InsufficientBalance();
    error InsufficientAllowance();
    error InvalidSignature();
    error ExpiredDeadline();
    error InvalidRecipient();
    error InvalidAmount();
    error Overflow();
    error AmountExceedsUint128();

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

    // ==================== View Functions ====================
    
    /**
     * @notice Returns the name of the token
     * @return The token name
     */
    function name() external pure returns (string memory);
    
    /**
     * @notice Returns the symbol of the token
     * @return The token symbol
     */
    function symbol() external pure returns (string memory);
    
    /**
     * @notice Returns the number of decimals
     * @return The number of decimals
     */
    function decimals() external pure returns (uint8);
    
    /**
     * @notice Returns the total supply of tokens
     * @return The total supply (internally stored as uint128, returned as uint256 for ERC20 compatibility)
     */
    function totalSupply() external view returns (uint128);
    
    /**
     * @notice Returns the balance of an account
     * @param owner The account address
     * @return The balance (internally stored as uint128, returned as uint256 for ERC20 compatibility)
     */
    function balanceOf(address owner) external view returns (uint128);
    
    /**
     * @notice Returns the allowance for a spender
     * @param owner The token owner
     * @param spender The spender address
     * @return The allowance amount (internally stored as uint128, returned as uint256 for ERC20 compatibility)
     */
    function allowance(address owner, address spender) external view returns (uint128);
    
    /**
     * @notice Returns the current nonce for an address (for permit)
     * @param owner The address to query
     * @return The current nonce
     */
    function nonces(address owner) external view returns (uint256);
    
    /**
     * @notice Returns the EIP-712 domain separator
     * @return The domain separator
     */
    function DOMAIN_SEPARATOR() external view returns (bytes32);
    
    /**
     * @notice Returns the permit typehash for EIP-2612
     * @return The permit typehash
     */
    function PERMIT_TYPEHASH() external pure returns (bytes32);

    // ==================== State-Changing Functions ====================
    
    /**
     * @notice Approves a spender to spend tokens
     * @param spender The spender address
     * @param value The amount to approve (must fit in uint128)
     * @return success Always returns true
     * @dev Reverts if value exceeds uint128 max
     */
    function approve(address spender, uint256 value) external returns (bool success);
    
    /**
     * @notice Transfers tokens to a recipient
     * @param to The recipient address
     * @param value The amount to transfer (must fit in uint128)
     * @return success Always returns true
     * @dev Reverts if value exceeds uint128 max
     */
    function transfer(address to, uint256 value) external returns (bool success);
    
    /**
     * @notice Transfers tokens from one address to another
     * @param from The sender address
     * @param to The recipient address
     * @param value The amount to transfer (must fit in uint128)
     * @return success Always returns true
     * @dev Reverts if value exceeds uint128 max
     */
    function transferFrom(
        address from,
        address to,
        uint256 value
    ) external returns (bool success);
    
    /**
     * @notice Approves spending via signature (EIP-2612)
     * @param owner The token owner
     * @param spender The spender address
     * @param value The amount to approve (must fit in uint128)
     * @param deadline The deadline timestamp
     * @param v The signature v value
     * @param r The signature r value
     * @param s The signature s value
     * @dev Reverts if value exceeds uint128 max
     */
    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;
}