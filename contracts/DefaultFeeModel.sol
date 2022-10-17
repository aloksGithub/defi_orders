// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "./interfaces/IFeeModel.sol";

contract DefaultFeeModel is IFeeModel {
    function calculateFee(uint positionSize, uint[3][] memory positionInteractions) external pure returns (uint fee) {
        fee = 0;
    }
}