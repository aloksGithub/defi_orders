// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "./interfaces/IPoolInteractor.sol";
import "./interfaces/ISwapper.sol";
import "./interfaces/IUniversalSwap.sol";
import "./interfaces/IWETH.sol";
import "./libraries/Strings.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "./interfaces/IOracle.sol";
import "hardhat/console.sol";

contract UniversalSwap is IUniversalSwap, Ownable {
    using Address for address;
    using strings for *;
    using SafeERC20 for IERC20;

    event NFTMinted(address manager, uint tokenId);

    address public networkToken;
    address[] public swappers;
    uint fractionDenominator = 10000;
    address[] public poolInteractors;
    address[] public nftPoolInteractors;
    IOracle public oracle;

    constructor (address[] memory _poolInteractors, address[] memory _nftPoolInteractors, address _networkToken, address[] memory _swappers, IOracle _oracle) {
        poolInteractors = _poolInteractors;
        nftPoolInteractors = _nftPoolInteractors;
        swappers = _swappers;
        networkToken = _networkToken;
        oracle = _oracle;
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

    function getUnderlying(address token) public returns (address[] memory underlyingTokens) {
        address poolInteractor = _getProtocol(token);
        if (poolInteractor==address(0)) {
            if (_isSimpleToken(token)) {
                underlyingTokens = new address[](1);
                underlyingTokens[0] = token;
                return underlyingTokens;
            } else {
                revert("Unsupported Token");
            }
        } else {
            IPoolInteractor poolInteractorContract = IPoolInteractor(poolInteractor);
            underlyingTokens = poolInteractorContract.getUnderlyingTokens(token);
        }
    }

    function _burn(address token, uint amount) internal returns (address[] memory underlyingTokens, uint[] memory underlyingTokenAmounts) {
        IERC20 tokenContract = IERC20(token);
        address poolInteractor = _getProtocol(token);
        tokenContract.safeApprove(poolInteractor, amount);
        (underlyingTokens, underlyingTokenAmounts) = IPoolInteractor(poolInteractor).burn(token, amount);
    }

    function _convertSimpleTokens(address token0, uint amount, address token1) internal returns (uint) {
        if (token0==token1 || amount==0) return amount;
        address bestSwapper;
        uint maxAmountOut;
        for (uint i = 0;i<swappers.length; i++) {
            uint amountOut = ISwapper(swappers[i]).getAmountOut(token0, amount, token1);
            if (amountOut>maxAmountOut) {
                maxAmountOut = amountOut;
                bestSwapper = swappers[i];
            }
        }
        if (bestSwapper==address(0) || maxAmountOut==0) return 0;
        bytes memory returnData = bestSwapper.functionDelegateCall(abi.encodeWithSelector(ISwapper(bestSwapper).swap.selector, token0, amount, token1, bestSwapper));
        (uint amountReturned) = abi.decode(returnData, (uint));
        return amountReturned;
    }

    function _convertAllToOne(address[] memory inputTokens, uint[] memory inputTokenAmounts, address toToken) internal returns (uint) {
        uint amount = 0;
        for (uint i = 0; i<inputTokens.length; i++) {
            amount+=_convertSimpleTokens(inputTokens[i], inputTokenAmounts[i], toToken);
        }
        return amount;
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
            return (inputTokens, inputTokenAmounts);
        } else {
            return _simplifyInputTokens(updatedTokens, updatedTokenAmounts);
        }
    }

    function _mint(address toMint, address[] memory underlyingTokens, uint[] memory underlyingAmounts) internal returns (uint amountMinted) {
        if (toMint==underlyingTokens[0]) return underlyingAmounts[0];
        address poolInteractor = _getProtocol(toMint);
        for (uint i = 0; i<underlyingTokens.length; i++) {
            IERC20(underlyingTokens[i]).safeApprove(poolInteractor, underlyingAmounts[i]);
        }
        amountMinted = IPoolInteractor(poolInteractor).mint(toMint, underlyingTokens, underlyingAmounts);
    }

    function _getFinalToken(address finalToken, uint fraction, address startingToken, uint startingTokenAmount) internal returns (uint) {
        address[] memory underlyingTokens = getUnderlying(finalToken);
        uint[] memory underlyingObtained = new uint[](underlyingTokens.length);
        for (uint i = 0; i<underlyingTokens.length; i++) {
            uint obtained;
            if (_isSimpleToken(underlyingTokens[i])) {
                obtained = _convertSimpleTokens(startingToken, fraction*startingTokenAmount/(fractionDenominator*underlyingTokens.length), underlyingTokens[i]);
            } else {
                obtained = _getFinalToken(underlyingTokens[i], fraction/(underlyingTokens.length*fractionDenominator), startingToken, startingTokenAmount);
            }
            underlyingObtained[i] = obtained;
        }
        uint minted = _mint(finalToken, underlyingTokens, underlyingObtained);
        return minted;
    }

    function _convert(address[] memory inputTokens, uint[] memory inputTokenAmounts, address[] memory outputTokens, uint[] memory outputRatios) internal returns (uint[] memory tokensObtained) {
        (address[] memory simplifiedTokens, uint[] memory simplifiedTokenAmounts) = _simplifyInputTokens(inputTokens, inputTokenAmounts);
        uint ethSupplied = _getWETH();
        if (ethSupplied>0) {
            bool found = false;
            for (uint i = 0; i<simplifiedTokens.length; i++) {
                if (simplifiedTokens[i]==networkToken) {
                    simplifiedTokenAmounts[i]+=ethSupplied;
                    found = true;
                    break;
                }
            }
            if (!found) {
                address[] memory newTokens = new address[](simplifiedTokens.length+1);
                newTokens[0] = networkToken;
                uint[] memory newAmounts = new uint[](simplifiedTokenAmounts.length+1);
                newAmounts[0] = ethSupplied;
                for (uint i = 0; i<simplifiedTokens.length; i++) {
                    newTokens[i+1] = simplifiedTokens[i];
                    newAmounts[i+1] = simplifiedTokenAmounts[i];
                }
                simplifiedTokenAmounts = newAmounts;
                simplifiedTokens = newTokens;
            }
        }
        // commonTokenAmount+=_convertAllToOne(simplifiedTokens, simplifiedTokenAmounts, networkToken);
        tokensObtained = new uint[](outputTokens.length);
        uint totalFraction = 0;
        for (uint i = 0; i<outputTokens.length; i++) {
            totalFraction+=outputRatios[i];
        }
        for (uint j = 0; j<simplifiedTokens.length; j++) {
            for (uint i = 0; i<outputTokens.length; i++) {
                uint tokensUsed = outputRatios[i]*simplifiedTokenAmounts[j]/totalFraction;
                tokensObtained[i]+=_getFinalToken(outputTokens[i], fractionDenominator, simplifiedTokens[j], tokensUsed);
            }
        }
        // for (uint i = 0; i<outputTokens.length; i++) {
        //     uint tokensUsed = outputRatios[i]*commonTokenAmount/totalFraction;
        //     tokensObtained[i] = _getFinalToken(outputTokens[i], fractionDenominator, networkToken, tokensUsed);
        // }
    }

    /// @inheritdoc IUniversalSwap
    function swap(
        address[] memory inputTokens,
        uint[] memory inputTokenAmounts,
        address[] memory outputTokens,
        uint[] memory outputRatios,
        uint[] memory minAmountsOut
    ) payable public returns (uint[] memory tokensObtained) {
        for (uint i = 0; i<inputTokenAmounts.length; i++) {
            uint balanceBefore = IERC20(inputTokens[i]).balanceOf(address(this));
            IERC20(inputTokens[i]).safeTransferFrom(msg.sender, address(this), inputTokenAmounts[i]);
            inputTokenAmounts[i] = IERC20(inputTokens[i]).balanceOf(address(this))-balanceBefore;
        }
        tokensObtained = _convert(inputTokens, inputTokenAmounts, outputTokens, outputRatios);
        for (uint i = 0; i<outputTokens.length; i++) {
            IERC20(outputTokens[i]).safeTransfer(msg.sender, tokensObtained[i]);
            require(minAmountsOut[i]<=tokensObtained[i], "slippage");
        }
    }

    function _checkArraysMatch(address[] memory array1, address[] memory array2) internal pure returns (bool) {
        if (array1.length!=array2.length) return false;
        for (uint i = 0; i<array1.length; i++) {
            bool matchFound = false;
            for (uint j = 0; j<array2.length; j++) {
                if (array1[i]==array2[j]) {
                    matchFound = true;
                    break;
                }
            }
            if (!matchFound) {
                return false;
            }
        }
        return true;
    }

    /// @inheritdoc IUniversalSwap
    function swapForNFT(address[] memory inputTokens, uint[] memory inputTokenAmounts, Asset memory nft) public returns (uint) {
        for (uint i = 0; i<inputTokenAmounts.length; i++) {
            IERC20(inputTokens[i]).safeTransferFrom(msg.sender, address(this), inputTokenAmounts[i]);
        }
        for (uint i = 0; i<nftPoolInteractors.length; i++) {
            if (INFTPoolInteractor(nftPoolInteractors[i]).testSupported(nft.manager)) {
                INFTPoolInteractor poolInteractor = INFTPoolInteractor(nftPoolInteractors[i]);
                address[] memory underlyingTokens = poolInteractor.getUnderlyingTokens(nft.pool);
                uint[] memory ratios = new uint[](underlyingTokens.length);
                {(int24 tick0, int24 tick1,,) = abi.decode(nft.data, (int24, int24, uint, uint));
                (uint ratio0, uint ratio1) = poolInteractor.getRatio(nft.pool, tick0, tick1);
                ratios[0] = ratio0;
                ratios[1] = ratio1;}
                inputTokenAmounts = _convert(inputTokens, inputTokenAmounts, underlyingTokens, ratios);
                (bool success, bytes memory returnData) = nftPoolInteractors[i].delegatecall(
                    abi.encodeWithSelector(INFTPoolInteractor(nftPoolInteractors[i]).mint.selector, nft, underlyingTokens, inputTokenAmounts)
                );
                if (success) {
                    uint tokenId = abi.decode(returnData, (uint));
                    emit NFTMinted(nft.manager, tokenId);
                    return tokenId;
                } else {
                    revert("Failed to get NFT");
                }
            }
        }
        revert("Failed to convert");
    }

    /// @inheritdoc IUniversalSwap
    function swapNFT(Asset memory nft, address outputToken, uint minAmount) public returns (uint) {
        for (uint i = 0; i<nftPoolInteractors.length; i++) {
            if (INFTPoolInteractor(nftPoolInteractors[i]).testSupported(nft.manager)) {
                IERC721(nft.manager).transferFrom(msg.sender, address(this), nft.tokenId);
                bytes memory returnData = nftPoolInteractors[i].functionDelegateCall(
                    abi.encodeWithSelector(INFTPoolInteractor(nftPoolInteractors[i]).burn.selector, nft)
                );
                (address[] memory inputTokens, uint[] memory inputTokenAmounts) = abi.decode(returnData, (address[], uint[]));
                (address[] memory simplifiedTokens, uint[] memory simplifiedTokenAmounts) = _simplifyInputTokens(inputTokens, inputTokenAmounts);
                uint commonTokenAmount = _convertAllToOne(simplifiedTokens, simplifiedTokenAmounts, networkToken);
                uint finalTokenObtained = _getFinalToken(outputToken, fractionDenominator, networkToken, commonTokenAmount);
                IERC20(outputToken).safeTransfer(msg.sender, finalTokenObtained);
                require(finalTokenObtained>minAmount, "slippage");
                return finalTokenObtained;
            }
        }
        revert("Failed to convert");
    }

    function swapERC20(
        address[] memory inputTokens,
        uint[] memory inputTokenAmounts,
        Asset[] memory nfts,
        address outputToken,
        uint minAmountOut
    ) payable external returns (uint tokenObtained) {
        tokenObtained = 0;
        for (uint i = 0; i<nfts.length; i++) {
            tokenObtained+=swapNFT(nfts[i], outputToken, 0);
        }
        address[] memory wanted = new address[](1);
        uint[] memory ratios = new uint[](1);
        uint[] memory slippage = new uint[](1);
        wanted[0] = outputToken;
        ratios[0] = 1;
        slippage[0] = minAmountOut;
        uint[] memory temp = swap(inputTokens, inputTokenAmounts, wanted, ratios, slippage);
        tokenObtained+=temp[0];
    }

    function swapERC721(
        address[] memory inputTokens,
        uint[] memory inputTokenAmounts,
        Asset[] memory nfts,
        Asset memory nftToGet
    ) payable external returns (uint) {
        uint networkTokenObtained = 0;
        for (uint i = 0; i<nfts.length; i++) {
            networkTokenObtained+=swapNFT(nfts[i], networkToken, 0);
        }
        bool found = false;
        for (uint i = 0; i<inputTokens.length; i++) {
            if (inputTokens[i]==networkToken) {
                inputTokenAmounts[i]+=networkTokenObtained;
                found = true;
            }
        }
        if (!found) {
            address[] memory updatedTokens = new address[](inputTokens.length+1);
            uint[] memory updatedAmounts = new uint[](inputTokens.length+1);
            updatedTokens[0] = networkToken;
            updatedAmounts[0] = networkTokenObtained;
            for (uint i = 0; i<inputTokens.length; i++) {
                updatedTokens[i+1] = inputTokens[i];
                updatedAmounts[i+1] = inputTokenAmounts[i];
            }
            inputTokens = updatedTokens;
            inputTokenAmounts = updatedAmounts;
        }
        return swapForNFT(inputTokens, inputTokenAmounts, nftToGet);
    }
}