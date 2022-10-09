// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

interface ISwapper {
    event Burn(address holderAddress, uint256 amount);

    function swap(
        address inToken,
        uint256 amount,
        address outToken,
        address self
    ) payable external returns (uint256);

    function checkSwappable(address inToken, address outToken)
        external
        view
        returns (bool);
}
