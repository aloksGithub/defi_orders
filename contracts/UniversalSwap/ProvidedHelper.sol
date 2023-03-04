// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

import "../interfaces/IPoolInteractor.sol";
import "../interfaces/IUniversalSwap.sol";
import "../libraries/UintArray.sol";
import "../libraries/AddressArray.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "hardhat/console.sol";

contract ProvidedHelper {
    using AddressArray for address[];
    using UintArray for uint256[];

    IUniversalSwap public universalSwap;

    constructor(IUniversalSwap _universalSwap) {
        universalSwap = _universalSwap;
    }

    ///-------------Internal logic-------------
    function simplifyWithoutWrite(
        Provided memory provided
    ) public view returns (address[] memory simplifiedTokens, uint256[] memory simplifiedAmounts) {
        address[] memory swappers = universalSwap.getSwappers();
        address[] memory poolInteractors = universalSwap.getPoolInteractors();
        address[] memory nftPoolInteractors = universalSwap.getNFTPoolInteractors();

        (simplifiedTokens, simplifiedAmounts) = _simplifyWithoutWriteERC20(
            provided.tokens,
            provided.amounts,
            poolInteractors,
            nftPoolInteractors,
            swappers
        );
        (
            address[] memory simplifiedTokensERC721,
            uint256[] memory simplifiedAmountsERC721
        ) = _simplifyWithoutWriteERC721(provided.nfts, nftPoolInteractors);
        simplifiedTokens = simplifiedTokens.concat(simplifiedTokensERC721);
        simplifiedAmounts = simplifiedAmounts.concat(simplifiedAmountsERC721);
        (simplifiedTokens, simplifiedAmounts) = simplifiedTokens.shrink(simplifiedAmounts);
    }

    ///-------------Internal logic-------------
    function _simplifyWithoutWriteERC20(
        address[] memory tokens,
        uint256[] memory amounts,
        address[] memory poolInteractors,
        address[] memory nftPoolInteractors,
        address[] memory swappers
    ) internal view returns (address[] memory simplifiedTokens, uint256[] memory simplifiedAmounts) {
        address networkToken = universalSwap.networkToken();
        for (uint256 i = 0; i < tokens.length; i++) {
            if (universalSwap.isSimpleToken(tokens[i])) {
                if (tokens[i] != address(0)) {
                    simplifiedTokens = simplifiedTokens.append(tokens[i]);
                } else {
                    simplifiedTokens = simplifiedTokens.append(networkToken);
                }
                simplifiedAmounts = simplifiedAmounts.append(amounts[i]);
                continue;
            }
            for (uint256 j = 0; j < poolInteractors.length; j++) {
                if (IPoolInteractor(poolInteractors[j]).testSupported(tokens[i])) {
                    (address[] memory brokenTokens, uint256[] memory brokenAmounts) = IPoolInteractor(
                        poolInteractors[j]
                    ).getUnderlyingAmount(tokens[i], amounts[i]);
                    (address[] memory simpleTokens, uint256[] memory simpleAmounts) = _simplifyWithoutWriteERC20(
                        brokenTokens,
                        brokenAmounts,
                        poolInteractors,
                        nftPoolInteractors,
                        swappers
                    );
                    simplifiedTokens = simplifiedTokens.concat(simpleTokens);
                    simplifiedAmounts = simplifiedAmounts.concat(simpleAmounts);
                }
            }
        }
    }

    function _simplifyWithoutWriteERC721(
        Asset[] memory nfts,
        address[] memory nftPoolInteractors
    ) internal view returns (address[] memory simplifiedTokens, uint256[] memory simplifiedAmounts) {
        for (uint256 i = 0; i < nfts.length; i++) {
            for (uint256 j = 0; j < nftPoolInteractors.length; j++) {
                if (INFTPoolInteractor(nftPoolInteractors[j]).testSupported(nfts[i].manager)) {
                    (address[] memory tokens, uint256[] memory amounts) = INFTPoolInteractor(nftPoolInteractors[j])
                        .getUnderlyingAmount(nfts[i]);
                    simplifiedTokens = simplifiedTokens.concat(tokens);
                    simplifiedAmounts = simplifiedAmounts.concat(amounts);
                }
            }
        }
    }
}