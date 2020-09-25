// SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;

import "./interfaces/IAdmin.sol";

contract Admin {
    address public admin;

    constructor () public {
        admin = msg.sender;
    }

    function changeAdmin(address addr) public {
        require(msg.sender == admin, "Not admin");
        admin = addr;
    }
}