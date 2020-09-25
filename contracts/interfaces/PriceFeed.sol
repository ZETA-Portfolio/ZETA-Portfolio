// SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;

interface PriceFeed {
    function addPriceFeed(address addr) external;
    function getLatestPrice(uint idx) external view returns (uint);
}