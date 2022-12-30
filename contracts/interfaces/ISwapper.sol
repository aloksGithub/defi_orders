// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.9;

import "../libraries/SwapFinder.sol";

interface ISwapper {
    event Burn(address holderAddress, uint256 amount);

    function getCommonPoolTokens() external view returns (address[] memory);

    function swap(uint256 amount, address[] memory path, address self) external payable returns (uint256);

    function getAmountOut(
        address inToken,
        uint256 amount,
        address outToken
    ) external view returns (uint256, address[] memory);

    function getAmountOut2(uint256 amount, address[] memory path) external view returns (uint256);

    function getAmountsOutWithPath(
        uint256 amount,
        address[] memory path,
        uint[][][] memory amountsForSwaps,
        SwapPoint[] memory priorSwaps
    ) external view returns (uint256[] memory);

    function checkSwappable(address token) external view returns (bool);
}
