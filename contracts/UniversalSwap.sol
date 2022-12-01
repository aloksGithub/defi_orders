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
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "./interfaces/IOracle.sol";
import "./interfaces/Venus/IVToken.sol";
import "./libraries/Conversions.sol";
import "./SwapHelper.sol";
import "hardhat/console.sol";

contract UniversalSwap is IUniversalSwap, Ownable {
    using Address for address;
    using UintArray for uint[];
    using AddressArray for address[];
    using SafeERC20 for IERC20;
    using Conversions for Conversion[];

    event NFTMinted(address manager, uint tokenId, address pool);
    event AssetsSent(address receiver, address[] tokens, address[] managers, uint[] amountsAndIds);

    address public networkToken;
    SwapHelper public helper;

    constructor (
        address[] memory _poolInteractors,
        address[] memory _nftPoolInteractors,
        address _networkToken,
        address[] memory _swappers,
        IOracle _oracle
    ) {
        networkToken = _networkToken;
        helper = new SwapHelper(_poolInteractors, _nftPoolInteractors, _networkToken, _swappers, _oracle);
        helper.transferOwnership(msg.sender);
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
            tokens = tokens.append(networkToken);
            amounts = amounts.append(ethSupplied);
        }
        return (tokens, amounts);
    }

    function _burn(address token, uint amount) internal returns (address[] memory underlyingTokens, uint[] memory underlyingTokenAmounts) {
        address poolInteractor = helper.getProtocol(token);
        bytes memory data = poolInteractor.functionDelegateCall(abi.encodeWithSelector(IPoolInteractor(poolInteractor).burn.selector, token, amount, poolInteractor));
        (underlyingTokens, underlyingTokenAmounts) = abi.decode(data, (address[], uint[]));
    }

    function _mint(address toMint, address[] memory underlyingTokens, uint[] memory underlyingAmounts, address receiver) internal returns (uint amountMinted) {
        if (toMint==underlyingTokens[0]) return underlyingAmounts[0];
        if (toMint==address(0)) {
            IWETH(payable(networkToken)).withdraw(underlyingAmounts[0]);
            payable(receiver).transfer(underlyingAmounts[0]);
            return underlyingAmounts[0];
        }
        address poolInteractor = helper.getProtocol(toMint);
        bytes memory returnData = poolInteractor.functionDelegateCall(
            abi.encodeWithSelector(IPoolInteractor(poolInteractor).mint.selector, toMint, underlyingTokens, underlyingAmounts, receiver, poolInteractor)
        );
        amountMinted = abi.decode(returnData, (uint));
    }

    function _simplifyInputTokens(address[] memory inputTokens, uint[] memory inputTokenAmounts) internal returns (address[] memory, uint[] memory) {
        bool allSimiplified = true;
        address[] memory updatedTokens = inputTokens;
        uint[] memory updatedTokenAmounts = inputTokenAmounts;
        for (uint i = 0; i<inputTokens.length; i++) {
            if (!helper.isSimpleToken(inputTokens[i])) {
                allSimiplified = false;
                (address[] memory newTokens, uint[] memory newTokenAmounts) = _burn(inputTokens[i], inputTokenAmounts[i]);
                // updatedTokens = updatedTokens.remove(i).concat(newTokens);
                // updatedTokenAmounts = updatedTokenAmounts.remove(i).concat(newTokenAmounts);
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

    function _collectAndBreak(address[] memory inputTokens, uint[] memory inputTokenAmounts, Asset[] memory inputNFTs) internal returns (address[] memory, uint[] memory) {
        for (uint i = 0; i<inputTokenAmounts.length; i++) {
            // uint balanceBefore = IERC20(inputTokens[i]).balanceOf(address(this));
            console.log(inputTokens[i], IERC20(inputTokens[i]).balanceOf(msg.sender), inputTokenAmounts[i]);
            IERC20(inputTokens[i]).safeTransferFrom(msg.sender, address(this), inputTokenAmounts[i]);
            // inputTokenAmounts[i] = IERC20(inputTokens[i]).balanceOf(address(this))-balanceBefore;
        }
        for (uint i = 0; i<inputNFTs.length; i++) {
            IERC721(inputNFTs[i].manager).transferFrom(msg.sender, address(this), inputNFTs[i].tokenId);
        }
        return _break(inputTokens, inputTokenAmounts, inputNFTs);
    }

    function _break(address[] memory inputTokens, uint[] memory inputTokenAmounts, Asset[] memory inputNFTs) internal returns (address[] memory, uint[] memory) {
        for (uint i = 0; i<inputNFTs.length; i++) {
            Asset memory nft = inputNFTs[i];
            address nftPoolInteractor = helper.getProtocol(nft.manager);
            if (nftPoolInteractor==address(0)) revert('UT');
            bytes memory returnData = nftPoolInteractor.functionDelegateCall(
                abi.encodeWithSelector(INFTPoolInteractor(nftPoolInteractor).burn.selector, nft)
            );
            (address[] memory nftTokens, uint[] memory nftTokenAmounts) = abi.decode(returnData, (address[], uint[]));
            inputTokens = inputTokens.concat(nftTokens);
            inputTokenAmounts = inputTokenAmounts.concat(nftTokenAmounts);
        }
        (address[] memory simplifiedTokens, uint[] memory simplifiedTokenAmounts) = _simplifyInputTokens(inputTokens, inputTokenAmounts);
        (simplifiedTokens, simplifiedTokenAmounts) = _addWETH(simplifiedTokens, simplifiedTokenAmounts);
        (simplifiedTokens, simplifiedTokenAmounts) = simplifiedTokens.shrink(simplifiedTokenAmounts);
        return (simplifiedTokens, simplifiedTokenAmounts);
    }

    function _conductERC20Conversion(Conversion memory conversion, address receiver) internal returns(uint) {
        if ((conversion.underlying[0]==conversion.desiredERC20 && conversion.underlying.length==1)) {
            uint balance = IERC20(conversion.underlying[0]).balanceOf(address(this));
            IERC20(conversion.underlying[0]).safeTransfer(receiver, balance*conversion.underlyingValues[0]/1e18);
            return balance*conversion.underlyingValues[0]/1e18;
        } else {
            uint[] memory inputTokenAmounts = new uint[](conversion.underlying.length);
            for (uint i = 0; i<conversion.underlying.length; i++) {
                uint balance = IERC20(conversion.underlying[i]).balanceOf(address(this));
                uint amountToUse = balance*conversion.underlyingValues[i]/1e18;
                inputTokenAmounts[i] = amountToUse;
            }
            return _mint(conversion.desiredERC20, conversion.underlying, inputTokenAmounts, receiver);
        }
    }
    
    function _conductERC721Conversion(Conversion memory conversion, address receiver) internal returns (uint) {
        Asset memory nft = conversion.desiredERC721;
        address nftPoolInteractor = helper.getProtocol(nft.manager);
        if (nftPoolInteractor==address(0)) revert('UT');
        uint[] memory inputTokenAmounts = new uint[](conversion.underlying.length);
        for (uint j = 0; j<conversion.underlying.length; j++) {
            uint balance = IERC20(conversion.underlying[j]).balanceOf(address(this));
            uint amountToUse = balance*conversion.underlyingValues[j]/1e18;
            inputTokenAmounts[j] = amountToUse;
        }
        bytes memory returnData = nftPoolInteractor.functionDelegateCall(
            abi.encodeWithSelector(INFTPoolInteractor(nftPoolInteractor).mint.selector, nft, conversion.underlying, inputTokenAmounts, receiver)
        );
        uint tokenId = abi.decode(returnData, (uint));
        emit NFTMinted(nft.manager, tokenId, nft.pool);
        return tokenId;
    }

    function _conductConversions(Conversion[] memory conversions, address[] memory outputTokens, uint[] memory minAmountsOut, address receiver) internal returns (uint[] memory amounts) {
        amounts = new uint[](conversions.length);
        uint amountsAdded;
        for (uint i = 0; i<conversions.length; i++) {
            if (conversions[i].desiredERC721.manager!=address(0)) {
                uint tokenId = _conductERC721Conversion(conversions[i], receiver);
                amounts[amountsAdded] = tokenId;
                amountsAdded+=1;
            } else {
                uint amountObtained = _conductERC20Conversion(conversions[i], receiver);
                if (outputTokens.exists(conversions[i].desiredERC20) && conversions[i].underlying.length!=0) {
                    amounts[amountsAdded] = amountObtained;
                    require(amountObtained>=minAmountsOut[amountsAdded]);
                    amountsAdded+=1;
                }
            }
        }
    }

    receive() external payable {}

    function _conductSwaps(SwapPoint[] memory swaps, address[] memory tokens, uint[] memory amounts) internal {
        for (uint i = 0; i<swaps.length; i++) {
            uint amount = swaps[i].amountIn*amounts[tokens.findFirst(swaps[i].tokenIn)]/1e18;
            swaps[i].swapper.functionDelegateCall(abi.encodeWithSelector(ISwapper(swaps[i].swapper).swap.selector, amount, swaps[i].path, swaps[i].swapper));
        }
    }

    function _swap(
        Provided memory provided,
        SwapPoint[] memory swaps,
        Conversion[] memory conversions,
        Desired memory desired,
        address receiver
    ) internal returns (uint[] memory) {
        if (swaps.length==0 || conversions.length==0) {
            (swaps, conversions) = preSwapComputation(provided, desired);
        }
        _conductSwaps(swaps, provided.tokens, provided.amounts);
        uint[] memory amountsAndIds = _conductConversions(conversions, desired.outputERC20s, desired.minAmountsOut, receiver);
        address[] memory managers = new address[](desired.outputERC721s.length);
        for (uint i = 0; i<managers.length; i++) {
            managers[i] = desired.outputERC721s[i].manager;
        }
        emit AssetsSent(msg.sender, desired.outputERC20s, managers, amountsAndIds);
        return amountsAndIds;
    }

    /// @inheritdoc IUniversalSwap
    function isSupported(address token) public view returns (bool) {
        if (helper.isSimpleToken(token)) return true;
        if (helper.getProtocol(token)!=address(0)) return true;
        return false;
    }

    /// @inheritdoc IUniversalSwap
    function estimateValue(Provided memory assets, address inTermsOf) external view returns (uint) {
        return helper.estimateValue(assets, inTermsOf);
    }

    /// @inheritdoc IUniversalSwap
    function getUnderlying(address[] memory tokens, uint[] memory amounts) external view returns (address[] memory, uint[] memory) {
        return helper.simplifyWithoutWrite(tokens, amounts, new Asset[](0));
    }

    /// @inheritdoc IUniversalSwap
    function preSwapComputation(
        Provided memory provided,
        Desired memory desired
    ) public view returns (SwapPoint[] memory, Conversion[] memory) {
        (provided.tokens, provided.amounts) = helper.simplifyWithoutWrite(provided.tokens, provided.amounts, provided.nfts);
        (uint[] memory inputTokenValues, uint totalValue) = helper.getTokenValues(provided.tokens, provided.amounts);

        Conversion[] memory conversions = helper.prepareConversions(desired.outputERC20s, desired.outputERC721s, desired.ratios, totalValue);
        (address[] memory underlyingTokens, uint[] memory underlyingValues) = conversions.getUnderlying();
        (underlyingTokens, underlyingValues) = underlyingTokens.shrink(underlyingValues);
        SwapPoint[] memory bestSwaps = helper.findMultipleSwaps(provided.tokens, provided.amounts, inputTokenValues, underlyingTokens, underlyingValues);
        conversions = conversions.normalizeRatios();
        return (bestSwaps, conversions);
    }

    /// @inheritdoc IUniversalSwap
    function swapAfterTransfer(
        Provided memory provided,
        SwapPoint[] memory swaps,
        Conversion[] memory conversions,
        Desired memory desired,
        address receiver
    ) payable external returns (uint[] memory) {
        (provided.tokens, provided.amounts) = _break(provided.tokens, provided.amounts, provided.nfts);
        return _swap(provided, swaps, conversions, desired, receiver);
    }

    /// @inheritdoc IUniversalSwap
    function swap(
        Provided memory provided,
        SwapPoint[] memory swaps,
        Conversion[] memory conversions,
        Desired memory desired,
        address receiver
    ) payable external returns (uint[] memory) {
        (provided.tokens, provided.amounts) = _collectAndBreak(provided.tokens, provided.amounts, provided.nfts);
        return _swap(provided, swaps, conversions, desired, receiver);
    }

    function getAmountsOut(
        Provided memory provided,
        Desired memory desired
    ) external view returns (uint[] memory amounts, SwapPoint[] memory swaps, Conversion[] memory conversions) {
        uint[] memory inputTokenValues;
        {
            (provided.tokens, provided.amounts) = helper.simplifyWithoutWrite(provided.tokens, provided.amounts, provided.nfts);
            uint totalValue;
            (inputTokenValues, totalValue) = helper.getTokenValues(provided.tokens, provided.amounts);

            conversions = helper.prepareConversions(desired.outputERC20s, desired.outputERC721s, desired.ratios, totalValue);
        }
        (address[] memory underlyingTokens, uint[] memory underlyingValues) = conversions.getUnderlying();
        (underlyingTokens, underlyingValues) = underlyingTokens.shrink(underlyingValues);
        swaps = helper.findMultipleSwaps(provided.tokens, provided.amounts, inputTokenValues, underlyingTokens, underlyingValues);
        uint[] memory expectedAmounts;
        (underlyingTokens, expectedAmounts) = helper.simulateSwaps(swaps, provided.tokens, provided.amounts);
        (underlyingTokens, expectedAmounts) = underlyingTokens.shrink(expectedAmounts);
        conversions = conversions.normalizeRatios();
        amounts = helper.simulateConversions(conversions, desired.outputERC20s, underlyingTokens, expectedAmounts);
        return (amounts, swaps, conversions);
    }
}