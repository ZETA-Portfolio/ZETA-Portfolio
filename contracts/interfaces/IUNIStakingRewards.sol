// SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;

interface IUNIStakingRewards {
    function stake(uint amount) external;
    function withdraw(uint amount) external;
    function getReward() external;
    function rewardPerToken() external view returns (uint);
    function rewardPerTokenStored() external view returns (uint);
    function earned(address account) external view returns (uint);
    function userRewardPerTokenPaid(address) external view returns (uint);
    function rewards(address) external view returns (uint);
    function balanceOf(address account) external view returns (uint);
}