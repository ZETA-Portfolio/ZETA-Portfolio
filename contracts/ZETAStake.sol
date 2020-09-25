// SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;

import "./interfaces/IERC20.sol";
import "./interfaces/SafeERC20.sol";
import "./interfaces/IAdmin.sol";
import "./interfaces/IZUSD.sol";

contract ZETAStake {
    using SafeMath for uint;
    using SafeERC20 for IERC20;

    IAdmin public admin;
    IZUSD public ZUSD;
    IERC20 public ZETA;

    poolInfo public rewardPool;

    struct userInfo {
        uint lastClaimAmount;
        uint depositAmount;
    }

    struct poolInfo {
        uint rewardRate;
        uint totalBalance;
    }

    mapping (address =>  userInfo) public userInfos;

    event Stake(address indexed _from, uint amount);
    event Unstake(address indexed _from, uint amount);
    event ClaimReward(address indexed _from, uint amount);

    constructor(address adminAddress, address zusdAddress, address zetaAddress) public {
        admin = IAdmin(adminAddress);
        ZUSD = IZUSD(zusdAddress);
        ZETA = IERC20(zetaAddress);
    }

    function changeZUSD(address addr) public {
        require(msg.sender == admin.admin(), "Not admin");
        ZUSD = IZUSD(addr);
    }

    function changeZETA(address addr) public {
        require(msg.sender == admin.admin(), "Not admin");
        ZETA = IERC20(addr);
    }

    function rewardAmount(address account) public view returns (uint) {
        poolInfo memory pool = rewardPool;
        userInfo memory user = userInfos[account];

        uint rewardRate = pool.rewardRate;
        if (pool.totalBalance != 0) {
            uint rewards = IERC20(address(ZUSD)).balanceOf(address(ZUSD));
            rewardRate = rewardRate.add(
                rewards
                .mul(1e18)
                .div(pool.totalBalance));
        }
        return user.depositAmount.mul(rewardRate).div(1e18).sub(user.lastClaimAmount);
    }

    function stake(uint amount) public {
        userInfo storage user = userInfos[msg.sender];

        if (user.depositAmount > 0) {
            claimReward();
        } else {
            updatePool();
        }

        rewardPool.totalBalance = rewardPool.totalBalance.add(amount);

        user.depositAmount = user.depositAmount.add(amount);
        user.lastClaimAmount = user.depositAmount.mul(rewardPool.rewardRate).div(1e18);

        ZETA.safeTransferFrom(msg.sender, address(this), amount);
        emit Stake(msg.sender, amount);
    }

    function updatePool() private {
        if (rewardPool.totalBalance == 0) {
            return;
        }

        uint _before = IERC20(address(ZUSD)).balanceOf(address(this));
        ZUSD.sendReward();
        uint _after = IERC20(address(ZUSD)).balanceOf(address(this));

        uint rewardTotal = _after.sub(_before);

        rewardPool.rewardRate = rewardPool.rewardRate
            .add(rewardTotal
                .mul(1e18)
                .div(rewardPool.totalBalance)
        );
    }

    function unstake(uint amount) public {
        userInfo storage user = userInfos[msg.sender];

        claimReward();

        rewardPool.totalBalance = rewardPool.totalBalance.sub(amount);

        user.depositAmount = user.depositAmount.sub(amount);
        user.lastClaimAmount = user.depositAmount.mul(rewardPool.rewardRate).div(1e18);

        ZETA.safeTransfer(msg.sender, amount);
        emit Unstake(msg.sender, amount);
    }

    function claimReward() public {
        userInfo storage user = userInfos[msg.sender];

        updatePool();

        uint reward = user.depositAmount
            .mul(rewardPool.rewardRate)
            .div(1e18)
            .sub(user.lastClaimAmount);


        user.lastClaimAmount = reward.add(user.lastClaimAmount);
        IERC20(address(ZUSD)).safeTransfer(msg.sender, reward);

        emit ClaimReward(msg.sender, reward);
    }
}