// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title ActivationHandler
 * @notice Handles activation logic for pools using timestamp-based activation only
 * @dev Simplified from Rust implementation to use only timestamp
 */
contract ActivationHandler {
    // ==================== Constants ====================
    
    // Time-based constants (in seconds)
    uint64 public constant TIME_BUFFER = 3600;                              // 1 hour in seconds
    uint64 public constant MAX_ACTIVATION_TIME_DURATION = TIME_BUFFER * 24 * 31;  // 31 days
    uint64 public constant MAX_VESTING_TIME_DURATION = TIME_BUFFER * 24 * 365 * 10; // 10 years
    uint64 public constant FIVE_MINUTES_TIME_BUFFER = TIME_BUFFER / 12;    // 5 minutes (300 seconds)
    uint64 public constant MAX_FEE_CURVE_TIME_DURATION = 3600 * 24;        // 1 day
    uint64 public constant MAX_HIGH_TAX_TIME_DURATION = TIME_BUFFER / 6;   // 10 minutes (600 seconds)
    
    // ==================== Custom Errors ====================
    error ArithmeticOverflow();
    error ArithmeticUnderflow();
    error DivisionByZero();
    error InvalidPool();
    error ActivationNotSet();
    
    // ==================== Structs ====================
    struct ActivationData {
        uint64 activationPoint;      // activation timestamp
        uint64 bufferDuration;       // buffer duration in seconds
        address whitelistedVault;    // whitelisted vault address
        bool initialized;            // whether this pool has been initialized
    }
    
    // ==================== State Variables ====================
    mapping(address => ActivationData) public poolActivations;
    
    // ==================== Events ====================
    event ActivationSet(
        address indexed pool,
        uint64 activationPoint,
        uint64 bufferDuration,
        address whitelistedVault
    );
    
    // ==================== Modifiers ====================
    modifier poolInitialized(address pool) {
        if (!poolActivations[pool].initialized) {
            revert ActivationNotSet();
        }
        _;
    }
    
    // ==================== Public View Functions ====================
    
    /**
     * @notice Get current timestamp
     * @return Current block timestamp
     */
    function getCurrentPoint() public view returns (uint64) {
        return uint64(block.timestamp);
    }
    
    /**
     * @notice Get current timestamp and max vesting duration
     * @return currentPoint Current timestamp
     * @return maxVestingDuration Maximum vesting duration in seconds
     */
    function getCurrentPointAndMaxVestingDuration() 
        public 
        view 
        returns (uint64 currentPoint, uint64 maxVestingDuration) 
    {
        currentPoint = uint64(block.timestamp);
        maxVestingDuration = MAX_VESTING_TIME_DURATION;
    }
    
    /**
     * @notice Get current timestamp and buffer duration
     * @return currentPoint Current timestamp
     * @return bufferDuration Buffer duration in seconds
     */
    function getCurrentPointAndBufferDuration() 
        public 
        view 
        returns (uint64 currentPoint, uint64 bufferDuration) 
    {
        currentPoint = uint64(block.timestamp);
        bufferDuration = TIME_BUFFER;
    }
    
    /**
     * @notice Get maximum allowed activation timestamp from now
     * @return Maximum activation timestamp
     */
    function getMaxActivationPoint() public view returns (uint64) {
        uint64 currentPoint = uint64(block.timestamp);
        return safeAdd(currentPoint, MAX_ACTIVATION_TIME_DURATION);
    }
    
    /**
     * @notice Get pre-activation start timestamp for a pool
     * @param pool The pool address
     * @return Pre-activation start timestamp
     */
    function getPreActivationStartPoint(address pool) 
        public 
        view 
        poolInitialized(pool)
        returns (uint64) 
    {
        ActivationData memory data = poolActivations[pool];
        return safeSub(data.activationPoint, data.bufferDuration);
    }
    
    /**
     * @notice Get last join timestamp from alpha-vault
     * @dev This is the deadline for alpha-vault to join the pool (5 minutes before pre-activation)
     * @param pool The pool address
     * @return Last join timestamp
     */
    function getLastJoinPoint(address pool) 
        public 
        view 
        poolInitialized(pool)
        returns (uint64) 
    {
        uint64 preActivationStartPoint = getPreActivationStartPoint(pool);
        // Use FIVE_MINUTES_TIME_BUFFER constant (5 minutes)
        return safeSub(preActivationStartPoint, FIVE_MINUTES_TIME_BUFFER);
    }
    
    /**
     * @notice Check if pool is in pre-activation phase
     * @param pool The pool address
     * @return true if in pre-activation phase
     */
    function isInPreActivation(address pool) 
        public 
        view 
        poolInitialized(pool)
        returns (bool) 
    {
        ActivationData memory data = poolActivations[pool];
        uint64 currentTimestamp = uint64(block.timestamp);
        uint64 preActivationStart = getPreActivationStartPoint(pool);
        
        return currentTimestamp >= preActivationStart && currentTimestamp < data.activationPoint;
    }
    
    /**
     * @notice Check if pool is activated
     * @param pool The pool address
     * @return true if activated
     */
    function isActivated(address pool) 
        public 
        view 
        poolInitialized(pool)
        returns (bool) 
    {
        ActivationData memory data = poolActivations[pool];
        return uint64(block.timestamp) >= data.activationPoint;
    }
    
    /**
     * @notice Check if current time is past the last join point
     * @param pool The pool address
     * @return true if past last join point
     */
    function isPastLastJoinPoint(address pool)
        public
        view
        poolInitialized(pool)
        returns (bool)
    {
        uint64 lastJoinPoint = getLastJoinPoint(pool);
        return uint64(block.timestamp) > lastJoinPoint;
    }
    
    /**
     * @notice Check if an address is the whitelisted vault for a pool
     * @param pool The pool address
     * @param vault The vault address to check
     * @return true if vault is whitelisted
     */
    function isWhitelistedVault(address pool, address vault) 
        public 
        view 
        poolInitialized(pool)
        returns (bool) 
    {
        return poolActivations[pool].whitelistedVault == vault;
    }
    
    /**
     * @notice Get all activation data for a pool
     * @param pool The pool address
     * @return Activation data struct
     */
    function getActivationData(address pool) 
        external 
        view 
        poolInitialized(pool)
        returns (ActivationData memory) 
    {
        return poolActivations[pool];
    }
    
    /**
     * @notice Get time until activation
     * @param pool The pool address
     * @return Seconds until activation (0 if already activated)
     */
    function getTimeUntilActivation(address pool)
        public
        view
        poolInitialized(pool)
        returns (uint64)
    {
        ActivationData memory data = poolActivations[pool];
        uint64 currentTimestamp = uint64(block.timestamp);
        
        if (currentTimestamp >= data.activationPoint) {
            return 0;
        }
        
        return data.activationPoint - currentTimestamp;
    }
    
    /**
     * @notice Get time until pre-activation starts
     * @param pool The pool address  
     * @return Seconds until pre-activation (0 if already in pre-activation or activated)
     */
    function getTimeUntilPreActivation(address pool)
        public
        view
        poolInitialized(pool)
        returns (uint64)
    {
        uint64 preActivationStart = getPreActivationStartPoint(pool);
        uint64 currentTimestamp = uint64(block.timestamp);
        
        if (currentTimestamp >= preActivationStart) {
            return 0;
        }
        
        return preActivationStart - currentTimestamp;
    }
    
    // ==================== External Functions ====================
    
    /**
     * @notice Set activation data for a pool
     * @param pool The pool address
     * @param activationPoint The activation timestamp
     * @param bufferDuration The buffer duration (defaults to TIME_BUFFER if 0)
     * @param whitelistedVault The whitelisted vault address
     */
    function setActivationData(
        address pool,
        uint64 activationPoint,
        uint64 bufferDuration,
        address whitelistedVault
    ) external {
        // Add access control here (onlyOwner, onlyPoolFactory, etc.)
        
        if (pool == address(0)) revert InvalidPool();
        
        // Use default buffer if not specified
        if (bufferDuration == 0) {
            bufferDuration = TIME_BUFFER;
        }
        
        // Validate activation point is in the future
        require(activationPoint > block.timestamp, "Activation must be in future");
        
        // Validate activation point is not too far in the future
        require(
            activationPoint <= getMaxActivationPoint(),
            "Activation too far in future"
        );
        
        poolActivations[pool] = ActivationData({
            activationPoint: activationPoint,
            bufferDuration: bufferDuration,
            whitelistedVault: whitelistedVault,
            initialized: true
        });
        
        emit ActivationSet(pool, activationPoint, bufferDuration, whitelistedVault);
    }
    
    // ==================== Internal Safe Math Functions ====================
    
    /**
     * @notice Safe addition with overflow check
     */
    function safeAdd(uint64 a, uint64 b) internal pure returns (uint64) {
        uint64 c = a + b;
        if (c < a) revert ArithmeticOverflow();
        return c;
    }
    
    /**
     * @notice Safe subtraction with underflow check
     */
    function safeSub(uint64 a, uint64 b) internal pure returns (uint64) {
        if (b > a) revert ArithmeticUnderflow();
        return a - b;
    }
    
    /**
     * @notice Safe division with zero check
     */
    function safeDiv(uint64 a, uint64 b) internal pure returns (uint64) {
        if (b == 0) revert DivisionByZero();
        return a / b;
    }
}