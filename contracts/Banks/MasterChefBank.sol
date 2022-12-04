// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./BankBase.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "./MasterChefWrappers.sol";
import "hardhat/console.sol";

contract MasterChefBank is ERC1155('MasterChefBank'), BankBase {
    using Address for address;
    using SafeERC20 for IERC20;

    event SetMasterChefWrapper(address masterChef, address wrapper);

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
        emit SetMasterChefWrapper(masterChef, wrapper);
    }

    function decodeId(uint id) public override view returns (address lpToken, address masterChef, uint pid) {
        pid = id>>160;
        masterChef = address(uint160(id & ((1 << 160) - 1)));
        lpToken = IMasterChefWrapper(masterChefWrappers[masterChef]).getLpToken(pid);
    }

    function getLPToken(uint id) override public view returns (address tokenAddress) {
        (tokenAddress,,) = decodeId(id);
    }

    function name() override public pure returns (string memory) {
        return "Masterchef Bank";
    }

    function getIdFromLpToken(address lpToken) override public view returns (bool, uint) {
        for (uint i = 0; i<supportedMasterChefs.length; i++) {
            IMasterChefWrapper wrapper = IMasterChefWrapper(masterChefWrappers[supportedMasterChefs[i]]);
            (bool success, uint id) = wrapper.getIdFromLpToken(lpToken);
            if (success) {
                return (true, encodeId(supportedMasterChefs[i], id));
            }
        }
        return (false, 0);
    }

    function getRewards(uint tokenId) override external view returns (address[] memory) {
        (, address masterChef, uint pid) = decodeId(tokenId);
        IMasterChefWrapper wrapper = IMasterChefWrapper(masterChefWrappers[masterChef]);
        return wrapper.getRewards(pid);
    }

    function getPendingRewardsForUser(uint tokenId, address user) override external view returns (address[] memory rewards, uint[] memory amounts) {
        PoolInfo storage pool = poolInfo[tokenId];
        uint lpSupply = pool.lpSupply;
        (, address masterChef, uint pid) = decodeId(tokenId);
        uint[] memory everyonesRewardAmounts;
        (rewards, everyonesRewardAmounts) = IMasterChefWrapper(masterChefWrappers[masterChef]).getPendingRewards(pid);
        amounts = new uint[](rewards.length);
        if (lpSupply>0) {
            for (uint i = 0; i<rewards.length; i++) {
                address reward = rewards[i];
                uint allocationPerShare = pool.rewardAllocationsPerShare[rewards[i]] + everyonesRewardAmounts[i]*PRECISION/lpSupply;
                int256 accumulatedReward = int256(pool.userShares[user]*allocationPerShare/PRECISION);
                uint pendingReward = uint(accumulatedReward-pool.rewardDebt[user][reward]);
                amounts[i] = pendingReward;
            }
        }
    }

    function getPositionTokens(uint tokenId, address userAddress) override external view returns (address[] memory outTokens, uint[] memory tokenAmounts) {
        (address lpToken,,) = decodeId(tokenId);
        uint amount = balanceOf(userAddress, tokenId);
        outTokens = new address[](1);
        tokenAmounts = new uint[](1);
        outTokens[0] = lpToken;
        tokenAmounts[0] = amount;
    }

    function _harvest(address masterChef, address lpToken, uint pid) internal {
        IERC20(lpToken).approve(masterChef, 10);
        address masterChefWrapperAddress = masterChefWrappers[masterChef];
        IMasterChefWrapper wrapper = IMasterChefWrapper(masterChefWrappers[masterChef]);
        masterChefWrapperAddress.functionDelegateCall(abi.encodeWithSelector(wrapper.harvest.selector, masterChef, pid));
    }

    function updateToken(uint tokenId) onlyAuthorized internal {
        (address lpToken, address masterChef, uint pid) = decodeId(tokenId);
        PoolInfo storage pool = poolInfo[tokenId];
        uint lpSupply = pool.lpSupply;
        if (lpSupply>0) {
            address[] memory rewards = IMasterChefWrapper(masterChefWrappers[masterChef]).getRewards(pid);
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

    function mint(uint tokenId, address userAddress, address[] memory suppliedTokens, uint[] memory suppliedAmounts) onlyAuthorized override public returns(uint) {
        updateToken(tokenId);
        (address lpToken, address masterChef, uint pid) = decodeId(tokenId);
        require(lpToken==suppliedTokens[0], "Incorrect supplied token");
        IERC20(lpToken).approve(masterChef, suppliedAmounts[0]);
        _deposit(masterChef, pid, suppliedAmounts[0]);
        PoolInfo storage pool = poolInfo[tokenId];
        pool.userShares[userAddress]+=suppliedAmounts[0];
        pool.lpSupply+=suppliedAmounts[0];
        address[] memory rewards = IMasterChefWrapper(masterChefWrappers[masterChef]).getRewards(pid);
        for (uint i = 0; i<rewards.length; i++) {
            address reward = rewards[i];
            pool.rewardDebt[userAddress][reward]+=int(suppliedAmounts[0]*pool.rewardAllocationsPerShare[reward]/PRECISION);
        }
        _mint(userAddress, tokenId, suppliedAmounts[0], '');
        emit Mint(tokenId, userAddress, suppliedAmounts[0]);
        return suppliedAmounts[0];
    }

    function burn(uint tokenId, address userAddress, uint amount, address receiver) onlyAuthorized override external returns (address[] memory outTokens, uint[] memory tokenAmounts) {
        updateToken(tokenId);
        (address lpToken, address masterChef, uint pid) = decodeId(tokenId);
        PoolInfo storage pool = poolInfo[tokenId];
        address[] memory rewards = IMasterChefWrapper(masterChefWrappers[masterChef]).getRewards(pid);
        for (uint i = 0; i<rewards.length; i++) {
            address reward = rewards[i];
            pool.rewardDebt[userAddress][reward]-=int(amount*pool.rewardAllocationsPerShare[reward]/PRECISION);
        }
        pool.userShares[userAddress]-=amount;
        pool.lpSupply-=amount;
        _withdraw(masterChef, pid, amount);
        IERC20(lpToken).safeTransfer(receiver, amount);
        _burn(userAddress, tokenId, amount);
        emit Burn(tokenId, userAddress, amount, receiver);
        outTokens = new address[](1);
        tokenAmounts = new uint[](1);
        outTokens[0] = lpToken;
        tokenAmounts[0] = amount;
    }

    function harvest(uint tokenId, address userAddress, address receiver) onlyAuthorized override external returns (address[] memory rewardAddresses, uint[] memory rewardAmounts) {
        updateToken(tokenId);
        PoolInfo storage pool = poolInfo[tokenId];
        (, address masterChef, uint pid) = decodeId(tokenId);
        address[] memory rewards = IMasterChefWrapper(masterChefWrappers[masterChef]).getRewards(pid);
        rewardAddresses = new address[](rewards.length);
        rewardAmounts = new uint[](rewards.length);
        for (uint i = 0; i<rewards.length; i++) {
            address reward = rewards[i];
            int256 accumulatedReward = int256(pool.userShares[userAddress]*pool.rewardAllocationsPerShare[reward]/PRECISION);
            uint pendingReward = uint(accumulatedReward-pool.rewardDebt[userAddress][reward]);
            pool.rewardDebt[userAddress][reward] = accumulatedReward;
            if (pendingReward!=0) {
                IERC20(reward).safeTransfer(receiver, pendingReward);
            }
            rewardAddresses[i] = rewards[i];
            rewardAmounts[i] = pendingReward;
        }
        emit Harvest(tokenId, userAddress, receiver);
    }
}