// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "../interfaces/IPoolInteractor.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../interfaces/IUniswapV2Pair.sol";
import "hardhat/console.sol";

contract UniswapV2PoolInteractor is IPoolInteractor {
    function burn(address lpTokenAddress, uint256 amount)
        external
        returns (address[] memory, uint256[] memory)
    {
        IUniswapV2Pair pair = IUniswapV2Pair(lpTokenAddress);
        pair.transferFrom(msg.sender, lpTokenAddress, amount);
        (uint256 token0Gained, uint256 token1Gained) = pair.burn(msg.sender);
        uint256[] memory receivedTokenAmounts = new uint256[](2);
        receivedTokenAmounts[0] = token0Gained;
        receivedTokenAmounts[1] = token1Gained;
        address[] memory receivedTokens = new address[](2);
        receivedTokens[0] = pair.token0();
        receivedTokens[1] = pair.token1();
        emit Burn(lpTokenAddress, amount);
        return (receivedTokens, receivedTokenAmounts);
    }

    function mint(
        address toMint,
        address[] memory underlyingTokens,
        uint256[] memory underlyingAmounts
    ) external returns (uint256) {
        IUniswapV2Pair poolContract = IUniswapV2Pair(toMint);
        for (uint256 i = 0; i < underlyingTokens.length; i++) {
            // ERC20 tokenContract = ERC20(underlyingTokens[i]);
            (bool success, ) = underlyingTokens[i].call(
                abi.encodeWithSignature(
                    "transferFrom(address,address,uint256)",
                    msg.sender,
                    toMint,
                    underlyingAmounts[i]
                )
            );
            if (!success) {
                revert("Failed to transfer token");
            }
            // tokenContract.transferFrom(
            //     msg.sender,
            //     toMint,
            //     underlyingAmounts[i]
            // );
        }
        uint256 minted = poolContract.mint(msg.sender);
        return minted;
    }

    function checkBurnable(address lpTokenAddress, uint256 liquidity)
        external
        view
        returns (
            bool,
            address[] memory,
            uint256[] memory
        )
    {
        IUniswapV2Pair poolContract = IUniswapV2Pair(lpTokenAddress);
        ERC20 token0 = ERC20(poolContract.token0());
        ERC20 token1 = ERC20(poolContract.token1());
        uint256 balance0 = token0.balanceOf(lpTokenAddress);
        uint256 balance1 = token1.balanceOf(lpTokenAddress);
        uint256 totalSupply = poolContract.totalSupply();
        uint256 amount0 = (liquidity * balance0) / totalSupply;
        uint256 amount1 = (liquidity * balance1) / totalSupply;
        address[] memory receivedTokens = new address[](2);
        receivedTokens[0] = poolContract.token0();
        receivedTokens[1] = poolContract.token1();
        uint256[] memory receivedTokenAmounts = new uint256[](2);
        receivedTokenAmounts[0] = amount0;
        receivedTokenAmounts[1] = amount1;
        return (
            amount0 > 0 && amount1 > 0,
            receivedTokens,
            receivedTokenAmounts
        );
    }

    function getUnderlyingTokens(address lpTokenAddress)
        external
        view
        returns (address[] memory, uint256[] memory balances)
    {
        IUniswapV2Pair poolContract = IUniswapV2Pair(lpTokenAddress);
        address[] memory receivedTokens = new address[](2);
        receivedTokens[0] = poolContract.token0();
        receivedTokens[1] = poolContract.token1();
        balances = new uint[](2);
        (uint reserve0, uint reserve1,) = poolContract.getReserves();
        balances[0] = reserve0;
        balances[1] = reserve1;

        return (receivedTokens, balances);
    }
}
