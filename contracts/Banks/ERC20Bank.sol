// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./BankBase.sol";

contract ERC20Bank is ERC1155('ERC20Bank'), BankBase {

    struct PoolInfo {
        mapping(address=>uint) userShares;
    }

    uint PRECISION = 1e12;
    string[] supportedAssetTypes;
    address[] supportedMasterchefs;
    mapping (uint=>address[]) rewards; // Rewards for a masterchef/gauge or some other reward giving contract
    mapping (uint=>PoolInfo) poolInfo;
    mapping (uint=>address) lpTokens;

    constructor(address _positionsManager) BankBase(_positionsManager) {}

    function encodeId(address tokenAddress) public pure returns (uint) {
        return uint256(uint160(tokenAddress));
    }

    function decodeId(uint id) public pure returns (address tokenAddress) {
        return address(uint160(id));
    }

    function getLPToken(uint id) override public pure returns (address tokenAddress) {
        return decodeId(id);
    }
    
    function getIdFromLpToken(address lpToken) override external pure returns (bool, uint) {
        return (true, encodeId(lpToken));
    }

    function getRewards(uint tokenId) override external pure returns (address[] memory rewardsArray) {
        return rewardsArray;
    }

    function name() override public pure returns (string memory) {
        return "ERC20 Bank";
    }

    function mint(uint tokenId, address userAddress, uint amount) onlyAuthorized override external {
        PoolInfo storage pool = poolInfo[tokenId];
        pool.userShares[userAddress]+=amount;
        _mint(userAddress, tokenId, amount, '');
    }

    function burn(uint tokenId, address userAddress, uint amount, address receiver) onlyAuthorized override external {
        address lpToken = decodeId(tokenId);
        PoolInfo storage pool = poolInfo[tokenId];
        if (amount == 0) {
            amount = balanceOf(userAddress, tokenId);
        }
        pool.userShares[userAddress]-=amount;
        IERC20(lpToken).transfer(receiver, amount);
        _burn(userAddress, tokenId, amount);
    }

    function harvest(uint tokenId, address userAddress, address receiver) onlyAuthorized override external view returns (address[] memory rewardAddresses, uint[] memory rewardAmounts) {
        return (rewardAddresses, rewardAmounts);
    }
}