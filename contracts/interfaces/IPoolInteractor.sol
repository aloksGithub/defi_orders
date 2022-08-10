// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

interface IPoolInteractor {
    struct ReceivingToken {
        address tokenAddress;
        uint256 amount;
    }

    event Burn(address lpTokenAddress, uint256 amount);

    function burn(address lpTokenAddress, uint256 amount)
        external
        returns (address[] memory, uint256[] memory);

    function mint(
        address toMint,
        address[] memory underlyingTokens,
        uint256[] memory underlyingAmounts
    ) external returns (uint256);

    function getUnderlyingTokens(address poolAddress)
        external
        view
        returns (address[] memory, uint[] memory);
}
