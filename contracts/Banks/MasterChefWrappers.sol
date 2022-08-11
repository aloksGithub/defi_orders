// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./BankBase.sol";
import "../interfaces/MasterChefInterfaces.sol";
import "hardhat/console.sol";

abstract contract IMasterChefWrapper is Ownable {
    mapping (address => mapping (uint => address)) supportedLps;
    mapping (address => mapping (address => uint)) supportedLpIndices;
    mapping (address=>address) baseRewards;
    mapping (address=>bool) hasExtraRewards;

    function initializeMasterChef(address masterChef, string memory rewardGetter, bool _hasExtraRewards) virtual public onlyOwner {
        (bool success, bytes memory returnData) = masterChef.call(abi.encodeWithSignature(rewardGetter));
        if (!success) revert("Failed to get reward token");
        (address reward) = abi.decode(returnData, (address));
        baseRewards[masterChef] = reward;
        hasExtraRewards[masterChef] = _hasExtraRewards;
    }
    function setSupportedLp(address masterChef, uint poolId, address lpToken) virtual external onlyOwner {
        supportedLpIndices[masterChef][lpToken] = poolId;
        supportedLps[masterChef][poolId] = lpToken;
    }

    function getIdFromLpToken(address masterChef, address lpToken) virtual external view returns (bool, uint) {
        uint index = supportedLpIndices[masterChef][lpToken];
        if (supportedLps[masterChef][index]==lpToken) {
            return (true, index);
        }
        return (false, 0);      
    }
    function getLpToken(address masterchef, uint pid) virtual external view returns (address);
    function getRewards(address masterchef, uint pid) virtual external view returns (address[] memory);
    function deposit(address masterChef, uint pid, uint amount) virtual external;
    function withdraw(address masterChef, uint pid, uint amount) virtual external;
    function harvest(address masterChef, uint pid) virtual external;
}

contract MasterChefV1Wrapper is IMasterChefWrapper {

    function initializeMasterChef(address masterChef, string memory rewardGetter, bool _hasExtraRewards) override public onlyOwner {
        super.initializeMasterChef(masterChef, rewardGetter, _hasExtraRewards);
        IMasterChefV1 sushiMasterChef = IMasterChefV1(masterChef);
        uint numPools = sushiMasterChef.poolLength();
        // WARNING: Don't forget to change 10 to numPools
        for (uint i = 0; i<10; i++) {
            IMasterChefV1.PoolInfo memory pool = sushiMasterChef.poolInfo(i);
            supportedLps[masterChef][i] = pool.lpToken;
            supportedLpIndices[masterChef][pool.lpToken] = i;
        }
    }

    function getLpToken(address masterchef, uint pid) override external view returns (address) {
        IMasterChefV1.PoolInfo memory pool = IMasterChefV1(masterchef).poolInfo(pid);
        return pool.lpToken;
    }

    function getRewards(address masterchef, uint pid) override external view returns (address[] memory) {
        address[] memory rewards = new address[](1);
        rewards[0] = baseRewards[masterchef];
        return rewards;
    }

    function deposit(address masterChef, uint pid, uint amount) override external {
        IMasterChefV1(masterChef).deposit(pid, amount);
    }
    
    function withdraw(address masterChef, uint pid, uint amount) override external {
        IMasterChefV1(masterChef).withdraw(pid, amount);
    }

    function harvest(address masterChef, uint pid) override external {
        IMasterChefV1(masterChef).withdraw(pid, 10);
        IMasterChefV1(masterChef).deposit(pid, 10);
    }
}

contract MasterChefV2Wrapper is IMasterChefWrapper {
    mapping (address => mapping (uint=>address)) extraRewards;

    function initializeMasterChef(address masterChef, string memory rewardGetter, bool _hasExtraRewards) virtual override public onlyOwner {
        super.initializeMasterChef(masterChef, rewardGetter, _hasExtraRewards);
        ISushiSwapMasterChefV2 sushiMasterChef = ISushiSwapMasterChefV2(masterChef);
        uint numPools = sushiMasterChef.poolLength();
        // WARNING: Don't forget to change 10 to numPools
        for (uint i = 0; i<10; i++) {
            address lpToken = sushiMasterChef.lpToken(i);
            supportedLps[masterChef][i] = lpToken;
            supportedLpIndices[masterChef][lpToken] = i;
        }
    }
    
    function getLpToken(address masterchef, uint pid) override external view returns (address) {
        return ISushiSwapMasterChefV2(masterchef).lpToken(pid);
    }

    function getRewards(address masterchef, uint pid) override external view returns (address[] memory) {
        if (extraRewards[masterchef][pid]!=address(0)) {
            address[] memory r = new address[](2);
            r[0] = baseRewards[masterchef];
            r[1] = extraRewards[masterchef][pid];
            return r;
        }
        address rewarder;
        if (hasExtraRewards[masterchef]) {
            rewarder = ISushiSwapMasterChefV2(masterchef).rewarder(pid);
        } else {
            rewarder = address(0);
        }
        if (rewarder==address(0)) {
            address[] memory reward = new address[](1);
            reward[0] = baseRewards[masterchef];
            return reward;
        } else {
            address rewardToken = IMasterChefRewarder(rewarder).rewardToken();
            address[] memory reward = new address[](2);
            reward[0] = baseRewards[masterchef];
            reward[1] = rewardToken;
            return reward;
        }
    }

    function deposit(address masterChef, uint pid, uint amount) override external {
        ISushiSwapMasterChefV2(masterChef).deposit(pid, amount, address(this));
    }
    
    function withdraw(address masterChef, uint pid, uint amount) override external {
        ISushiSwapMasterChefV2(masterChef).withdraw(pid, amount, address(this));
    }

    function harvest(address masterChef, uint pid) override external {
        ISushiSwapMasterChefV2(masterChef).harvest(pid, address(this));
    }
}

contract PancakeSwapMasterChefV2Wrapper is MasterChefV2Wrapper {
    function initializeMasterChef(address masterChef, string memory rewardGetter, bool _hasExtraRewards) override public onlyOwner {
        (bool success, bytes memory returnData) = masterChef.call(abi.encodeWithSignature(rewardGetter));
        if (!success) revert("Failed to get reward token");
        (address reward) = abi.decode(returnData, (address));
        baseRewards[masterChef] = reward;
        hasExtraRewards[masterChef] = _hasExtraRewards;
        IPancakeSwapMasterChefV2 pancakeMasterChef = IPancakeSwapMasterChefV2(masterChef);
        uint numPools = pancakeMasterChef.poolLength();
        // WARNING: Don't forget to change 10 to numPools
        for (uint i = 0; i<10; i++) {
            address lpToken = pancakeMasterChef.lpToken(i);
            bool isRegular = pancakeMasterChef.poolInfo(i).isRegular;
            if (isRegular) {
                supportedLps[masterChef][i] = lpToken;
                supportedLpIndices[masterChef][lpToken] = i;
            }
        }
    }
}