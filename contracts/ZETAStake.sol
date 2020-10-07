// SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;

import "./interfaces/ERC20.sol";
import "./interfaces/IERC20.sol";
import "./interfaces/SafeERC20.sol";
import "./interfaces/IAdmin.sol";
import "./interfaces/ZRewards.sol";

contract ZETAStake is ERC20 {
    using SafeMath for uint;
    using SafeERC20 for IERC20;

    IAdmin public admin;
    ZRewards[] public rewardsList;
    IERC20 public ZETA;

    uint[] public rewardRates;
    mapping (uint => mapping(address => uint)) public lastClaimAmount;

    event ClaimReward(uint indexed idx, address indexed _from, uint amount);

    constructor(address adminAddress, address zusdAddress, address zetaAddress) ERC20("sZETA", "sZETA") public {
        admin = IAdmin(adminAddress);

        rewardsList.push(ZRewards(zusdAddress));
        rewardRates.push(0);

        ZETA = IERC20(zetaAddress);
    }

    function addRewards(address addr) public {
        require(msg.sender == admin.admin(), "Not admin");
        rewardsList.push(ZRewards(addr));
        rewardRates.push(0);
    }

    function rewardAmount(uint idx, address account) public view returns (uint) {
        uint rewardRate = rewardRates[idx];
        uint TotalSupply = totalSupply();
        if (TotalSupply != 0) {
            uint rewards = IERC20(address(rewardsList[idx])).balanceOf(address(rewardsList[idx]));
            rewardRate = rewardRate.add(
                rewards
                .mul(1e18)
                .div(TotalSupply));
        }
        return balanceOf(account).mul(rewardRate).div(1e18).sub(lastClaimAmount[idx][account]);
    }

    function stake(uint amount) public {
        for(uint idx=0; idx<rewardsList.length; idx++) {
            _claimReward(idx, msg.sender, false);
        }

        _mint(msg.sender, amount);
        uint balance = balanceOf(msg.sender);

        for(uint idx=0; idx<rewardsList.length; idx++) {
            lastClaimAmount[idx][msg.sender] = balance.mul(rewardRates[idx]).div(1e18);
        }

        ZETA.safeTransferFrom(msg.sender, address(this), amount);
    }

    function updatePool(uint idx) private {
        if(IERC20(address(rewardsList[idx])).balanceOf(address(rewardsList[idx])) == 0) {
            return;
        }

        uint TotalSupply = totalSupply();
        if (TotalSupply == 0) {
            return;
        }

        uint _before = IERC20(address(rewardsList[idx])).balanceOf(address(this));
        rewardsList[idx].sendReward();
        uint _after = IERC20(address(rewardsList[idx])).balanceOf(address(this));

        uint rewardTotal = _after.sub(_before);

        rewardRates[idx] = rewardRates[idx]
            .add(rewardTotal
                .mul(1e18)
                .div(TotalSupply)
            );
    }

    function unstake(uint amount) public {
        for(uint idx=0; idx<rewardsList.length; idx++) {
            _claimReward(idx, msg.sender, false);
        }

        _burn(msg.sender, amount);
        uint balance = balanceOf(msg.sender);

        for(uint idx=0; idx<rewardsList.length; idx++) {
            lastClaimAmount[idx][msg.sender] = balance.mul(rewardRates[idx]).div(1e18);
        }

        ZETA.safeTransfer(msg.sender, amount);
    }

    function _claimReward(uint idx, address addr, bool isUpdated) private {
        if(!isUpdated) {
            updatePool(idx);
        }

        uint balance = balanceOf(addr);
        if(balance == 0) {
            return;
        }

        uint reward = balance
            .mul(rewardRates[idx])
            .div(1e18)
            .sub(lastClaimAmount[idx][addr]);

        if(reward > 0) {
            IERC20(address(rewardsList[idx])).safeTransfer(addr, reward);
        }
        emit ClaimReward(idx, addr, reward);
    }

    function claimReward() public {
        for(uint idx=0; idx<rewardsList.length; idx++) {
            _claimReward(idx, msg.sender, false);
            lastClaimAmount[idx][msg.sender] = balanceOf(msg.sender).mul(rewardRates[idx]).div(1e18);
        }
    }

    function transfer(address recipient, uint256 amount) public override returns (bool) {
        for(uint idx=0; idx<rewardsList.length; idx++) {
            _claimReward(idx, msg.sender, false);
            _claimReward(idx, recipient, true);
        }
        super.transfer(recipient, amount);
        uint fromBalance = balanceOf(msg.sender);
        uint toBalance = balanceOf(recipient);
        for(uint idx=0; idx<rewardsList.length; idx++) {
            lastClaimAmount[idx][msg.sender] = fromBalance.mul(rewardRates[idx]).div(1e18);
            lastClaimAmount[idx][recipient] = toBalance.mul(rewardRates[idx]).div(1e18);
        }
        return true;
    }

    function transferFrom(address sender, address recipient, uint256 amount) public override returns (bool) {
        for(uint idx=0; idx<rewardsList.length; idx++) {
            _claimReward(idx, sender, false);
            _claimReward(idx, recipient, true);
        }
        super.transferFrom(sender, recipient, amount);
        uint fromBalance = balanceOf(sender);
        uint toBalance = balanceOf(recipient);
        for(uint idx=0; idx<rewardsList.length; idx++) {
            lastClaimAmount[idx][sender] = fromBalance.mul(rewardRates[idx]).div(1e18);
            lastClaimAmount[idx][recipient] = toBalance.mul(rewardRates[idx]).div(1e18);
        }
        return true;
    }
}