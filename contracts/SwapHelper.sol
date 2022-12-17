// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
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
import "./interfaces/Venus/IVToken.sol";
import "./libraries/Conversions.sol";
import "hardhat/console.sol";

contract SwapHelper is Ownable {
    using Address for address;
    using UintArray for uint[];
    using AddressArray for address[];
    using SwapFinder for SwapPoint[];
    using SafeERC20 for IERC20;
    using Conversions for Conversion[];

    struct FindSwapsBetween {
        address tokenIn;
        address tokenOut;
        uint valueNeeded;
        uint amountInAvailable;
        uint valueInAvailable;
    }

    address public networkToken;
    address[] public swappers;
    address[] public poolInteractors;
    address[] public nftPoolInteractors;
    IOracle public oracle;

    constructor (
        address[] memory _poolInteractors,
        address[] memory _nftPoolInteractors,
        address _networkToken,
        address[] memory _swappers,
        IOracle _oracle
    ) {
        poolInteractors = _poolInteractors;
        nftPoolInteractors = _nftPoolInteractors;
        swappers = _swappers;
        networkToken = _networkToken;
        oracle = _oracle;
    }

    function setSwappers(address[] calldata _swappers) external view onlyOwner {
        _swappers = _swappers;
    }

    function setPoolInteractors(address[] calldata _poolInteractors) external onlyOwner {
        poolInteractors = _poolInteractors;
    }

    function setNFTPoolInteractors(address[] calldata _nftPoolInteractors) external onlyOwner {
        nftPoolInteractors = _nftPoolInteractors;
    }

    function isSimpleToken(address token) public view returns (bool) {
        if (token==networkToken || token==address(0)) return true;
        for (uint i = 0;i<swappers.length; i++) {
            if (ISwapper(swappers[i]).checkSwappable(token)) {
                return true;
            }
        }
        return false;
    }

    function getProtocol(address token) public view returns (address) {
        if (isSimpleToken(token)) return address(0);
        for (uint x = 0; x<poolInteractors.length; x++) {
            if (IPoolInteractor(poolInteractors[x]).testSupported(token)) return poolInteractors[x];
        }
        for (uint i = 0; i<nftPoolInteractors.length; i++) {
            if (INFTPoolInteractor(nftPoolInteractors[i]).testSupported(token)) return nftPoolInteractors[i];
        }
        return address(0);
    }

    function getTokenValues(address[] memory tokens, uint[] memory tokenAmounts) public view returns (uint[] memory values, uint total) {
        values = new uint[](tokens.length);
        for (uint i = 0; i<tokens.length; i++) {
            uint tokenWorth = oracle.getPrice(tokens[i], networkToken);
            values[i] = tokenWorth*tokenAmounts[i]/uint(10)**ERC20(tokens[i]).decimals();
            total+=values[i];
        }
    }

    function estimateValue(Provided memory assets, address inTermsOf) public view returns (uint) {
        (address[] memory tokens, uint[] memory amounts) = simplifyWithoutWrite(assets.tokens, assets.amounts, assets.nfts);
        (,uint value) = getTokenValues(tokens, amounts);
        uint tokenWorth = oracle.getPrice(networkToken, inTermsOf);
        value = tokenWorth*value/uint(10)**ERC20(networkToken).decimals();
        return value;
    }

    function _getConversionsERC20(address desired, uint valueAllocated) internal view returns (Conversion[] memory) {
        (address[] memory underlying, uint[] memory ratios) = getUnderlyingERC20(desired);
        ratios = ratios.scale(valueAllocated);
        Asset memory placeholder;
        Conversion[] memory conversions;
        for (uint i = 0; i<underlying.length; i++) {
            if (!isSimpleToken(underlying[i])) {
                Conversion[] memory underlyingConversions = _getConversionsERC20(underlying[i], ratios[i]);
                conversions = conversions.concat(underlyingConversions);
            }
        }
        Conversion memory finalConversion = Conversion(placeholder, desired, valueAllocated, underlying, ratios);
        conversions = conversions.append(finalConversion);
        return conversions;
    }

    function _getConversionsERC721(Asset memory nft, uint valueAllocated) internal view returns (Conversion[] memory) {
        (address[] memory underlying, uint[] memory ratios) = getUnderlyingERC721(nft);
        ratios = ratios.scale(valueAllocated);
        Conversion[] memory conversions;
        Conversion memory finalConversion = Conversion(nft, address(0), valueAllocated, underlying, ratios);
        conversions = conversions.append(finalConversion);
        return conversions;
    }

    function prepareConversions(address[] memory desiredERC20s, Asset[] memory desiredERC721s, uint[] memory ratios, uint totalAvailable) public view returns (Conversion[] memory conversions) {
        ratios = ratios.scale(totalAvailable);
        for (uint i = 0; i<desiredERC20s.length; i++) {
            conversions = conversions.concat(_getConversionsERC20(desiredERC20s[i], ratios[i]));
        }
        for (uint i = 0; i<desiredERC721s.length; i++) {
            conversions = conversions.concat(_getConversionsERC721(desiredERC721s[i], ratios[desiredERC20s.length+i]));
        }
    }

    function _simulateConversionERC20(Conversion memory conversion, address[] memory inputTokens, uint[] memory inputTokenAmounts) internal view returns (uint, uint[] memory) {
        if ((conversion.underlying[0]==conversion.desiredERC20 && conversion.underlying.length==1) || conversion.desiredERC20==address(0)) {
            uint idx = inputTokens.findFirst(conversion.underlying[0]);
            uint balance = inputTokenAmounts[idx];
            inputTokenAmounts[idx]-=balance*conversion.underlyingValues[0]/1e18;
            return (balance*conversion.underlyingValues[0]/1e18, inputTokenAmounts);
        } else {
            uint[] memory amounts = new uint[](conversion.underlying.length);
            for (uint i = 0; i<conversion.underlying.length; i++) {
                uint idx = inputTokens.findFirst(conversion.underlying[i]);
                uint balance = inputTokenAmounts[idx];
                uint amountToUse = balance*conversion.underlyingValues[i]/1e18;
                amounts[i] = amountToUse;
                inputTokenAmounts[idx]-=amountToUse;
            }
            address poolInteractor = getProtocol(conversion.desiredERC20);
            uint mintable = IPoolInteractor(poolInteractor).simulateMint(conversion.desiredERC20, conversion.underlying, amounts);
            return (mintable, inputTokenAmounts);
        }
    }

    function _simulateConversionERC721(Conversion memory conversion, address[] memory inputTokens, uint[] memory inputTokenAmounts) internal view returns (uint, uint[] memory) {
        uint[] memory amounts = new uint[](conversion.underlying.length);
        for (uint j = 0; j<conversion.underlying.length; j++) {
            uint idx = inputTokens.findFirst(conversion.underlying[j]);
            uint balance = inputTokenAmounts[idx];
            uint amountToUse = balance*conversion.underlyingValues[j]/1e18;
            inputTokenAmounts[idx]-=amountToUse;
            amounts[j] = amountToUse;
        }
        address poolInteractor = getProtocol(conversion.desiredERC721.manager);
        uint liquidityMinted = INFTPoolInteractor(poolInteractor).simulateMint(conversion.desiredERC721, conversion.underlying, amounts);
        return (liquidityMinted, inputTokenAmounts);
    }

    function simulateConversions(
        Conversion[] memory conversions,
        address[] memory outputTokens,
        address[] memory inputTokens,
        uint[] memory inputAmounts
    ) public view returns (uint[] memory amounts) {
        amounts = new uint[](conversions.length);
        uint amountsAdded;
        for (uint i = 0; i<conversions.length; i++) {
            if (conversions[i].desiredERC721.manager!=address(0)) {
                (uint liquidity, uint[] memory newAmounts) = _simulateConversionERC721(conversions[i], inputTokens, inputAmounts);
                inputAmounts = newAmounts;
                amounts[amountsAdded] = liquidity;
                amountsAdded+=1;
            } else {
                (uint amountObtained, uint[] memory newAmounts) = _simulateConversionERC20(conversions[i], inputTokens, inputAmounts);
                inputAmounts = newAmounts;
                if (outputTokens.exists(conversions[i].desiredERC20) && conversions[i].underlying.length!=0) {
                    amounts[amountsAdded] = amountObtained;
                    amountsAdded+=1;
                } else {
                    inputTokens = inputTokens.append(conversions[i].desiredERC20);
                    inputAmounts.append(amountObtained);
                }
            }
        }
    }

    function getUnderlyingERC20(address token) public view returns (address[] memory underlyingTokens, uint[] memory ratios) {
        if (isSimpleToken(token)) {
            underlyingTokens = new address[](1);
            underlyingTokens[0] = token!=address(0)?token:networkToken;
            ratios = new uint[](1);
            ratios[0] = 1;
        } else {
            address poolInteractor = getProtocol(token);
            if (poolInteractor!=address(0)) {
                IPoolInteractor poolInteractorContract = IPoolInteractor(poolInteractor);
                (underlyingTokens, ratios) = poolInteractorContract.getUnderlyingTokens(token);
            } else {
                revert("UT"); //Unsupported Token
            }
        }
    }

    function getUnderlyingERC721(Asset memory nft) public view returns (address[] memory underlying, uint[] memory ratios) {
        for (uint i = 0; i<nftPoolInteractors.length; i++) {
            if (INFTPoolInteractor(nftPoolInteractors[i]).testSupported(nft.manager)) {
                INFTPoolInteractor poolInteractor = INFTPoolInteractor(nftPoolInteractors[i]);
                underlying = poolInteractor.getUnderlyingTokens(nft.pool);
                ratios = new uint[](underlying.length);
                (int24 tick0, int24 tick1,,) = abi.decode(nft.data, (int24, int24, uint, uint));
                (uint ratio0, uint ratio1) = poolInteractor.getRatio(nft.pool, tick0, tick1);
                ratios[0] = ratio0;
                ratios[1] = ratio1;
            }
        }
    }

    function _simplifyWithoutWriteERC20(address[] memory tokens, uint[] memory amounts) internal view returns (address[] memory simplifiedTokens, uint[] memory simplifiedAmounts) {
        for (uint i = 0; i<tokens.length; i++) {
            if (isSimpleToken(tokens[i])) {
                if (tokens[i]!=address(0)) {
                    simplifiedTokens = simplifiedTokens.append(tokens[i]);
                } else {
                    simplifiedTokens = simplifiedTokens.append(networkToken);
                }
                simplifiedAmounts = simplifiedAmounts.append(amounts[i]);
                continue;
            }
            for (uint j = 0; j<poolInteractors.length; j++) {
                if (IPoolInteractor(poolInteractors[j]).testSupported(tokens[i])) {
                    (address[] memory brokenTokens, uint[] memory brokenAmounts) = IPoolInteractor(poolInteractors[j]).getUnderlyingAmount(tokens[i], amounts[i]);
                    (address[] memory simpleTokens, uint[] memory simpleAmounts) = _simplifyWithoutWriteERC20(brokenTokens, brokenAmounts);
                    simplifiedTokens = simplifiedTokens.concat(simpleTokens);
                    simplifiedAmounts = simplifiedAmounts.concat(simpleAmounts);
                }
            }
        }
    }

    function _simplifyWithoutWriteERC721(Asset[] memory nfts) internal view returns (address[] memory simplifiedTokens, uint[] memory simplifiedAmounts) {
        for (uint i = 0; i<nfts.length; i++) {
            for (uint j = 0; j<nftPoolInteractors.length; j++) {
                if (INFTPoolInteractor(nftPoolInteractors[j]).testSupported(nfts[i].manager)) {
                    (address[] memory tokens, uint[] memory amounts) = INFTPoolInteractor(nftPoolInteractors[j]).getUnderlyingAmount(nfts[i]);
                    simplifiedTokens = simplifiedTokens.concat(tokens);
                    simplifiedAmounts = simplifiedAmounts.concat(amounts);
                }
            }
        }
    }

    function simplifyWithoutWrite(address[] memory tokens, uint[] memory amounts, Asset[] memory nfts) public view returns (address[] memory simplifiedTokens, uint[] memory simplifiedAmounts) {
        (simplifiedTokens, simplifiedAmounts) = _simplifyWithoutWriteERC20(tokens, amounts);
        (address[] memory simplifiedTokensERC721, uint[] memory simplifiedAmountsERC721) = _simplifyWithoutWriteERC721(nfts);
        simplifiedTokens = simplifiedTokens.concat(simplifiedTokensERC721);
        simplifiedAmounts = simplifiedAmounts.concat(simplifiedAmountsERC721);
        (simplifiedTokens, simplifiedAmounts) = simplifiedTokens.shrink(simplifiedAmounts);
    }

    function findMultipleSwaps(
        address[] memory inputTokens,
        uint[] memory inputAmounts,
        uint[] memory inputValues,
        address[] memory outputTokens,
        uint[] memory outputValues
    ) public view returns (SwapPoint[] memory bestSwaps) {
        bestSwaps = new SwapPoint[](inputTokens.length*outputTokens.length);
        for (uint i = 0; i<inputTokens.length; i++) {
            for (uint j = 0; j<outputTokens.length; j++) {
                bestSwaps[(i*outputTokens.length)+j] = _findBestRoute(FindSwapsBetween(inputTokens[i], outputTokens[j], outputValues[j], inputAmounts[i], inputValues[i]));
            }
        }
        bestSwaps = bestSwaps.sort();
        bestSwaps = bestSwaps.findBestSwaps(inputTokens, inputValues, inputAmounts, outputTokens, outputValues);
    }

    function _findBestRoute(FindSwapsBetween memory swapsBetween) internal view returns (SwapPoint memory swapPoint) {
        uint amountIn = swapsBetween.valueNeeded>swapsBetween.valueInAvailable?swapsBetween.amountInAvailable:swapsBetween.valueNeeded*swapsBetween.amountInAvailable/swapsBetween.valueInAvailable;
        uint valueIn = amountIn*swapsBetween.valueInAvailable/swapsBetween.amountInAvailable;
        SwapPoint memory bestSingleSwap;
        uint maxAmountOut;
        uint tokenWorth = oracle.getPrice(swapsBetween.tokenOut, networkToken);
        if (swapsBetween.tokenIn==swapsBetween.tokenOut) {
            address[] memory path;
            return SwapPoint(amountIn, valueIn, amountIn, valueIn, 0, swapsBetween.tokenIn, swappers[0], swapsBetween.tokenOut, path);
        }
        for (uint i = 0; i<swappers.length; i++) {
            (uint amountOut, address[] memory path) = ISwapper(swappers[i]).getAmountOut(swapsBetween.tokenIn, amountIn, swapsBetween.tokenOut);
            if (amountOut>maxAmountOut) {
                maxAmountOut = amountOut;
                uint valueOut = tokenWorth*amountOut/uint(10)**ERC20(swapsBetween.tokenOut).decimals();
                int slippage = (1e12*(int(valueIn)-int(valueOut)))/int(valueIn);
                bestSingleSwap = SwapPoint(amountIn, valueIn, amountOut, valueOut, slippage, swapsBetween.tokenIn, swappers[i], swapsBetween.tokenOut, path);
            }
        }
        return bestSingleSwap;
    }

    function simulateSwaps(SwapPoint[] memory swaps, address[] memory tokens, uint[] memory amounts) public view returns (address[] memory tokensOut, uint[] memory amountsOut) {
        tokensOut = new address[](swaps.length);
        amountsOut = new uint[](swaps.length);
        for (uint i = 0; i<swaps.length; i++) {
            uint amount = swaps[i].amountIn*amounts[tokens.findFirst(swaps[i].tokenIn)]/1e18;
            tokensOut[i] = swaps[i].tokenOut;
            amountsOut[i] = ISwapper(swaps[i].swapper).getAmountOutWithPath(amount, swaps[i].path);
        }
    }
}