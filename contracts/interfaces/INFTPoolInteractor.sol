// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

struct Asset {
    address pool;
    address manager;
    uint tokenId;
    bytes data;
}

interface INFTPoolInteractor {
    function setSupportedProtocols(string[] memory _supportedProtocols) external;
    function burn(Asset memory asset) external returns (address[] memory receivedTokens, uint256[] memory receivedTokenAmounts);
    function mint(Asset memory toMint, address[] memory underlyingTokens, uint256[] memory underlyingAmounts) external returns (uint256);
    function testSupported(address token) external view returns (bool);
    function getUnderlyingTokens(address lpTokenAddress) external view returns (address[] memory);
}