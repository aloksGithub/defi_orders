// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

import "@openzeppelin/contracts-upgradeable/token/ERC721/IERC721Upgradeable.sol";
import "../interfaces/IPoolInteractor.sol";
import "../interfaces/ISwapper.sol";
import "../interfaces/IUniversalSwap.sol";
import "../interfaces/IWETH.sol";
import "../libraries/UintArray.sol";
import "../libraries/AddressArray.sol";
import "../utils/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "../libraries/Conversions.sol";
import "../libraries/SaferERC20.sol";
import "./UniversalSwap.sol";
import "./ETHWithdrawer.sol";
import "hardhat/console.sol";

contract CoreLogic {
    using Address for address;
    using UintArray for uint256[];
    using AddressArray for address[];
    using SaferERC20 for IERC20;

    function _addWETH(
        address[] memory tokens,
        uint256[] memory amounts
    ) internal returns (address[] memory, uint256[] memory) {
        uint256 startingBalance = IERC20(IUniversalSwap(address(this)).networkToken()).balanceOf(address(this));
        if (msg.value > 0) {
            IWETH(payable(IUniversalSwap(address(this)).networkToken())).deposit{value: msg.value}();
        }
        if (address(this).balance > 0) {
            IWETH(payable(IUniversalSwap(address(this)).networkToken())).deposit{value: address(this).balance}();
        }
        uint256 ethSupplied = IERC20(IUniversalSwap(address(this)).networkToken()).balanceOf(address(this)) - startingBalance;
        if (ethSupplied > 0) {
            tokens = tokens.append(IUniversalSwap(address(this)).networkToken());
            amounts = amounts.append(ethSupplied);
        }
        uint addressZeroIndex = tokens.findFirst(address(0));
        if (addressZeroIndex != tokens.length) {
            tokens.remove(addressZeroIndex);
            amounts.remove(addressZeroIndex);
        }
        return (tokens, amounts);
    }

    function _isContract(address _addr) private view returns (bool isContract){
        uint32 size;
        assembly {
            size := extcodesize(_addr)
        }
        return (size > 0);
    }

    function _burn(
        address token,
        uint256 amount
    ) internal returns (address[] memory underlyingTokens, uint256[] memory underlyingTokenAmounts) {
        address poolInteractor = IUniversalSwap(address(this)).getProtocol(token);
        bytes memory data = poolInteractor.functionDelegateCall(
            abi.encodeWithSelector(IPoolInteractor(poolInteractor).burn.selector, token, amount, poolInteractor)
        );
        (underlyingTokens, underlyingTokenAmounts) = abi.decode(data, (address[], uint256[]));
    }

    function _mint(
        address toMint,
        address[] memory underlyingTokens,
        uint256[] memory underlyingAmounts,
        address receiver
    ) internal returns (uint256 amountMinted) {
        if (toMint == underlyingTokens[0]) return underlyingAmounts[0];
        if (toMint == address(0)) {
            IERC20 networkToken = IERC20(IUniversalSwap(address(this)).networkToken());
            ETHWithdrawer withdrawer = ETHWithdrawer(IUniversalSwap(address(this)).ethWithdrawer());
            networkToken.transfer(address(withdrawer), underlyingAmounts[0]);
            withdrawer.withdraw(address(networkToken), underlyingAmounts[0]);
            if (_isContract(receiver)) {
                (bool success,) = payable(address(receiver)).call{ value: underlyingAmounts[0] }("");
                require(success, "Transfer Failed");
            } else {
                payable(receiver).transfer(underlyingAmounts[0]);
            }
            return underlyingAmounts[0];
        }
        address poolInteractor = IUniversalSwap(address(this)).getProtocol(toMint);
        bytes memory returnData = poolInteractor.functionDelegateCall(
            abi.encodeWithSelector(
                IPoolInteractor(poolInteractor).mint.selector,
                toMint,
                underlyingTokens,
                underlyingAmounts,
                receiver,
                poolInteractor
            )
        );
        amountMinted = abi.decode(returnData, (uint256));
    }

    function _simplifyInputTokens(
        address[] memory inputTokens,
        uint256[] memory inputTokenAmounts
    ) internal returns (address[] memory, uint256[] memory) {
        bool allSimiplified = true;
        address[] memory updatedTokens = inputTokens;
        uint256[] memory updatedTokenAmounts = inputTokenAmounts;
        for (uint256 i = 0; i < inputTokens.length; i++) {
            if (!IUniversalSwap(address(this)).isSimpleToken(inputTokens[i])) {
                allSimiplified = false;
                (address[] memory newTokens, uint256[] memory newTokenAmounts) = _burn(
                    inputTokens[i],
                    inputTokenAmounts[i]
                );
                updatedTokens[i] = newTokens[0];
                updatedTokenAmounts[i] = newTokenAmounts[0];
                address[] memory tempTokens = new address[](updatedTokens.length + newTokens.length - 1);
                uint256[] memory tempTokenAmounts = new uint256[](
                    updatedTokenAmounts.length + newTokenAmounts.length - 1
                );
                uint256 j = 0;
                while (j < updatedTokens.length) {
                    tempTokens[j] = updatedTokens[j];
                    tempTokenAmounts[j] = updatedTokenAmounts[j];
                    j++;
                }
                uint256 k = 0;
                while (k < newTokens.length - 1) {
                    tempTokens[j + k] = newTokens[k + 1];
                    tempTokenAmounts[j + k] = newTokenAmounts[k + 1];
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

    function collectAndBreak(
        address[] memory inputTokens,
        uint256[] memory inputTokenAmounts,
        Asset[] memory inputNFTs
    ) public payable returns (address[] memory, uint256[] memory) {
        for (uint256 i = 0; i < inputTokenAmounts.length; i++) {
            if (inputTokens[i] == address(0)) continue;
            IERC20(inputTokens[i]).safeTransferFrom(msg.sender, address(this), inputTokenAmounts[i]);
        }
        for (uint256 i = 0; i < inputNFTs.length; i++) {
            IERC721Upgradeable(inputNFTs[i].manager).transferFrom(msg.sender, address(this), inputNFTs[i].tokenId);
        }
        return breakAssets(inputTokens, inputTokenAmounts, inputNFTs);
    }

    function breakAssets(
        address[] memory inputTokens,
        uint256[] memory inputTokenAmounts,
        Asset[] memory inputNFTs
    ) public payable returns (address[] memory, uint256[] memory) {
        for (uint256 i = 0; i < inputNFTs.length; i++) {
            Asset memory nft = inputNFTs[i];
            address nftPoolInteractor = IUniversalSwap(address(this)).getProtocol(nft.manager);
            if (nftPoolInteractor == address(0)) revert("UT");
            bytes memory returnData = nftPoolInteractor.functionDelegateCall(
                abi.encodeWithSelector(INFTPoolInteractor(nftPoolInteractor).burn.selector, nft)
            );
            (address[] memory nftTokens, uint256[] memory nftTokenAmounts) = abi.decode(
                returnData,
                (address[], uint256[])
            );
            inputTokens = inputTokens.concat(nftTokens);
            inputTokenAmounts = inputTokenAmounts.concat(nftTokenAmounts);
        }
        (address[] memory simplifiedTokens, uint256[] memory simplifiedTokenAmounts) = _simplifyInputTokens(
            inputTokens,
            inputTokenAmounts
        );
        (simplifiedTokens, simplifiedTokenAmounts) = _addWETH(simplifiedTokens, simplifiedTokenAmounts);
        (simplifiedTokens, simplifiedTokenAmounts) = simplifiedTokens.shrink(simplifiedTokenAmounts);
        simplifiedTokenAmounts = _collectFee(simplifiedTokens, simplifiedTokenAmounts);
        return (simplifiedTokens, simplifiedTokenAmounts);
    }

    function _collectFee(address[] memory tokens, uint[] memory amounts) internal returns (uint[] memory) {
        for (uint i = 0; i<tokens.length; i++) {
            IERC20(tokens[i]).safeTransfer(
                IUniversalSwap(address(this)).treasury(),
                amounts[i]*IUniversalSwap(address(this)).devFee()/100000
            );
            amounts[i]-=amounts[i]*IUniversalSwap(address(this)).devFee()/100000;
        }
        return amounts;
    }

    function _conductERC20Conversion(
        Conversion memory conversion,
        address receiver,
        address[] memory tokensAvailable,
        uint256[] memory amountsAvailable
    ) internal returns (uint256) {
        if ((conversion.underlying[0] == conversion.desiredERC20 && conversion.underlying.length == 1)) {
            uint256 tokenToUseIndex = tokensAvailable.findFirst(conversion.underlying[0]);
            uint256 balance = amountsAvailable[tokenToUseIndex];
            uint256 amountToUse = (balance * conversion.underlyingValues[0]) / 1e18;
            IERC20(conversion.underlying[0]).safeTransfer(receiver, amountToUse);
            amountsAvailable[tokenToUseIndex] -= amountToUse;
            return amountToUse;
        } else {
            uint256[] memory inputTokenAmounts = new uint256[](conversion.underlying.length);
            for (uint256 i = 0; i < conversion.underlying.length; i++) {
                uint256 tokenToUseIndex = tokensAvailable.findFirst(conversion.underlying[i]);
                uint256 balance = amountsAvailable[tokenToUseIndex];
                uint256 amountToUse = (balance * conversion.underlyingValues[i]) / 1e18;
                amountsAvailable[tokenToUseIndex] -= amountToUse;
                inputTokenAmounts[i] = amountToUse;
            }
            return _mint(conversion.desiredERC20, conversion.underlying, inputTokenAmounts, receiver);
        }
    }

    function _conductERC721Conversion(
        Conversion memory conversion,
        address receiver,
        address[] memory tokensAvailable,
        uint256[] memory amountsAvailable
    ) internal returns (uint256) {
        Asset memory nft = conversion.desiredERC721;
        address nftPoolInteractor = IUniversalSwap(address(this)).getProtocol(nft.manager);
        if (nftPoolInteractor == address(0)) revert("UT");
        uint256[] memory inputTokenAmounts = new uint256[](conversion.underlying.length);
        for (uint256 j = 0; j < conversion.underlying.length; j++) {
            uint256 tokenToUseIndex = tokensAvailable.findFirst(conversion.underlying[j]);
            uint256 balance = amountsAvailable[tokenToUseIndex];
            uint256 amountToUse = (balance * conversion.underlyingValues[j]) / 1e18;
            amountsAvailable[tokenToUseIndex] -= amountToUse;
            // uint balance = IERC20(conversion.underlying[j]).balanceOf(address(this));
            // uint amountToUse = balance*conversion.underlyingValues[j]/1e18;
            inputTokenAmounts[j] = amountToUse;
        }
        bytes memory returnData = nftPoolInteractor.functionDelegateCall(
            abi.encodeWithSelector(
                INFTPoolInteractor(nftPoolInteractor).mint.selector,
                nft,
                conversion.underlying,
                inputTokenAmounts,
                receiver
            )
        );
        uint256 tokenId = abi.decode(returnData, (uint256));
        return tokenId;
    }

    function _conductConversions(
        Conversion[] memory conversions,
        address[] memory outputTokens,
        uint256[] memory minAmountsOut,
        address receiver,
        address[] memory tokensAvailable,
        uint256[] memory amountsAvailable
    ) internal returns (uint256[] memory amounts) {
        amounts = new uint256[](conversions.length);
        uint256 amountsAdded;
        for (uint256 i = 0; i < conversions.length; i++) {
            if (conversions[i].desiredERC721.manager != address(0)) {
                uint256 tokenId = _conductERC721Conversion(conversions[i], receiver, tokensAvailable, amountsAvailable);
                amounts[amountsAdded] = tokenId;
                amountsAdded += 1;
            } else {
                uint256 amountObtained = _conductERC20Conversion(
                    conversions[i],
                    receiver,
                    tokensAvailable,
                    amountsAvailable
                );
                if (outputTokens.exists(conversions[i].desiredERC20) && conversions[i].underlying.length != 0) {
                    amounts[amountsAdded] = amountObtained;
                    require(amountObtained >= minAmountsOut[amountsAdded], "3");
                    amountsAdded += 1;
                }
            }
        }
    }

    function _conductSwaps(
        SwapPoint[] memory swaps,
        address[] memory tokens,
        uint256[] memory amounts
    ) internal returns (address[] memory tokensObtained, uint256[] memory amountsObtained) {
        tokensObtained = new address[](swaps.length);
        amountsObtained = new uint256[](swaps.length);
        for (uint256 i = 0; i < swaps.length; i++) {
            uint256 amount = (swaps[i].amountIn * amounts[tokens.findFirst(swaps[i].tokenIn)]) / 1e18;
            for (uint256 j = 0; j < swaps[i].swappers.length; j++) {
                bytes memory returnData = swaps[i].swappers[j].functionDelegateCall(
                    abi.encodeWithSelector(
                        ISwapper(swaps[i].swappers[j]).swap.selector,
                        amount,
                        swaps[i].paths[j],
                        swaps[i].swappers[j]
                    )
                );
                amount = abi.decode(returnData, (uint256));
            }
            tokensObtained[i] = swaps[i].tokenOut;
            amountsObtained[i] = amount;
        }
        (tokensObtained, amountsObtained) = tokensObtained.shrink(amountsObtained);
    }

    function swap(
        Provided memory provided,
        SwapPoint[] memory swaps,
        Conversion[] memory conversions,
        Desired memory desired,
        address receiver
    ) public payable returns (uint256[] memory) {
        if (swaps.length == 0 || conversions.length == 0) {
            (swaps, conversions) = IUniversalSwap(address(this)).preSwapCalculateSwaps(provided, desired);
        }
        require(provided.tokens.length > 0, "4");
        (address[] memory tokensAfterSwap, uint256[] memory amountsAfterSwap) = _conductSwaps(
            swaps,
            provided.tokens,
            provided.amounts
        );
        uint256[] memory amountsAndIds = _conductConversions(
            conversions,
            desired.outputERC20s,
            desired.minAmountsOut,
            receiver,
            tokensAfterSwap,
            amountsAfterSwap
        );
        address[] memory managers = new address[](desired.outputERC721s.length);
        for (uint256 i = 0; i < managers.length; i++) {
            managers[i] = desired.outputERC721s[i].manager;
        }
        return amountsAndIds;
    }
}