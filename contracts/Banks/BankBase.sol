// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

abstract contract BankBase is Ownable {
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
    function getLPToken(uint tokenId) virtual external returns (address);
    function getRewards(uint tokenId) virtual external view returns (address[] memory);
    function mint(uint tokenId, address userAddress, uint amount) virtual external;
    function burn(uint tokenId, address userAddress, uint amount, address receiver) virtual external;
    function harvest(uint tokenId, address userAddress, address receiver) virtual external returns (address[] memory, uint[] memory);
}