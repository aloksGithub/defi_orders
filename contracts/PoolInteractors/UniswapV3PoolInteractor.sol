// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "../interfaces/IPoolInteractor.sol";
import "../interfaces/UniswapV3/INonfungiblePositionManager.sol";
import "../interfaces/UniswapV3/IUniswapV3Pool.sol";
import "../libraries/Strings.sol";
import "../interfaces/INFTPoolInteractor.sol";
import '../libraries/TickMath.sol';
import "../libraries/LiquidityAmounts.sol";
import "hardhat/console.sol";

contract UniswapV3PoolInteractor is INFTPoolInteractor, Ownable {
    using SafeERC20 for IERC20;

    address public supportedManager;

    constructor(address _supportedManager) {
        supportedManager = _supportedManager;
    }
    
    function burn(Asset memory asset) payable external returns (address[] memory receivedTokens, uint256[] memory receivedTokenAmounts) {
        (,,address token0, address token1,,,,,,,,) = INonfungiblePositionManager(asset.manager).positions(asset.tokenId);
        INonfungiblePositionManager.DecreaseLiquidityParams memory withdrawParams = INonfungiblePositionManager.DecreaseLiquidityParams(
            asset.tokenId,
            uint128(asset.liquidity),
            0, 0, block.timestamp
        );
        (uint token0Amount, uint token1Amount) = INonfungiblePositionManager(asset.manager).decreaseLiquidity(withdrawParams);
        INonfungiblePositionManager.CollectParams memory params = INonfungiblePositionManager.CollectParams(
            asset.tokenId,
            address(this),
            uint128(token0Amount),
            uint128(token1Amount)
        );
        INonfungiblePositionManager(asset.manager).collect(params);
        receivedTokens = new address[](2);
        receivedTokens[0] = token0;
        receivedTokens[1] = token1;
        receivedTokenAmounts = new uint[](2);
        receivedTokenAmounts[0] = token0Amount;
        receivedTokenAmounts[1] = token1Amount;
        IERC721(asset.manager).transferFrom(address(this), msg.sender, asset.tokenId);
    }

    function getRatio(address poolAddress, int24 tick0, int24 tick1) external view returns (uint, uint) {
        IUniswapV3Pool pool = IUniswapV3Pool(poolAddress);
        (uint160 sqrtPriceX96, , , , , , ) = pool.slot0();
        uint160 sqrtRatioAX96 = TickMath.getSqrtRatioAtTick(tick0);
        uint160 sqrtRatioBX96 = TickMath.getSqrtRatioAtTick(tick1);
        uint128 liquidity = LiquidityAmounts.getLiquidityForAmounts(sqrtPriceX96, sqrtRatioAX96, sqrtRatioBX96, 1e18, 1e18);
        (uint amount0, uint amount1) = LiquidityAmounts.getAmountsForLiquidity(sqrtPriceX96, sqrtRatioAX96, sqrtRatioBX96, liquidity);
        uint MAX = 2**256 - 1;
        if (uint(sqrtPriceX96)*uint(sqrtPriceX96)>MAX/1e18) {
            uint price = (uint(sqrtPriceX96)*uint(sqrtPriceX96)>>(96 * 2))*1e18;
            return (amount0, amount1*1e18/price);
        } else {
            uint price = uint(sqrtPriceX96)*uint(sqrtPriceX96)*1e18 >> (96 * 2);
            return (amount0, amount1*1e18/price);
        }
    }

    function mint(Asset memory toMint, address[] memory underlyingTokens, uint256[] memory underlyingAmounts, address receiver) payable external returns (uint256) {
        IUniswapV3Pool pool = IUniswapV3Pool(toMint.pool);
        address token0 = pool.token0();
        address token1 = pool.token1();
        require((token0==underlyingTokens[0] && token1==underlyingTokens[1]), "Invalid input");
        INonfungiblePositionManager.MintParams memory mintParams;
        for (uint i=0; i<underlyingAmounts.length; i++) {
            IERC20(underlyingTokens[i]).safeIncreaseAllowance(toMint.manager, underlyingAmounts[i]);
        }
        uint24 fees = pool.fee();
        uint minAmount0; uint minAmount1;
        {
            (int24 tick0, int24 tick1, uint m0, uint m1) = abi.decode(toMint.data, (int24, int24, uint, uint));
            minAmount0 = m0;
            minAmount1 = m1;
            mintParams = INonfungiblePositionManager.MintParams(
                token0, token1, fees,
                tick0, tick1,
                underlyingAmounts[0], underlyingAmounts[1],
                0, 0,
                receiver, block.timestamp
            );
        }
        (uint256 tokenId,,uint amount0, uint amount1) = INonfungiblePositionManager(toMint.manager).mint(mintParams);
        require(amount0>minAmount0 && amount1>minAmount1, "Failed slippage check");
        return tokenId;
    }
    
    function testSupported(address token) external view returns (bool) {
        if (token==supportedManager) {
            return true;
        }
        return false;
    }

    function testSupportedPool(address poolAddress) external view returns (bool) {
        IUniswapV3Pool pool = IUniswapV3Pool(poolAddress);
        // (bool success, bytes memory returnData) = poolAddress.staticcall(abi.encodeWithSelector(
        //     pool.factory.selector));
        // if (success) {
        //     (address factory) = abi.decode(returnData, (address));
        //     if (factory==INonfungiblePositionManager(supportedManager).factory()) return true;
        // }
        // return false;
        try pool.factory() returns (address factory) {
            if (factory==INonfungiblePositionManager(supportedManager).factory()) {
                return true;
            }
            return false;
        } catch {return false;} 
    }

    function getUnderlyingAmount(Asset memory nft) external view returns (address[] memory underlying, uint[] memory amounts) {
        IUniswapV3Pool pool = IUniswapV3Pool(nft.pool);
        underlying = getUnderlyingTokens(nft.pool);
        (uint160 sqrtPriceX96, , , , , , ) = pool.slot0();
        (int24 tick0, int24 tick1,,) = abi.decode(nft.data, (int24, int24, uint, uint));
        (uint amount0, uint amount1) = LiquidityAmounts.getAmountsForLiquidity(sqrtPriceX96, TickMath.getSqrtRatioAtTick(tick0), TickMath.getSqrtRatioAtTick(tick1), uint128(nft.liquidity));
        amounts = new uint[](2);
        amounts[0] = amount0;
        amounts[1] = amount1;
    }

    function getUnderlyingTokens(address lpTokenAddress) public view returns (address[] memory) {
        IUniswapV3Pool pool = IUniswapV3Pool(lpTokenAddress);
        address[] memory receivedTokens = new address[](2);
        receivedTokens[0] = pool.token0();
        receivedTokens[1] = pool.token1();
        return receivedTokens;
    }

    function getTickAtRatio(uint160 ratio) external pure returns (int24) {
        return TickMath.getTickAtSqrtRatio(ratio);
    }
}