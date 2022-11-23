// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "./AddressArray.sol";
import "hardhat/console.sol";

struct SwapPoint {
    uint amountIn;
    uint valueIn;
    uint amountOut;
    uint valueOut;
    int slippage;
    address tokenIn;
    address swapper;
    address tokenOut;
    address[] path;
}

library SwapFinder {
    using AddressArray for address[];

    function sort(SwapPoint[] memory self) internal pure returns (SwapPoint[] memory sorted) {
        sorted = new SwapPoint[](self.length);
        for (uint i = 0; i<self.length; i++) {
            int minSlippage = 2**128-1;
            uint minSlippageIndex = 0;
            for (uint j = 0; j<self.length; j++) {
                if (self[j].slippage<minSlippage) {
                    minSlippageIndex = j;
                }
            }
            sorted[i] = self[minSlippageIndex];
            self[minSlippageIndex].slippage = 2**128-1;
        }
    }

    struct StackMinimizingStruct {
        uint valueIn;
        uint toConvertIndex;
        uint convertToIndex;
    }

    struct StackMinimizingStruct2 {
        uint[] valuesUsed;
        uint[] valuesProvided;
        uint swapsAdded;        
    }

    function findBestSwaps(
        SwapPoint[] memory self,
        address[] memory toConvert,
        uint[] memory valuesToConvert,
        uint[] memory amountsToConvert,
        address[] memory convertTo,
        uint[] memory wantedValues
    ) internal pure returns (SwapPoint[] memory swaps) {
        SwapPoint[] memory bestSwaps = new SwapPoint[](self.length);
        StackMinimizingStruct2 memory data2 = StackMinimizingStruct2(new uint[](toConvert.length), new uint[](wantedValues.length), 0);
        for (uint i = 0; i<self.length; i++) {
            StackMinimizingStruct memory data = StackMinimizingStruct(self[i].valueIn, toConvert.findFirst(self[i].tokenIn), convertTo.findFirst(self[i].tokenOut));
            if (self[i].tokenIn==address(0) || self[i].tokenOut==address(0)) continue;
            if (data2.valuesUsed[data.toConvertIndex]<valuesToConvert[data.toConvertIndex] && data2.valuesProvided[data.convertToIndex]<wantedValues[data.convertToIndex]) {
                uint valueInAdjusted;
                {
                    uint moreValueInAvailable = valuesToConvert[data.toConvertIndex]-data2.valuesUsed[data.toConvertIndex];
                    uint moreValueOutNeeded = wantedValues[data.convertToIndex]-data2.valuesProvided[data.convertToIndex];
                    valueInAdjusted = moreValueInAvailable>=data.valueIn?data.valueIn:moreValueInAvailable;
                    if (valueInAdjusted>moreValueOutNeeded) {
                        valueInAdjusted = moreValueOutNeeded;
                    }
                }
                self[i].amountIn = valueInAdjusted*amountsToConvert[data.toConvertIndex]/valuesToConvert[data.toConvertIndex];
                self[i].valueIn = valueInAdjusted;
                self[i].valueOut = valueInAdjusted*self[i].valueOut/self[i].valueIn;
                self[i].amountOut = valueInAdjusted*self[i].amountOut/self[i].valueIn;
                bestSwaps[data2.swapsAdded] = self[i];
                data2.swapsAdded+=1;
                data2.valuesUsed[data.toConvertIndex]+=valueInAdjusted;
                data2.valuesProvided[data.convertToIndex]+=valueInAdjusted;
                continue;
            }
        }
        uint numSwaps = 0;
        for (uint i = 0; i<bestSwaps.length; i++) {
            if (bestSwaps[i].tokenIn!=address(0)) {
                numSwaps+=1;
            }
        }
        swaps = new SwapPoint[](numSwaps);
        uint swapsAdded;
        for (uint i = 0; i<bestSwaps.length; i++) {
            if (bestSwaps[i].tokenIn!=address(0)) {
                swaps[swapsAdded] = bestSwaps[i];
                swapsAdded+=1;
            }
        }
        return swaps;
    }
}