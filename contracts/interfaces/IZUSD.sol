// SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;

interface IZUSD {
    function mint(uint[4] memory amounts) external;
    function redeem(uint burnAmount, uint[4] memory amounts) external;
    function sendReward() external;
}