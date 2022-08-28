// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;


import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../libraries/Strings.sol";
import "hardhat/console.sol";

interface IPoolInteractor {

    event Burn(address lpTokenAddress, uint256 amount);

    function burn(address lpTokenAddress, uint256 amount)
        external
        returns (address[] memory, uint256[] memory);

    function mint(
        address toMint,
        address[] memory underlyingTokens,
        uint256[] memory underlyingAmounts
    ) external returns (uint256);

    function testSupported(address lpToken) external returns (bool);

    function getUnderlyingTokens(address poolAddress)
        external
        returns (address[] memory);
}
