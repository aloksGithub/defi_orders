// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

interface IOracle {
    /// @notice Gives price of token in terms of another token
    function getPrice(address token, address inTermsOf) external view returns (uint);
}