// SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;

import "./interfaces/IAdmin.sol";
import "./interfaces/IERC20.sol";

contract ReserveContract {
    IAdmin public admin;
    IERC20 public zeta;

    constructor (address adminAddress) public {
        admin = IAdmin(adminAddress);
    }

    function setZETA(address zetaAddress) public {
        require(msg.sender == admin.admin(), "Not admin");
        zeta = IERC20(zetaAddress);
    }

    function sendReserveFunds(address addr, uint amount) public {
        require(msg.sender == admin.admin(), "Not admin");
        zeta.transfer(addr, amount);
    }
}