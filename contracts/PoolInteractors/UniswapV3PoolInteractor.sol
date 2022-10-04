// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "../interfaces/IPoolInteractor.sol";
import "../interfaces/UniswapV3/INonfungiblePositionManager.sol";
import "../interfaces/UniswapV3/IUniswapV3Pool.sol";
import "../libraries/Strings.sol";
import "../interfaces/INFTPoolInteractor.sol";
import "../interfaces/UniswapV2/IUniswapV2Router02.sol";
import "../interfaces/UniswapV2/IUniswapV2Factory.sol";
import "../interfaces/UniswapV2/IUniswapV2Pair.sol";
import "hardhat/console.sol";

contract UniswapV3PoolInteractor is INFTPoolInteractor, Ownable {
    using strings for *;
    using SafeERC20 for IERC20;

    address[] supportedManagers;
    IUniswapV2Router02 router;
    IUniswapV2Factory factory;

    constructor(address[] memory _supportedManagers, address _router) {
        supportedManagers = _supportedManagers;
        router = IUniswapV2Router02(_router);
        factory = IUniswapV2Factory(router.factory());
    }

    function setSupportedManagers(address[] memory _supportedManagers) external onlyOwner {
        supportedManagers = _supportedManagers;
    }
    
    function burn(Asset memory asset) external returns (address[] memory receivedTokens, uint256[] memory receivedTokenAmounts) {
        (,,address token0, address token1,,,,uint128 liquidity,,,,) = INonfungiblePositionManager(asset.manager).positions(asset.tokenId);
        INonfungiblePositionManager.DecreaseLiquidityParams memory withdrawParams = INonfungiblePositionManager.DecreaseLiquidityParams(
            asset.tokenId,
            liquidity,
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
        IERC20(token0).safeTransfer(msg.sender, token0Amount);
        IERC20(token1).safeTransfer(msg.sender, token1Amount);
    }

    function sqrt(uint y) internal pure returns (uint z) {
        if (y > 3) {
            z = y;
            uint x = y / 2 + 1;
            while (x < z) {
                z = x;
                x = (y / x + x) / 2;
            }
        } else if (y != 0) {
            z = 1;
        }
    }

    function _solveQuadratic(int a, int b, int c) internal pure returns (int sol1, int sol2) {
        uint sqrtTerm = sqrt(uint(b*b-4*a*c));
        sol1 = (int(sqrtTerm)-b)/(2*a);
        sol2 = -1*(b+int(sqrtTerm))/(2*a);
    }

    function _swap() internal {
        
    }

    function _mintHelper(address token0, address token1, uint amount0, uint amount1) internal {
        uint bal0 = IERC20(token0).balanceOf(address(this));
        uint bal1 = IERC20(token1).balanceOf(address(this));
        uint wantedRatio = amount1>0?1e18*amount0/amount1:2**256 - 1;
        uint existingRatio = bal1>0?1e18*bal0/bal1:2**256 - 1;
        IUniswapV2Pair swapPool = IUniswapV2Pair(factory.getPair(token0, token1));
        (uint r0, uint r1,) = swapPool.getReserves();
        if (wantedRatio>existingRatio) { // Swap token1
            uint toConvert;
            {int const = int(amount0*bal1)-int(amount1*bal0);
            if (swapPool.token0()==token0) {
                int b = int(amount1*r0+amount0*r1)-const;
                int c = -const*int(r1);
                (int y1, int y2) = _solveQuadratic(int(amount0), b, c);
                toConvert = y1>0?uint(y1):uint(y2);
            } else {
                int b = int(amount1*r1+amount0*r0)-const;
                int c = -const*int(r0);
                (int y1, int y2) = _solveQuadratic(int(amount0), b, c);
                toConvert = y1>0?uint(y1):uint(y2);
            }}
            address[] memory path = new address[](2);
            path[0] = token1;
            path[1] = token0;
            IERC20(token1).safeIncreaseAllowance(address(router), IERC20(token1).balanceOf(address(this)));
            router.swapExactTokensForTokens(toConvert, router.getAmountsOut(toConvert, path)[1], path, address(this), block.timestamp);
        } else { // Swap token0
            uint toConvert;
            {int const = int(amount1*bal0)-int(amount0*bal1);
            if (swapPool.token0()==token0) {
                int b = int(amount1*r0+amount0*r1)-const;
                int c = -const*int(r0);
                (int y1, int y2) = _solveQuadratic(int(amount1), b, c);
                toConvert = y1>0?uint(y1):uint(y2);
            } else {
                int b = int(amount1*r1+amount0*r0)-const;
                int c = -const*int(r1);
                (int y1, int y2) = _solveQuadratic(int(amount1), b, c);
                toConvert = y1>0?uint(y1):uint(y2);
            }}
            address[] memory path = new address[](2);
            path[0] = token0;
            path[1] = token1;
            IERC20(token0).safeIncreaseAllowance(address(router), IERC20(token0).balanceOf(address(this)));
            router.swapExactTokensForTokens(toConvert, router.getAmountsOut(toConvert, path)[1], path, address(this), block.timestamp);
        }
    }

    function _increaseLiquidity(address token0, address token1, address manager, uint tokenId) internal {
        uint bal0 = IERC20(token0).balanceOf(address(this));
        uint bal1 = IERC20(token1).balanceOf(address(this));
        uint allowance0 = IERC20(token0).allowance(address(this), manager);
        uint allowance1 = IERC20(token1).allowance(address(this), manager);
        IERC20(token0).safeIncreaseAllowance(manager, bal0);
        if (allowance0<bal0) {
            IERC20(token0).safeIncreaseAllowance(manager, bal0-allowance0);
        }
        if (allowance1<bal1) {
            IERC20(token1).safeIncreaseAllowance(manager, bal1-allowance1);
        }
        INonfungiblePositionManager.IncreaseLiquidityParams memory params = INonfungiblePositionManager.IncreaseLiquidityParams(
            tokenId,
            IERC20(token0).balanceOf(address(this)), IERC20(token1).balanceOf(address(this)),
            0, 0,
            block.timestamp
        );
        INonfungiblePositionManager(manager).increaseLiquidity(params);

    }

    function mint(Asset memory toMint, address[] memory underlyingTokens, uint256[] memory underlyingAmounts) external returns (uint256) {
        IUniswapV3Pool pool = IUniswapV3Pool(toMint.pool);
        address token0 = pool.token0();
        address token1 = pool.token1();
        require((token0==underlyingTokens[0] && token1==underlyingTokens[1]), "Invalid input");
        INonfungiblePositionManager.MintParams memory mintParams;
        {for (uint i=0; i<underlyingAmounts.length; i++) {
            IERC20(underlyingTokens[i]).safeIncreaseAllowance(toMint.manager, underlyingAmounts[i]);
        }
        uint24 fees = pool.fee();
        (int24 tick0, int24 tick1) = abi.decode(toMint.data, (int24, int24));
        mintParams = INonfungiblePositionManager.MintParams(
            token0, token1, fees,
            tick0, tick1,
            underlyingAmounts[0], underlyingAmounts[1],
            100, 100,
            msg.sender, block.timestamp
        );}
        (uint256 tokenId,, uint256 amount0, uint256 amount1) = INonfungiblePositionManager(toMint.manager).mint(mintParams);
        _mintHelper(token0, token1, amount0, amount1);
        _increaseLiquidity(token0, token1, toMint.manager, tokenId);
        console.log(underlyingAmounts[0], underlyingAmounts[1], IERC20(token0).balanceOf(address(this)), IERC20(token1).balanceOf(address(this)));
        return tokenId;
    }

    function testSupported(address token) external view returns (bool) {
        for (uint i = 0; i<supportedManagers.length; i++) {
            if (token==supportedManagers[i]) {
                return true;
            }
        }
        return false;
    }

    function testSupportedPool(address poolAddress) external view returns (bool) {
        IUniswapV3Pool pool = IUniswapV3Pool(poolAddress);
        try pool.factory() returns (address factory) {
            for (uint i = 0; i<supportedManagers.length; i++) {
                if (factory==INonfungiblePositionManager(supportedManagers[i]).factory()) {
                    return true;
                }
            }
            return false;
        } catch {return false;} 
    }

    function getUnderlyingTokens(address lpTokenAddress) public view returns (address[] memory) {
        IUniswapV3Pool pool = IUniswapV3Pool(lpTokenAddress);
        address[] memory receivedTokens = new address[](2);
        receivedTokens[0] = pool.token0();
        receivedTokens[1] = pool.token1();
        return receivedTokens;
    }
}