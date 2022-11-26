// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "./INFTPoolInteractor.sol";
import "../libraries/SwapFinder.sol";
import "../libraries/Conversions.sol";
    
struct Desired {
    address[] outputERC20s;
    Asset[] outputERC721s;
    uint[] ratios;
    uint[] minAmountsOut;
}

struct Provided {
    address[] tokens;
    uint[] amounts;
    Asset[] nfts;
}

/// @title Interface for UniversalSwap utility
/// @notice UniversalSwap allows trading between pool tokens and tokens tradeable on DEXes
interface IUniversalSwap {

    /// @notice Returns the address of the wrapped network token contract such as WETH, WBNB, etc.
    function networkToken() external view returns (address tokenAddress);

    /// @notice Sets the swappers which are used to convert between ERC20 tokens
    /// @dev Currently only uniswapV2 based swappers are used
    /// @param _swappers The list of deployed swapper contracts with the logic for swapping using some DEX
    // function setSwappers(address[] calldata _swappers) external view;

    /// @notice Sets the pool interactors which are used to interact with protocols to mint and burn pool tokens
    /// @param _poolInteractors List of deployed pool interactors with logic to interact with protocols
    // function setPoolInteractors(address[] calldata _poolInteractors) external;

    /// @notice UniswapV3 like protocols use ERC721 tokens for pools, hence the pool interactors for such protocols differ and are set using this function
    /// @param _nftPoolInteractors List of deployed pool interactors with logic to interact with NFT based protocols
    // function setNFTPoolInteractors(address[] calldata _nftPoolInteractors) external;

    /// @notice Checks if a provided token is swappable using UniversalSwap
    /// @param token Address of token to be swapped or swapped for
    /// @return supported Wether the provided token is supported or not
    function isSupported(address token) external returns (bool supported);

    /// @notice Gets the underlying tokens and ratios for an ERC20 contract
    /// @param token Contract address for token whose underlying assets need to be determined
    /// @return underlyingTokens Underlying tokens for specified token
    /// @return ratios Ratio of usd value underlying tokens to be used when supplying
    // function getUnderlyingERC20(address token) external returns (address[] memory underlyingTokens, uint[] memory ratios);

    /// @notice Gets the underlying tokens and ratios for an ERC721 contract
    /// @param nft Contract address for token whose underlying assets need to be determined
    /// @return underlyingTokens Underlying tokens for specified token
    /// @return ratios Ratio of usd value underlying tokens to be used when supplying
    // function getUnderlyingERC721(Asset memory nft) external returns (address[] memory underlyingTokens, uint[] memory ratios);

    /// @notice Calculates the swaps and conversions that need to be performed prior to calling swap/swapAfterTransfer
    /// @notice It is recommended to use this function and provide the return values to swap/swapAfterTransfer as that greatly reduces gas consumption
    /// @param provided List of provided ERC20/ERC721 assets provided to convert into the desired assets
    /// @param desired Assets to convert provided assets into
    /// @return swaps Swaps that need to be performed with the provided assets
    /// @return conversions List of conversions from simple ERC20 tokens to complex assets such as LP tokens, Uniswap v3 positions, etc
    function preSwapComputation(
        Provided memory provided,
        Desired memory desired
    ) external view returns (SwapPoint[] memory swaps, Conversion[] memory conversions);

    /// @notice Swap provided assets into desired assets
    /// @dev Before calling, make sure UniversalSwap contract has approvals to transfer provided assets
    /// @dev swaps ans conversions can be provided as empty list, in which case the contract will calculate them, but this will result in high gas usage
    /// @param provided List of provided ERC20/ERC721 assets provided to convert into the desired assets
    /// @param swaps Swaps that need to be performed with the provided assets
    /// @param conversions List of conversions from simple ERC20 tokens to complex assets such as LP tokens, Uniswap v3 positions, etc
    /// @param desired Assets to convert provided assets into
    /// @param receiver Address that will receive output desired assets
    /// @return amountsAndIds Amount of outputTokens obtained and Token IDs for output NFTs
    function swap(
        Provided memory provided,
        SwapPoint[] memory swaps,
        Conversion[] memory conversions,
        Desired memory desired,
        address receiver
    ) payable external returns (uint[] memory amountsAndIds);

    /// @notice Functions just like swap, but assets are transferred to universal swap contract before calling this function rather than using approval
    /// @notice Implemented as a way to save gas by eliminating needless transfers
    /// @dev Before calling, make sure all assets in provided have been transferred to universal swap contract
    /// @param provided List of provided ERC20/ERC721 assets provided to convert into the desired assets
    /// @param swaps Swaps that need to be performed with the provided assets. Can be provided as empty list, in which case it will be calculated by the contract
    /// @param conversions List of conversions from simple ERC20 tokens to complex assets such as LP tokens, Uniswap v3 positions, etc. Can be provided as empty list.
    /// @param desired Assets to convert provided assets into
    /// @param receiver Address that will receive output desired assets
    /// @return amountsAndIds Amount of outputTokens obtained and Token IDs for output NFTs
    function swapAfterTransfer(
        Provided memory provided,
        SwapPoint[] memory swaps,
        Conversion[] memory conversions,
        Desired memory desired,
        address receiver
    ) payable external returns (uint[] memory amountsAndIds);
}