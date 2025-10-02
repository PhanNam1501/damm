// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IActivationHandler
 * @notice Interface for ActivationHandler contract
 * @dev Handles activation logic for pools using timestamp-based activation
 */
interface IActivationHandler {
    // ==================== Structs ====================
    struct ActivationData {
        uint64 activationPoint;      // activation timestamp
        uint64 bufferDuration;       // buffer duration in seconds
        address whitelistedVault;    // whitelisted vault address
        bool initialized;            // whether this pool has been initialized
    }
    
    // ==================== Events ====================
    event ActivationSet(
        address indexed pool,
        uint64 activationPoint,
        uint64 bufferDuration,
        address whitelistedVault
    );
    
    // ==================== Custom Errors ====================
    error ArithmeticOverflow();
    error ArithmeticUnderflow();
    error DivisionByZero();
    error InvalidPool();
    error ActivationNotSet();
    
    // ==================== View Functions ====================
    
    /**
     * @notice Get current timestamp
     * @return Current block timestamp
     */
    function getCurrentPoint() external view returns (uint64);
    
    /**
     * @notice Get current timestamp and max vesting duration
     * @return currentPoint Current timestamp
     * @return maxVestingDuration Maximum vesting duration in seconds
     */
    function getCurrentPointAndMaxVestingDuration() 
        external 
        view 
        returns (uint64 currentPoint, uint64 maxVestingDuration);
    
    /**
     * @notice Get current timestamp and buffer duration
     * @return currentPoint Current timestamp
     * @return bufferDuration Buffer duration in seconds
     */
    function getCurrentPointAndBufferDuration() 
        external 
        view 
        returns (uint64 currentPoint, uint64 bufferDuration);
    
    /**
     * @notice Get maximum allowed activation timestamp from now
     * @return Maximum activation timestamp
     */
    function getMaxActivationPoint() external view returns (uint64);
    
    /**
     * @notice Get pre-activation start timestamp for a pool
     * @param pool The pool address
     * @return Pre-activation start timestamp
     */
    function getPreActivationStartPoint(address pool) 
        external 
        view 
        returns (uint64);
    
    /**
     * @notice Get last join timestamp from alpha-vault
     * @dev This is the deadline for alpha-vault to join the pool
     * @param pool The pool address
     * @return Last join timestamp
     */
    function getLastJoinPoint(address pool) 
        external 
        view 
        returns (uint64);
    
    /**
     * @notice Check if pool is in pre-activation phase
     * @param pool The pool address
     * @return true if in pre-activation phase
     */
    function isInPreActivation(address pool) 
        external 
        view 
        returns (bool);
    
    /**
     * @notice Check if pool is activated
     * @param pool The pool address
     * @return true if activated
     */
    function isActivated(address pool) 
        external 
        view 
        returns (bool);
    
    /**
     * @notice Check if current time is past the last join point
     * @param pool The pool address
     * @return true if past last join point
     */
    function isPastLastJoinPoint(address pool)
        external
        view
        returns (bool);
    
    /**
     * @notice Check if an address is the whitelisted vault for a pool
     * @param pool The pool address
     * @param vault The vault address to check
     * @return true if vault is whitelisted
     */
    function isWhitelistedVault(address pool, address vault) 
        external 
        view 
        returns (bool);
    
    /**
     * @notice Get all activation data for a pool
     * @param pool The pool address
     * @return Activation data struct
     */
    function getActivationData(address pool) 
        external 
        view 
        returns (ActivationData memory);
    
    /**
     * @notice Get time until activation
     * @param pool The pool address
     * @return Seconds until activation (0 if already activated)
     */
    function getTimeUntilActivation(address pool)
        external
        view
        returns (uint64);
    
    /**
     * @notice Get time until pre-activation starts
     * @param pool The pool address  
     * @return Seconds until pre-activation (0 if already in pre-activation or activated)
     */
    function getTimeUntilPreActivation(address pool)
        external
        view
        returns (uint64);
    
    /**
     * @notice Get pool activations mapping value
     * @param pool The pool address
     * @return activationPoint The activation timestamp
     * @return bufferDuration The buffer duration 
     * @return whitelistedVault The whitelisted vault address
     * @return initialized Whether pool is initialized
     */
    function poolActivations(address pool) 
        external 
        view 
        returns (
            uint64 activationPoint,
            uint64 bufferDuration,
            address whitelistedVault,
            bool initialized
        );
    
    // ==================== State-Changing Functions ====================
    
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
    ) external;
    
    // ==================== Constants ====================
    
    function TIME_BUFFER() external view returns (uint64);
    function MAX_ACTIVATION_TIME_DURATION() external view returns (uint64);
    function MAX_VESTING_TIME_DURATION() external view returns (uint64);
    function FIVE_MINUTES_TIME_BUFFER() external view returns (uint64);
    function MAX_FEE_CURVE_TIME_DURATION() external view returns (uint64);
    function MAX_HIGH_TAX_TIME_DURATION() external view returns (uint64);
}