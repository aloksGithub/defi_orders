// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "./interfaces/IPoolInteractor.sol";
import "./interfaces/ISwapper.sol";
import "./interfaces/IUniversalSwap.sol";
import "./libraries/Strings.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "hardhat/console.sol";

contract UniversalSwap is IUniversalSwap, Ownable {
    using Address for address;
    using strings for *;
    using SafeERC20 for IERC20;

    event NFTMinted(address manager, uint tokenId);

    address public networkToken;
    address[] swappers;
    string[] protocols;
    uint fractionDenominator = 10000;
    address[] poolInteractors;
    address[] nftPoolInteractors;

    constructor (address[] memory _poolInteractors, address[] memory _nftPoolInteractors, address _networkToken, address[] memory _swappers) {
        poolInteractors = _poolInteractors;
        nftPoolInteractors = _nftPoolInteractors;
        swappers = _swappers;
        networkToken = _networkToken;
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

    function _isSimpleToken(address token) internal returns (bool) {
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
        return address(0);
    }

    function _getUnderlying(address token) internal returns (address[] memory underlyingTokens) {
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
        for (uint i = 0;i<swappers.length; i++) {
            (bool success, bytes memory returnData) = swappers[i].delegatecall(
                abi.encodeWithSelector(ISwapper(swappers[i]).swap.selector, token0, amount, token1, swappers[i])
            );
            if (success) {
                uint amountReturned = abi.decode(returnData, (uint));
                return amountReturned;
            }
        }
        revert("Failed to convert token");
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
        address[] memory underlyingTokens = _getUnderlying(finalToken);
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
        uint commonTokenAmount = _convertAllToOne(simplifiedTokens, simplifiedTokenAmounts, networkToken);
        tokensObtained = new uint[](outputTokens.length);
        uint totalFraction = 0;
        for (uint i = 0; i<outputTokens.length; i++) {
            totalFraction+=outputRatios[i];
        }
        for (uint i = 0; i<outputTokens.length; i++) {
            uint tokensUsed = outputRatios[i]*commonTokenAmount/totalFraction;
            tokensObtained[i] = _getFinalToken(outputTokens[i], fractionDenominator, networkToken, tokensUsed);
        }
    }

    /// @inheritdoc IUniversalSwap
    function swap(address[] memory inputTokens, uint[] memory inputTokenAmounts, address[] memory outputTokens, uint[] memory outputRatios, uint[] memory minAmountsOut) public returns (uint[] memory tokensObtained) {
        for (uint i = 0; i<inputTokenAmounts.length; i++) {
            IERC20(inputTokens[i]).safeTransferFrom(msg.sender, address(this), inputTokenAmounts[i]);
        }
        tokensObtained = _convert(inputTokens, inputTokenAmounts, outputTokens, outputRatios);
        for (uint i = 0; i<outputTokens.length; i++) {
            IERC20(outputTokens[i]).safeTransfer(msg.sender, tokensObtained[i]);
            require(minAmountsOut[i]<=tokensObtained[i], "Too much slippage");
        }
    }

    /// @inheritdoc IUniversalSwap
    function swap(address[] memory inputTokens, uint[] memory inputTokenAmounts, address[] memory outputTokens, uint[] memory minAmountsOut) public returns (uint[] memory tokensObtained) {
        uint[] memory ratios = new uint[](outputTokens.length);
        for (uint j = 0; j<outputTokens.length; j++) {
            ratios[j] = 1;
        }
        for (uint i = 0; i<inputTokenAmounts.length; i++) {
            IERC20(inputTokens[i]).safeTransferFrom(msg.sender, address(this), inputTokenAmounts[i]);
        }
        tokensObtained = _convert(inputTokens, inputTokenAmounts, outputTokens, ratios);
        for (uint i = 0; i<outputTokens.length; i++) {
            IERC20(outputTokens[i]).safeTransfer(msg.sender, tokensObtained[i]);
            require(minAmountsOut[i]<=tokensObtained[i], "Too much slippage");
        }
    }

    /// @inheritdoc IUniversalSwap
    function swap(address[] memory inputTokens, uint[] memory inputTokenAmounts, address outputToken, uint minAmountOut) public returns (uint finalTokenObtained) {
        for (uint i = 0; i<inputTokenAmounts.length; i++) {
            IERC20(inputTokens[i]).safeTransferFrom(msg.sender, address(this), inputTokenAmounts[i]);
        }
        (address[] memory simplifiedTokens, uint[] memory simplifiedTokenAmounts) = _simplifyInputTokens(inputTokens, inputTokenAmounts);
        uint commonTokenAmount = _convertAllToOne(simplifiedTokens, simplifiedTokenAmounts, networkToken);
        finalTokenObtained = _getFinalToken(outputToken, fractionDenominator, networkToken, commonTokenAmount);
        IERC20(outputToken).safeTransfer(msg.sender, finalTokenObtained);
        require(finalTokenObtained>=minAmountOut, "Too much slippage");
        return finalTokenObtained;
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
                if (!_checkArraysMatch(underlyingTokens, inputTokens)) {
                    uint[] memory ratios = new uint[](underlyingTokens.length);
                    for (uint j = 0; j<underlyingTokens.length; j++) {
                        ratios[j] = 1;
                    }
                    inputTokenAmounts = _convert(inputTokens, inputTokenAmounts, underlyingTokens, ratios);
                    inputTokens = underlyingTokens;
                }
                for (uint j = 0; j<inputTokens.length; j++) {
                    IERC20(inputTokens[j]).safeTransfer(nftPoolInteractors[i], inputTokenAmounts[j]);
                }
                uint tokenId = INFTPoolInteractor(nftPoolInteractors[i]).mint(nft, inputTokens, inputTokenAmounts);
                IERC721(nft.manager).transferFrom(address(this), msg.sender, tokenId);
                emit NFTMinted(nft.manager, tokenId);
                return tokenId;
            }
        }
        revert("Failed to convert");
    }

    /// @inheritdoc IUniversalSwap
    function swapNFT(Asset memory nft, address outputToken) external returns (uint) {
        for (uint i = 0; i<nftPoolInteractors.length; i++) {
            if (INFTPoolInteractor(nftPoolInteractors[i]).testSupported(nft.manager)) {  
                IERC721(nft.manager).transferFrom(msg.sender, nftPoolInteractors[i], nft.tokenId);              
                (address[] memory inputTokens, uint[] memory inputTokenAmounts) = INFTPoolInteractor(nftPoolInteractors[i]).burn(nft);
                (address[] memory simplifiedTokens, uint[] memory simplifiedTokenAmounts) = _simplifyInputTokens(inputTokens, inputTokenAmounts);
                uint commonTokenAmount = _convertAllToOne(simplifiedTokens, simplifiedTokenAmounts, networkToken);
                uint finalTokenObtained = _getFinalToken(outputToken, fractionDenominator, networkToken, commonTokenAmount);
                IERC20(outputToken).safeTransfer(msg.sender, finalTokenObtained);
                return finalTokenObtained;
            }
        }
        revert("Failed to convert");
    }
}