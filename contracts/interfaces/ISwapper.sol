// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

interface ISwapper {
    event Burn(address holderAddress, uint256 amount);

    function swap(
        uint256 amount,
        address[] memory path,
        address self
    ) payable external returns (uint256);

    function getAmountOut(
        address inToken,
        uint256 amount,
        address outToken
    ) external view returns (uint256, address[] memory);

    function checkSwappable(address inToken, address outToken)
        external
        view
        returns (bool);
}
