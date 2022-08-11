// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

interface ISwapper {
    event Burn(address holderAddress, uint256 amount);

    function swap(
        address inToken,
        uint256 amount,
        address outToken,
        address _routerAddress
    ) external returns (uint256);

    function checkWillSwap(
        address inToken,
        uint256 amount,
        address outToken
    ) external view returns (bool);

    function routerAddress() external returns (address);

    function checkSwappable(address inToken, address outToken)
        external
        view
        returns (bool);
}
