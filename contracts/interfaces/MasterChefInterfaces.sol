// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

interface IMasterChefV1 {
    struct PoolInfo {
        address lpToken;
        uint accSushiPerShare;
        uint lastRewardBlock;
        uint allocPoint;
    }
    function poolInfo(uint poolId) external view returns (PoolInfo memory);
    function poolLength() external view returns (uint);
    function totalAllocPoint() external view returns (uint);
    function deposit(uint _pid, uint _amount) external;
    function withdraw(uint _pid, uint _amount) external;
}

interface IMasterChefRewarder {
    function rewardToken() external view returns (address);
}

interface ISushiSwapMasterChefV2 {
    function lpToken(uint poolId) external view returns (address);
    function poolLength() external view returns (uint);
    function totalAllocPoint() external view returns (uint);
    function deposit(uint _pid, uint _amount, address to) external;
    function withdrawAndHarvest(uint _pid, uint _amount, address to) external;
    function withdraw(uint _pid, uint _amount, address to) external;
    function harvest(uint pid, address to) external;
    function rewarder(uint pid) external view returns (address);
}

interface IPancakeSwapMasterChefV2 is ISushiSwapMasterChefV2 {
    struct PoolInfo {
        uint accCakePerShare;
        uint lastRewardBlock;
        uint allocPoint;
        uint totalBoostedShare;
        bool isRegular;
    }
    function poolInfo(uint _pid) external view returns (PoolInfo memory);
}