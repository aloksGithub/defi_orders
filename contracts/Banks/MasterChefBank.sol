// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./BankBase.sol";
import "hardhat/console.sol";
import "./MasterChefWrappers.sol";

contract MasterChefBank is ERC1155('MasterChefBank'), BankBase {
    struct PoolInfo {
        address lpToken;
        uint lpSupply;
        mapping(address=>uint) rewardAllocationsPerShare;
        mapping(address=>uint) userShares;
        mapping(address=>mapping(address=>int256)) rewardDebt;    // Mapping from user to reward to debt
    }

    uint PRECISION = 1e12;
    mapping (uint=>PoolInfo) poolInfo;
    mapping (address=>address) masterChefWrappers;
    address[] supportedMasterChefs;

    constructor(address _positionsManager) BankBase(_positionsManager) {}

    function encodeId(address masterChef, uint pid) public pure returns (uint) {
        return (pid << 160) | uint160(masterChef);
    }

    function setMasterChefWrapper(address masterChef, address wrapper) external onlyOwner {
        masterChefWrappers[masterChef] = wrapper;
        for (uint i = 0; i<supportedMasterChefs.length; i++) {
            if (supportedMasterChefs[i]==masterChef) {
                return;
            }
        }
        supportedMasterChefs.push(masterChef);
    }

    function decodeId(uint id) public view returns (address masterChef, address lpToken, uint pid) {
        pid = id>>160;
        masterChef = address(uint160(id & ((1 << 160) - 1)));
        lpToken = IMasterChefWrapper(masterChefWrappers[masterChef]).getLpToken(masterChef, pid);
    }

    function getLPToken(uint id) override public view returns (address tokenAddress) {
        (,tokenAddress,) = decodeId(id);
    }

    function name() override public pure returns (string memory) {
        return "Masterchef Bank";
    }

    function getIdFromLpToken(address lpToken) override public view returns (bool, uint) {
        for (uint i = 0; i<supportedMasterChefs.length; i++) {
            IMasterChefWrapper wrapper = IMasterChefWrapper(masterChefWrappers[supportedMasterChefs[i]]);
            (bool success, uint id) = wrapper.getIdFromLpToken(supportedMasterChefs[i], lpToken);
            if (success) {
                return (true, encodeId(supportedMasterChefs[i], id));
            }
        }
        return (false, 0);
    }

    function getRewards(uint tokenId) override external view returns (address[] memory) {
        (address masterChef,, uint pid) = decodeId(tokenId);
        IMasterChefWrapper wrapper = IMasterChefWrapper(masterChefWrappers[masterChef]);
        return wrapper.getRewards(masterChef, pid);
    }

    function _harvest(address masterChef, address lpToken, uint pid) internal {
        IERC20(lpToken).approve(masterChef, 10);
        address masterChefWrapperAddress = masterChefWrappers[masterChef];
        IMasterChefWrapper wrapper = IMasterChefWrapper(masterChefWrappers[masterChef]);
        (bool success,) = masterChefWrapperAddress.delegatecall(abi.encodeWithSelector(wrapper.harvest.selector, masterChef, pid));
        if (!success) revert("Failed to harvest");
    }

    function updateToken(uint tokenId) onlyAuthorized internal {
        (address masterChef, address lpToken, uint pid) = decodeId(tokenId);
        PoolInfo storage pool = poolInfo[tokenId];
        uint lpSupply = pool.lpSupply;
        if (lpSupply>0) {
            address[] memory rewards = IMasterChefWrapper(masterChefWrappers[masterChef]).getRewards(masterChef, pid);
            uint[] memory rewardAmounts = new uint[](rewards.length);
            for (uint i = 0; i<rewards.length; i++) {
                rewardAmounts[i] = IERC20(rewards[i]).balanceOf(address(this));
            }
            _harvest(masterChef, lpToken, pid);
            for (uint i = 0; i<rewards.length; i++) {
                rewardAmounts[i] = IERC20(rewards[i]).balanceOf(address(this))-rewardAmounts[i];
                pool.rewardAllocationsPerShare[rewards[i]]+=rewardAmounts[i]*PRECISION/lpSupply;
            }
        }
    }

    function _deposit(address masterChef, uint pid, uint amount) internal {
        address masterChefWrapper = masterChefWrappers[masterChef];
        (bool success,) = masterChefWrapper.delegatecall(abi.encodeWithSelector(IMasterChefWrapper.deposit.selector, masterChef, pid, amount));
        if (!success) revert("Failed to deposit");
    }
    
    function _withdraw(address masterChef, uint pid, uint amount) internal {
        address masterChefWrapper = masterChefWrappers[masterChef];
        (bool success,) = masterChefWrapper.delegatecall(abi.encodeWithSelector(IMasterChefWrapper.withdraw.selector, masterChef, pid, amount));
        if (!success) revert("Failed to withdraw");
    }

    function mint(uint tokenId, address userAddress, uint amount) onlyAuthorized override external {
        updateToken(tokenId);
        (address masterChef, address lpToken, uint pid) = decodeId(tokenId);
        IERC20(lpToken).approve(masterChef, amount);
        _deposit(masterChef, pid, amount);
        PoolInfo storage pool = poolInfo[tokenId];
        pool.userShares[userAddress]+=amount;
        pool.lpSupply+=amount;
        address[] memory rewards = IMasterChefWrapper(masterChefWrappers[masterChef]).getRewards(masterChef, pid);
        for (uint i = 0; i<rewards.length; i++) {
            address reward = rewards[i];
            pool.rewardDebt[userAddress][reward]+=int(amount*pool.rewardAllocationsPerShare[reward]/PRECISION);
        }
        _mint(userAddress, tokenId, amount, '');
    }

    function burn(uint tokenId, address userAddress, uint amount, address receiver) onlyAuthorized override external {
        updateToken(tokenId);
        (address masterChef, address lpToken, uint pid) = decodeId(tokenId);
        PoolInfo storage pool = poolInfo[tokenId];
        if (amount == 0) {
            amount = balanceOf(userAddress, tokenId);
        }
        address[] memory rewards = IMasterChefWrapper(masterChefWrappers[masterChef]).getRewards(masterChef, pid);
        for (uint i = 0; i<rewards.length; i++) {
            address reward = rewards[i];
            pool.rewardDebt[userAddress][reward]-=int(amount*pool.rewardAllocationsPerShare[reward]/PRECISION);
        }
        pool.userShares[userAddress]-=amount;
        pool.lpSupply-=amount;
        _withdraw(masterChef, pid, amount);
        IERC20(lpToken).transfer(receiver, amount);
        _burn(userAddress, tokenId, amount);
    }

    function harvest(uint tokenId, address userAddress, address receiver) onlyAuthorized override external returns (address[] memory rewardAddresses, uint[] memory rewardAmounts) {
        updateToken(tokenId);
        PoolInfo storage pool = poolInfo[tokenId];
        (address masterChef,, uint pid) = decodeId(tokenId);
        address[] memory rewards = IMasterChefWrapper(masterChefWrappers[masterChef]).getRewards(masterChef, pid);
        rewardAddresses = new address[](rewards.length);
        rewardAmounts = new uint[](rewards.length);
        for (uint i = 0; i<rewards.length; i++) {
            address reward = rewards[i];
            int256 accumulatedReward = int256(pool.userShares[userAddress]*pool.rewardAllocationsPerShare[reward]/PRECISION);
            uint pendingReward = uint(accumulatedReward-pool.rewardDebt[userAddress][reward]);
            pool.rewardDebt[userAddress][reward] = accumulatedReward;
            if (pendingReward!=0) {
                IERC20(reward).transfer(receiver, pendingReward);
            }
            rewardAddresses[i] = rewards[i];
            rewardAmounts[i] = pendingReward;
        }
    }
}