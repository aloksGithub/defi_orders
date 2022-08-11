// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "./interfaces/IPoolInteractor.sol";
import "./libraries/Strings.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./Swappers/UniswapV2Swapper.sol";
import "hardhat/console.sol";

contract UniversalSwap is Ownable {
    using Address for address;
    using strings for *;

    address networkToken;
    UniswapV2Swapper uniswapSwapper;
    address[] uniswapV2Routers;
    address[] swappers;
    string[] protocols;
    uint fractionDenominator = 10000;
    mapping(string=>address) poolInteractors;

    constructor (string[] memory _protocols, address[] memory _poolInteractors, address _networkToken, address[] memory _uniswapV2Routers, address swapper) {
        for (uint i = 0; i<_protocols.length; i++) {
            poolInteractors[_protocols[i]] = _poolInteractors[i];
            protocols.push(_protocols[i]);
        }
        uniswapV2Routers = _uniswapV2Routers;
        networkToken = _networkToken;
        uniswapSwapper = UniswapV2Swapper(swapper);
    }
    
    function setRouters(address[] calldata _uniswapV2Routers) external onlyOwner {
        uniswapV2Routers = _uniswapV2Routers;
    }

    function setPoolInteractor(string[] calldata _protocols, address[] calldata _poolInteractors) external onlyOwner {
        for (uint i = 0; i<_protocols.length; i++) {
            poolInteractors[_protocols[i]] = _poolInteractors[i];
            protocols.push(_protocols[i]);
        }
    }

    function isSupported(address token) public view returns (bool) {
        if (_isSimpleToken(token)) return true;
        if (_isPoolToken(token)) return true;
        return false;
    }

    function _isSimpleToken(address token) internal view returns (bool) {
        for (uint i = 0;i<uniswapV2Routers.length; i++) {
            bool liquidable = uniswapSwapper.checkSwappable(token, networkToken, uniswapV2Routers[i]);
            if (liquidable) {
                return true;
            }
        }
        return false;
    }

    function _isPoolToken(address token) internal view returns (bool) {
        ERC20 tokenContract = ERC20(token);
        string memory name = tokenContract.name();
        for (uint x = 0; x<protocols.length; x++) {
            if (name.toSlice().startsWith(protocols[x].toSlice())) {
                return true;
            }
        }
        return false;
    }

    function _getUnderlying(address token) private view returns (address[] memory underlyingTokens) {
        ERC20 tokenContract = ERC20(token);
        address poolInteractor;
        IPoolInteractor poolInteractorContract;
        string memory name = tokenContract.name();
        for (uint x = 0; x<protocols.length; x++) {
            if (name.toSlice().startsWith(protocols[x].toSlice())) {
                poolInteractor = poolInteractors[protocols[x]];
            }
        }
        if (poolInteractor==address(0)) {
            if (_isSimpleToken(token)) {
                underlyingTokens = new address[](1);
                underlyingTokens[0] = token;
                return underlyingTokens;
            } else {
                revert("Unsupported Token");
            }
        } else {
            poolInteractorContract = IPoolInteractor(poolInteractor);
            underlyingTokens = poolInteractorContract.getUnderlyingTokens(token);
        }
    }

    function _burn(address token, uint amount) private returns (address[] memory underlyingTokens, uint[] memory underlyingTokenAmounts) {
        ERC20 tokenContract = ERC20(token);
        address poolInteractor;
        // IPoolInteractor poolInteractorContract;
        string memory name = tokenContract.name();
        for (uint x = 0; x<protocols.length; x++) {
            if (name.toSlice().startsWith(protocols[x].toSlice())) {
                poolInteractor = poolInteractors[protocols[x]];
            }
        }
        tokenContract.approve(poolInteractor, amount);
        (underlyingTokens, underlyingTokenAmounts) = IPoolInteractor(poolInteractor).burn(token, amount);
        // bytes memory returnData = poolInteractor.functionDelegateCall(abi.encodeWithSelector(poolInteractorContract.burn.selector, token, amount), "Failed to burn");
        // (underlyingTokens, underlyingTokenAmounts) = abi.decode(returnData, (address[], uint[]));
    }

    function _convertSimpleTokens(address token0, uint amount, address token1) private returns (uint) {
        if (token0==token1 || amount==0) return amount;
        for (uint i = 0;i<uniswapV2Routers.length; i++) {
            (bool success, bytes memory returnData) = address(uniswapSwapper).delegatecall(
                abi.encodeWithSelector(uniswapSwapper.swap.selector, token0, amount, token1, uniswapV2Routers[i])
            );
            if (success) {
                uint amountReturned = abi.decode(returnData, (uint));
                return amountReturned;
            }
        }
        revert("Failed to convert token");
    }

    function _convertAllToOne(address[] memory inputTokens, uint[] memory inputTokenAmounts, address toToken) private returns (uint) {
        uint amount = 0;
        for (uint i = 0; i<inputTokens.length; i++) {
            amount+=_convertSimpleTokens(inputTokens[i], inputTokenAmounts[i], toToken);
        }
        return amount;
    }

    function _simplifyInputTokens(address[] memory inputTokens, uint[] memory inputTokenAmounts) private returns (address[] memory, uint[] memory) {
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

    function _mint(address toMint, address[] memory underlyingTokens, uint[] memory underlyingAmounts) private returns (uint amountMinted) {
        if (toMint==underlyingTokens[0]) return underlyingAmounts[0];
        ERC20 tokenContract = ERC20(toMint);
        address poolInteractor;
        string memory name = tokenContract.name();
        for (uint x = 0; x<protocols.length; x++) {
            if (name.toSlice().startsWith(protocols[x].toSlice())) {
                poolInteractor = poolInteractors[protocols[x]];
            }
        }
        for (uint i = 0; i<underlyingTokens.length; i++) {
            (bool success, ) = underlyingTokens[i].call(
                abi.encodeWithSignature(
                    "approve(address,uint256)",
                    poolInteractor,
                    underlyingAmounts[i]
                )
            );
            if (!success) {
                revert("Failed to approve token");
            }
        }
        amountMinted = IPoolInteractor(poolInteractor).mint(toMint, underlyingTokens, underlyingAmounts);
    }

    function _getFinalToken(address finalToken, uint fraction, address startingToken, uint startingTokenAmount) private returns (uint) {
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

    function swap(address[] memory inputTokens, uint[] memory inputTokenAmounts, address outputToken) public returns (uint) {
        for (uint i = 0; i<inputTokenAmounts.length; i++) {
            IERC20(inputTokens[i]).transferFrom(msg.sender, address(this), inputTokenAmounts[i]);
        }
        (address[] memory simplifiedTokens, uint[] memory simplifiedTokenAmounts) = _simplifyInputTokens(inputTokens, inputTokenAmounts);
        uint commonTokenAmount = _convertAllToOne(simplifiedTokens, simplifiedTokenAmounts, networkToken);
        uint finalTokenObtained = _getFinalToken(outputToken, fractionDenominator, networkToken, commonTokenAmount);
        IERC20(outputToken).transfer(msg.sender, finalTokenObtained);
        return finalTokenObtained;
    }
}