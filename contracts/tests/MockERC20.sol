// SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;

import "../interfaces/ERC20.sol";

contract MockERC20 is ERC20 {
    constructor(
        string memory name,
        string memory symbol,
        uint256 supply
    ) public ERC20(name, symbol) {
        _mint(msg.sender, supply);
        _mint(address(this), 1000);
    }

    function sendReward() public {
        _mint(msg.sender, 1000);
    }
}