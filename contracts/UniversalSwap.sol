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
import "hardhat/console.sol";

contract UniversalSwap is IUniversalSwap, Ownable {
    using Address for address;
    using UintArray for uint[];
    using AddressArray for address[];
    using SwapFinder for SwapPoint[];
    using SafeERC20 for IERC20;

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
    function isSupported(address token) public returns (bool) {
        if (_isSimpleToken(token)) return true;
        if (_isPoolToken(token)) return true;
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

    function _isSimpleToken(address token) internal returns (bool) {
        if (token==networkToken) return true;
        if (_isPoolToken(token)) return false;
        for (uint i = 0;i<swappers.length; i++) {
            bool liquidable = ISwapper(swappers[i]).checkSwappable(token, networkToken);
            if (liquidable) {
                return true;
            }
        }
        return false;
    }

    function _isPoolToken(address token) internal returns (bool) {
        for (uint x = 0; x<poolInteractors.length; x++) {
            try IPoolInteractor(poolInteractors[x]).testSupported(token) returns (bool supported) {
                if (supported==true) {
                    return true;
                }
            } catch {}
        }
        return false;
    }

    function _getProtocol(address token) internal returns (address) {
        for (uint x = 0; x<poolInteractors.length; x++) {
            try IPoolInteractor(poolInteractors[x]).testSupported(token) returns (bool supported) {
                if (supported==true) {
                    return poolInteractors[x];
                }
            } catch {}
        }
        for (uint i = 0; i<nftPoolInteractors.length; i++) {
            try INFTPoolInteractor(nftPoolInteractors[i]).testSupportedPool(token) returns (bool supported) {
                if (supported==true) {
                    return nftPoolInteractors[i];
                }
            } catch {}
        }
        return address(0);
    }

    /// @inheritdoc IUniversalSwap
    function getUnderlyingERC20(address token) public returns (address[] memory underlyingTokens, uint[] memory ratios) {
        address poolInteractor = _getProtocol(token);
        if (poolInteractor==address(0)) {
            if (_isSimpleToken(token)) {
                underlyingTokens = new address[](1);
                underlyingTokens[0] = token;
                ratios = new uint[](1);
                ratios[0] = 1;
            } else {
                revert("Unsupported Token");
            }
        } else {
            IPoolInteractor poolInteractorContract = IPoolInteractor(poolInteractor);
            (underlyingTokens, ratios) = poolInteractorContract.getUnderlyingTokens(token);
        }
    }

    /// @inheritdoc IUniversalSwap
    function getUnderlyingERC721(Asset memory nft) public returns (address[] memory underlying, uint[] memory ratios) {
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

    function _convertSimpleTokens2(uint amount, address[] memory path, address swapper) internal returns (uint) {
        bytes memory returnData = swapper.functionDelegateCall(abi.encodeWithSelector(ISwapper(swapper).swap.selector, amount, path, swapper));
        (uint amountReturned) = abi.decode(returnData, (uint));
        return amountReturned;
    }

    function _simplifyInputTokens(address[] memory inputTokens, uint[] memory inputTokenAmounts) internal returns (address[] memory, uint[] memory) {
        bool allSimiplified = true;
        address[] memory updatedTokens = inputTokens;
        uint[] memory updatedTokenAmounts = inputTokenAmounts;
        for (uint i = 0; i<inputTokens.length; i++) {
            if (_isPoolToken(inputTokens[i])) {
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

    function _mint(address toMint, address[] memory underlyingTokens, uint[] memory underlyingAmounts) internal returns (uint amountMinted) {
        if (toMint==underlyingTokens[0]) return underlyingAmounts[0];
        address poolInteractor = _getProtocol(toMint);
        // for (uint i = 0; i<underlyingTokens.length; i++) {
        //     IERC20(underlyingTokens[i]).safeApprove(poolInteractor, underlyingAmounts[i]);
        // }
        // amountMinted = IPoolInteractor(poolInteractor).mint(toMint, underlyingTokens, underlyingAmounts);
        bytes memory returnData = poolInteractor.functionDelegateCall(
            abi.encodeWithSelector(IPoolInteractor(poolInteractor).mint.selector, toMint, underlyingTokens, underlyingAmounts, msg.sender, poolInteractor)
        );
        amountMinted = abi.decode(returnData, (uint));
    }

    function _getTokenValues(address[] memory tokens, uint[] memory tokenAmounts) internal view returns (uint[] memory values, uint total) {
        values = new uint[](tokens.length);
        for (uint i = 0; i<tokens.length; i++) {
            uint tokenWorth = oracle.getPrice(tokens[i], networkToken);
            values[i] = tokenWorth*tokenAmounts[i]/uint(10)**ERC20(tokens[i]).decimals();
            total+=values[i];
        }
    }

    function _getDesiredValues(address[] memory tokens, uint[] memory ratios, uint totalValue) internal pure returns (uint[] memory values) {
        values = new uint[](tokens.length);
        uint totalRatio;
        for (uint i = 0; i<tokens.length; i++) {
            totalRatio+=ratios[i];
        }
        for (uint i = 0; i<tokens.length; i++) {
            values[i] = ratios[i]*totalValue/totalRatio;
        }
    }

    struct Conversion {
        Asset desiredERC721;
        address desiredERC20;
        Conversion[] underlyingConversions;
        uint[] valueAllocated;
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

    function _getConversionsERC20(address desired, uint valueAllocated) internal returns (Conversion memory) {
        (address[] memory underlying, uint[] memory ratios) = getUnderlyingERC20(desired);
        ratios = _scaleRatios(ratios, valueAllocated);
        Asset memory placeholder;
        Conversion[] memory underlyingConversions = new Conversion[](underlying.length);
        for (uint i = 0; i<underlying.length; i++) {
            Conversion memory underlyingConversion;
            if (_isSimpleToken(underlying[i])) {
                uint[] memory value = new uint[](1);
                value[0] = ratios[i];
                underlyingConversion = Conversion(placeholder, underlying[i], new Conversion[](0), value);
            } else {
                underlyingConversion = _getConversionsERC20(underlying[i], ratios[i]);
            }
            underlyingConversions[i] = underlyingConversion;
        }
        return Conversion(placeholder, desired, underlyingConversions, ratios);
    }

    function _getConversionsERC721(Asset memory nft, uint valueAllocated) internal returns (Conversion memory) {
        (address[] memory underlying, uint[] memory ratios) = getUnderlyingERC721(nft);
        ratios = _scaleRatios(ratios, valueAllocated);
        Asset memory placeholder;
        Conversion[] memory underlyingConversions = new Conversion[](underlying.length);
        for (uint i = 0; i<underlying.length; i++) {
            uint[] memory value = new uint[](1);
            value[0] = ratios[i];
            underlyingConversions[i] = Conversion(placeholder, underlying[i], new Conversion[](0), value);
        }
        return Conversion(nft, address(0), underlyingConversions, ratios);
    }

    function _prepareConversions(address[] memory desiredERC20s, Asset[] memory desiredERC721s, uint[] memory ratios, uint totalAvailable) internal returns (Conversion[] memory conversions) {
        ratios = _scaleRatios(ratios, totalAvailable);
        conversions = new Conversion[](desiredERC20s.length+desiredERC721s.length);
        for (uint i = 0; i<desiredERC20s.length; i++) {
            conversions[i] = _getConversionsERC20(desiredERC20s[i], ratios[i]);
        }
        for (uint i = 0; i<desiredERC721s.length; i++) {
            conversions[desiredERC20s.length+i] = _getConversionsERC721(desiredERC721s[i], ratios[desiredERC20s.length+i]);
        }
    }

    function _getUnderlyingForConversions(Conversion[] memory conversions) internal view returns (address[] memory underlying, uint[] memory underlyingValues) {
        for (uint i = 0; i<conversions.length; i++) {
            if (conversions[i].underlyingConversions.length==0) {
                underlying = underlying.append(conversions[i].desiredERC20);
                underlyingValues = underlyingValues.append(conversions[i].valueAllocated[0]);
            } else {
                (address[] memory underlyingUnderlying, uint[] memory underlyingUnderlyingValues) = _getUnderlyingForConversions(conversions[i].underlyingConversions);
                underlying = underlying.concat(underlyingUnderlying);
                underlyingValues = underlyingValues.concat(underlyingUnderlyingValues);
            }
        }
    }

    function _getNumUnderlying(Conversion memory conversion) internal view returns (uint) {
        if (conversion.underlyingConversions.length==0) {
            return 1;
        } else {
            uint numUnderlying;
            for (uint i = 0; i<conversion.underlyingConversions.length; i++) {
                numUnderlying+=_getNumUnderlying(conversion.underlyingConversions[i]);
            }
            return numUnderlying;
        }
    }

    function _getTokenValue(address token, uint amount) internal view returns (uint) {
        uint tokenWorth = oracle.getPrice(token, networkToken);
        return tokenWorth*amount/uint(10)**ERC20(token).decimals();
    }

    function _conductERC20Conversion(Conversion memory conversion, uint[] memory underlyingValues, uint index) internal returns(uint, uint) {
        if (conversion.underlyingConversions.length==0) {
            return (underlyingValues[index], 1);
        } else {
            address[] memory inputTokens = new address[](conversion.underlyingConversions.length);
            uint[] memory inputTokenAmounts = new uint[](conversion.underlyingConversions.length);
            uint underlyingUsed;
            for (uint i = 0; i<conversion.underlyingConversions.length; i++) {
                Conversion memory underlyingConversion = conversion.underlyingConversions[i];
                inputTokens[i] = underlyingConversion.desiredERC20;
                if (underlyingConversion.underlyingConversions.length==0) {
                    inputTokenAmounts[i] = underlyingValues[index+i];
                    underlyingUsed+=1;
                } else {
                    (uint tokensNeeded, uint indexChange) = _conductERC20Conversion(underlyingConversion, underlyingValues, index+i);
                    underlyingUsed+=indexChange;
                    inputTokenAmounts[i] = tokensNeeded;
                }
            }
            return (_mint(conversion.desiredERC20, inputTokens, inputTokenAmounts), underlyingUsed);
        }
    }
    
    function _conductERC721Conversion(Conversion memory conversion, uint[] memory underlyingValues, uint index) internal returns (uint, uint) {
        Asset memory nft = conversion.desiredERC721;
        for (uint i = 0; i<nftPoolInteractors.length; i++) {
            if (INFTPoolInteractor(nftPoolInteractors[i]).testSupported(nft.manager)) {
                address[] memory inputTokens = new address[](conversion.underlyingConversions.length);
                uint[] memory inputTokenAmounts = new uint[](conversion.underlyingConversions.length);
                uint underlyingUsed;
                for (uint j = 0; j<conversion.underlyingConversions.length; j++) {
                    Conversion memory underlyingConversion = conversion.underlyingConversions[j];
                    inputTokens[j] = underlyingConversion.desiredERC20;
                    if (underlyingConversion.underlyingConversions.length==0) {
                        inputTokenAmounts[j] = underlyingValues[index+j];
                        underlyingUsed+=1;
                    } else {
                        (uint tokensNeeded, uint indexChange) = _conductERC20Conversion(underlyingConversion, underlyingValues, index+j);
                        underlyingUsed+=indexChange;
                        inputTokenAmounts[j] = tokensNeeded;
                    }
                }
                bytes memory returnData = nftPoolInteractors[i].functionDelegateCall(
                    abi.encodeWithSelector(INFTPoolInteractor(nftPoolInteractors[i]).mint.selector, nft, inputTokens, inputTokenAmounts, msg.sender)
                );
                uint tokenId = abi.decode(returnData, (uint));
                emit NFTMinted(nft.manager, tokenId, nft.pool);
                return (tokenId, underlyingUsed);
            }
        }
        revert("Failed to get NFT");
    }

    function _conductConversions(Conversion[] memory conversions, uint[] memory underlyingValues, uint[] memory minAmountsOut) internal returns (uint[] memory amounts) {
        uint underlyingStartingIndex;
        amounts = new uint[](conversions.length);
        for (uint i = 0; i<conversions.length; i++) {
            if (conversions[i].desiredERC20==address(0)) {
                (uint tokenId, uint indexChange) = _conductERC721Conversion(conversions[i], underlyingValues, underlyingStartingIndex);
                underlyingStartingIndex+=indexChange;
                amounts[i] = tokenId;
            } else {
                (uint amountObtained, uint indexChange) = _conductERC20Conversion(conversions[i], underlyingValues, underlyingStartingIndex);
                require(amountObtained>=minAmountsOut[i]);
                underlyingStartingIndex+=indexChange;
                amounts[i] = amountObtained;
            }
        }
    }

    function _conductSwaps(SwapPoint[] memory swaps) internal {
        for (uint i = 0; i<swaps.length; i++) {
            if (swaps[i].tokenIn==address(0)) return;
            _convertSimpleTokens2(swaps[i].amountIn, swaps[i].path, swaps[i].swapper);
        }
    }

    /// @notice Adjust values for slippage and change them to token amounts rather than corresponding usd values
    function _adjustValuesAfterSwap(address[] memory underlyingTokens, uint[] memory underlyingValues) internal view returns (uint[] memory) {
        for (uint i = 0; i<underlyingTokens.length; i++) {
            uint[] memory repeatedAddresses = underlyingTokens.findAll(underlyingTokens[i]);
            uint tokensAvailable = IERC20(underlyingTokens[i]).balanceOf(address(this));
            uint totalRatio = 0;
            for (uint j = 0; j<repeatedAddresses.length; j++) {
                totalRatio+=underlyingValues[repeatedAddresses[j]];
            }
            for (uint j = 0; j<repeatedAddresses.length; j++) {
                if (totalRatio==0) {
                    underlyingValues[repeatedAddresses[j]] = 0;
                } else {
                    uint value = tokensAvailable*underlyingValues[repeatedAddresses[j]]/totalRatio;
                    underlyingValues[repeatedAddresses[j]] = value;
                }
            }
        }
        return underlyingValues;
    }

    function _convertV2(
        address[] memory inputTokens,
        uint[] memory inputTokenAmounts,
        address[] memory desiredERC20s,
        Asset[] memory desiredERC721s,
        uint[] memory ratios,
        uint[] memory minAmountsOut
    ) internal returns (uint[] memory) {
        (address[] memory simplifiedTokens, uint[] memory simplifiedTokenAmounts) = _simplifyInputTokens(inputTokens, inputTokenAmounts);
        (simplifiedTokens, simplifiedTokenAmounts) = _addWETH(simplifiedTokens, simplifiedTokenAmounts);
        (uint[] memory simplifiedTokenValues, uint totalValue) = _getTokenValues(simplifiedTokens, simplifiedTokenAmounts);
        Conversion[] memory conversions = _prepareConversions(desiredERC20s, desiredERC721s, ratios, totalValue);
        (address[] memory underlyingTokens, uint[] memory underlyingValues) = _getUnderlyingForConversions(conversions);
        (underlyingTokens, underlyingValues) = _shrink(underlyingTokens, underlyingValues);
        SwapPoint[] memory bestSwaps = new SwapPoint[](simplifiedTokens.length*underlyingTokens.length);
        for (uint i = 0; i<simplifiedTokens.length; i++) {
            for (uint j = 0; j<underlyingTokens.length; j++) {
                // Calculating amountIn and valueIn here to prevent stack too deep error
                uint amountIn = underlyingValues[j]>simplifiedTokenValues[i]?simplifiedTokenAmounts[i]:underlyingValues[j]*simplifiedTokenAmounts[i]/simplifiedTokenValues[i];
                uint valueIn = amountIn*simplifiedTokenValues[i]/simplifiedTokenAmounts[i];
                bestSwaps[(i*underlyingTokens.length)+j] = _findBestRoute(FindSwapsBetween(simplifiedTokens[i], underlyingTokens[j], amountIn, valueIn));
            }
        }
        bestSwaps = bestSwaps.sort();
        bestSwaps = bestSwaps.findBestSwaps(simplifiedTokens, simplifiedTokenValues, underlyingTokens, underlyingValues);
        _conductSwaps(bestSwaps);
        (underlyingTokens, underlyingValues) = _getUnderlyingForConversions(conversions);
        underlyingValues = _adjustValuesAfterSwap(underlyingTokens, underlyingValues);
        uint[] memory amountsAndIds = _conductConversions(conversions, underlyingValues, minAmountsOut);
        for (uint i = 0; i<underlyingTokens.length; i++) {
            IERC20(underlyingTokens[i]).safeTransfer(msg.sender, IERC20(underlyingTokens[i]).balanceOf(address(this)));
        }
        return amountsAndIds;
    }

    struct FindSwapsBetween {
        address tokenIn;
        address tokenOut;
        uint amountIn;
        uint valueIn;
    }

    function _findBestRoute(FindSwapsBetween memory input) internal view returns (SwapPoint memory swapPoint) {
        SwapPoint memory bestSingleSwap;
        uint maxAmountOut;
        uint tokenWorth = oracle.getPrice(input.tokenOut, networkToken);
        if (input.tokenIn==input.tokenOut) {
            address[] memory path;
            return SwapPoint(input.amountIn, input.valueIn, input.amountIn, input.valueIn, 0, input.tokenIn, swappers[0], input.tokenOut, path);
        }
        for (uint i = 0; i<swappers.length; i++) {
            (bool success, bytes memory returnData) = swappers[i].staticcall(
                abi.encodeWithSignature("getAmountOut(address,uint256,address)", input.tokenIn, input.amountIn, input.tokenOut
            ));
            if (success) {
                (uint amountOut, address[] memory path) = abi.decode(returnData, (uint, address[]));
                if (amountOut>maxAmountOut) {
                    maxAmountOut = amountOut;
                    uint valueOut = tokenWorth*amountOut/uint(10)**ERC20(input.tokenOut).decimals();
                    int slippage = (1e12*(int(input.valueIn)-int(valueOut)))/int(input.valueIn);
                    bestSingleSwap = SwapPoint(input.amountIn, input.valueIn, amountOut, valueOut, slippage, input.tokenIn, swappers[i], input.tokenOut, path);
                }
            }
        }
        return bestSingleSwap;
        // SwapPoint[] memory bestDoubleSwap = new SwapPoint[](2);
        // for (uint i=0; i<swappers.length; i++) {
        //     for (uint j = 0; j<commonPoolTokens.length; j++) {
        //         uint amountOutIntermediate = ISwapper(swappers[i]).getAmountOut(input.tokenIn, input.amountIn, commonPoolTokens[j]);
        //         numEvals+=1;
        //         for (uint k = 0; k<swappers.length; k++) {
        //             uint amountOut = ISwapper(swappers[k]).getAmountOut(commonPoolTokens[j], amountOutIntermediate, input.tokenOut);
        //             numEvals+=1;
        //             if (amountOut>maxAmountOut) {
        //                 maxAmountOut = amountOut;
        //                 uint valueOut = tokenWorth*amountOut/uint(10)**ERC20(input.tokenOut).decimals();
        //                 int slippage = (1e12*(int(input.valueIn)-int(valueOut)))/int(input.valueIn);
        //                 bestDoubleSwap[0] = SwapPoint(input.amountIn, input.valueIn, amountOutIntermediate, 0, 0, input.tokenIn, swappers[i], commonPoolTokens[j]);
        //                 bestDoubleSwap[1] = SwapPoint(amountOutIntermediate, 0, amountOut, valueOut, slippage, commonPoolTokens[j], swappers[k], input.tokenOut);
        //             }
        //         }
        //     }
        // }
        // console.log(numEvals);
        // if (bestSingleSwap.amountOut>bestDoubleSwap[1].amountOut) {
        //     SwapPoint[] memory swapPoints = new SwapPoint[](1);
        //     swapPoints[0] = bestSingleSwap;
        //     // console.log(input.tokenIn, input.tokenOut, maxAmountOut);
        //     return swapPoints;
        // } else {
        //     // console.log(input.tokenIn, input.tokenOut, maxAmountOut);
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
        address[] memory outputERC20s,
        Asset[] memory outputERC721s,
        uint[] memory ratios,
        uint[] memory minAmountsOut
    ) external returns (uint[] memory) {
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
        
        return _convertV2(inputTokens, inputTokenAmounts, outputERC20s, outputERC721s, ratios, minAmountsOut);
    }

    function swapV3(
        address[] memory inputTokens,
        uint[] memory inputTokenAmounts,
        Asset[] memory inputNFTs,
        address[] memory outputERC20s,
        Asset[] memory outputERC721s,
        uint[] memory ratios,
        uint[] memory minAmountsOut
    ) external returns (uint[] memory) {
        _isSimpleToken(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
        // INFTPoolInteractor(nftPoolInteractors[0]).testSupportedPool(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
        // for (uint i = 0; i<inputTokenAmounts.length; i++) {
        //     uint balanceBefore = IERC20(inputTokens[i]).balanceOf(address(this));
        //     IERC20(inputTokens[i]).safeTransferFrom(msg.sender, address(this), inputTokenAmounts[i]);
        //     inputTokenAmounts[i] = IERC20(inputTokens[i]).balanceOf(address(this))-balanceBefore;
        // }
        // for (uint i = 0; i<inputNFTs.length; i++) {
        //     Asset memory nft = inputNFTs[i];
        //     for (uint j = 0; j<nftPoolInteractors.length; j++) {
        //         if (INFTPoolInteractor(nftPoolInteractors[j]).testSupported(nft.manager)) {
        //             IERC721(nft.manager).transferFrom(msg.sender, address(this), nft.tokenId);
        //             bytes memory returnData = nftPoolInteractors[j].functionDelegateCall(
        //                 abi.encodeWithSelector(INFTPoolInteractor(nftPoolInteractors[j]).burn.selector, nft)
        //             );
        //             (address[] memory nftTokens, uint[] memory nftTokenAmounts) = abi.decode(returnData, (address[], uint[]));
        //             inputTokens = inputTokens.concat(nftTokens);
        //             inputTokenAmounts = inputTokenAmounts.concat(nftTokenAmounts);
        //         }
        //     }
        // }
        
        // return _convertV3(inputTokens, inputTokenAmounts, outputERC20s, outputERC721s, ratios, minAmountsOut);
    }

    function _getProtocol2(address token) internal view returns (address) {
        for (uint x = 0; x<poolInteractors.length; x++) {
            (bool success, bytes memory returnData) = poolInteractors[x].staticcall(abi.encodeWithSelector(
                IPoolInteractor(poolInteractors[x]).testSupported.selector, token));
            if (success) {
                (bool supported) = abi.decode(returnData, (bool));
                if (supported) return poolInteractors[x];
            }
        }
        for (uint i = 0; i<nftPoolInteractors.length; i++) {
            (bool success, bytes memory returnData) = nftPoolInteractors[i].staticcall(abi.encodeWithSelector(
                INFTPoolInteractor(nftPoolInteractors[i]).testSupportedPool.selector, token));
            if (success) {
                (bool supported) = abi.decode(returnData, (bool));
                if (supported) return nftPoolInteractors[i];
            }
        }
        return address(0);
    }

    function getUnderlyingERC202(address token) public returns (address[] memory underlyingTokens, uint[] memory ratios) {
        address poolInteractor = _getProtocol2(token);
        if (poolInteractor==address(0)) {
            if (_isSimpleToken(token)) {
                underlyingTokens = new address[](1);
                underlyingTokens[0] = token;
                ratios = new uint[](1);
                ratios[0] = 1;
            } else {
                revert("Unsupported Token");
            }
        } else {
            IPoolInteractor poolInteractorContract = IPoolInteractor(poolInteractor);
            (underlyingTokens, ratios) = poolInteractorContract.getUnderlyingTokens(token);
        }
    }

    function _getConversionsERC202(address desired, uint valueAllocated) internal returns (Conversion memory) {
        (address[] memory underlying, uint[] memory ratios) = getUnderlyingERC202(desired);
        ratios = _scaleRatios(ratios, valueAllocated);
        Asset memory placeholder;
        Conversion[] memory underlyingConversions = new Conversion[](underlying.length);
        for (uint i = 0; i<underlying.length; i++) {
            Conversion memory underlyingConversion;
            if (_isSimpleToken(underlying[i])) {
                uint[] memory value = new uint[](1);
                value[0] = ratios[i];
                underlyingConversion = Conversion(placeholder, underlying[i], new Conversion[](0), value);
            } else {
                underlyingConversion = _getConversionsERC202(underlying[i], ratios[i]);
            }
            underlyingConversions[i] = underlyingConversion;
        }
        return Conversion(placeholder, desired, underlyingConversions, ratios);
    }

    function _getConversionsERC7212(Asset memory nft, uint valueAllocated) internal returns (Conversion memory) {
        (address[] memory underlying, uint[] memory ratios) = getUnderlyingERC721(nft);
        ratios = _scaleRatios(ratios, valueAllocated);
        Asset memory placeholder;
        Conversion[] memory underlyingConversions = new Conversion[](underlying.length);
        for (uint i = 0; i<underlying.length; i++) {
            uint[] memory value = new uint[](1);
            value[0] = ratios[i];
            underlyingConversions[i] = Conversion(placeholder, underlying[i], new Conversion[](0), value);
        }
        return Conversion(nft, address(0), underlyingConversions, ratios);
    }

    function _prepareConversions2(address[] memory desiredERC20s, Asset[] memory desiredERC721s, uint[] memory ratios, uint totalAvailable) internal returns (Conversion[] memory conversions) {
        ratios = _scaleRatios(ratios, totalAvailable);
        conversions = new Conversion[](desiredERC20s.length+desiredERC721s.length);
        for (uint i = 0; i<desiredERC20s.length; i++) {
            conversions[i] = _getConversionsERC202(desiredERC20s[i], ratios[i]);
        }
        for (uint i = 0; i<desiredERC721s.length; i++) {
            console.log(desiredERC721s[i].pool);
            conversions[desiredERC20s.length+i] = _getConversionsERC7212(desiredERC721s[i], ratios[desiredERC20s.length+i]);
        }
    }

    function _convertV3(
        address[] memory inputTokens,
        uint[] memory inputTokenAmounts,
        address[] memory desiredERC20s,
        Asset[] memory desiredERC721s,
        uint[] memory ratios,
        uint[] memory minAmountsOut
    ) internal returns (uint[] memory) {
        (address[] memory simplifiedTokens, uint[] memory simplifiedTokenAmounts) = _simplifyInputTokens(inputTokens, inputTokenAmounts);
        (simplifiedTokens, simplifiedTokenAmounts) = _addWETH(simplifiedTokens, simplifiedTokenAmounts);
        (uint[] memory simplifiedTokenValues, uint totalValue) = _getTokenValues(simplifiedTokens, simplifiedTokenAmounts);
        Conversion[] memory conversions = _prepareConversions2(desiredERC20s, desiredERC721s, ratios, totalValue);
        // (address[] memory underlyingTokens, uint[] memory underlyingValues) = _getUnderlyingForConversions(conversions);
        // (underlyingTokens, underlyingValues) = _shrink(underlyingTokens, underlyingValues);
        // SwapPoint[] memory bestSwaps = new SwapPoint[](simplifiedTokens.length*underlyingTokens.length);
        // for (uint i = 0; i<simplifiedTokens.length; i++) {
        //     for (uint j = 0; j<underlyingTokens.length; j++) {
        //         // Calculating amountIn and valueIn here to prevent stack too deep error
        //         uint amountIn = underlyingValues[j]>simplifiedTokenValues[i]?simplifiedTokenAmounts[i]:underlyingValues[j]*simplifiedTokenAmounts[i]/simplifiedTokenValues[i];
        //         uint valueIn = amountIn*simplifiedTokenValues[i]/simplifiedTokenAmounts[i];
        //         bestSwaps[(i*underlyingTokens.length)+j] = _findBestRoute(FindSwapsBetween(simplifiedTokens[i], underlyingTokens[j], amountIn, valueIn));
        //     }
        // }
        // bestSwaps = bestSwaps.sort();
        // bestSwaps = bestSwaps.findBestSwaps(simplifiedTokens, simplifiedTokenValues, underlyingTokens, underlyingValues);
        // _conductSwaps(bestSwaps);
        // (underlyingTokens, underlyingValues) = _getUnderlyingForConversions(conversions);
        // underlyingValues = _adjustValuesAfterSwap(underlyingTokens, underlyingValues);
        // uint[] memory amountsAndIds = _conductConversions(conversions, underlyingValues, minAmountsOut);
        // for (uint i = 0; i<underlyingTokens.length; i++) {
        //     IERC20(underlyingTokens[i]).safeTransfer(msg.sender, IERC20(underlyingTokens[i]).balanceOf(address(this)));
        // }
        // return amountsAndIds;
    }
}