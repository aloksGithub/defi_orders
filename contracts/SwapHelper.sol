// SPDX-License-Identifier: BUSL 1.1
pragma solidity ^0.8.9;

import "./interfaces/IPoolInteractor.sol";
import "./interfaces/ISwapper.sol";
import "./interfaces/IUniversalSwap.sol";
import "./interfaces/IWETH.sol";
import "./libraries/UintArray.sol";
import "./libraries/AddressArray.sol";
import "./libraries/SwapFinder.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "./interfaces/IOracle.sol";
import "./libraries/Conversions.sol";
import "./libraries/UintArray2D.sol";
import "hardhat/console.sol";

contract SwapHelper is Ownable {
    using Address for address;
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

    address public networkToken;
    address public stableToken;
    address[] public swappers;
    address[] public poolInteractors;
    address[] public nftPoolInteractors;
    IOracle public oracle;

    constructor(
        address[] memory _poolInteractors,
        address[] memory _nftPoolInteractors,
        address _networkToken,
        address _stableToken,
        address[] memory _swappers,
        IOracle _oracle
    ) {
        poolInteractors = _poolInteractors;
        nftPoolInteractors = _nftPoolInteractors;
        swappers = _swappers;
        networkToken = _networkToken;
        stableToken = _stableToken;
        oracle = _oracle;
    }

    function setSwappers(address[] calldata _swappers) external onlyOwner {
        swappers = _swappers;
    }

    function getSwappers() external view returns (address[] memory) {
        return swappers;
    }

    function setOracle(address _oracle) external onlyOwner {
        oracle = IOracle(_oracle);
    }

    function setPoolInteractors(address[] calldata _poolInteractors) external onlyOwner {
        poolInteractors = _poolInteractors;
    }

    function setNFTPoolInteractors(address[] calldata _nftPoolInteractors) external onlyOwner {
        nftPoolInteractors = _nftPoolInteractors;
    }

    function isSimpleToken(address token) public view returns (bool) {
        if (token == networkToken || token == address(0)) return true;
        for (uint256 i = 0; i < swappers.length; i++) {
            if (ISwapper(swappers[i]).checkSwappable(token)) {
                return true;
            }
        }
        return false;
    }

    function getProtocol(address token) public view returns (address) {
        if (isSimpleToken(token)) return address(0);
        for (uint256 x = 0; x < poolInteractors.length; x++) {
            if (IPoolInteractor(poolInteractors[x]).testSupported(token)) return poolInteractors[x];
        }
        for (uint256 i = 0; i < nftPoolInteractors.length; i++) {
            if (INFTPoolInteractor(nftPoolInteractors[i]).testSupported(token)) return nftPoolInteractors[i];
        }
        return address(0);
    }

    function getTokenValues(
        address[] memory tokens,
        uint256[] memory tokenAmounts
    ) public view returns (uint256[] memory values, uint256 total) {
        values = new uint256[](tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            uint256 tokenWorth = oracle.getPrice(tokens[i], networkToken);
            values[i] = (tokenWorth * tokenAmounts[i]) / uint256(10) ** ERC20(tokens[i]).decimals();
            total += values[i];
        }
    }

    function estimateValue(Provided memory assets, address inTermsOf) public view returns (uint256) {
        (address[] memory tokens, uint256[] memory amounts) = simplifyWithoutWrite(
            assets.tokens,
            assets.amounts,
            assets.nfts
        );
        (, uint256 value) = getTokenValues(tokens, amounts);
        uint256 tokenWorth = oracle.getPrice(networkToken, inTermsOf);
        value = (tokenWorth * value) / uint256(10) ** ERC20(networkToken).decimals();
        return value;
    }

    function _getConversionsERC20(address desired, uint256 valueAllocated) internal view returns (Conversion[] memory) {
        (address[] memory underlying, uint256[] memory ratios) = getUnderlyingERC20(desired);
        ratios = ratios.scale(valueAllocated);
        Asset memory placeholder;
        Conversion[] memory conversions;
        for (uint256 i = 0; i < underlying.length; i++) {
            if (!isSimpleToken(underlying[i])) {
                Conversion[] memory underlyingConversions = _getConversionsERC20(underlying[i], ratios[i]);
                conversions = conversions.concat(underlyingConversions);
            }
        }
        Conversion memory finalConversion = Conversion(placeholder, desired, valueAllocated, underlying, ratios);
        conversions = conversions.append(finalConversion);
        return conversions;
    }

    function _getConversionsERC721(
        Asset memory nft,
        uint256 valueAllocated
    ) internal view returns (Conversion[] memory) {
        (address[] memory underlying, uint256[] memory ratios) = getUnderlyingERC721(nft);
        ratios = ratios.scale(valueAllocated);
        Conversion[] memory conversions;
        Conversion memory finalConversion = Conversion(nft, address(0), valueAllocated, underlying, ratios);
        conversions = conversions.append(finalConversion);
        return conversions;
    }

    function prepareConversions(
        address[] memory desiredERC20s,
        Asset[] memory desiredERC721s,
        uint256[] memory ratios,
        uint256 totalAvailable
    ) public view returns (Conversion[] memory conversions) {
        ratios = ratios.scale(totalAvailable);
        for (uint256 i = 0; i < desiredERC20s.length; i++) {
            conversions = conversions.concat(_getConversionsERC20(desiredERC20s[i], ratios[i]));
        }
        for (uint256 i = 0; i < desiredERC721s.length; i++) {
            conversions = conversions.concat(
                _getConversionsERC721(desiredERC721s[i], ratios[desiredERC20s.length + i])
            );
        }
    }

    function _simulateConversionERC20(
        Conversion memory conversion,
        address[] memory inputTokens,
        uint256[] memory inputTokenAmounts
    ) internal view returns (uint256, uint256[] memory) {
        if (
            (conversion.underlying[0] == conversion.desiredERC20 && conversion.underlying.length == 1) ||
            conversion.desiredERC20 == address(0)
        ) {
            uint256 idx = inputTokens.findFirst(conversion.underlying[0]);
            uint256 balance = inputTokenAmounts[idx];
            inputTokenAmounts[idx] -= (balance * conversion.underlyingValues[0]) / 1e18;
            return ((balance * conversion.underlyingValues[0]) / 1e18, inputTokenAmounts);
        } else {
            uint256[] memory amounts = new uint256[](conversion.underlying.length);
            for (uint256 i = 0; i < conversion.underlying.length; i++) {
                uint256 idx = inputTokens.findFirst(conversion.underlying[i]);
                uint256 balance = inputTokenAmounts[idx];
                uint256 amountToUse = (balance * conversion.underlyingValues[i]) / 1e18;
                amounts[i] = amountToUse;
                inputTokenAmounts[idx] -= amountToUse;
            }
            address poolInteractor = getProtocol(conversion.desiredERC20);
            uint256 mintable = IPoolInteractor(poolInteractor).simulateMint(
                conversion.desiredERC20,
                conversion.underlying,
                amounts
            );
            return (mintable, inputTokenAmounts);
        }
    }

    function _simulateConversionERC721(
        Conversion memory conversion,
        address[] memory inputTokens,
        uint256[] memory inputTokenAmounts
    ) internal view returns (uint256, uint256[] memory) {
        uint256[] memory amounts = new uint256[](conversion.underlying.length);
        for (uint256 j = 0; j < conversion.underlying.length; j++) {
            uint256 idx = inputTokens.findFirst(conversion.underlying[j]);
            uint256 balance = inputTokenAmounts[idx];
            uint256 amountToUse = (balance * conversion.underlyingValues[j]) / 1e18;
            inputTokenAmounts[idx] -= amountToUse;
            amounts[j] = amountToUse;
        }
        address poolInteractor = getProtocol(conversion.desiredERC721.manager);
        uint256 liquidityMinted = INFTPoolInteractor(poolInteractor).simulateMint(
            conversion.desiredERC721,
            conversion.underlying,
            amounts
        );
        return (liquidityMinted, inputTokenAmounts);
    }

    function simulateConversions(
        Conversion[] memory conversions,
        address[] memory outputTokens,
        address[] memory inputTokens,
        uint256[] memory inputAmounts
    ) public view returns (uint256[] memory amounts) {
        amounts = new uint256[](conversions.length);
        uint256 amountsAdded;
        for (uint256 i = 0; i < conversions.length; i++) {
            if (conversions[i].desiredERC721.manager != address(0)) {
                (uint256 liquidity, uint256[] memory newAmounts) = _simulateConversionERC721(
                    conversions[i],
                    inputTokens,
                    inputAmounts
                );
                inputAmounts = newAmounts;
                amounts[amountsAdded] = liquidity;
                amountsAdded += 1;
            } else {
                (uint256 amountObtained, uint256[] memory newAmounts) = _simulateConversionERC20(
                    conversions[i],
                    inputTokens,
                    inputAmounts
                );
                inputAmounts = newAmounts;
                if (outputTokens.exists(conversions[i].desiredERC20) && conversions[i].underlying.length != 0) {
                    amounts[amountsAdded] = amountObtained;
                    amountsAdded += 1;
                } else {
                    inputTokens = inputTokens.append(conversions[i].desiredERC20);
                    inputAmounts.append(amountObtained);
                }
            }
        }
    }

    function getUnderlyingERC20(
        address token
    ) public view returns (address[] memory underlyingTokens, uint256[] memory ratios) {
        if (isSimpleToken(token)) {
            underlyingTokens = new address[](1);
            underlyingTokens[0] = token != address(0) ? token : networkToken;
            ratios = new uint256[](1);
            ratios[0] = 1;
        } else {
            address poolInteractor = getProtocol(token);
            if (poolInteractor != address(0)) {
                IPoolInteractor poolInteractorContract = IPoolInteractor(poolInteractor);
                (underlyingTokens, ratios) = poolInteractorContract.getUnderlyingTokens(token);
            } else {
                revert("UT"); //Unsupported Token
            }
        }
    }

    function getUnderlyingERC721(
        Asset memory nft
    ) public view returns (address[] memory underlying, uint256[] memory ratios) {
        for (uint256 i = 0; i < nftPoolInteractors.length; i++) {
            if (INFTPoolInteractor(nftPoolInteractors[i]).testSupported(nft.manager)) {
                INFTPoolInteractor poolInteractor = INFTPoolInteractor(nftPoolInteractors[i]);
                underlying = poolInteractor.getUnderlyingTokens(nft.pool);
                ratios = new uint256[](underlying.length);
                (int24 tick0, int24 tick1, , ) = abi.decode(nft.data, (int24, int24, uint256, uint256));
                (uint256 ratio0, uint256 ratio1) = poolInteractor.getRatio(nft.pool, tick0, tick1);
                ratios[0] = ratio0;
                ratios[1] = ratio1;
            }
        }
    }

    function _simplifyWithoutWriteERC20(
        address[] memory tokens,
        uint256[] memory amounts
    ) internal view returns (address[] memory simplifiedTokens, uint256[] memory simplifiedAmounts) {
        for (uint256 i = 0; i < tokens.length; i++) {
            if (isSimpleToken(tokens[i])) {
                if (tokens[i] != address(0)) {
                    simplifiedTokens = simplifiedTokens.append(tokens[i]);
                } else {
                    simplifiedTokens = simplifiedTokens.append(networkToken);
                }
                simplifiedAmounts = simplifiedAmounts.append(amounts[i]);
                continue;
            }
            for (uint256 j = 0; j < poolInteractors.length; j++) {
                if (IPoolInteractor(poolInteractors[j]).testSupported(tokens[i])) {
                    (address[] memory brokenTokens, uint256[] memory brokenAmounts) = IPoolInteractor(
                        poolInteractors[j]
                    ).getUnderlyingAmount(tokens[i], amounts[i]);
                    (address[] memory simpleTokens, uint256[] memory simpleAmounts) = _simplifyWithoutWriteERC20(
                        brokenTokens,
                        brokenAmounts
                    );
                    simplifiedTokens = simplifiedTokens.concat(simpleTokens);
                    simplifiedAmounts = simplifiedAmounts.concat(simpleAmounts);
                }
            }
        }
    }

    function _simplifyWithoutWriteERC721(
        Asset[] memory nfts
    ) internal view returns (address[] memory simplifiedTokens, uint256[] memory simplifiedAmounts) {
        for (uint256 i = 0; i < nfts.length; i++) {
            for (uint256 j = 0; j < nftPoolInteractors.length; j++) {
                if (INFTPoolInteractor(nftPoolInteractors[j]).testSupported(nfts[i].manager)) {
                    (address[] memory tokens, uint256[] memory amounts) = INFTPoolInteractor(nftPoolInteractors[j])
                        .getUnderlyingAmount(nfts[i]);
                    simplifiedTokens = simplifiedTokens.concat(tokens);
                    simplifiedAmounts = simplifiedAmounts.concat(amounts);
                }
            }
        }
    }

    function simplifyWithoutWrite(
        address[] memory tokens,
        uint256[] memory amounts,
        Asset[] memory nfts
    ) public view returns (address[] memory simplifiedTokens, uint256[] memory simplifiedAmounts) {
        (simplifiedTokens, simplifiedAmounts) = _simplifyWithoutWriteERC20(tokens, amounts);
        (
            address[] memory simplifiedTokensERC721,
            uint256[] memory simplifiedAmountsERC721
        ) = _simplifyWithoutWriteERC721(nfts);
        simplifiedTokens = simplifiedTokens.concat(simplifiedTokensERC721);
        simplifiedAmounts = simplifiedAmounts.concat(simplifiedAmountsERC721);
        (simplifiedTokens, simplifiedAmounts) = simplifiedTokens.shrink(simplifiedAmounts);
    }

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

    function _recommendConnector(
        address tokenIn,
        address tokenOut,
        uint amount
    ) internal view returns (address[4] memory connectors) {
        uint[][] memory scoresIn;
        uint[][] memory scoresOut;
        for (uint i = 0; i < swappers.length; i++) {
            ISwapper swapper = ISwapper(swappers[i]);
            address[] memory commonPoolTokens = swapper.getCommonPoolTokens();
            for (uint j = 0; j < commonPoolTokens.length; j++) {
                address[] memory path = new address[](3);
                path[0] = tokenIn;
                path[1] = commonPoolTokens[j];
                path[2] = tokenIn;
                uint amountIn = swapper.getAmountOut2(amount, path);
                uint[] memory scoreIn = new uint[](3);
                scoreIn[0] = i;
                scoreIn[1] = j;
                scoreIn[2] = amountIn;
                scoresIn = scoresIn.append(scoreIn);
                path[0] = tokenOut;
                path[2] = tokenOut;
                uint amountOut = swapper.getAmountOut2(amount, path);
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
            amount = ISwapper(swappersUsed[i]).getAmountOut2(amount, paths[i]);
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
        // SwapPoint memory bestSingleSwap;
        // uint256 maxAmountOut;
        uint256 tokenWorth = oracle.getPrice(swapsBetween.tokenOut, networkToken);
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
        amounts = simulateConversions(conversions, desired.outputERC20s, underlyingTokens, expectedAmounts);
        expectedUSDValues = new uint256[](amounts.length);
        for (uint256 i = 0; i < desired.outputERC20s.length; i++) {
            address[] memory token = new address[](1);
            uint256[] memory amount = new uint256[](1);
            token[0] = desired.outputERC20s[i];
            amount[0] = amounts[i];
            uint256 value = estimateValue(Provided(token, amount, new Asset[](0)), stableToken);
            expectedUSDValues[i] = value;
        }
        for (uint256 i = 0; i < desired.outputERC721s.length; i++) {
            desired.outputERC721s[i].liquidity = amounts[desired.outputERC20s.length + i];
            Asset[] memory nft = new Asset[](1);
            nft[0] = desired.outputERC721s[i];
            uint256 value = estimateValue(Provided(new address[](0), new uint256[](0), nft), stableToken);
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
}
