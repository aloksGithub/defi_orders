// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./BankBase.sol";
import "../interfaces/MasterChefInterfaces.sol";
import "../libraries/AddressArray.sol";
import "../libraries/UintArray.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "hardhat/console.sol";

abstract contract IMasterChefWrapper is Ownable {
    using AddressArray for address[];
    using UintArray for uint[];
    using Address for address;

    event LPTokenAdded(address masterChef, address lpToken, uint poolId);

    mapping (address => bool) public supportedLps;
    mapping (address => uint) public supportedLpIndices;
    address public masterChef;
    address public baseReward;
    string public pendingRewardGetter;

    function getRewards(uint pid) virtual external view returns (address[] memory) {
        address[] memory rewards = new address[](1);
        rewards[0] = baseReward;
        return rewards;
    }

    function initialize() virtual public {
        uint poolLength = IMasterChefV1(masterChef).poolLength();
        for (uint i = 0; i<poolLength; i++) {
            setSupported(i);
        }
    }

    function setSupported(uint pid) virtual public {
        address lpToken = getLpToken(pid);
        supportedLpIndices[lpToken] = pid;
        supportedLps[lpToken] = true;
    }

    function getIdFromLpToken(address lpToken) virtual external view returns (bool, uint) {
        if (!supportedLps[lpToken]) return (false, 0);
        else return (true, supportedLpIndices[lpToken]);
    }

    function getPendingRewards(uint pid) virtual external view returns (address[] memory rewards, uint[] memory amounts) {
        bytes memory returnData = masterChef.functionStaticCall(abi.encodeWithSignature(pendingRewardGetter, pid, msg.sender));
        (uint pending) = abi.decode(returnData, (uint));
        rewards = new address[](1);
        rewards[0] = baseReward;
        amounts = new uint[](1);
        amounts[0] = pending;
    }

    function getLpToken(uint pid) virtual public view returns (address);
    function deposit(address masterChef, uint pid, uint amount) virtual external;
    function withdraw(address masterChef, uint pid, uint amount) virtual external;
    function harvest(address masterChef, uint pid) virtual external;
}

contract MasterChefV1Wrapper is IMasterChefWrapper {
    using AddressArray for address[];
    using UintArray for uint[];
    using Address for address;

    constructor(address _masterChef, address _baseReward, string memory _pendingRewardGetter) {
        masterChef = _masterChef;
        baseReward = _baseReward;
        pendingRewardGetter = _pendingRewardGetter;
        initialize();
    }

    // function getIdFromLpToken(address lpToken) override external view returns (bool, uint) {
    //     uint poolLength = IMasterChefV1(masterChef).poolLength();
    //     for (uint i = 0; i<poolLength; i++) {
    //         IMasterChefV1.PoolInfo memory poolInfo = IMasterChefV1(masterChef).poolInfo(i);
    //         if (poolInfo.lpToken==lpToken) {
    //             return (true, i);
    //         }
    //     }
    //     return (false, 0);      
    // }

    function getLpToken(uint pid) override public view returns (address) {
        IMasterChefV1.PoolInfo memory pool = IMasterChefV1(masterChef).poolInfo(pid);
        return pool.lpToken;
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
    using AddressArray for address[];
    using UintArray for uint[];
    using Address for address;
    mapping (uint=>address) extraRewards;

    constructor(address _masterChef, address _baseReward, string memory _pendingRewardGetter) {
        masterChef = _masterChef;
        baseReward = _baseReward;
        pendingRewardGetter = _pendingRewardGetter;
        initialize();
    }

    // function getIdFromLpToken(address lpToken) override external view returns (bool, uint) {
    //     uint poolLength = ISushiSwapMasterChefV2(masterChef).poolLength();
    //     for (uint i = 0; i<poolLength; i++) {
    //         if (ISushiSwapMasterChefV2(masterChef).lpToken(i)==lpToken) {
    //             return (true, i);
    //         }
    //     }
    //     return (false, 0);      
    // }
    
    function getLpToken(uint pid) override public view returns (address) {
        return ISushiSwapMasterChefV2(masterChef).lpToken(pid);
    }

    function getRewards(uint pid) override external view returns (address[] memory) {
        address[] memory rewards = new address[](1);
        rewards[0] = baseReward;
        address rewarder = ISushiSwapMasterChefV2(masterChef).rewarder(pid);
        if (rewarder!=address(0)) {
            (address[] memory tokens,) = IRewarder(rewarder).pendingTokens(0, address(this), 0);
            rewards = rewards.concat(tokens);
        }
        return rewards;
    }

    function getPendingRewards(uint pid) override external view returns (address[] memory rewards, uint[] memory rewardAmounts) {
        bytes memory returnData = masterChef.functionStaticCall(abi.encodeWithSignature(pendingRewardGetter, pid, msg.sender));
        (uint pending) = abi.decode(returnData, (uint));
        rewards = new address[](1);
        rewards[0] = baseReward;
        rewardAmounts = new uint[](1);
        rewardAmounts[0] = pending;
        address rewarder = ISushiSwapMasterChefV2(masterChef).rewarder(pid);
        if (rewarder!=address(0)) {
            (address[] memory tokens, uint[] memory amounts) = IRewarder(rewarder).pendingTokens(pid, msg.sender, 0);
            rewards = rewards.concat(tokens);
            rewardAmounts = rewardAmounts.concat(amounts);
        }
    }

    function deposit(address masterChef, uint pid, uint amount) override external {
        ISushiSwapMasterChefV2(masterChef).deposit(pid, amount, address(this));
    }
    
    function withdraw(address masterChef, uint pid, uint amount) override external {
        ISushiSwapMasterChefV2(masterChef).withdraw(pid, amount, address(this));
    }

    function harvest(address masterChef, uint pid) override external {
        try ISushiSwapMasterChefV2(masterChef).pendingSushi(pid, address(this)) returns (uint) {
            ISushiSwapMasterChefV2(masterChef).harvest(pid, address(this));
        } catch {}
    }
}

contract PancakeSwapMasterChefV2Wrapper is IMasterChefWrapper {
    using AddressArray for address[];
    using UintArray for uint[];
    using Address for address;

    constructor(address _masterChef, address _baseReward, string memory _pendingRewardGetter) {
        masterChef = _masterChef;
        baseReward = _baseReward;
        pendingRewardGetter = _pendingRewardGetter;
        initialize();
    }

    // function getIdFromLpToken(address lpToken) override external view returns (bool, uint) {
    //     uint poolLength = IPancakeSwapMasterChefV2(masterChef).poolLength();
    //     for (uint i = 0; i<poolLength; i++) {
    //         if (IPancakeSwapMasterChefV2(masterChef).lpToken(i)==lpToken) {
    //             return (true, i);
    //         }
    //     }
    //     return (false, 0);      
    // }
    
    function getLpToken(uint pid) override public view returns (address) {
        return ISushiSwapMasterChefV2(masterChef).lpToken(pid);
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