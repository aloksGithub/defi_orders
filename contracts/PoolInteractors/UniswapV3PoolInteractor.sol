// SPDX-License-Identifier: BUSL 1.1
pragma solidity ^0.8.17;

import "../interfaces/IPoolInteractor.sol";
import "../interfaces/UniswapV3/INonfungiblePositionManager.sol";
import "../interfaces/UniswapV3/IUniswapV3Pool.sol";
import "../interfaces/UniswapV3/IUniswapV3Factory.sol";
import "../interfaces/INFTPoolInteractor.sol";
import "../libraries/TickMath.sol";
import "../libraries/LiquidityAmounts.sol";
import "hardhat/console.sol";

contract UniswapV3PoolInteractor is INFTPoolInteractor, Ownable {
    using SaferERC20 for IERC20;

    address public supportedManager;

    constructor(address _supportedManager) {
        supportedManager = _supportedManager;
    }

    function burn(
        Asset memory asset
    ) external payable returns (address[] memory receivedTokens, uint256[] memory receivedTokenAmounts) {
        (, , address token0, address token1, , , , , , , , ) = INonfungiblePositionManager(asset.manager).positions(
            asset.tokenId
        );
        INonfungiblePositionManager.DecreaseLiquidityParams memory withdrawParams = INonfungiblePositionManager
            .DecreaseLiquidityParams(asset.tokenId, uint128(asset.liquidity), 0, 0, block.timestamp);
        (uint256 token0Amount, uint256 token1Amount) = INonfungiblePositionManager(asset.manager).decreaseLiquidity(
            withdrawParams
        );
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
        receivedTokenAmounts = new uint256[](2);
        receivedTokenAmounts[0] = token0Amount;
        receivedTokenAmounts[1] = token1Amount;
        IERC721(asset.manager).transferFrom(address(this), msg.sender, asset.tokenId);
    }

    function getRatio(address poolAddress, int24 tick0, int24 tick1) external view returns (uint256, uint256) {
        IUniswapV3Pool pool = IUniswapV3Pool(poolAddress);
        (uint160 sqrtPriceX96, , , , , , ) = pool.slot0();
        int24 currentTick = TickMath.getTickAtSqrtRatio(sqrtPriceX96);
        uint absTick = currentTick < 0 ? uint(-int(currentTick)) : uint(int(currentTick));
        uint24 tickSpacing = uint24(pool.tickSpacing());
        absTick -= absTick % tickSpacing;
        currentTick = currentTick < 0 ? -int24(int(absTick)) : int24(int(absTick));

        uint160 sqrtRatioAX96 = TickMath.getSqrtRatioAtTick(tick0);
        uint160 sqrtRatioBX96 = TickMath.getSqrtRatioAtTick(tick1);
        // uint128 liquidity = LiquidityAmounts.getLiquidityForAmounts(
        //     sqrtPriceX96,
        //     sqrtRatioAX96,
        //     sqrtRatioBX96,
        //     1e18,
        //     1e18
        // );
        (uint256 amount0, uint256 amount1) = LiquidityAmounts.getAmountsForLiquidity(
            TickMath.getSqrtRatioAtTick(currentTick),
            sqrtRatioAX96,
            sqrtRatioBX96,
            pool.liquidity()
        );
        uint256 MAX = 2 ** 256 - 1;
        if (uint256(sqrtPriceX96) * uint256(sqrtPriceX96) > MAX / 1e18) {
            uint256 price = ((uint256(sqrtPriceX96) * uint256(sqrtPriceX96)) >> (96 * 2)) * 1e18;
            return (amount0, (amount1 * 1e18) / price);
        } else {
            uint256 price = (uint256(sqrtPriceX96) * uint256(sqrtPriceX96) * 1e18) >> (96 * 2);
            return (amount0, (amount1 * 1e18) / price);
        }
    }

    function mint(
        Asset memory toMint,
        address[] memory underlyingTokens,
        uint256[] memory underlyingAmounts,
        address receiver
    ) external payable returns (uint256) {
        IUniswapV3Pool pool = IUniswapV3Pool(toMint.pool);
        address token0 = pool.token0();
        address token1 = pool.token1();
        require((token0 == underlyingTokens[0] && token1 == underlyingTokens[1]), "6");
        INonfungiblePositionManager.MintParams memory mintParams;
        for (uint256 i = 0; i < underlyingAmounts.length; i++) {
            IERC20(underlyingTokens[i]).safeIncreaseAllowance(toMint.manager, underlyingAmounts[i]);
        }
        uint256 minAmount0;
        uint256 minAmount1;
        {
            uint24 fees = pool.fee();
            (int24 tick0, int24 tick1, uint256 m0, uint256 m1) = abi.decode(
                toMint.data,
                (int24, int24, uint256, uint256)
            );
            minAmount0 = m0;
            minAmount1 = m1;
            mintParams = INonfungiblePositionManager.MintParams(
                token0,
                token1,
                fees,
                tick0,
                tick1,
                underlyingAmounts[0],
                underlyingAmounts[1],
                0,
                0,
                receiver,
                block.timestamp
            );
        }
        (uint256 tokenId, , uint256 amount0, uint256 amount1) = INonfungiblePositionManager(toMint.manager).mint(
            mintParams
        );
        require(amount0 > minAmount0 && amount1 > minAmount1, "3");
        IERC20(token0).safeTransfer(receiver, underlyingAmounts[0] - amount0);
        IERC20(token1).safeTransfer(receiver, underlyingAmounts[1] - amount1);
        return tokenId;
    }

    function simulateMint(
        Asset memory toMint,
        address[] memory underlyingTokens,
        uint256[] memory underlyingAmounts
    ) external view returns (uint256 liquidity) {
        IUniswapV3Pool pool = IUniswapV3Pool(toMint.pool);
        (uint160 sqrtRatioX96, , , , , , ) = pool.slot0();
        int24 currentTick = TickMath.getTickAtSqrtRatio(sqrtRatioX96);
        uint absTick = currentTick < 0 ? uint(-int(currentTick)) : uint(int(currentTick));
        uint24 tickSpacing = uint24(pool.tickSpacing());
        absTick -= absTick % tickSpacing;
        currentTick = currentTick < 0 ? -int24(int(absTick)) : int24(int(absTick));
        (int24 tick0, int24 tick1, , ) = abi.decode(toMint.data, (int24, int24, uint256, uint256));
        uint256 amount0;
        uint256 amount1;
        if (underlyingTokens[0] == pool.token0()) {
            amount0 = underlyingAmounts[0];
            amount1 = underlyingAmounts[1];
        } else {
            amount0 = underlyingAmounts[1];
            amount1 = underlyingAmounts[0];
        }
        liquidity = LiquidityAmounts.getLiquidityForAmounts(
            TickMath.getSqrtRatioAtTick(currentTick),
            TickMath.getSqrtRatioAtTick(tick0),
            TickMath.getSqrtRatioAtTick(tick1),
            amount0,
            amount1
        );
    }

    function testSupported(address token) external view returns (bool) {
        if (token == supportedManager) {
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
            if (factory == INonfungiblePositionManager(supportedManager).factory()) {
                return true;
            }
            return false;
        } catch {
            return false;
        }
    }

    function getUnderlyingAmount(
        Asset memory nft
    ) external view returns (address[] memory underlying, uint256[] memory amounts) {
        IUniswapV3Pool pool;
        int24 tick0;
        int24 tick1;
        if (nft.tokenId == 0) {
            pool = IUniswapV3Pool(nft.pool);
            (tick0, tick1, , ) = abi.decode(nft.data, (int24, int24, uint256, uint256));
        } else {
            INonfungiblePositionManager manager = INonfungiblePositionManager(nft.manager);
            IUniswapV3Factory factory = IUniswapV3Factory(manager.factory());
            (, , address token0, address token1, uint24 fee, int24 tickLower, int24 tickUpper, , , , , ) = manager
                .positions(nft.tokenId);
            tick0 = tickLower;
            tick1 = tickUpper;
            pool = IUniswapV3Pool(factory.getPool(token0, token1, fee));
        }
        underlying = getUnderlyingTokens(address(pool));
        (uint160 sqrtPriceX96, , , , , , ) = pool.slot0();
        (uint256 amount0, uint256 amount1) = LiquidityAmounts.getAmountsForLiquidity(
            sqrtPriceX96,
            TickMath.getSqrtRatioAtTick(tick0),
            TickMath.getSqrtRatioAtTick(tick1),
            uint128(nft.liquidity)
        );
        amounts = new uint256[](2);
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
