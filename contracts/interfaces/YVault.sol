// SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;

interface YVault {
    function deposit(uint _amount) external;
    function depositAll() external;
    function withdraw(uint _amount) external;
    function balance() external view returns (uint);
}