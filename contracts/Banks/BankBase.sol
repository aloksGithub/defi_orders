// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

abstract contract BankBase is Ownable {
    using SafeERC20 for IERC20;

    event Mint(uint tokenId, address userAddress, uint amount);
    event Burn(uint tokenId, address userAddress, uint amount, address receiver);
    event Harvest(uint tokenId, address userAddress, address receiver);

    address positionsManager;

    constructor(address _positionsManager) {
        positionsManager = _positionsManager;
    }

    modifier onlyAuthorized() {
        require(msg.sender==positionsManager || msg.sender==owner(), "Unauthorized access");
        _;
    }

    function name() virtual external pure returns (string memory);
    function getIdFromLpToken(address lpToken) virtual external view returns (bool, uint);
    function decodeId(uint id) virtual external view returns (address, address, uint);
    function getUnderlyingForFirstDeposit(uint tokenId) virtual public returns (address[] memory underlying) {
        underlying = new address[](1);
        underlying[0] = getLPToken(tokenId);
    }
    function getUnderlyingForRecurringDeposit(uint tokenId) virtual external returns (address[] memory) {
        return getUnderlyingForFirstDeposit(tokenId);
    }
    function getLPToken(uint tokenId) virtual public returns (address);
    function getRewards(uint tokenId) virtual external view returns (address[] memory rewardsArray) {
        return rewardsArray;
    }
    function mint(uint tokenId, address userAddress, address[] memory suppliedTokens, uint[] memory suppliedAmounts) virtual public returns (uint);
    function mintRecurring(uint tokenId, address userAddress, address[] memory suppliedTokens, uint[] memory suppliedAmounts) virtual external returns (uint) {
        return mint(tokenId, userAddress, suppliedTokens, suppliedAmounts);
    }
    function burn(uint tokenId, address userAddress, uint amount, address receiver) virtual external returns (address[] memory, uint[] memory);
    function harvest(uint tokenId, address userAddress, address receiver) onlyAuthorized virtual external returns (address[] memory rewardAddresses, uint[] memory rewardAmounts) {
        return (rewardAddresses, rewardAmounts);
    }
}