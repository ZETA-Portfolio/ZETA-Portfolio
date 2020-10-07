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
    uint public tokenPerBlockAdmin;

    uint public BONUS_MULTIPLIER;

    uint public startBlock;
    uint public bonusEndBlock;
    uint public endBlock;

    uint public adminClaimRewardEndBlock;
    uint public lastClaimBlockAdmin;

    uint public totalPoolWeight;

    IAdmin public admin;

    poolInfo[] public rewardPools;
    address public UNIAddress;
    address public adminReceiveAddress;

    struct userInfo {
        uint lastClaimAmount;
        uint depositAmount;
        uint rewardsUni;
        uint userRewardPerTokenPaidUni;
    }

    struct poolInfo {
        address addrToken;
        address addrUniStakingRewards;
        uint rewardRate;
        uint lastUpdateBlock;
        uint totalBalance;
        uint poolWeight;
        uint totalRewardsUni;
    }


    mapping (address => mapping (uint => userInfo)) public userInfos;

    event NewRewardPool(address rewardPool);
    event Deposit(address indexed account, uint indexed idx, uint amount);
    event Withdrawal(address indexed account, uint indexed idx, uint amount);
    event ClaimReward(address indexed account, uint indexed idx, uint amount);

    constructor (
        address adminAddress,
        address _adminReceiveAddress,
        address reserveContractAddress,
        address YFIInspirdropAddress,
        address uniAddress,
        uint _tokenPerBlock,
        uint _startBlock,
        uint _bonusEndBlock,
        uint _endBlock,
        uint _adminEndBlock,
        uint initialReserveAmount,
        uint yfiAirdropAmount,
        uint _tokenPerBlockAdmin,
        uint _bonus_multiplier
    ) ERC20("ZETA", "ZETA") public {
        tokenPerBlock = _tokenPerBlock;
        startBlock = _startBlock;
        bonusEndBlock = _bonusEndBlock;
        endBlock = _endBlock;
        adminClaimRewardEndBlock = _adminEndBlock;
        tokenPerBlockAdmin = _tokenPerBlockAdmin;
        BONUS_MULTIPLIER = _bonus_multiplier;

        lastClaimBlockAdmin = startBlock;

        admin = IAdmin(adminAddress);
        adminReceiveAddress = _adminReceiveAddress;
        _mint(reserveContractAddress, initialReserveAmount);
        _mint(YFIInspirdropAddress, yfiAirdropAmount);
        UNIAddress = uniAddress;
    }

    function setAdminReceiveAddress(address addr) public {
        require(msg.sender == admin.admin(), "Not admin");
        adminReceiveAddress = addr;
    }

    function addRewardPool(address addrToken, address addrUniStakingRewards, uint poolWeight) public {
        require(msg.sender == admin.admin(), "Not admin");
        for (uint i = 0; i < rewardPools.length; i++) {
            updatePool(i);
        }
        rewardPools.push(
            poolInfo(
                addrToken,
                addrUniStakingRewards,
                0,
                startBlock > block.number ? startBlock : block.number,
                0,
                poolWeight,
                0
            )
        );
        totalPoolWeight = totalPoolWeight.add(poolWeight);
        emit NewRewardPool(addrToken);
    }

    function setPoolWeight(uint idx, uint poolWeight) public {
        require(msg.sender == admin.admin(), "Not admin");
        for (uint i = 0; i < rewardPools.length; i++) {
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

    function rewardAmount(uint idx, address account) public view returns (uint) {
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

    function rewardAmountUni(uint idx, address account) public view returns (uint) {
        poolInfo memory pool = rewardPools[idx];
        userInfo memory user = userInfos[account][idx];
        uint rewardPerTokenUni = 0;
        if(pool.addrUniStakingRewards != address(0)) {
            rewardPerTokenUni = IUNIStakingRewards(pool.addrUniStakingRewards)
                .rewardPerToken();
        }
        return user.depositAmount
            .mul(rewardPerTokenUni.sub(user.userRewardPerTokenPaidUni))
            .div(1e18)
            .add(user.rewardsUni);
    }

    function deposit(uint idx, uint amount) public {
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

        IERC20(pool.addrToken).safeTransferFrom(msg.sender, address(this), amount);

        if (pool.addrUniStakingRewards != address(0)) {
            IERC20(pool.addrToken).approve(pool.addrUniStakingRewards, amount);
            IUNIStakingRewards(pool.addrUniStakingRewards).stake(amount);
        }

        emit Deposit(msg.sender, idx, amount);
    }

    function withdraw(uint idx, uint amount) public {
        require(idx < rewardPools.length, "Not in reward pool list");

        userInfo storage user = userInfos[msg.sender][idx];
        poolInfo storage pool = rewardPools[idx];

        claimReward(idx);

        pool.totalBalance = pool.totalBalance.sub(amount);

        user.depositAmount = user.depositAmount.sub(amount);
        user.lastClaimAmount = user.depositAmount.mul(pool.rewardRate).div(1e18);

        if (pool.addrUniStakingRewards != address(0)) {
            IUNIStakingRewards(pool.addrUniStakingRewards).withdraw(amount);
        }

        IERC20(pool.addrToken).safeTransfer(msg.sender, amount);

        emit Withdrawal(msg.sender, idx, amount);
    }

    function updatePoolUni(uint idx) private {
        poolInfo storage pool = rewardPools[idx];
        userInfo storage user = userInfos[msg.sender][idx];
        IUNIStakingRewards uni = IUNIStakingRewards(pool.addrUniStakingRewards);

        uint _before = IERC20(UNIAddress).balanceOf(address(this));
        uni.getReward();
        uint _after = IERC20(UNIAddress).balanceOf(address(this));
        pool.totalRewardsUni = pool.totalRewardsUni.add(_after.sub(_before));

        uint rewardPerTokenUni = uni.rewardPerTokenStored();

        user.rewardsUni = user.depositAmount
            .mul(rewardPerTokenUni.sub(user.userRewardPerTokenPaidUni))
            .div(1e18)
            .add(user.rewardsUni);
        user.userRewardPerTokenPaidUni = rewardPerTokenUni;
    }

    function claimRewardUni(uint idx) private {
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
            IERC20(UNIAddress).safeTransfer(msg.sender, _rewardAmount);
        }
    }

    function updatePool(uint idx) private {
        poolInfo storage pool = rewardPools[idx];

        if (pool.addrUniStakingRewards != address(0)) {
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

    function claimReward(uint idx) public {
        require(idx < rewardPools.length, "Not in reward pool list");
        userInfo storage user = userInfos[msg.sender][idx];

        updatePool(idx);

        uint reward = user.depositAmount
            .mul(rewardPools[idx].rewardRate)
            .div(1e18)
            .sub(user.lastClaimAmount);

        if(reward > 0) {
            user.lastClaimAmount = reward.add(user.lastClaimAmount);
            _mint(msg.sender, reward);
        }

        emit ClaimReward(msg.sender, idx, reward);
    }

    function claimRewardAdmin() public {
        require(lastClaimBlockAdmin < adminClaimRewardEndBlock, "No more reward for admin");
        uint toBlock = block.number >= adminClaimRewardEndBlock ? adminClaimRewardEndBlock : block.number;
        uint reward = toBlock.sub(lastClaimBlockAdmin).mul(tokenPerBlockAdmin);
        _mint(adminReceiveAddress, reward);
        lastClaimBlockAdmin = toBlock;
        emit ClaimReward(adminReceiveAddress, 0, reward);
    }
}