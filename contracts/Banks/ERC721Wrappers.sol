// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../interfaces/UniswapV3/INonfungiblePositionManager.sol";
import "../interfaces/UniswapV3/IUniswapV3Pool.sol";
import "../interfaces/UniswapV3/IUniswapV3Factory.sol";
import "./BankBase.sol";
import "hardhat/console.sol";
import '../libraries/TickMath.sol';
import "../libraries/LiquidityAmounts.sol";

abstract contract IERC721Wrapper is Ownable {
    function isSupported(address manager, address pool) virtual external view returns (bool);
    function getPoolAddress(address manager, uint id) virtual external view returns (address);
    function deposit(address manager, uint id, address[] memory suppliedTokens, uint[] memory suppliedAmounts) virtual external returns (uint);
    function withdraw(address manager, uint id, uint amount, address receiver) virtual external returns (address[] memory outTokens, uint[] memory tokenAmounts);
    function harvest(address manager, uint id, address receiver) virtual external returns (address[] memory outTokens, uint[] memory tokenAmounts);
    function getRatio(address manager, uint id) virtual view external returns (address[] memory tokens, uint[] memory ratios);
    function getRewardsForPosition(address manager, uint tokenId) virtual external view returns (address[] memory rewards, uint[] memory amounts);
    function getERC20Base(address pool) virtual external view returns (address[] memory underlyingTokens);
    function getPositionUnderlying(address manager, uint tokenId) virtual external view returns (address[] memory tokens, uint[] memory amounts);
}

contract UniswapV3Wrapper is IERC721Wrapper {
    using SafeERC20 for IERC20;

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
            uint allowance = IERC20(suppliedTokens[i]).allowance(address(this), manager);
            IERC20(suppliedTokens[i]).safeDecreaseAllowance(manager, allowance);
            IERC20(suppliedTokens[i]).safeIncreaseAllowance(manager, suppliedAmounts[i]);
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
        (uint minted, uint a0, uint a1) = INonfungiblePositionManager(manager).increaseLiquidity(params);
        address owner = INonfungiblePositionManager(manager).ownerOf(id);
        // Refund left overs
        if (token0==suppliedTokens[0] && token1==suppliedTokens[1]) {
            IERC20(token0).safeTransfer(owner, suppliedAmounts[0]-a0);
            IERC20(token1).safeTransfer(owner, suppliedAmounts[1]-a1);
        } else {
            IERC20(token0).safeTransfer(owner, suppliedAmounts[1]-a0);
            IERC20(token1).safeTransfer(owner, suppliedAmounts[0]-a1);
        }
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
        IERC20(token0).safeTransfer(receiver, token0Amount);
        IERC20(token1).safeTransfer(receiver, token1Amount);
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

    function getRatio(address manager, uint tokenId) external override view returns (address[] memory tokens, uint[] memory ratios) {
        (,,address token0, address token1, uint24 fee, int24 tick0, int24 tick1,,,,,) = INonfungiblePositionManager(manager).positions(tokenId);
        IUniswapV3Factory factory = IUniswapV3Factory(INonfungiblePositionManager(manager).factory());
        IUniswapV3Pool pool = IUniswapV3Pool(factory.getPool(token0, token1, fee));
        (uint160 sqrtPriceX96, , , , , , ) = pool.slot0();
        tokens = new address[](2);
        tokens[0] = token0;
        tokens[1] = token1;
        ratios = new uint[](2);
        {
            uint128 liquidity = LiquidityAmounts.getLiquidityForAmounts(sqrtPriceX96, TickMath.getSqrtRatioAtTick(tick0), TickMath.getSqrtRatioAtTick(tick1), 1e18, 1e18);
            (uint amount0, uint amount1) = LiquidityAmounts.getAmountsForLiquidity(sqrtPriceX96, TickMath.getSqrtRatioAtTick(tick0), TickMath.getSqrtRatioAtTick(tick1), liquidity);
            uint price;
            uint MAX = 2**256 - 1;
            if (uint(sqrtPriceX96)*uint(sqrtPriceX96)>MAX/1e18) {
                price = (uint(sqrtPriceX96)*uint(sqrtPriceX96)>>(96 * 2))*1e18;
            } else {
                price = uint(sqrtPriceX96)*uint(sqrtPriceX96)*1e18 >> (96 * 2);
            }
                ratios[0] = amount0;
                ratios[1] = amount1*1e18/price;
        }
    }

    function getRewardsForPosition(address manager, uint tokenId) override external view returns (address[] memory rewards, uint[] memory amounts) {
        (,,address token0, address token1,,,,,,,uint128 fee0, uint128 fee1) = INonfungiblePositionManager(manager).positions(tokenId);
        rewards = new address[](2);
        rewards[0] = token0;
        rewards[1] = token1;
        amounts =  new uint[](2);
        amounts[0] = fee0;
        amounts[1] = fee1;
    }

    function getPositionUnderlying(address manager, uint tokenId) override external view returns (address[] memory tokens, uint[] memory amounts) {
        (,,address token0, address token1, uint24 fee, int24 tickLower, int24 tickUpper, uint128 liquidity,,,,) = INonfungiblePositionManager(manager).positions(tokenId);
        IUniswapV3Pool pool = IUniswapV3Pool(
            IUniswapV3Factory(INonfungiblePositionManager(manager).factory()).getPool(token0, token1, fee)
        );
        (uint160 sqrtRatioX96,,,,,,) = pool.slot0();
        (uint amount0, uint amount1) = LiquidityAmounts.getAmountsForLiquidity(
        sqrtRatioX96, TickMath.getSqrtRatioAtTick(tickLower), TickMath.getSqrtRatioAtTick(tickUpper), liquidity);
        tokens = new address[](2);
        tokens[0] = token0;
        tokens[1] = token1;
        amounts =  new uint[](2);
        amounts[0] = amount0;
        amounts[1] = amount1;
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