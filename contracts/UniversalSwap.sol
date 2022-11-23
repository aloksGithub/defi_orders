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

contract UniversalSwap is IUniversalSwap, Ownable {
    using Address for address;
    using UintArray for uint[];
    using AddressArray for address[];
    using SwapFinder for SwapPoint[];
    using SafeERC20 for IERC20;
    using Conversions for Conversion[];

    event NFTMinted(address manager, uint tokenId, address pool);

    address public networkToken;
    address[] public swappers;
    uint fractionDenominator = 10000;
    address[] public poolInteractors;
    address[] public nftPoolInteractors;
    IOracle public oracle;
    address[] public commonPoolTokens; // Common pool tokens are used to test different swap paths with commonly used pool tokens to find the best swaps

    constructor (
        address[] memory _poolInteractors,
        address[] memory _nftPoolInteractors,
        address _networkToken,
        address[] memory _swappers,
        IOracle _oracle,
        address[] memory _commonPoolTokens
    ) {
        poolInteractors = _poolInteractors;
        nftPoolInteractors = _nftPoolInteractors;
        swappers = _swappers;
        networkToken = _networkToken;
        oracle = _oracle;
        commonPoolTokens = _commonPoolTokens;
    }
    
    function setSwappers(address[] calldata _swappers) external view onlyOwner {
        _swappers = _swappers;
    }

    /// @inheritdoc IUniversalSwap
    function setPoolInteractors(address[] calldata _poolInteractors) external onlyOwner {
        poolInteractors = _poolInteractors;
    }

    /// @inheritdoc IUniversalSwap
    function setNFTPoolInteractors(address[] calldata _nftPoolInteractors) external onlyOwner {
        nftPoolInteractors = _nftPoolInteractors;
    }

    /// @inheritdoc IUniversalSwap
    function isSupported(address token) public view returns (bool) {
        if (_isSimpleToken(token)) return true;
        if (_getProtocol(token)!=address(0)) return true;
        return false;
    }

    function _getWETH() internal returns (uint networkTokenObtained){
        uint startingBalance = IERC20(networkToken).balanceOf(address(this));
        if (msg.value>0) {
            IWETH(payable(networkToken)).deposit{value:msg.value}();
        }
        networkTokenObtained = IERC20(networkToken).balanceOf(address(this))-startingBalance;
    }

    function _addWETH(address[] memory tokens, uint[] memory amounts) internal returns (address[] memory, uint[] memory) {
        uint ethSupplied = _getWETH();
        if (ethSupplied>0) {
            bool found = false;
            for (uint i = 0; i<tokens.length; i++) {
                if (tokens[i]==networkToken) {
                    amounts[i]+=ethSupplied;
                    found = true;
                    break;
                }
            }
            if (!found) {
                address[] memory newTokens = new address[](tokens.length+1);
                newTokens[0] = networkToken;
                uint[] memory newAmounts = new uint[](amounts.length+1);
                newAmounts[0] = ethSupplied;
                for (uint i = 0; i<tokens.length; i++) {
                    newTokens[i+1] = tokens[i];
                    newAmounts[i+1] = amounts[i];
                }
                amounts = newAmounts;
                tokens = newTokens;
            }
        }
        return (tokens, amounts);
    }

    function _isSimpleToken(address token) internal view returns (bool) {
        for (uint i = 0;i<swappers.length; i++) {
            if (ISwapper(swappers[i]).checkSwappable(token)) {
                return true;
            }
        }
        return false;
    }

    function _getProtocol(address token) internal view returns (address) {
        if (_isSimpleToken(token)) return address(0);
        for (uint x = 0; x<poolInteractors.length; x++) {
            if (IPoolInteractor(poolInteractors[x]).testSupported(token)) return poolInteractors[x];
        }
        for (uint i = 0; i<nftPoolInteractors.length; i++) {
            if (INFTPoolInteractor(nftPoolInteractors[i]).testSupported(token)) return nftPoolInteractors[i];
        }
        return address(0);
    }

    /// @inheritdoc IUniversalSwap
    function getUnderlyingERC20(address token) public view returns (address[] memory underlyingTokens, uint[] memory ratios) {
        if (_isSimpleToken(token)) {
            underlyingTokens = new address[](1);
            underlyingTokens[0] = token;
            ratios = new uint[](1);
            ratios[0] = 1;
        } else {
            address poolInteractor = _getProtocol(token);
            if (poolInteractor!=address(0)) {
                IPoolInteractor poolInteractorContract = IPoolInteractor(poolInteractor);
                (underlyingTokens, ratios) = poolInteractorContract.getUnderlyingTokens(token);
            } else {
                revert("Unsupported Token");
            }
        }
    }

    /// @inheritdoc IUniversalSwap
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

    function _burn(address token, uint amount) internal returns (address[] memory underlyingTokens, uint[] memory underlyingTokenAmounts) {
        address poolInteractor = _getProtocol(token);
        bytes memory data = poolInteractor.functionDelegateCall(abi.encodeWithSelector(IPoolInteractor(poolInteractor).burn.selector, token, amount, poolInteractor));
        (underlyingTokens, underlyingTokenAmounts) = abi.decode(data, (address[], uint[]));
    }

    function _mint(address toMint, address[] memory underlyingTokens, uint[] memory underlyingAmounts) internal returns (uint amountMinted) {
        if (toMint==underlyingTokens[0]) return underlyingAmounts[0];
        address poolInteractor = _getProtocol(toMint);
        bytes memory returnData = poolInteractor.functionDelegateCall(
            abi.encodeWithSelector(IPoolInteractor(poolInteractor).mint.selector, toMint, underlyingTokens, underlyingAmounts, msg.sender, poolInteractor)
        );
        amountMinted = abi.decode(returnData, (uint));
    }

    function _convertSimpleTokens(uint amount, address[] memory path, address swapper) internal returns (uint) {
        bytes memory returnData = swapper.functionDelegateCall(abi.encodeWithSelector(ISwapper(swapper).swap.selector, amount, path, swapper));
        (uint amountReturned) = abi.decode(returnData, (uint));
        return amountReturned;
    }

    function _simplifyInputTokens(address[] memory inputTokens, uint[] memory inputTokenAmounts) internal returns (address[] memory, uint[] memory) {
        bool allSimiplified = true;
        address[] memory updatedTokens = inputTokens;
        uint[] memory updatedTokenAmounts = inputTokenAmounts;
        for (uint i = 0; i<inputTokens.length; i++) {
            if (!_isSimpleToken(inputTokens[i])) {
                allSimiplified = false;
                (address[] memory newTokens, uint[] memory newTokenAmounts) = _burn(inputTokens[i], inputTokenAmounts[i]);
                updatedTokens[i] = newTokens[0];
                updatedTokenAmounts[i] = newTokenAmounts[0];
                address[] memory tempTokens = new address[](updatedTokens.length + newTokens.length-1);
                uint[] memory tempTokenAmounts = new uint[](updatedTokenAmounts.length + newTokenAmounts.length-1);
                uint j = 0;
                while (j<updatedTokens.length) {
                    tempTokens[j] = updatedTokens[j];
                    tempTokenAmounts[j] = updatedTokenAmounts[j];
                    j++;
                }
                uint k = 0;
                while (k<newTokens.length-1) {
                    tempTokens[j+k] = newTokens[k+1];
                    tempTokenAmounts[j+k] = newTokenAmounts[k+1];
                    k++;
                }
                updatedTokens = tempTokens;
                updatedTokenAmounts = tempTokenAmounts;
            }
        }
        if (allSimiplified) {
            (inputTokens, inputTokenAmounts) = _shrink(inputTokens, inputTokenAmounts);
            return (inputTokens, inputTokenAmounts);
        } else {
            return _simplifyInputTokens(updatedTokens, updatedTokenAmounts);
        }
    }

    function _collectAndBreak(address[] memory inputTokens, uint[] memory inputTokenAmounts, Asset[] memory inputNFTs) internal returns (address[] memory, uint[] memory) {
        for (uint i = 0; i<inputTokenAmounts.length; i++) {
            uint balanceBefore = IERC20(inputTokens[i]).balanceOf(address(this));
            IERC20(inputTokens[i]).safeTransferFrom(msg.sender, address(this), inputTokenAmounts[i]);
            inputTokenAmounts[i] = IERC20(inputTokens[i]).balanceOf(address(this))-balanceBefore;
        }
        for (uint i = 0; i<inputNFTs.length; i++) {
            Asset memory nft = inputNFTs[i];
            for (uint j = 0; j<nftPoolInteractors.length; j++) {
                if (INFTPoolInteractor(nftPoolInteractors[j]).testSupported(nft.manager)) {
                    IERC721(nft.manager).transferFrom(msg.sender, address(this), nft.tokenId);
                    bytes memory returnData = nftPoolInteractors[j].functionDelegateCall(
                        abi.encodeWithSelector(INFTPoolInteractor(nftPoolInteractors[j]).burn.selector, nft)
                    );
                    (address[] memory nftTokens, uint[] memory nftTokenAmounts) = abi.decode(returnData, (address[], uint[]));
                    inputTokens = inputTokens.concat(nftTokens);
                    inputTokenAmounts = inputTokenAmounts.concat(nftTokenAmounts);
                }
            }
        }
        (address[] memory simplifiedTokens, uint[] memory simplifiedTokenAmounts) = _simplifyInputTokens(inputTokens, inputTokenAmounts);
        (simplifiedTokens, simplifiedTokenAmounts) = _addWETH(simplifiedTokens, simplifiedTokenAmounts);
        return (simplifiedTokens, simplifiedTokenAmounts);
    }

    function _getTokenValues(address[] memory tokens, uint[] memory tokenAmounts) internal view returns (uint[] memory values, uint total) {
        values = new uint[](tokens.length);
        for (uint i = 0; i<tokens.length; i++) {
            uint tokenWorth = oracle.getPrice(tokens[i], networkToken);
            values[i] = tokenWorth*tokenAmounts[i]/uint(10)**ERC20(tokens[i]).decimals();
            total+=values[i];
        }
    }

    function _scaleRatios(uint[] memory ratios, uint newTotal) internal pure returns (uint[] memory) {
        uint totalRatios;
        for (uint i = 0; i<ratios.length; i++) {
            totalRatios+=ratios[i];
        }
        for (uint i = 0; i<ratios.length; i++) {
            ratios[i] = ratios[i]*newTotal/totalRatios;
        }
        return ratios;
    }

    function _getConversionsERC20(address desired, uint valueAllocated) internal view returns (Conversion[] memory) {
        (address[] memory underlying, uint[] memory ratios) = getUnderlyingERC20(desired);
        ratios = _scaleRatios(ratios, valueAllocated);
        Asset memory placeholder;
        Conversion[] memory conversions;
        for (uint i = 0; i<underlying.length; i++) {
            if (!_isSimpleToken(underlying[i])) {
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
        ratios = _scaleRatios(ratios, valueAllocated);
        Conversion[] memory conversions;
        Conversion memory finalConversion = Conversion(nft, address(0), valueAllocated, underlying, ratios);
        conversions = conversions.append(finalConversion);
        return conversions;
    }

    function _prepareConversions(address[] memory desiredERC20s, Asset[] memory desiredERC721s, uint[] memory ratios, uint totalAvailable) internal view returns (Conversion[] memory conversions) {
        ratios = _scaleRatios(ratios, totalAvailable);
        for (uint i = 0; i<desiredERC20s.length; i++) {
            conversions = conversions.concat(_getConversionsERC20(desiredERC20s[i], ratios[i]));
        }
        for (uint i = 0; i<desiredERC721s.length; i++) {
            conversions = conversions.concat(_getConversionsERC721(desiredERC721s[i], ratios[desiredERC20s.length+i]));
        }
    }

    function _conductERC20Conversion(Conversion memory conversion) internal returns(uint) {
        if (conversion.underlying[0]==conversion.desiredERC20 && conversion.underlying.length==1) {
            uint balance = IERC20(conversion.desiredERC20).balanceOf(address(this));
            IERC20(conversion.desiredERC20).safeTransfer(msg.sender, balance*conversion.underlyingValues[0]/1e18);
            return balance*conversion.underlyingValues[0]/1e18;
        } else {
            uint[] memory inputTokenAmounts = new uint[](conversion.underlying.length);
            for (uint i = 0; i<conversion.underlying.length; i++) {
                uint balance = IERC20(conversion.underlying[i]).balanceOf(address(this));
                uint amountToUse = balance*conversion.underlyingValues[i]/1e18;
                inputTokenAmounts[i] = amountToUse;
            }
            return _mint(conversion.desiredERC20, conversion.underlying, inputTokenAmounts);
        }
    }
    
    function _conductERC721Conversion(Conversion memory conversion) internal returns (uint) {
        Asset memory nft = conversion.desiredERC721;
        for (uint i = 0; i<nftPoolInteractors.length; i++) {
            if (INFTPoolInteractor(nftPoolInteractors[i]).testSupported(nft.manager)) {
                uint[] memory inputTokenAmounts = new uint[](conversion.underlying.length);
                for (uint j = 0; j<conversion.underlying.length; j++) {
                    uint balance = IERC20(conversion.underlying[j]).balanceOf(address(this));
                    uint amountToUse = balance*conversion.underlyingValues[j]/1e18;
                    inputTokenAmounts[j] = amountToUse;
                }
                bytes memory returnData = nftPoolInteractors[i].functionDelegateCall(
                    abi.encodeWithSelector(INFTPoolInteractor(nftPoolInteractors[i]).mint.selector, nft, conversion.underlying, inputTokenAmounts, msg.sender)
                );
                uint tokenId = abi.decode(returnData, (uint));
                emit NFTMinted(nft.manager, tokenId, nft.pool);
                return tokenId;
            }
        }
        revert("Failed to get NFT");
    }

    function _conductConversions(Conversion[] memory conversions, address[] memory outputTokens, uint[] memory minAmountsOut) internal returns (uint[] memory amounts) {
        amounts = new uint[](conversions.length);
        uint amountsAdded;
        for (uint i = 0; i<conversions.length; i++) {
            if (conversions[i].desiredERC20==address(0)) {
                uint tokenId = _conductERC721Conversion(conversions[i]);
                amounts[i] = tokenId;
            } else {
                uint amountObtained = _conductERC20Conversion(conversions[i]);
                if (outputTokens.exists(conversions[i].desiredERC20) && conversions[i].underlying.length!=0) {
                    amounts[amountsAdded] = amountObtained;
                    require(amountObtained>=minAmountsOut[amountsAdded]);
                    amountsAdded+=1;
                }
                amounts[i] = amountObtained;
            }
        }
    }

    function _conductSwaps(SwapPoint[] memory swaps) internal {
        for (uint i = 0; i<swaps.length; i++) {
            if (swaps[i].tokenIn==address(0)) return;
            _convertSimpleTokens(swaps[i].amountIn, swaps[i].path, swaps[i].swapper);
        }
    }

    struct FindSwapsBetween {
        address tokenIn;
        address tokenOut;
        uint valueNeeded;
        uint amountInAvailable;
        uint valueInAvailable;
    }

    function _simplifyWithoutWriteERC20(address[] memory tokens, uint[] memory amounts) internal view returns (address[] memory simplifiedTokens, uint[] memory simplifiedAmounts) {
        for (uint i = 0; i<tokens.length; i++) {
            if (_isSimpleToken(tokens[i])) {
                simplifiedTokens = simplifiedTokens.append(tokens[i]);
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

    function _simplifyWithoutWrite(address[] memory tokens, uint[] memory amounts, Asset[] memory nfts) internal view returns (address[] memory simplifiedTokens, uint[] memory simplifiedAmounts) {
        (simplifiedTokens, simplifiedAmounts) = _simplifyWithoutWriteERC20(tokens, amounts);
        (address[] memory simplifiedTokensERC721, uint[] memory simplifiedAmountsERC721) = _simplifyWithoutWriteERC721(nfts);
        simplifiedTokens = simplifiedTokens.concat(simplifiedTokensERC721);
        simplifiedAmounts = simplifiedAmounts.concat(simplifiedAmountsERC721);
        (simplifiedTokens, simplifiedAmounts) = _shrink(simplifiedTokens, simplifiedAmounts);
    }

    function _findMultipleSwaps(
        address[] memory inputTokens,
        uint[] memory inputAmounts,
        uint[] memory inputValues,
        address[] memory outputTokens,
        uint[] memory outputValues
    ) internal view returns (SwapPoint[] memory bestSwaps) {
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
        // SwapPoint[] memory bestDoubleSwap = new SwapPoint[](2);
        // for (uint i=0; i<swappers.length; i++) {
        //     for (uint j = 0; j<commonPoolTokens.length; j++) {
        //         uint amountOutIntermediate = ISwapper(swappers[i]).getAmountOut(tokenIn, amountIn, commonPoolTokens[j]);
        //         numEvals+=1;
        //         for (uint k = 0; k<swappers.length; k++) {
        //             uint amountOut = ISwapper(swappers[k]).getAmountOut(commonPoolTokens[j], amountOutIntermediate, tokenOut);
        //             numEvals+=1;
        //             if (amountOut>maxAmountOut) {
        //                 maxAmountOut = amountOut;
        //                 uint valueOut = tokenWorth*amountOut/uint(10)**ERC20(tokenOut).decimals();
        //                 int slippage = (1e12*(int(valueIn)-int(valueOut)))/int(valueIn);
        //                 bestDoubleSwap[0] = SwapPoint(amountIn, valueIn, amountOutIntermediate, 0, 0, tokenIn, swappers[i], commonPoolTokens[j]);
        //                 bestDoubleSwap[1] = SwapPoint(amountOutIntermediate, 0, amountOut, valueOut, slippage, commonPoolTokens[j], swappers[k], tokenOut);
        //             }
        //         }
        //     }
        // }
        // console.log(numEvals);
        // if (bestSingleSwap.amountOut>bestDoubleSwap[1].amountOut) {
        //     SwapPoint[] memory swapPoints = new SwapPoint[](1);
        //     swapPoints[0] = bestSingleSwap;
        //     // console.log(tokenIn, tokenOut, maxAmountOut);
        //     return swapPoints;
        // } else {
        //     // console.log(tokenIn, tokenOut, maxAmountOut);
        //     return bestDoubleSwap;
        // }
    }

    function _shrink(address[] memory tokens, uint[] memory amounts) internal pure returns (address[] memory shrunkTokens, uint[] memory shrunkAmounts) {
        for (uint i = 0; i<tokens.length; i++) {
            for (uint j = i; j<tokens.length; j++) {
                if (j>i && tokens[i]==tokens[j]) {
                    amounts[i] = amounts[i]+amounts[j];
                    amounts[j] = 0;
                }
            }
        }
        uint shrunkSize;
        for (uint i = 0; i<tokens.length; i++) {
            if (amounts[i]>0) {
                shrunkSize+=1;
            }
        }
        shrunkTokens = new address[](shrunkSize);
        shrunkAmounts = new uint[](shrunkSize);
        uint tokensAdded;
        for (uint i = 0; i<tokens.length; i++) {
            if (amounts[i]>0) {
                shrunkTokens[tokensAdded] = tokens[i];
                shrunkAmounts[tokensAdded] = amounts[i];
                tokensAdded+=1;
            }
        }
    }

    function swapV2(
        address[] memory inputTokens,
        uint[] memory inputTokenAmounts,
        Asset[] memory inputNFTs,
        Desired memory desired
    ) external returns (uint[] memory) {
        (inputTokens, inputTokenAmounts) = _collectAndBreak(inputTokens, inputTokenAmounts, inputNFTs);
        (SwapPoint[] memory bestSwaps, Conversion[] memory conversions) = preSwapComputation(inputTokens, inputTokenAmounts, inputNFTs, desired);
        _conductSwaps(bestSwaps);
        uint[] memory amountsAndIds = _conductConversions(conversions, desired.outputERC20s, desired.minAmountsOut);
        return amountsAndIds;
    }

    function preSwapComputation(
        address[] memory inputTokens,
        uint[] memory inputTokenAmounts,
        Asset[] memory inputNFTs,
        Desired memory desired
    ) public view returns (SwapPoint[] memory, Conversion[] memory) {
        (inputTokens, inputTokenAmounts) = _simplifyWithoutWrite(inputTokens, inputTokenAmounts, inputNFTs);
        (uint[] memory inputTokenValues, uint totalValue) = _getTokenValues(inputTokens, inputTokenAmounts);

        Conversion[] memory conversions = _prepareConversions(desired.outputERC20s, desired.outputERC721s, desired.ratios, totalValue);
        (address[] memory underlyingTokens, uint[] memory underlyingValues) = conversions.getUnderlying();
        (underlyingTokens, underlyingValues) = _shrink(underlyingTokens, underlyingValues);
        SwapPoint[] memory bestSwaps = _findMultipleSwaps(inputTokens, inputTokenAmounts, inputTokenValues, underlyingTokens, underlyingValues);
        conversions = conversions.normalizeRatios();
        return (bestSwaps, conversions);
    }

    function swapWithPreCompute(
        address[] memory inputTokens,
        uint[] memory inputTokenAmounts,
        Asset[] memory inputNFTs,
        SwapPoint[] memory swaps,
        Conversion[] memory conversions,
        Desired memory desired
    ) external returns (uint[] memory) {
        (inputTokens, inputTokenAmounts) = _collectAndBreak(inputTokens, inputTokenAmounts, inputNFTs);
        _conductSwaps(swaps);
        uint[] memory amountsAndIds = _conductConversions(conversions, desired.outputERC20s, desired.minAmountsOut);
        return amountsAndIds;
    }
}