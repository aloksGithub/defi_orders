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

    /// @notice Checks if a provided token is swappable using UniversalSwap
    /// @param token Address of token to be swapped or swapped for
    /// @return supported Wether the provided token is supported or not
    function isSupported(address token) external returns (bool supported);

    /// @notice Estimates the combined values of the provided tokens in terms of another token
    /// @param tokens Tokens for which to estimate value
    /// @param amounts Amounts of tokens to use to estimate value
    /// @param inTermsOf Token whose value equivalent value to the provided tokens needs to be returned
    /// @return value The amount of inTermsOf that is equal in value to the provided tokens
    function estimateValue(address[] memory tokens, uint[] memory amounts, address inTermsOf) external view returns (uint value);

    /// @notice Find the underlying tokens and amounts for some complex tokens
    function getUnderlying(address[] memory tokens, uint[] memory amounts) external view returns (address[] memory underlyingTokens, uint[] memory underlyingAmounts);

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