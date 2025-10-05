// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import './interfaces/IUniswapV2ERC20.sol';
import './libraries/math/SafeMath.sol';
import {Constants} from './libraries/Constants.sol';
import {Uint256x256Math} from './libraries/math/Uint256x256Math.sol';
import {SafeCast} from './libraries/SafeCast.sol';

contract UniswapV2ERC20 is IUniswapV2ERC20 {
    using SafeMath for uint256;
    using Uint256x256Math for uint256;
    using SafeCast for uint256;
    using SafeCast for uint8;
    
    // State variables - Changed to uint128 for optimization
    string public constant override name = 'Uniswap V2';
    string public constant override symbol = 'UNI-V2';
    uint8 public constant override decimals = 18;
    uint256 constant NUM_REWARDS = 2;
    uint128 public totalSupply; 
    uint128 public permanentTotalSupply;
    
    mapping(address => uint128) public balanceOf;  // Changed to uint128
    mapping(address => mapping(address => uint128)) public allowance;  // Changed to uint128
    mapping(address => uint256) public override nonces;

    //Position
    mapping(address => Position) public positions;

    // Modifiers
    modifier onlyInitialized(address user) {
        require(positions[user].initialized, "Position not initialized");
        _;
    }

    // EIP-712 
    bytes32 public immutable override DOMAIN_SEPARATOR;
    // keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");
    bytes32 public constant override PERMIT_TYPEHASH = 0x6e71edae12b1b97f4d1f60370fef10105fa2faae0126114a169c64845d6126c9;

    constructor() {
        uint256 chainId;
        assembly {
            chainId := chainid()
        }
        
        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                keccak256('EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)'),
                keccak256(bytes(name)),
                keccak256(bytes('1')),
                chainId,
                address(this)
            )
        );
    }

    function getUnlockedLiquiditybyPercentage(
        address user,
        uint8 percentage
    ) internal view returns (uint128 liquidityDelta) {
        Position memory position = positions[user];
        liquidityDelta = position.unlockedLiquidity * percentage.safe128() / 100;
    }

    function getPermanentLockedLiquidityByPercentage(
        address user,
        uint8 percentage
    ) internal view returns (uint128 permanentLockedLiquidityDelta) {
        Position memory position = positions[user];
        permanentLockedLiquidityDelta = position.permanentLockedLiquidity * percentage.safe128() / 100;
    }

    function getPendingFeeByPercentage(
        address user,
        uint8 feeAPercentage,
        uint8 feeBPercentage
    ) internal view returns (uint128 feeAAmount, uint128 feeBAmount) {
        Position memory position = positions[user];
        feeAAmount = position.feeAPending * feeAPercentage / 100;
        feeBAmount = position.feeBPending * feeBPercentage / 100;
    }

    /**
     * @notice Create or get position for user in a pool
     * @param user User address
     */
    function initializePosition(
        address user
    ) external returns (bool) {
        Position storage position = positions[user];

        if (!position.initialized) {
            position.initialized = true;
            emit PositionCreated(user);
        }
        return true;
    }

    /**
     * @notice Add liquidity to user's position
     * @param user User address
     * @param liquidityDelta Amount of liquidity to add
     */
    function addLiquidity(
        address user,
        uint128 liquidityDelta
    ) internal {
        Position storage position = positions[user];

        if (!position.initialized) {
            position.initialized = true;
            emit PositionCreated(user);
        }

        position.unlockedLiquidity += liquidityDelta;
        emit LiquidityModified(user, int128(liquidityDelta));
    }

    /**
     * @notice Remove liquidity to user's position
     * @param user User address
     * @param liquidityDelta Amount of liquidity to add
     */
    function removeLiquidity(
        address user,
        uint128 liquidityDelta
    ) internal onlyInitialized(user) {
        Position storage position = positions[user];
        require(position.unlockedLiquidity >= liquidityDelta, "Insufficient liquidity");

        position.unlockedLiquidity -= liquidityDelta;
        emit LiquidityModified(user, -int128(liquidityDelta));
    }

    function addPermanentLiquidity(
        address user,
        uint128 liquidityDelta
    ) internal onlyInitialized(user) {
        Position storage position = positions[user];
        position.permanentLockedLiquidity += liquidityDelta;
    }

    function removePermanentLiquidity(
        address user,
        uint128 liquidityDelta
    ) internal onlyInitialized(user) {
        Position storage position = positions[user];
        require(position.permanentLockedLiquidity >= liquidityDelta, "Insufficient liquidity");

        position.permanentLockedLiquidity -= liquidityDelta;
    }

    function addFeePending(
        address user,
        uint128 feeADelta,
        uint128 feeBDelta
    ) internal onlyInitialized(user) {
        Position storage position = positions[user];
        position.feeAPending += feeADelta;
        position.feeBPending += feeBDelta;
    }

    function removeFeePending(
        address user,
        uint128 feeADelta,
        uint128 feeBDelta
    ) internal onlyInitialized(user) {
        Position storage position = positions[user];
        require(position.feeAPending >= feeADelta && position.feeBPending >= feeBDelta, "Insufficient fee");
        position.feeAPending -= feeADelta;
        position.feeBPending -= feeBDelta;
    }

    /**
     * @notice Get total liquidity for a user's position
     * @param user User address
     */
    function getTotalLiquidity(
        address user
    ) public view returns (uint128) {
        Position memory position = positions[user];
        return position.unlockedLiquidity +
               position.vestedLiquidity +
               position.permanentLockedLiquidity;
    }

    /**
     * @notice Lock liquidity for vesting
     * @param user User address
     * @param lockAmount Amount of liqudity locked
     */
    function lockLiquidity(
        address user,
        uint128 lockAmount
    ) internal onlyInitialized(user) {
        Position storage position = positions[user];

        require(position.unlockedLiquidity >= lockAmount, "Insufficient unlocked liquidity");

        position.unlockedLiquidity -= lockAmount;
        position.vestedLiquidity += lockAmount;
    }

    /**
     * @notice Release vested liquidity
     * @param user User address
     * @param releaseAmount Amount of liqudity to release
     */
    function releaseVestedLiquidity(
        address user,
        uint128 releaseAmount
    ) external onlyInitialized(user) {
        Position storage position = positions[user];

        require(position.vestedLiquidity >= releaseAmount, "Insufficient vested liquidity");

        position.unlockedLiquidity += releaseAmount;
        position.vestedLiquidity -= releaseAmount;
    }

    function permanentLockLiquidity(
        address user,
        uint128 permanentAmount
    ) external onlyInitialized(user) {
        Position storage position = positions[user];

        require(position.unlockedLiquidity >= permanentAmount, "Insufficient unlocked liquidity");

        position.unlockedLiquidity -= permanentAmount;
        position.permanentLockedLiquidity += permanentAmount;
    }

    function releasePermanentLiquidity(
        address user,
        uint128 releaseAmount
    ) external onlyInitialized(user) {
        Position storage position = positions[user];

        require(position.permanentLockedLiquidity >= releaseAmount, "Insufficient permanent liquidity");
        position.unlockedLiquidity += releaseAmount;
        position.permanentLockedLiquidity -= releaseAmount;
    }

    // ==================== Fee Management ====================
    
    /**
     * @notice Update fees for a user's position (called by pool)
     */
    function updateFees(
        address user,
        uint256 feeAPerTokenStored,
        uint256 feeBPerTokenStored
    ) external {
        Position storage position = positions[user];

        if (!position.initialized) return;
        uint128 liquidity = getTotalLiquidity(user);

        if (liquidity > 0) {
            if (feeAPerTokenStored > position.feeAPerTokenCheckpoint) {
                uint256 deltaFeeA = feeAPerTokenStored - position.feeAPerTokenCheckpoint;
                uint128 newFeeA = uint256(liquidity).mulShiftRoundDown(deltaFeeA, Constants.SCALE_OFFSET).safe128();
                position.feeAPending += newFeeA;
            }

            if (feeBPerTokenStored > position.feeBPerTokenCheckpoint) {
                uint256 deltaFeeB = feeBPerTokenStored - position.feeBPerTokenCheckpoint;
                uint128 newFeeB = uint256(liquidity).mulShiftRoundDown(deltaFeeB, Constants.SCALE_OFFSET).safe128();
                position.feeBPending += newFeeB;
            }
        }

        position.feeAPerTokenCheckpoint = feeAPerTokenStored;
        position.feeBPerTokenCheckpoint = feeBPerTokenStored;

        emit FeesUpdated(user, position.feeAPending, position.feeBPending);
    }

    /**
     * @notice Claim all pending fees
     */
    function claimFees(
        address user
    ) external onlyInitialized(user) returns (uint128 feeA, uint128 feeB) {
        Position storage position = positions[user];

        feeA = position.feeAPending;
        feeB = position.feeBPending;

        if (feeA > 0 || feeB > 0) {
            position.totalClaimedAFee += feeA;
            position.totalClaimedBFee += feeA;

            position.feeAPending = 0;
            position.feeBPending = 0;

            emit FeesClaimed(user, feeA, feeB);
        }
    }

    /**
     * @notice Get claimable fees for a user
     */
    function getClaimableFees(
        address user
    ) external view returns (uint128 feeA, uint128 feeB) {
        Position memory position = positions[user];
        return (position.feeAPending, position.feeBPending);
    }

    //Rewards

    function getTotalReward(
        address user,
        uint256 index
    ) public view returns (uint128) {
        Position memory position = positions[user];
        return position.rewardInfos[index].rewardPendings;
    }

    function accumlateTotalClaimedRewards(
        address user,
        uint256 index,
        uint128 reward
    ) private {
        Position storage position = positions[user];
        uint128 totalClaimedReward = position.rewardInfos[index].totalClaimedRewards;
        position.rewardInfos[index].totalClaimedRewards = totalClaimedReward + reward;
    }

    function resetAllPendingReward(
        address user,
        uint256 index
    ) private {
        Position storage position = positions[user];
        position.rewardInfos[index].rewardPendings = 0;
    }

    function claimReward(
        address user,
        uint256 index
    ) internal returns (uint128) {
        uint128 totalReward = getTotalReward(user, index);
        accumlateTotalClaimedRewards(user, index, totalReward);
        resetAllPendingReward(user, index);

        return totalReward;
    }

    function updateRewardByPosition(
        address user,
        uint256 index,
        uint128 positionLiquidity,
        uint256 rewardPerTokenStored
    ) internal {
        Position storage position = positions[user];
        uint128 newReward = (uint256(positionLiquidity).mul(rewardPerTokenStored.sub(position.rewardInfos[index].rewardPerTokenCheckpoint)) >> 128).safe128();

        position.rewardInfos[index].rewardPendings += newReward;
        position.rewardInfos[index].rewardPerTokenCheckpoint = rewardPerTokenStored;
    }

    function getPendingRewardByPercentage(
        address user,
        uint256 index,
        uint8 rewardPercentage
    ) internal view returns (uint128 rewardSplit) {
        Position memory position = positions[user];
        rewardSplit = position.rewardInfos[index].rewardPendings * uint128(rewardPercentage) / 100;
    }

    function addRewardPending(
        address user,
        uint256 index,
        uint128 rewardAmount
    ) internal {
        Position storage position = positions[user];
        position.rewardInfos[index].rewardPendings += rewardAmount;
    }

    function removeRewardPending(
        address user,
        uint256 index,
        uint128 rewardAmount
    ) internal {
        Position storage position = positions[user];
        require(rewardAmount < position.rewardInfos[index].rewardPendings, "Not enough reward");
        position.rewardInfos[index].rewardPendings += rewardAmount;
    }

    /**
     * @notice Get complete position data
     */
    function getPosition(
        address user
    ) external view returns (Position memory) {
        return positions[user];
    }

    /**
     * @notice Check if position is empty
     */
    function isPositionEmpty(
        address user
    ) external view returns (bool) {
        Position memory position = positions[user];
        
        if (!position.initialized) return true;
        
        // Check if has any liquidity
        if (getTotalLiquidity(user) > 0) return false;
        
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
        address user
    ) external view returns (bool) {
        return positions[user].initialized;
    }

    /**
     * @dev Mints tokens to the specified address
     * @param to The address to mint tokens to
     * @param value The amount of tokens to mint (must fit in uint128)
     */
    function _mint(address to, uint128 value) internal {
        if (to == address(0)) revert InvalidRecipient();
        
        // Check for overflow
        uint128 newTotalSupply = totalSupply + value;
        if (newTotalSupply < totalSupply) revert Overflow();
        
        totalSupply = newTotalSupply;
        
        // Check for overflow in balance
        uint128 newBalance = balanceOf[to] + value;
        if (newBalance < balanceOf[to]) revert Overflow();
        
        balanceOf[to] = newBalance;
        
        emit Transfer(address(0), to, uint256(value));
    }

    /**
     * @dev Burns tokens from the specified address
     * @param from The address to burn tokens from
     * @param value The amount of tokens to burn
     */
    function _burn(address from, uint128 value) internal {
        uint128 balance = balanceOf[from];
        if (balance < value) revert InsufficientBalance();
        
        unchecked {
            balanceOf[from] = balance - value;
            totalSupply -= value;
        }
        
        emit Transfer(from, address(0), uint256(value));
    }

    /**
     * @dev Sets approval for spender
     * @param owner The owner of the tokens
     * @param spender The spender address
     * @param value The amount to approve
     */
    function _approve(address owner, address spender, uint128 value) private {
        allowance[owner][spender] = value;
        emit Approval(owner, spender, uint256(value));
    }

    /**
     * @dev Internal transfer function
     * @param from The sender address
     * @param to The recipient address
     * @param value The amount to transfer
     */
    function _transfer(address from, address to, uint128 value) private {
        if (to == address(0)) revert InvalidRecipient();
        
        uint128 fromBalance = balanceOf[from];
        if (fromBalance < value) revert InsufficientBalance();
        
        unchecked {
            balanceOf[from] = fromBalance - value;
        }
        
        // Check for overflow in recipient balance
        uint128 newToBalance = balanceOf[to] + value;
        if (newToBalance < balanceOf[to]) revert Overflow();
        
        balanceOf[to] = newToBalance;
        
        emit Transfer(from, to, uint256(value));
    }

    /**
     * @dev Approves spender to spend tokens on behalf of msg.sender
     * @param spender The address to approve
     * @param value The amount to approve
     * @return bool Always returns true
     */
    function approve(address spender, uint256 value) external override returns (bool) {
        require(value <= type(uint128).max, "Value exceeds uint128");
        _approve(msg.sender, spender, uint128(value));
        return true;
    }

    /**
     * @dev Transfers tokens from msg.sender to recipient
     * @param to The recipient address
     * @param value The amount to transfer
     * @return bool Always returns true
     */
    function transfer(address to, uint256 value) external override returns (bool) {
        require(value <= type(uint128).max, "Value exceeds uint128");
        _transfer(msg.sender, to, uint128(value));
        return true;
    }

    /**
     * @dev Transfers tokens from one address to another
     * @param from The sender address
     * @param to The recipient address
     * @param value The amount to transfer
     * @return bool Always returns true
     */
    function transferFrom(address from, address to, uint256 value) external override returns (bool) {
        require(value <= type(uint128).max, "Value exceeds uint128");
        uint128 value128 = uint128(value);
        uint128 currentAllowance = allowance[from][msg.sender];
        
        // Check for unlimited approval (max uint128)
        if (currentAllowance != type(uint128).max) {
            if (currentAllowance < value128) revert InsufficientAllowance();
            
            unchecked {
                allowance[from][msg.sender] = currentAllowance - value128;
            }
        }
        
        _transfer(from, to, value128);
        return true;
    }

    /**
     * @dev Allows approval via signature (EIP-2612)
     * @param owner The token owner
     * @param spender The spender address  
     * @param value The amount to approve
     * @param deadline The deadline timestamp
     * @param v The signature v value
     * @param r The signature r value
     * @param s The signature s value
     */
    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external override {
        if (deadline < block.timestamp) revert ExpiredDeadline();
        require(value <= type(uint128).max, "Value exceeds uint128");
        
        bytes32 structHash = keccak256(
            abi.encode(
                PERMIT_TYPEHASH,
                owner,
                spender,
                value,
                nonces[owner]++,
                deadline
            )
        );
        
        bytes32 digest = keccak256(
            abi.encodePacked(
                '\x19\x01',
                DOMAIN_SEPARATOR,
                structHash
            )
        );
        
        address recoveredAddress = ecrecover(digest, v, r, s);
        if (recoveredAddress == address(0) || recoveredAddress != owner) {
            revert InvalidSignature();
        }
        
        _approve(owner, spender, uint128(value));
    }
}