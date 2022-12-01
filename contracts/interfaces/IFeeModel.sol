// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "./IPositionsManager.sol";

interface IFeeModel {
    function calculateFee(uint positionSize, PositionInteraction[] memory positionInteractions) external view returns (uint fee);
}