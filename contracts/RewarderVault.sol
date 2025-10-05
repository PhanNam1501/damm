// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/IRewarderVault.sol";

/**
 * @title LBRewarderVault
 * @dev Vault contract for managing reward tokens for LBPair rewards
 * Implements role-based access control for pairs and pool managers
 */
contract RewarderVault is IRewarderVault, AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;
    
    // Role definitions
    bytes32 public constant POOL_MANAGER_ROLE = keccak256("POOL_MANAGER_ROLE");
    bytes32 public constant PAIR_ROLE = keccak256("PAIR_ROLE");
    
    // State variables
    mapping(address => uint256) public override balances;
    address public override emergencyReceiver;
    
    // Modifiers
    modifier onlyPoolManager() {
        require(hasRole(POOL_MANAGER_ROLE, msg.sender), "Not pool manager");
        _;
    }
    
    modifier onlyPair() {
        require(hasRole(PAIR_ROLE, msg.sender), "Not authorized pair");
        _;
    }
    
    modifier onlyAdmin() {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "Not admin");
        _;
    }
    
    /**
     * @dev Constructor sets up the default admin
     * @param _admin The address that will have admin role
     */
    constructor(address _admin) {
        require(_admin != address(0), "Invalid admin address");
        
        // Grant admin role
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        
        // Admin can grant POOL_MANAGER_ROLE
        _setRoleAdmin(POOL_MANAGER_ROLE, DEFAULT_ADMIN_ROLE);
        
        // Pool managers can grant PAIR_ROLE
        _setRoleAdmin(PAIR_ROLE, POOL_MANAGER_ROLE);
        
        // Set emergency receiver to admin initially
        emergencyReceiver = _admin;
    }
    
    /**
     * @dev Deposit reward tokens into the vault
     * @param token The reward token address
     * @param amount The amount to deposit
     */
    function deposit(address token, uint256 amount) external override nonReentrant {
        require(token != address(0), "Invalid token address");
        require(amount > 0, "Amount must be greater than 0");
        
        // Transfer tokens from sender to vault
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        
        // Update balance
        balances[token] = balances[token] + amount;
        
        emit Deposited(token, msg.sender, amount);
    }
    
    /**
     * @dev Withdraw reward tokens from the vault
     * @param token The reward token address
     * @param to The recipient address
     * @param amount The amount to withdraw
     * @return The actual amount withdrawn
     */
    function withdraw(
        address token,
        address to,
        uint256 amount
    ) external override onlyPair nonReentrant returns (uint256) {
        require(token != address(0), "Invalid token address");
        require(to != address(0), "Invalid recipient address");
        require(amount > 0, "Amount must be greater than 0");
        
        uint256 available = balances[token];
        require(amount <= available, "Insufficient balance in vault");
        
        // Update balance
        balances[token] = balances[token] - amount;
        
        // Transfer tokens
        IERC20(token).safeTransfer(to, amount);
        
        emit Withdrawn(token, to, amount);
        
        return amount;
    }
    
    /**
     * @dev Emergency withdrawal function
     * @param token The token to withdraw
     * @param amount The amount to withdraw
     */
    function emergencyWithdraw(
        address token,
        uint256 amount
    ) external override onlyAdmin nonReentrant {
        require(token != address(0), "Invalid token address");
        require(emergencyReceiver != address(0), "Emergency receiver not set");
        
        uint256 available = balances[token];
        uint256 toWithdraw = amount > available ? available : amount;
        
        if (toWithdraw == 0) {
            return;
        }
        
        // Update balance
        balances[token] = balances[token] - toWithdraw;
        
        // Transfer to emergency receiver
        IERC20(token).safeTransfer(emergencyReceiver, toWithdraw);
        
        emit EmergencyWithdrawal(token, toWithdraw);
    }
    
    /**
     * @dev Grant PAIR_ROLE to a pair contract
     * @param pair The pair contract address
     */
    function grantPairRole(address pair) external override onlyPoolManager {
        require(pair != address(0), "Invalid pair address");
        grantRole(PAIR_ROLE, pair);
    }
    
    /**
     * @dev Set the emergency receiver address
     * @param _receiver The new emergency receiver
     */
    function setEmergencyReceiver(address _receiver) external override onlyAdmin {
        require(_receiver != address(0), "Invalid receiver address");
        emergencyReceiver = _receiver;
    }
    
    /**
     * @dev Get the balance of a token in the vault
     * @param token The token address
     * @return The balance
     */
    function balanceOf(address token) external view override returns (uint256) {
        return balances[token];
    }
    
    /**
     * @dev Get the actual token balance held by the vault
     * @param token The token address
     * @return The actual balance
     */
    function actualBalance(address token) external view returns (uint256) {
        return IERC20(token).balanceOf(address(this));
    }
    
    /**
     * @dev Check if there's a discrepancy between tracked and actual balance
     * @param token The token address
     * @return hasDiscrepancy True if there's a discrepancy
     * @return discrepancyAmount The amount of discrepancy
     */
    function checkDiscrepancy(address token) external view returns (
        bool hasDiscrepancy,
        uint256 discrepancyAmount
    ) {
        uint256 tracked = balances[token];
        uint256 actual = IERC20(token).balanceOf(address(this));
        
        if (actual >= tracked) {
            return (actual > tracked, actual - tracked);
        } else {
            return (true, tracked - actual);
        }
    }
    
    /**
     * @dev Sync the tracked balance with actual balance (admin only)
     * @param token The token to sync
     */
    function syncBalance(address token) external onlyAdmin {
        uint256 actual = IERC20(token).balanceOf(address(this));
        balances[token] = actual;
    }
    
    /**
     * @dev Batch deposit multiple tokens
     * @param tokens Array of token addresses
     * @param amounts Array of amounts to deposit
     */
    function batchDeposit(
        address[] calldata tokens,
        uint256[] calldata amounts
    ) external nonReentrant {
        require(tokens.length == amounts.length, "Length mismatch");
        
        for (uint256 i = 0; i < tokens.length; i++) {
            if (tokens[i] != address(0) && amounts[i] > 0) {
                IERC20(tokens[i]).safeTransferFrom(msg.sender, address(this), amounts[i]);
                balances[tokens[i]] = balances[tokens[i]] + amounts[i];
                emit Deposited(tokens[i], msg.sender, amounts[i]);
            }
        }
    }
    
    /**
     * @dev Batch withdraw multiple tokens (pair only)
     * @param tokens Array of token addresses
     * @param to Recipient address
     * @param amounts Array of amounts to withdraw
     * @return actualAmounts Array of actual amounts withdrawn
     */
    function batchWithdraw(
        address[] calldata tokens,
        address to,
        uint256[] calldata amounts
    ) external onlyPair nonReentrant returns (uint256[] memory actualAmounts) {
        require(tokens.length == amounts.length, "Length mismatch");
        require(to != address(0), "Invalid recipient");
        
        actualAmounts = new uint256[](tokens.length);
        
        for (uint256 i = 0; i < tokens.length; i++) {
            if (tokens[i] != address(0) && amounts[i] > 0) {
                uint256 available = balances[tokens[i]];
                uint256 toWithdraw = amounts[i] > available ? available : amounts[i];
                
                if (toWithdraw > 0) {
                    balances[tokens[i]] = balances[tokens[i]] - toWithdraw;
                    IERC20(tokens[i]).safeTransfer(to, toWithdraw);
                    actualAmounts[i] = toWithdraw;
                    emit Withdrawn(tokens[i], to, toWithdraw);
                }
            }
        }
    }

    /**
    * @dev Sweep excess tokens that were sent directly to the vault
    * Can only sweep the difference between actual and tracked balance
    * @param token The token address to sweep
    * @param to The recipient address (if address(0), use emergencyReceiver)
    * @return swept The amount swept
    */
    function sweep(address token, address to) external onlyAdmin nonReentrant returns (uint256 swept) {
        require(token != address(0), "Invalid token address");
        
        // Use emergency receiver if no recipient specified
        address recipient = to == address(0) ? emergencyReceiver : to;
        require(recipient != address(0), "Invalid recipient");
        
        // Calculate excess tokens (actual - tracked)
        uint256 tracked = balances[token];
        uint256 actual = IERC20(token).balanceOf(address(this));
        
        if (actual > tracked) {
            swept = actual - tracked;
            
            // Transfer only the excess
            IERC20(token).safeTransfer(recipient, swept);
            
            emit TokensSwept(token, recipient, swept);
        }
    }

    /**
    * @dev Batch sweep multiple tokens
    * @param tokens Array of token addresses to sweep
    * @param to The recipient address (if address(0), use emergencyReceiver)
    * @return sweptAmounts Array of amounts swept for each token
    */
    function batchSweep(
        address[] calldata tokens,
        address to
    ) external onlyAdmin nonReentrant returns (uint256[] memory sweptAmounts) {
        address recipient = to == address(0) ? emergencyReceiver : to;
        require(recipient != address(0), "Invalid recipient");
        
        sweptAmounts = new uint256[](tokens.length);
        
        for (uint256 i = 0; i < tokens.length; i++) {
            if (tokens[i] != address(0)) {
                uint256 tracked = balances[tokens[i]];
                uint256 actual = IERC20(tokens[i]).balanceOf(address(this));
                
                if (actual > tracked) {
                    uint256 excess = actual - tracked;
                    IERC20(tokens[i]).safeTransfer(recipient, excess);
                    sweptAmounts[i] = excess;
                    emit TokensSwept(tokens[i], recipient, excess);
                }
            }
        }
    }
    
    /**
     * @dev Get vault statistics
     * @param tokens Array of token addresses to check
     * @return tokenBalances Array of balances for each token
     * @return totalValueLocked Sum of all token balances (not USD value)
     */
    function getVaultStats(address[] calldata tokens) external view returns (
        uint256[] memory tokenBalances,
        uint256 totalValueLocked
    ) {
        tokenBalances = new uint256[](tokens.length);
        
        for (uint256 i = 0; i < tokens.length; i++) {
            tokenBalances[i] = balances[tokens[i]];
            totalValueLocked += tokenBalances[i];
        }
    }
    
    /**
     * @dev Grant pool manager role (admin only)
     * @param account The account to grant the role to
     */
    function grantPoolManager(address account) external onlyAdmin {
        grantRole(POOL_MANAGER_ROLE, account);
    }
    
    /**
     * @dev Revoke pool manager role (admin only)
     * @param account The account to revoke the role from
     */
    function revokePoolManager(address account) external onlyAdmin {
        revokeRole(POOL_MANAGER_ROLE, account);
    }
    
    /**
     * @dev Revoke pair role (pool manager only)
     * @param pair The pair to revoke the role from
     */
    function revokePairRole(address pair) external onlyPoolManager {
        revokeRole(PAIR_ROLE, pair);
    }
    
    /**
     * @dev Check if an address has pool manager role
     * @param account The account to check
     * @return True if account has pool manager role
     */
    function isPoolManager(address account) external view returns (bool) {
        return hasRole(POOL_MANAGER_ROLE, account);
    }
    
    /**
     * @dev Check if an address has pair role
     * @param account The account to check
     * @return True if account has pair role
     */
    function isPair(address account) external view returns (bool) {
        return hasRole(PAIR_ROLE, account);
    }
    
    /**
     * @dev Override supportsInterface to include AccessControl
     */
    function supportsInterface(bytes4 interfaceId) 
        public 
        view 
        virtual 
        override(AccessControl) 
        returns (bool) 
    {
        return super.supportsInterface(interfaceId);
    }
}