// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../interfaces/UniswapV3/INonfungiblePositionManager.sol";
import "../interfaces/UniswapV3/IUniswapV3Pool.sol";
import "../interfaces/UniswapV3/IUniswapV3Factory.sol";
import "./BankBase.sol";
import "hardhat/console.sol";

abstract contract IERC721Wrapper is Ownable {
    function isSupported(address manager, address pool) virtual external view returns (bool);
    function getPoolAddress(address manager, uint id) virtual external view returns (address);
    function deposit(address manager, uint id, address[] memory suppliedTokens, uint[] memory suppliedAmounts) virtual external returns (uint);
    function withdraw(address manager, uint id, uint amount, address receiver) virtual external returns (address[] memory outTokens, uint[] memory tokenAmounts);
    function harvest(address manager, uint id, address receiver) virtual external returns (address[] memory outTokens, uint[] memory tokenAmounts);
    function getERC20Base(address pool) virtual external view returns (address[] memory underlyingTokens);
}

contract UniswapV3Wrapper is IERC721Wrapper {

    function isSupported(address managerAddress, address poolAddress) override external view returns (bool) {
        IUniswapV3Pool pool = IUniswapV3Pool(poolAddress);
        address token0 = pool.token0();
        address token1 = pool.token1();
        uint24 fee = pool.fee();
        INonfungiblePositionManager manager = INonfungiblePositionManager(managerAddress);
        IUniswapV3Factory factory = IUniswapV3Factory(manager.factory());
        address expectedPoolAddress = factory.getPool(token0, token1, fee);
        if (expectedPoolAddress==poolAddress) {
            return true;
        }
        return false;
    }
    
    function getPoolAddress(address manager, uint id) override external view returns (address) {
        (,,address token0, address token1, uint24 fee,,,,,,,) = INonfungiblePositionManager(manager).positions(id);
        address factory = INonfungiblePositionManager(manager).factory();
        address poolAddress = IUniswapV3Factory(factory).getPool(token0, token1, fee);
        return poolAddress;
    }

    function deposit(address manager, uint id, address[] memory suppliedTokens, uint[] memory suppliedAmounts) override external returns (uint) {
        for (uint i = 0;i<suppliedTokens.length; i++) {
            IERC20(suppliedTokens[i]).approve(manager, suppliedAmounts[i]);
        }
        (,,address token0, address token1,,,,,,,,) = INonfungiblePositionManager(manager).positions(id);
        uint amount0;
        uint amount1;
        if (token0==suppliedTokens[0] && token1==suppliedTokens[1]) {
            amount0 = suppliedAmounts[0];
            amount1 = suppliedAmounts[1];
        } else {
            amount1 = suppliedAmounts[0];
            amount0 = suppliedAmounts[1];
        }
        INonfungiblePositionManager.IncreaseLiquidityParams memory params = INonfungiblePositionManager.IncreaseLiquidityParams(
            id,
            amount0, amount1,
            0, 0,
            block.timestamp
        );
        (uint minted,,) = INonfungiblePositionManager(manager).increaseLiquidity(params);
        return minted;
    }

    function withdraw(address manager, uint id, uint amount, address receiver) override external returns (address[] memory outTokens, uint[] memory tokenAmounts) {
        (,,address token0, address token1,,,,,,,,) = INonfungiblePositionManager(manager).positions(id);
        INonfungiblePositionManager.DecreaseLiquidityParams memory withdrawParams = INonfungiblePositionManager.DecreaseLiquidityParams(
            id,
            uint128(amount),
            0, 0, block.timestamp
        );
        (uint token0Amount, uint token1Amount) = INonfungiblePositionManager(manager).decreaseLiquidity(withdrawParams);
        INonfungiblePositionManager.CollectParams memory params = INonfungiblePositionManager.CollectParams(
            id,
            address(this),
            2**128 - 1,
            2**128 - 1
        );
        INonfungiblePositionManager(manager).collect(params);
        IERC20(token0).transfer(receiver, token0Amount);
        IERC20(token1).transfer(receiver, token1Amount);
        outTokens = new address[](2);
        outTokens[0] = token0;
        outTokens[1] = token1;
        tokenAmounts = new uint[](2);
        tokenAmounts[0] = token0Amount;
        tokenAmounts[1] = token1Amount;
    }

    function harvest(address manager, uint id, address receiver) override external returns (address[] memory outTokens, uint[] memory tokenAmounts) {
        (,,address token0, address token1,,,,,,,,) = INonfungiblePositionManager(manager).positions(id);
        INonfungiblePositionManager.CollectParams memory params = INonfungiblePositionManager.CollectParams(
            id,
            receiver,
            2**128 - 1,
            2**128 - 1
        );
        (uint256 amount0, uint256 amount1) = INonfungiblePositionManager(manager).collect(params);
        outTokens = new address[](2);
        outTokens[0] = token0;
        outTokens[1] = token1;
        tokenAmounts = new uint[](2);
        tokenAmounts[0] = amount0;
        tokenAmounts[1] = amount1;
    }

    function getERC20Base(address poolAddress) external override view returns (address[] memory underlyingTokens) {
        IUniswapV3Pool pool = IUniswapV3Pool(poolAddress);
        address token0 = pool.token0();
        address token1 = pool.token1();
        underlyingTokens = new address[](2);
        underlyingTokens[0] = token0;
        underlyingTokens[1] = token1;
    }
}