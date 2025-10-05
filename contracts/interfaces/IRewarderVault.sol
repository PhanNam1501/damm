// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IRewarderVault
 * @dev Interface for reward token vault
 */
interface IRewarderVault {
    event Deposited(address indexed token, address indexed from, uint256 amount);
    event Withdrawn(address indexed token, address indexed to, uint256 amount);
    event EmergencyWithdrawal(address indexed token, uint256 amount);
    event TokensSwept(address indexed token, address indexed recipient, uint256 swept);
    
    function balances(address token) external view returns (uint256);
    function emergencyReceiver() external view returns (address);
    
    function deposit(address token, uint256 amount) external;
    
    function withdraw(
        address token,
        address to,
        uint256 amount
    ) external returns (uint256);
    
    function emergencyWithdraw(address token, uint256 amount) external;
    
    function grantPairRole(address pair) external;
    
    function setEmergencyReceiver(address _receiver) external;
    
    function balanceOf(address token) external view returns (uint256);
}