// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

import "../interfaces/IPoolInteractor.sol";
import "../interfaces/IUniversalSwap.sol";
import "../libraries/UintArray.sol";
import "../libraries/AddressArray.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "../libraries/Conversions.sol";
import "hardhat/console.sol";

contract ConversionHelper {
    using UintArray for uint256[];
    using AddressArray for address[];
    using Conversions for Conversion[];

    IUniversalSwap public universalSwap;

    constructor(IUniversalSwap _universalSwap) {
        universalSwap = _universalSwap;
    }

    ///-------------Public view functions-------------
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

    ///-------------Internal logic-------------
    function _getConversionsERC20(address desired, uint256 valueAllocated) internal view returns (Conversion[] memory) {
        (address[] memory underlying, uint256[] memory ratios) = _getUnderlyingERC20(desired);
        ratios = ratios.scale(valueAllocated);
        Asset memory placeholder;
        Conversion[] memory conversions;
        for (uint256 i = 0; i < underlying.length; i++) {
            if (!universalSwap.isSimpleToken(underlying[i])) {
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
        (address[] memory underlying, uint256[] memory ratios) = _getUnderlyingERC721(nft);
        ratios = ratios.scale(valueAllocated);
        Conversion[] memory conversions;
        Conversion memory finalConversion = Conversion(nft, address(0), valueAllocated, underlying, ratios);
        conversions = conversions.append(finalConversion);
        return conversions;
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
            address poolInteractor = universalSwap.getProtocol(conversion.desiredERC20);
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
        address poolInteractor = universalSwap.getProtocol(conversion.desiredERC721.manager);
        uint256 liquidityMinted = INFTPoolInteractor(poolInteractor).simulateMint(
            conversion.desiredERC721,
            conversion.underlying,
            amounts
        );
        return (liquidityMinted, inputTokenAmounts);
    }

    function _getUnderlyingERC20(
        address token
    ) internal view returns (address[] memory underlyingTokens, uint256[] memory ratios) {
        if (universalSwap.isSimpleToken(token)) {
            underlyingTokens = new address[](1);
            underlyingTokens[0] = token != address(0) ? token : universalSwap.networkToken();
            ratios = new uint256[](1);
            ratios[0] = 1;
        } else {
            address poolInteractor = universalSwap.getProtocol(token);
            if (poolInteractor != address(0)) {
                IPoolInteractor poolInteractorContract = IPoolInteractor(poolInteractor);
                (underlyingTokens, ratios) = poolInteractorContract.getUnderlyingTokens(token);
            } else {
                revert("UT"); //Unsupported Token
            }
        }
    }

    function _getUnderlyingERC721(
        Asset memory nft
    ) internal view returns (address[] memory underlying, uint256[] memory ratios) {
        address[] memory nftPoolInteractors = universalSwap.getNFTPoolInteractors();
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
}