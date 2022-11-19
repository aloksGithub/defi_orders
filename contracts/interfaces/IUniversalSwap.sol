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

    /// @notice Gets the underlying tokens and ratios for an ERC20 contract
    /// @param token Contract address for token whose underlying assets need to be determined
    /// @return underlyingTokens Underlying tokens for specified token
    /// @return ratios Ratio of usd value underlying tokens to be used when supplying
    function getUnderlyingERC20(address token) external returns (address[] memory underlyingTokens, uint[] memory ratios);

    /// @notice Gets the underlying tokens and ratios for an ERC721 contract
    /// @param nft Contract address for token whose underlying assets need to be determined
    /// @return underlyingTokens Underlying tokens for specified token
    /// @return ratios Ratio of usd value underlying tokens to be used when supplying
    function getUnderlyingERC721(Asset memory nft) external returns (address[] memory underlyingTokens, uint[] memory ratios);

    // /// @notice Swap ERC20 tokens for multiple ERC20 tokens in provided ratio
    // /// @dev Before calling, make sure UniversalSwap contract has approvals according to inputTokenAmounts
    // /// @param inputTokens ERC20 tokens to be converted
    // /// @param inputTokenAmounts Amounts for the ERC20 tokens to be converted
    // /// @param outputTokens ERC20 tokens to convert to
    // /// @param outputRatios Ratios of ERC20 tokens to be converted to
    // /// @param minAmountsOut Slippage control
    // /// @return tokensObtained Amount of outputTokens obtained
    // function swap(address[] memory inputTokens, uint[] memory inputTokenAmounts, address[] memory outputTokens, uint[] memory outputRatios, uint[] memory minAmountsOut) payable external returns (uint[] memory tokensObtained);

    // /// @notice Swap ERC20 tokens for ERV721 token for a UniswapV3 like position
    // /// @param inputTokens ERC20 tokens to be converted
    // /// @param inputTokenAmounts Amounts for the ERC20 tokens to be converted
    // /// @param nft Details for the ERC721 token to be minted
    // /// @return id The token id for the minted ERC721 token
    // function swapForNFT(address[] memory inputTokens, uint[] memory inputTokenAmounts, Asset memory nft) external returns (uint id);

    // /// @notice Swap ERC721 token for ERC20 token
    // /// @param nft Structure describing NFT to swap
    // /// @param outputToken ERC20 token to swap for
    // /// @param minAmount Slippage control
    // /// @return finalTokenObtained Amount of outputToken obtained
    // function swapNFT(Asset memory nft, address outputToken, uint minAmount) external returns (uint finalTokenObtained);
}