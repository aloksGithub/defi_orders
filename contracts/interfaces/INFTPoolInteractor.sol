// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

/// @notice
/// @param pool Address of liquidity pool
/// @param manager NFT manager contract, such as uniswap V3 positions manager
/// @param tokenId ID representing NFT
/// @param liquidity Amount of liquidity, used when converting part of the NFT to some other asset
/// @param data Data used when creating the NFT position, contains int24 tickLower, int24 tickUpper, uint minAmount0 and uint minAmount1
struct Asset {
    address pool;
    address manager;
    uint tokenId;
    uint liquidity;
    bytes data;
}

interface INFTPoolInteractor {
    function setSupportedManagers(address[] memory _supportedManagers) external;
    function burn(Asset memory asset) payable external returns (address[] memory receivedTokens, uint256[] memory receivedTokenAmounts);
    function mint(Asset memory toMint, address[] memory underlyingTokens, uint256[] memory underlyingAmounts) payable external returns (uint256);
    function getRatio(address poolAddress, int24 tick0, int24 tick1) external returns (uint, uint);
    function testSupported(address token) external view returns (bool);
    function testSupportedPool(address token) external view returns (bool);
    function getUnderlyingTokens(address lpTokenAddress) external view returns (address[] memory);
}