// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

interface IMasterChef {
    struct UserInfo {
        uint256 amount;
        uint256 rewardDebt;
    }

    struct PoolInfo {
        uint128 accSushiPerShare;
        uint64 lastRewardTime;
        uint64 allocPoint;
    }

    function poolLength() external view returns (uint256);

    function lpToken(uint pid) external view returns (address);

    function updatePool(uint256 pid)
        external
        returns (IMasterChef.PoolInfo memory);

    function userInfo(uint256 _pid, address _user)
        external
        view
        returns (uint256, uint256);

    function deposit(
        uint256 pid,
        uint256 amount,
        address to
    ) external;

    function withdraw(
        uint256 pid,
        uint256 amount,
        address to
    ) external;

    function harvest(uint256 pid, address to) external;

    function withdrawAndHarvest(
        uint256 pid,
        uint256 amount,
        address to
    ) external;

    function emergencyWithdraw(uint256 pid, address to) external;
}
