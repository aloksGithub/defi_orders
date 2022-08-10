// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

interface ILiquidator {
    event Burn(address holderAddress, uint256 amount);

    function liquidate(
        address toLiquidate,
        uint256 amount,
        address liquidateTo,
        address _routerAddress
    ) external returns (uint256);

    function checkWillLiquidate(
        address toLiquidate,
        uint256 amount,
        address liquidateTo
    ) external view returns (bool);

    function factoryAddress() external returns (address);

    function routerAddress() external returns (address);

    function checkLiquidable(address toLiquidate, address liquidateTo)
        external
        view
        returns (bool);
}
