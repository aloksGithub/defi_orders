// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "./interfaces/ILiquidator.sol";
import "./interfaces/IPoolInteractor.sol";
import "./libraries/Strings.sol";
import "hardhat/console.sol";

contract UniversalSwap {
    using Address for address;
    using strings for *;

    address networkToken;
    address[] liquidators;
    string[] protocols;
    uint fractionDenominator = 10000;
    mapping(string=>address) poolInteractors;

    function init(address[] calldata _liquidators, string[] calldata _protocols, address[] calldata _poolInteractors, address _networkToken) public {
        liquidators = _liquidators;
        for (uint i = 0; i<_protocols.length; i++) {
            poolInteractors[_protocols[i]] = _poolInteractors[i];
            protocols.push(_protocols[i]);
        }
        networkToken = _networkToken;
    }

    function isSupported(address token) public view returns (bool) {
        if (_isSimpleToken(token)) return true;
        ERC20 tokenContract = ERC20(token);
        string memory name = tokenContract.name();
        for (uint x = 0; x<protocols.length; x++) {
            if (name.toSlice().startsWith(protocols[x].toSlice())) {
                return true;
            }
        }
        return false;
    }

    function _isSimpleToken(address token) private view returns (bool) {
        for (uint i = 0;i<liquidators.length; i++) {
            ILiquidator liquidator = ILiquidator(liquidators[i]);
            bool liquidable = liquidator.checkLiquidable(token, networkToken);
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

    function _getUnderlying(address token) private view returns (address[] memory underlyingTokens, uint[] memory underlyingRatios) {
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
                underlyingRatios = new uint[](1);
                underlyingTokens[0] = token;
                underlyingRatios[0] = 1;
                return (underlyingTokens, underlyingRatios);
            } else {
                revert("Unsupported Token");
            }
        } else {
            poolInteractorContract = IPoolInteractor(poolInteractor);
            (underlyingTokens, underlyingRatios) = poolInteractorContract.getUnderlyingTokens(token);
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
        for (uint i = 0;i<liquidators.length; i++) {
            ILiquidator liquidator = ILiquidator(liquidators[i]);
            address router = liquidator.routerAddress();
            // bool liquidable = liquidator.checkWillLiquidate(token0, amount, token1);
            (bool success, bytes memory returnData) = liquidators[i].delegatecall(abi.encodeWithSelector(liquidator.liquidate.selector, token0, amount, token1, router));
            if (success) {
                uint amountReturned = abi.decode(returnData, (uint));
                return amountReturned;
            }
        }
        console.log(token0, token1, amount);
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
        (address[] memory underlyingTokens,) = _getUnderlying(finalToken);
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