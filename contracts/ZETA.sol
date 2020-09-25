// SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;

import "./interfaces/ERC20.sol";
import "./interfaces/IERC20.sol";
import "./interfaces/SafeERC20.sol";
import "./interfaces/IAdmin.sol";
import "./interfaces/IUNIStakingRewards.sol";

contract ZETA is ERC20 {
    using SafeMath for uint;
    using SafeERC20 for IERC20;

    uint public tokenPerBlock;

    uint public constant BONUS_MULTIPLIER = 3;
    uint public constant ADMIN_DIVIDER = 10;

    uint public startBlock;
    uint public bonusEndBlock;
    uint public endBlock;

    uint public adminEndBlock;
    uint public lastClaimBlockAdmin;

    uint public totalPoolWeight;

    IAdmin public admin;

    poolInfo[] public rewardPools;
    address public UNI;

    struct userInfo {
        uint lastClaimAmount;
        uint depositAmount;
        uint rewardsUni;
        uint userRewardPerTokenPaidUni;
    }

    struct poolInfo {
        address addr;
        address addrUni;
        uint rewardRate;
        uint lastUpdateBlock;
        uint totalBalance;
        uint poolWeight;
        uint totalRewardsUni;
    }


    mapping (address => mapping (uint8 => userInfo)) public userInfos;

    event NewRewardPool(address rewardPool);
    event Deposit(address indexed _from, uint8 indexed idx, uint amount);
    event Withdrawal(address indexed _from, uint8 indexed idx, uint amount);
    event ClaimReward(address indexed _from, uint8 indexed idx, uint amount);

    constructor (
        address adminAddress,
        address uni,
        uint _tokenPerBlock,
        uint _startBlock,
        uint _bonusEndBlock,
        uint _endBlock,
        uint _adminEndBlock
    ) ERC20("ZETA", "ZETA") public {
        tokenPerBlock = _tokenPerBlock;
        startBlock = _startBlock;
        bonusEndBlock = _bonusEndBlock;
        endBlock = _endBlock;
        adminEndBlock = _adminEndBlock;
        lastClaimBlockAdmin = startBlock;

        admin = IAdmin(adminAddress);
        UNI = uni;
        userInfos[admin.admin()][0] = userInfo(0, 0, 0, 0);
    }

    function addRewardPool(address addr, address addrUni, uint poolWeight) public {
        require(msg.sender == admin.admin(), "Not admin");
        for (uint8 i = 0; i < rewardPools.length; i++) {
            updatePool(i);
        }
        rewardPools.push(
            poolInfo(
                addr,
                addrUni,
                0,
                startBlock > block.number ? startBlock : block.number,
                0,
                poolWeight,
                0
            )
        );
        totalPoolWeight = totalPoolWeight.add(poolWeight);
        emit NewRewardPool(addr);
    }

    function setPoolWeight(uint8 idx, uint poolWeight) public {
        require(msg.sender == admin.admin(), "Not admin");
        for (uint8 i = 0; i < rewardPools.length; i++) {
            updatePool(i);
        }
        totalPoolWeight = totalPoolWeight.sub(rewardPools[idx].poolWeight).add(poolWeight);
        rewardPools[idx].poolWeight = poolWeight;
    }

    function rewardPerPeriod(uint lastUpdateBlock) public view returns (uint) {
        uint _from = lastUpdateBlock;
        uint _to = block.number < startBlock ? startBlock : (block.number > endBlock ? endBlock : block.number);

        uint period;
        if (_to <= bonusEndBlock) {
            period = _to.sub(_from).mul(BONUS_MULTIPLIER);
        } else if (_from >= bonusEndBlock) {
            period = _to.sub(_from);
        } else {
            period = bonusEndBlock.sub(_from).mul(BONUS_MULTIPLIER).add(
                _to.sub(bonusEndBlock)
            );
        }

        return period.mul(tokenPerBlock);
    }

    function rewardAmount(uint8 idx, address account) public view returns (uint) {
        poolInfo memory pool = rewardPools[idx];
        userInfo memory user = userInfos[account][idx];

        uint rewardRate = pool.rewardRate;
        if (block.number > pool.lastUpdateBlock && pool.totalBalance != 0) {
            rewardRate = rewardRate.add(
                rewardPerPeriod(pool.lastUpdateBlock)
                    .mul(pool.poolWeight)
                    .div(totalPoolWeight)
                    .mul(1e18)
                    .div(pool.totalBalance));
        }
        return user.depositAmount.mul(rewardRate).div(1e18).sub(user.lastClaimAmount);
    }

    function rewardAmountUni(uint8 idx, address account) public view returns (uint) {
        poolInfo memory pool = rewardPools[idx];
        userInfo memory user = userInfos[account][idx];
        uint rewardPerTokenUni = 0;
        if(pool.addrUni != address(0)) {
            rewardPerTokenUni = IUNIStakingRewards(pool.addrUni).rewardPerToken();
        }
        return user.depositAmount
            .mul(rewardPerTokenUni.sub(user.userRewardPerTokenPaidUni))
            .div(1e18)
            .add(user.rewardsUni);
    }

    function deposit(uint8 idx, uint amount) public {
        require(idx < rewardPools.length, "Not in reward pool list");

        userInfo storage user = userInfos[msg.sender][idx];
        poolInfo storage pool = rewardPools[idx];

        if (user.depositAmount > 0) {
            claimReward(idx);
        } else {
            updatePool(idx);
        }

        pool.totalBalance = pool.totalBalance.add(amount);

        user.depositAmount = user.depositAmount.add(amount);
        user.lastClaimAmount = user.depositAmount.mul(pool.rewardRate).div(1e18);

        IERC20(pool.addr).safeTransferFrom(msg.sender, address(this), amount);

        if (pool.addrUni != address(0)) {
            IERC20(pool.addr).approve(pool.addrUni, amount);
            IUNIStakingRewards(pool.addrUni).stake(amount);
        }

        emit Deposit(msg.sender, idx, amount);
    }

    function withdraw(uint8 idx, uint amount) public {
        require(idx < rewardPools.length, "Not in reward pool list");

        userInfo storage user = userInfos[msg.sender][idx];
        poolInfo storage pool = rewardPools[idx];

        claimReward(idx);

        pool.totalBalance = pool.totalBalance.sub(amount);

        user.depositAmount = user.depositAmount.sub(amount);
        user.lastClaimAmount = user.depositAmount.mul(pool.rewardRate).div(1e18);

        if (pool.addrUni != address(0)) {
            IUNIStakingRewards(pool.addrUni).withdraw(amount);
        }

        IERC20(pool.addr).safeTransfer(msg.sender, amount);

        emit Withdrawal(msg.sender, idx, amount);
    }

    function updatePoolUni(uint8 idx) private {
        poolInfo storage pool = rewardPools[idx];
        userInfo storage user = userInfos[msg.sender][idx];
        IUNIStakingRewards uni = IUNIStakingRewards(pool.addrUni);

        uint _before = IERC20(UNI).balanceOf(address(this));
        uni.getReward();
        uint _after = IERC20(UNI).balanceOf(address(this));
        pool.totalRewardsUni = pool.totalRewardsUni.add(_after.sub(_before));

        uint rewardPerTokenUni = uni.rewardPerTokenStored();

        user.rewardsUni = user.depositAmount
            .mul(rewardPerTokenUni.sub(user.userRewardPerTokenPaidUni))
            .div(1e18)
            .add(user.rewardsUni);
        user.userRewardPerTokenPaidUni = rewardPerTokenUni;
    }

    function claimRewardUni(uint8 idx) private {
        poolInfo storage pool = rewardPools[idx];
        userInfo storage user = userInfos[msg.sender][idx];
        updatePoolUni(idx);

        if(user.rewardsUni > 0) {
            uint _rewardAmount = user.rewardsUni;
            if(_rewardAmount > pool.totalRewardsUni) {
                _rewardAmount = pool.totalRewardsUni;
            }
            user.rewardsUni = 0;
            pool.totalRewardsUni = pool.totalRewardsUni.sub(_rewardAmount);
            IERC20(UNI).safeTransfer(msg.sender, _rewardAmount);
        }
    }

    function updatePool(uint8 idx) private {
        poolInfo storage pool = rewardPools[idx];

        if (pool.addrUni != address(0)) {
            claimRewardUni(idx);
        }

        if (block.number <= pool.lastUpdateBlock) {
            return;
        }

        uint currentBlock = block.number >= endBlock ? endBlock : block.number;

        if (pool.totalBalance == 0) {
            pool.lastUpdateBlock = currentBlock;
            return;
        }

        uint rewardPerPool = rewardPerPeriod(pool.lastUpdateBlock)
            .mul(pool.poolWeight)
            .div(totalPoolWeight);

        pool.rewardRate = pool.rewardRate
            .add(rewardPerPool
                .mul(1e18)
                .div(pool.totalBalance)
        );

        pool.lastUpdateBlock = currentBlock;
    }

    function claimReward(uint8 idx) public {
        require(idx < rewardPools.length, "Not in reward pool list");
        userInfo storage user = userInfos[msg.sender][idx];

        updatePool(idx);

        uint reward = user.depositAmount
            .mul(rewardPools[idx].rewardRate)
            .div(1e18)
            .sub(user.lastClaimAmount);

        user.lastClaimAmount = reward.add(user.lastClaimAmount);
        _mint(msg.sender, reward);

        emit ClaimReward(msg.sender, idx, reward);
    }

    function removeDust(uint8 idx) public {
        poolInfo memory pool = rewardPools[idx];

        IERC20(pool.addr).safeTransfer(
            admin.admin(),
            IERC20(pool.addr).balanceOf(address(this)).sub(pool.totalBalance)
        );
    }

    function claimRewardAdmin() public {
        require(lastClaimBlockAdmin < adminEndBlock, "No more reward");
        uint toBlock = block.number >= adminEndBlock ? adminEndBlock : block.number;
        uint reward = toBlock.sub(lastClaimBlockAdmin).mul(tokenPerBlock).div(ADMIN_DIVIDER);
        _mint(admin.admin(), reward);
        lastClaimBlockAdmin = toBlock;
        emit ClaimReward(admin.admin(), 0, reward);
    }
}