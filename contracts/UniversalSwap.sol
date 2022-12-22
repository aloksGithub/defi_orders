// SPDX-License-Identifier: BUSL 1.1
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
    using UintArray for uint256[];
    using AddressArray for address[];
    using SafeERC20 for IERC20;
    using Conversions for Conversion[];

    event NFTMinted(address manager, uint256 tokenId, address pool);
    event AssetsSent(
        address receiver,
        address[] tokens,
        address[] managers,
        uint256[] amountsAndIds
    );

    address public networkToken;
    address public stableToken;
    SwapHelper public helper;

    constructor(
        address[] memory _poolInteractors,
        address[] memory _nftPoolInteractors,
        address _networkToken,
        address _stableToken,
        address[] memory _swappers,
        IOracle _oracle
    ) {
        networkToken = _networkToken;
        stableToken = _stableToken;
        helper = new SwapHelper(
            _poolInteractors,
            _nftPoolInteractors,
            _networkToken,
            _swappers,
            _oracle
        );
        helper.transferOwnership(msg.sender);
    }

    function _getWETH() internal returns (uint256 networkTokenObtained) {
        uint256 startingBalance = IERC20(networkToken).balanceOf(address(this));
        if (msg.value > 0) {
            IWETH(payable(networkToken)).deposit{value: msg.value}();
        }
        networkTokenObtained =
            IERC20(networkToken).balanceOf(address(this)) -
            startingBalance;
    }

    function _addWETH(address[] memory tokens, uint256[] memory amounts)
        internal
        returns (address[] memory, uint256[] memory)
    {
        uint256 ethSupplied = _getWETH();
        if (ethSupplied > 0) {
            tokens = tokens.append(networkToken);
            amounts = amounts.append(ethSupplied);
        }
        return (tokens, amounts);
    }

    function _burn(address token, uint256 amount)
        internal
        returns (
            address[] memory underlyingTokens,
            uint256[] memory underlyingTokenAmounts
        )
    {
        address poolInteractor = helper.getProtocol(token);
        bytes memory data = poolInteractor.functionDelegateCall(
            abi.encodeWithSelector(
                IPoolInteractor(poolInteractor).burn.selector,
                token,
                amount,
                poolInteractor
            )
        );
        (underlyingTokens, underlyingTokenAmounts) = abi.decode(
            data,
            (address[], uint256[])
        );
    }

    function _mint(
        address toMint,
        address[] memory underlyingTokens,
        uint256[] memory underlyingAmounts,
        address receiver
    ) internal returns (uint256 amountMinted) {
        if (toMint == underlyingTokens[0]) return underlyingAmounts[0];
        if (toMint == address(0)) {
            IWETH(payable(networkToken)).withdraw(underlyingAmounts[0]);
            payable(receiver).transfer(underlyingAmounts[0]);
            return underlyingAmounts[0];
        }
        address poolInteractor = helper.getProtocol(toMint);
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
            if (!helper.isSimpleToken(inputTokens[i])) {
                allSimiplified = false;
                (
                    address[] memory newTokens,
                    uint256[] memory newTokenAmounts
                ) = _burn(inputTokens[i], inputTokenAmounts[i]);
                // updatedTokens = updatedTokens.remove(i).concat(newTokens);
                // updatedTokenAmounts = updatedTokenAmounts.remove(i).concat(newTokenAmounts);
                updatedTokens[i] = newTokens[0];
                updatedTokenAmounts[i] = newTokenAmounts[0];
                address[] memory tempTokens = new address[](
                    updatedTokens.length + newTokens.length - 1
                );
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

    function _collectAndBreak(
        address[] memory inputTokens,
        uint256[] memory inputTokenAmounts,
        Asset[] memory inputNFTs
    ) internal returns (address[] memory, uint256[] memory) {
        for (uint256 i = 0; i < inputTokenAmounts.length; i++) {
            // uint balanceBefore = IERC20(inputTokens[i]).balanceOf(address(this));
            IERC20(inputTokens[i]).safeTransferFrom(
                msg.sender,
                address(this),
                inputTokenAmounts[i]
            );
            // inputTokenAmounts[i] = IERC20(inputTokens[i]).balanceOf(address(this))-balanceBefore;
        }
        for (uint256 i = 0; i < inputNFTs.length; i++) {
            IERC721(inputNFTs[i].manager).transferFrom(
                msg.sender,
                address(this),
                inputNFTs[i].tokenId
            );
        }
        return _break(inputTokens, inputTokenAmounts, inputNFTs);
    }

    function _break(
        address[] memory inputTokens,
        uint256[] memory inputTokenAmounts,
        Asset[] memory inputNFTs
    ) internal returns (address[] memory, uint256[] memory) {
        for (uint256 i = 0; i < inputNFTs.length; i++) {
            Asset memory nft = inputNFTs[i];
            address nftPoolInteractor = helper.getProtocol(nft.manager);
            if (nftPoolInteractor == address(0)) revert("UT");
            bytes memory returnData = nftPoolInteractor.functionDelegateCall(
                abi.encodeWithSelector(
                    INFTPoolInteractor(nftPoolInteractor).burn.selector,
                    nft
                )
            );
            (address[] memory nftTokens, uint256[] memory nftTokenAmounts) = abi
                .decode(returnData, (address[], uint256[]));
            inputTokens = inputTokens.concat(nftTokens);
            inputTokenAmounts = inputTokenAmounts.concat(nftTokenAmounts);
        }
        (
            address[] memory simplifiedTokens,
            uint256[] memory simplifiedTokenAmounts
        ) = _simplifyInputTokens(inputTokens, inputTokenAmounts);
        (simplifiedTokens, simplifiedTokenAmounts) = _addWETH(
            simplifiedTokens,
            simplifiedTokenAmounts
        );
        (simplifiedTokens, simplifiedTokenAmounts) = simplifiedTokens.shrink(
            simplifiedTokenAmounts
        );
        return (simplifiedTokens, simplifiedTokenAmounts);
    }

    function _conductERC20Conversion(
        Conversion memory conversion,
        address receiver,
        address[] memory tokensAvailable,
        uint256[] memory amountsAvailable
    ) internal returns (uint256) {
        if (
            (conversion.underlying[0] == conversion.desiredERC20 &&
                conversion.underlying.length == 1)
        ) {
            uint256 tokenToUseIndex = tokensAvailable.findFirst(
                conversion.underlying[0]
            );
            uint256 balance = amountsAvailable[tokenToUseIndex];
            uint256 amountToUse = (balance * conversion.underlyingValues[0]) /
                1e18;
            IERC20(conversion.underlying[0]).safeTransfer(
                receiver,
                amountToUse
            );
            amountsAvailable[tokenToUseIndex] -= amountToUse;
            return amountToUse;
        } else {
            uint256[] memory inputTokenAmounts = new uint256[](
                conversion.underlying.length
            );
            for (uint256 i = 0; i < conversion.underlying.length; i++) {
                uint256 tokenToUseIndex = tokensAvailable.findFirst(
                    conversion.underlying[i]
                );
                uint256 balance = amountsAvailable[tokenToUseIndex];
                uint256 amountToUse = (balance *
                    conversion.underlyingValues[i]) / 1e18;
                amountsAvailable[tokenToUseIndex] -= amountToUse;
                inputTokenAmounts[i] = amountToUse;
            }
            return
                _mint(
                    conversion.desiredERC20,
                    conversion.underlying,
                    inputTokenAmounts,
                    receiver
                );
        }
    }

    function _conductERC721Conversion(
        Conversion memory conversion,
        address receiver,
        address[] memory tokensAvailable,
        uint256[] memory amountsAvailable
    ) internal returns (uint256) {
        Asset memory nft = conversion.desiredERC721;
        address nftPoolInteractor = helper.getProtocol(nft.manager);
        if (nftPoolInteractor == address(0)) revert("UT");
        uint256[] memory inputTokenAmounts = new uint256[](
            conversion.underlying.length
        );
        for (uint256 j = 0; j < conversion.underlying.length; j++) {
            uint256 tokenToUseIndex = tokensAvailable.findFirst(
                conversion.underlying[j]
            );
            uint256 balance = amountsAvailable[tokenToUseIndex];
            uint256 amountToUse = (balance * conversion.underlyingValues[j]) /
                1e18;
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
        emit NFTMinted(nft.manager, tokenId, nft.pool);
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
                uint256 tokenId = _conductERC721Conversion(
                    conversions[i],
                    receiver,
                    tokensAvailable,
                    amountsAvailable
                );
                amounts[amountsAdded] = tokenId;
                amountsAdded += 1;
            } else {
                uint256 amountObtained = _conductERC20Conversion(
                    conversions[i],
                    receiver,
                    tokensAvailable,
                    amountsAvailable
                );
                if (
                    outputTokens.exists(conversions[i].desiredERC20) &&
                    conversions[i].underlying.length != 0
                ) {
                    amounts[amountsAdded] = amountObtained;
                    require(
                        amountObtained >= minAmountsOut[amountsAdded],
                        "3"
                    );
                    amountsAdded += 1;
                }
            }
        }
    }

    receive() external payable {}

    function _conductSwaps(
        SwapPoint[] memory swaps,
        address[] memory tokens,
        uint256[] memory amounts
    )
        internal
        returns (
            address[] memory tokensObtained,
            uint256[] memory amountsObtained
        )
    {
        tokensObtained = new address[](swaps.length);
        amountsObtained = new uint256[](swaps.length);
        for (uint256 i = 0; i < swaps.length; i++) {
            uint256 amount = (swaps[i].amountIn *
                amounts[tokens.findFirst(swaps[i].tokenIn)]) / 1e18;
            bytes memory returnData = swaps[i].swapper.functionDelegateCall(
                abi.encodeWithSelector(
                    ISwapper(swaps[i].swapper).swap.selector,
                    amount,
                    swaps[i].path,
                    swaps[i].swapper
                )
            );
            uint256 amountObtained = abi.decode(returnData, (uint256));
            tokensObtained[i] = swaps[i].tokenOut;
            amountsObtained[i] = amountObtained;
        }
        (tokensObtained, amountsObtained) = tokensObtained.shrink(
            amountsObtained
        );
    }

    function _swap(
        Provided memory provided,
        SwapPoint[] memory swaps,
        Conversion[] memory conversions,
        Desired memory desired,
        address receiver
    ) internal returns (uint256[] memory) {
        if (swaps.length == 0 || conversions.length == 0) {
            (swaps, conversions) = preSwapComputation(provided, desired);
        }
        require(provided.tokens.length > 0, "4");
        (
            address[] memory tokensAfterSwap,
            uint256[] memory amountsAfterSwap
        ) = _conductSwaps(swaps, provided.tokens, provided.amounts);
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
        emit AssetsSent(
            msg.sender,
            desired.outputERC20s,
            managers,
            amountsAndIds
        );
        return amountsAndIds;
    }

    /// @inheritdoc IUniversalSwap
    function isSupported(address token) public view returns (bool) {
        if (helper.isSimpleToken(token)) return true;
        if (helper.getProtocol(token) != address(0)) return true;
        return false;
    }

    /// @inheritdoc IUniversalSwap
    function estimateValue(Provided memory assets, address inTermsOf)
        public
        view
        returns (uint256)
    {
        return helper.estimateValue(assets, inTermsOf);
    }

    function estimateValueERC20(
        address token,
        uint256 amount,
        address inTermsOf
    ) public view returns (uint256) {
        address[] memory tokens = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        tokens[0] = token;
        amounts[0] = amount;
        Provided memory asset = Provided(tokens, amounts, new Asset[](0));
        return helper.estimateValue(asset, inTermsOf);
    }

    function estimateValueERC721(Asset memory nft, address inTermsOf)
        public
        view
        returns (uint256)
    {
        Asset[] memory assets = new Asset[](1);
        assets[0] = nft;
        return
            helper.estimateValue(
                Provided(new address[](0), new uint256[](0), assets),
                inTermsOf
            );
    }

    /// @inheritdoc IUniversalSwap
    function getUnderlying(address[] memory tokens, uint256[] memory amounts)
        external
        view
        returns (address[] memory, uint256[] memory)
    {
        return helper.simplifyWithoutWrite(tokens, amounts, new Asset[](0));
    }

    /// @inheritdoc IUniversalSwap
    function preSwapComputation(
        Provided memory provided,
        Desired memory desired
    )
        public
        view
        returns (SwapPoint[] memory swaps, Conversion[] memory conversions)
    {
        (provided.tokens, provided.amounts) = helper.simplifyWithoutWrite(
            provided.tokens,
            provided.amounts,
            provided.nfts
        );
        (uint256[] memory inputTokenValues, uint256 totalValue) = helper
            .getTokenValues(provided.tokens, provided.amounts);

        conversions = helper.prepareConversions(
            desired.outputERC20s,
            desired.outputERC721s,
            desired.ratios,
            totalValue
        );
        (
            address[] memory underlyingTokens,
            uint256[] memory underlyingValues
        ) = conversions.getUnderlying();
        (underlyingTokens, underlyingValues) = underlyingTokens.shrink(
            underlyingValues
        );
        swaps = helper.findMultipleSwaps(
            provided.tokens,
            provided.amounts,
            inputTokenValues,
            underlyingTokens,
            underlyingValues
        );
        conversions = conversions.normalizeRatios();
        return (swaps, conversions);
    }

    /// @inheritdoc IUniversalSwap
    function swapAfterTransfer(
        Provided memory provided,
        SwapPoint[] memory swaps,
        Conversion[] memory conversions,
        Desired memory desired,
        address receiver
    ) external payable returns (uint256[] memory) {
        (provided.tokens, provided.amounts) = _break(
            provided.tokens,
            provided.amounts,
            provided.nfts
        );
        provided.nfts = new Asset[](0);
        return _swap(provided, swaps, conversions, desired, receiver);
    }

    /// @inheritdoc IUniversalSwap
    function swap(
        Provided memory provided,
        SwapPoint[] memory swaps,
        Conversion[] memory conversions,
        Desired memory desired,
        address receiver
    ) external payable returns (uint256[] memory) {
        (provided.tokens, provided.amounts) = _collectAndBreak(
            provided.tokens,
            provided.amounts,
            provided.nfts
        );
        provided.nfts = new Asset[](0);
        return _swap(provided, swaps, conversions, desired, receiver);
    }

    function getAmountsOut(Provided memory provided, Desired memory desired)
        external
        view
        returns (
            uint256[] memory amounts,
            SwapPoint[] memory swaps,
            Conversion[] memory conversions,
            uint256[] memory expectedUSDValues
        )
    {
        uint256[] memory inputTokenValues;
        for (uint256 i = 0; i < provided.tokens.length; i++) {
            if (provided.tokens[i] == address(0)) {
                provided.tokens[i] = networkToken;
            }
        }
        {
            (provided.tokens, provided.amounts) = helper.simplifyWithoutWrite(
                provided.tokens,
                provided.amounts,
                provided.nfts
            );
            uint256 totalValue;
            (inputTokenValues, totalValue) = helper.getTokenValues(
                provided.tokens,
                provided.amounts
            );

            conversions = helper.prepareConversions(
                desired.outputERC20s,
                desired.outputERC721s,
                desired.ratios,
                totalValue
            );
        }
        (
            address[] memory underlyingTokens,
            uint256[] memory underlyingValues
        ) = conversions.getUnderlying();
        (underlyingTokens, underlyingValues) = underlyingTokens.shrink(
            underlyingValues
        );
        swaps = helper.findMultipleSwaps(
            provided.tokens,
            provided.amounts,
            inputTokenValues,
            underlyingTokens,
            underlyingValues
        );
        uint256[] memory expectedAmounts;
        (underlyingTokens, expectedAmounts) = helper.simulateSwaps(
            swaps,
            provided.tokens,
            provided.amounts
        );
        (underlyingTokens, expectedAmounts) = underlyingTokens.shrink(
            expectedAmounts
        );
        conversions = conversions.normalizeRatios();
        amounts = helper.simulateConversions(
            conversions,
            desired.outputERC20s,
            underlyingTokens,
            expectedAmounts
        );
        expectedUSDValues = new uint256[](amounts.length);
        for (uint256 i = 0; i < desired.outputERC20s.length; i++) {
            address[] memory token = new address[](1);
            uint256[] memory amount = new uint256[](1);
            token[0] = desired.outputERC20s[i];
            amount[0] = amounts[i];
            uint256 value = estimateValue(
                Provided(token, amount, new Asset[](0)),
                stableToken
            );
            expectedUSDValues[i] = value;
        }
        for (uint256 i = 0; i < desired.outputERC721s.length; i++) {
            desired.outputERC721s[i].liquidity = amounts[
                desired.outputERC20s.length + i
            ];
            Asset[] memory nft = new Asset[](1);
            nft[0] = desired.outputERC721s[i];
            uint256 value = estimateValue(
                Provided(new address[](0), new uint256[](0), nft),
                stableToken
            );
            expectedUSDValues[desired.outputERC20s.length + i] = value;
        }
    }
}
