// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "./INFTPoolInteractor.sol";

/// @title Interface for UniversalSwap utility
/// @notice UniversalSwap allows trading between pool tokens and tokens tradeable on DEXes
interface IUniversalSwap {

    /// @notice Sets the swappers which are used to convert between ERC20 tokens
    /// @dev Currently only uniswapV2 based swappers are used
    /// @param _swappers The list of deployed swapper contracts with the logic for swapping using some DEX
    function setSwappers(address[] calldata _swappers) external view;

    /// @notice Sets the pool interactors which are used to interact with protocols to mint and burn pool tokens
    /// @param _poolInteractors List of deployed pool interactors with logic to interact with protocols
    function setPoolInteractors(address[] calldata _poolInteractors) external;

    /// @notice UniswapV3 like protocols use ERC721 tokens for pools, hence the pool interactors for such protocols differ and are set using this function
    /// @param _nftPoolInteractors List of deployed pool interactors with logic to interact with NFT based protocols
    function setNFTPoolInteractors(address[] calldata _nftPoolInteractors) external;

    /// @notice Checks if a provided token is swappable using UniversalSwap
    /// @param token Address of token to be swapped or swapped for
    /// @return supported Wether the provided token is supported or not
    function isSupported(address token) external returns (bool supported);

    /// @notice Gets the underlying tokens for an ERC20 or ERC721 contract
    /// @param token Contract address for token whose underlying assets need to be determined
    /// @return underlyingTokens Underlying tokens for specified token
    function getUnderlying(address token) external returns (address[] memory underlyingTokens);

    /// @notice Swap ERC20 tokens for multiple ERC20 tokens in provided ratio
    /// @dev Before calling, make sure UniversalSwap contract has approvals according to inputTokenAmounts
    /// @param inputTokens ERC20 tokens to be converted
    /// @param inputTokenAmounts Amounts for the ERC20 tokens to be converted
    /// @param outputTokens ERC20 tokens to convert to
    /// @param outputRatios Ratios of ERC20 tokens to be converted to
    /// @param minAmountsOut Slippage control
    /// @return tokensObtained Amount of outputTokens obtained
    function swap(address[] memory inputTokens, uint[] memory inputTokenAmounts, address[] memory outputTokens, uint[] memory outputRatios, uint[] memory minAmountsOut) external returns (uint[] memory tokensObtained);

    /// @notice Swap ERC20 tokens for multiple ERC20 tokens in an equal ratio
    /// @dev Before calling, make sure UniversalSwap contract has approvals according to inputTokenAmounts
    /// @param inputTokens ERC20 tokens to be converted
    /// @param inputTokenAmounts Amounts for the ERC20 tokens to be converted
    /// @param outputTokens ERC20 tokens to convert to
    /// @param minAmountsOut Slippage control
    /// @return tokensObtained Amount of outputTokens obtained
    function swap(address[] memory inputTokens, uint[] memory inputTokenAmounts, address[] memory outputTokens, uint[] memory minAmountsOut) external returns (uint[] memory tokensObtained);

    /// @notice Swap ERC20 tokens for a single ERC20 token
    /// @dev Before calling, make sure UniversalSwap contract has approvals according to inputTokenAmounts
    /// @param inputTokens ERC20 tokens to be converted
    /// @param inputTokenAmounts Amounts for the ERC20 tokens to be converted
    /// @param outputToken ERC20 tokens to convert to
    /// @param minAmountOut Slippage control
    /// @return tokenObtained Amount of outputToken obtained
    function swap(address[] memory inputTokens, uint[] memory inputTokenAmounts, address outputToken, uint minAmountOut) external returns (uint tokenObtained);

    /// @notice Swap ERC20 tokens for ERV721 token for a UniswapV3 like position
    /// @param inputTokens ERC20 tokens to be converted
    /// @param inputTokenAmounts Amounts for the ERC20 tokens to be converted
    /// @param nft Details for the ERC721 token to be minted
    /// @return id The token id for the minted ERC721 token
    function swapForNFT(address[] memory inputTokens, uint[] memory inputTokenAmounts, Asset memory nft) external returns (uint id);

    /// @notice Swap ERC721 token for ERC20 token
    function swapNFT(Asset memory nft, address outputToken) external returns (uint);
}