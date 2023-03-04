// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

import "../interfaces/ISwapper.sol";
import "../interfaces/IUniversalSwap.sol";
import "../libraries/UintArray.sol";
import "../libraries/AddressArray.sol";
import "../libraries/SwapFinder.sol";
import "../interfaces/IOracle.sol";
import "../libraries/Conversions.sol";
import "../libraries/UintArray2D.sol";
import "./ConversionHelper.sol";
import "hardhat/console.sol";

contract SwapHelper {
    using UintArray for uint256[];
    using UintArray2D for uint[][];
    using AddressArray for address[];
    using SwapFinder for SwapPoint[];
    using SwapFinder for SwapPoint;
    using Conversions for Conversion[];

    struct FindSwapsBetween {
        address tokenIn;
        address tokenOut;
        uint256 valueNeeded;
        uint256 amountInAvailable;
        uint256 valueInAvailable;
    }

    ConversionHelper public conversionHelper;
    IUniversalSwap public universapSwap;

    constructor(
        IUniversalSwap _universalSwap,
        ConversionHelper _conversionHelper
    ) {
        universapSwap = _universalSwap;
        conversionHelper = _conversionHelper;
    }

    ///-------------Internal logic-------------
    function findMultipleSwaps(
        address[] memory inputTokens,
        uint256[] memory inputAmounts,
        uint256[] memory inputValues,
        address[] memory outputTokens,
        uint256[] memory outputValues
    ) public view returns (SwapPoint[] memory bestSwaps) {
        bestSwaps = new SwapPoint[](inputTokens.length * outputTokens.length);
        for (uint256 i = 0; i < inputTokens.length; i++) {
            for (uint256 j = 0; j < outputTokens.length; j++) {
                bestSwaps[(i * outputTokens.length) + j] = _findBestRoute(
                    FindSwapsBetween(inputTokens[i], outputTokens[j], outputValues[j], inputAmounts[i], inputValues[i])
                );
            }
        }
        bestSwaps = bestSwaps.sort();
        bestSwaps = bestSwaps.findBestSwaps(inputTokens, inputValues, inputAmounts, outputTokens, outputValues);
    }

    function getAmountsOut(
        Provided memory provided,
        Desired memory desired,
        SwapPoint[] memory swaps,
        Conversion[] memory conversions
    ) external view returns (uint256[] memory amounts, uint256[] memory expectedUSDValues) {
        (address[] memory underlyingTokens, ) = conversions.getUnderlying();
        uint256[] memory expectedAmounts;
        (underlyingTokens, expectedAmounts) = simulateSwaps(swaps, provided.tokens, provided.amounts);
        (underlyingTokens, expectedAmounts) = underlyingTokens.shrink(expectedAmounts);
        amounts = conversionHelper.simulateConversions(conversions, desired.outputERC20s, underlyingTokens, expectedAmounts);
        expectedUSDValues = new uint256[](amounts.length);
        for (uint256 i = 0; i < desired.outputERC20s.length; i++) {
            address[] memory token = new address[](1);
            uint256[] memory amount = new uint256[](1);
            token[0] = desired.outputERC20s[i];
            amount[0] = amounts[i];
            uint256 value = universapSwap.estimateValue(Provided(token, amount, new Asset[](0)), universapSwap.stableToken());
            expectedUSDValues[i] = value;
        }
        for (uint256 i = 0; i < desired.outputERC721s.length; i++) {
            desired.outputERC721s[i].liquidity = amounts[desired.outputERC20s.length + i];
            Asset[] memory nft = new Asset[](1);
            nft[0] = desired.outputERC721s[i];
            uint256 value = universapSwap.estimateValue(Provided(new address[](0), new uint256[](0), nft), universapSwap.stableToken());
            expectedUSDValues[desired.outputERC20s.length + i] = value;
        }
    }

    function simulateSwaps(
        SwapPoint[] memory swaps,
        address[] memory tokens,
        uint256[] memory amounts
    ) public view returns (address[] memory tokensOut, uint256[] memory amountsOut) {
        tokensOut = new address[](swaps.length);
        amountsOut = new uint256[](swaps.length);

        SwapPoint[] memory swapsConducted = new SwapPoint[](swaps.length);
        uint[][][] memory amountsForSwaps = new uint[][][](swaps.length);

        for (uint256 i = 0; i < swaps.length; i++) {
            uint256 amount = (swaps[i].amountIn * amounts[tokens.findFirst(swaps[i].tokenIn)]) / 1e18;
            amountsForSwaps[i] = new uint[][](swaps[i].swappers.length);
            for (uint j = 0; j < swaps[i].swappers.length; j++) {
                uint[] memory amountsForSwap = ISwapper(swaps[i].swappers[j]).getAmountsOutWithPath(
                    amount,
                    swaps[i].paths[j],
                    amountsForSwaps,
                    swapsConducted
                );
                amount = amountsForSwap[amountsForSwap.length - 1];
                amountsForSwaps[i][j] = amountsForSwap;
            }
            tokensOut[i] = swaps[i].tokenOut;
            amountsOut[i] = amount;
            swapsConducted[i] = swaps[i];
        }
    }

    ///-------------Internal logic-------------
    function _recommendConnector(
        address tokenIn,
        address tokenOut,
        uint amount
    ) internal view returns (address[4] memory connectors) {
        uint[][] memory scoresIn;
        uint[][] memory scoresOut;
        address[] memory swappers = universapSwap.getSwappers();
        for (uint i = 0; i < swappers.length; i++) {
            ISwapper swapper = ISwapper(swappers[i]);
            address[] memory commonPoolTokens = swapper.getCommonPoolTokens();
            for (uint j = 0; j < commonPoolTokens.length; j++) {
                address[] memory path = new address[](3);
                path[0] = tokenIn;
                path[1] = commonPoolTokens[j];
                path[2] = tokenIn;
                uint amountIn = swapper.getAmountOut(amount, path);
                uint[] memory scoreIn = new uint[](3);
                scoreIn[0] = i;
                scoreIn[1] = j;
                scoreIn[2] = amountIn;
                scoresIn = scoresIn.append(scoreIn);
                path[0] = tokenOut;
                path[2] = tokenOut;
                uint amountOut = swapper.getAmountOut(amount, path);
                uint[] memory scoreOut = new uint[](3);
                scoreOut[0] = i;
                scoreOut[1] = j;
                scoreOut[2] = amountOut;
                scoresOut = scoresOut.append(scoreOut);
            }
        }
        uint maxAmountIn;
        uint maxAmountInIndex;
        uint maxAmountOut;
        uint maxAmountOutIndex;
        for (uint i = 0; i < scoresIn.length; i++) {
            if (scoresIn[i][2] > maxAmountIn) {
                maxAmountIn = scoresIn[i][2];
                maxAmountInIndex = i;
            }
        }
        for (uint i = 0; i < scoresOut.length; i++) {
            if (scoresOut[i][2] > maxAmountOut) {
                maxAmountOut = scoresOut[i][2];
                maxAmountOutIndex = i;
            }
        }
        connectors[0] = swappers[scoresIn[maxAmountInIndex][0]];
        connectors[1] = ISwapper(swappers[scoresIn[maxAmountInIndex][0]]).getCommonPoolTokens()[
            scoresIn[maxAmountInIndex][1]
        ];
        connectors[2] = swappers[scoresOut[maxAmountOutIndex][0]];
        connectors[3] = ISwapper(swappers[scoresOut[maxAmountOutIndex][0]]).getCommonPoolTokens()[
            scoresOut[maxAmountOutIndex][1]
        ];
    }

    function _calculateRouteAmount(
        address[] memory swappersUsed,
        address[][] memory paths,
        uint amount
    ) internal view returns (uint) {
        for (uint i = 0; i < swappersUsed.length; i++) {
            amount = ISwapper(swappersUsed[i]).getAmountOut(amount, paths[i]);
        }
        return amount;
    }

    function _routeHelper(
        address[] memory swappersUsed,
        address[][] memory paths,
        uint amountIn,
        FindSwapsBetween memory swapsBetween,
        uint tokenWorth,
        uint valueIn
    ) internal view returns (SwapPoint memory, uint) {
        uint score = _calculateRouteAmount(swappersUsed, paths, amountIn);
        uint256 valueOut = (tokenWorth * score) / uint256(10) ** ERC20(swapsBetween.tokenOut).decimals();
        int256 slippage = (1e12 * (int256(valueIn) - int256(valueOut))) / int256(valueIn);
        return (
            SwapPoint(
                amountIn,
                valueIn,
                score,
                valueOut,
                slippage,
                swapsBetween.tokenIn,
                swappersUsed,
                swapsBetween.tokenOut,
                paths
            ),
            score
        );
    }

    function _findBestRoute(FindSwapsBetween memory swapsBetween) internal view returns (SwapPoint memory swapPoint) {
        uint256 amountIn = swapsBetween.valueNeeded > swapsBetween.valueInAvailable
            ? swapsBetween.amountInAvailable
            : (swapsBetween.valueNeeded * swapsBetween.amountInAvailable) / swapsBetween.valueInAvailable;
        uint256 valueIn = (amountIn * swapsBetween.valueInAvailable) / swapsBetween.amountInAvailable;
        address[] memory swappers = universapSwap.getSwappers();
        uint256 tokenWorth = IOracle(universapSwap.oracle()).getPrice(swapsBetween.tokenOut, universapSwap.networkToken());
        address[4] memory connectors = _recommendConnector(swapsBetween.tokenIn, swapsBetween.tokenOut, amountIn);
        SwapPoint[] memory swaps = new SwapPoint[](swappers.length + 3);
        uint[] memory scores = new uint[](swappers.length + 3);
        for (uint i = 0; i < swappers.length; i++) {
            address[][] memory paths = new address[][](1);
            paths[0] = new address[](2);
            paths[0][0] = swapsBetween.tokenIn;
            paths[0][1] = swapsBetween.tokenOut;
            address[] memory swappersUsed = new address[](1);
            swappersUsed[0] = swappers[i];
            (swaps[i], scores[i]) = _routeHelper(swappersUsed, paths, amountIn, swapsBetween, tokenWorth, valueIn);
        }
        {
            address[][] memory paths = new address[][](1);
            paths[0] = new address[](3);
            paths[0][0] = swapsBetween.tokenIn;
            paths[0][1] = connectors[1];
            paths[0][2] = swapsBetween.tokenOut;
            address[] memory swappersUsed = new address[](1);
            swappersUsed[0] = connectors[0];
            (swaps[swappers.length], scores[swappers.length]) = _routeHelper(
                swappersUsed,
                paths,
                amountIn,
                swapsBetween,
                tokenWorth,
                valueIn
            );
        }
        {
            address[][] memory paths = new address[][](1);
            paths[0] = new address[](3);
            paths[0][0] = swapsBetween.tokenIn;
            paths[0][1] = connectors[3];
            paths[0][2] = swapsBetween.tokenOut;
            address[] memory swappersUsed = new address[](1);
            swappersUsed[0] = connectors[2];
            (swaps[swappers.length + 1], scores[swappers.length + 1]) = _routeHelper(
                swappersUsed,
                paths,
                amountIn,
                swapsBetween,
                tokenWorth,
                valueIn
            );
        }
        {
            address[][] memory paths;
            address[] memory swappersUsed;
            if (connectors[0] != connectors[2]) {
                paths = new address[][](2);
                swappersUsed = new address[](2);
                paths[0] = new address[](2);
                paths[0][0] = swapsBetween.tokenIn;
                paths[0][1] = connectors[1];
                paths[1] = new address[](3);
                paths[1][0] = connectors[1];
                paths[1][1] = connectors[3];
                paths[1][2] = swapsBetween.tokenOut;
                swappersUsed[0] = connectors[0];
                swappersUsed[1] = connectors[2];
            } else {
                paths = new address[][](1);
                swappersUsed = new address[](1);
                swappersUsed[0] = connectors[0];
                paths[0] = new address[](4);
                paths[0][0] = swapsBetween.tokenIn;
                paths[0][1] = connectors[1];
                paths[0][2] = connectors[3];
                paths[0][3] = swapsBetween.tokenOut;
            }
            (swaps[swappers.length + 2], scores[swappers.length + 2]) = _routeHelper(
                swappersUsed,
                paths,
                amountIn,
                swapsBetween,
                tokenWorth,
                valueIn
            );
        }
        uint maxScore;
        uint bestScoreIndex;
        for (uint i = 0; i < scores.length; i++) {
            if (scores[i] > maxScore) {
                maxScore = scores[i];
                bestScoreIndex = i;
            }
        }
        return swaps[bestScoreIndex];
    }
}