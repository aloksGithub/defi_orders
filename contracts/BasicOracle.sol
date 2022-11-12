// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "./interfaces/IOracle.sol";
import "./interfaces/UniswapV2/IUniswapV2Factory.sol";
import "./interfaces/UniswapV2/IUniswapV2Pair.sol";
import "./interfaces/UniswapV3/IUniswapV3Factory.sol";
import "./interfaces/UniswapV3/IUniswapV3Pool.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./libraries/TickMath.sol";
import "./libraries/FullMath.sol";
import "./libraries/FixedPoint96.sol";
import "hardhat/console.sol";

contract UniswapV3Source is IOracle {
    IUniswapV3Factory factory;
    address[] commonPoolTokens;

    constructor(address _factory) {
        factory = IUniswapV3Factory(_factory);
    }
    
    function getSqrtTwapX96(address uniswapV3Pool, uint32 twapInterval) public view returns (uint160 sqrtPriceX96) {
        if (twapInterval == 0) {
            (sqrtPriceX96, , , , , , ) = IUniswapV3Pool(uniswapV3Pool).slot0();
        } else {
            uint32[] memory secondsAgos = new uint32[](2);
            secondsAgos[0] = twapInterval;
            secondsAgos[1] = 0;
            (int56[] memory tickCumulatives, ) = IUniswapV3Pool(uniswapV3Pool).observe(secondsAgos);
            sqrtPriceX96 = TickMath.getSqrtRatioAtTick(
                int24((tickCumulatives[1] - tickCumulatives[0]) / int56(uint56(twapInterval)))
            );
        }
    }

    function getPrice1X96FromSqrtPriceX96(uint160 sqrtPriceX96, uint decimals) public pure returns(uint256 priceX96) {
        uint MAX_INT = 2**256-1;
        if (uint(sqrtPriceX96)*uint(sqrtPriceX96)>MAX_INT/1e18) {
            return decimals*(uint(sqrtPriceX96)*uint(sqrtPriceX96)>>(96 * 2));
        } else {
            return (decimals*uint(sqrtPriceX96)*uint(sqrtPriceX96)>>(96 * 2));
        }
    }

    function getPrice0X96FromSqrtPriceX96(uint160 sqrtPriceX96, uint decimals) public pure returns(uint256 priceX96) {
        return (decimals*2**192)/(uint(sqrtPriceX96)**2);
    }

    function getMainPair(address token0, address token1) public view returns (address) {
        uint16[4] memory availableFees = [100, 500, 3000, 10000];
        uint maxLiquidity = 0;
        address mainPool;
        for (uint i = 0; i<availableFees.length; i++) {
            address poolAddress = factory.getPool(token0, token1, availableFees[i]);
            if (poolAddress!=address(0)) {
                uint liquidity = IUniswapV3Pool(poolAddress).liquidity();
                if (liquidity>maxLiquidity) {
                    maxLiquidity = liquidity;
                    mainPool = poolAddress;
                }
            }
        }
        return mainPool;
    }

    function getPrice(address token, address inTermsOf) public view returns (uint) {
        address mainPool = getMainPair(token, inTermsOf);
        if (mainPool!=address(0)) {
            IUniswapV3Pool pool = IUniswapV3Pool(mainPool);
            uint160 sqrtTwapX96 = getSqrtTwapX96(mainPool, 60);
            if (token==pool.token0()) {
                return getPrice1X96FromSqrtPriceX96(sqrtTwapX96, uint(10)**ERC20(token).decimals());
            } else {
                return getPrice0X96FromSqrtPriceX96(sqrtTwapX96, uint(10)**ERC20(token).decimals());
            }
        }
        for (uint i = 0; i<commonPoolTokens.length; i++) {
            address poolAddress = getMainPair(token, commonPoolTokens[i]);
            if (poolAddress!=address(0)) {
                IUniswapV3Pool pair = IUniswapV3Pool(poolAddress);
                uint priceOfCommonPoolToken = getPrice(commonPoolTokens[i], inTermsOf);
                uint priceIntermediate;
                uint160 sqrtTwapX96 = getSqrtTwapX96(poolAddress, 60);
                if (token==pair.token0()) {
                    priceIntermediate = getPrice1X96FromSqrtPriceX96(sqrtTwapX96, uint(10)**ERC20(token).decimals());
                } else {
                    priceIntermediate = getPrice0X96FromSqrtPriceX96(sqrtTwapX96, uint(10)**ERC20(token).decimals());
                }
                return priceIntermediate*priceOfCommonPoolToken/uint(10)**ERC20(commonPoolTokens[i]).decimals();
            }
        }
        return 0;
    }
}

contract UniswapV2Source is IOracle {
    IUniswapV2Factory factory;
    address[] commonPoolTokens;

    constructor(address _factory) {
        factory = IUniswapV2Factory(_factory);
    }

    function getPrice(address token, address inTermsOf) public view returns (uint) {
        address poolAddress = factory.getPair(token, inTermsOf);
        if (poolAddress!=address(0)) {
            IUniswapV2Pair pair = IUniswapV2Pair(poolAddress);
            (uint r0, uint r1,) = pair.getReserves();
            if (token==pair.token0()) {
                return (r1*uint(10)**ERC20(token).decimals()/r0);
            } else {
                return (r0*uint(10)**ERC20(token).decimals()/r1);
            }
        }
        for (uint i = 0; i<commonPoolTokens.length; i++) {
            poolAddress = factory.getPair(token, commonPoolTokens[i]);
            if (poolAddress!=address(0)) {
                IUniswapV2Pair pair = IUniswapV2Pair(poolAddress);
                uint priceOfCommonPoolToken = getPrice(commonPoolTokens[i], inTermsOf);
                (uint r0, uint r1,) = pair.getReserves();
                uint priceIntermediate;
                if (token==pair.token0()) {
                    priceIntermediate = (r1*uint(10)**ERC20(token).decimals()/r0);
                } else {
                    priceIntermediate = (r0*uint(10)**ERC20(token).decimals()/r1);
                }
                return priceIntermediate*priceOfCommonPoolToken/uint(10)**ERC20(commonPoolTokens[i]).decimals();
            }
        }
        return 0;
    }
}

contract BasicOracle is IOracle, Ownable {
    IOracle[] public sources;

    constructor(IOracle[] memory _sources) {
        sources = _sources;
    }

    function setSources(IOracle[] memory _sources) external onlyOwner {
        sources = _sources;
    }

    function _calculateMean(uint[] memory prices) internal pure returns (uint) {
        uint total;
        uint numPrices;
        for (uint i = 0; i<prices.length; i++) {
            if (prices[i]>0) {
                total+=prices[i];
                numPrices+=1;
            }
        }
        return total/numPrices;
    }

    function getPrice(address token, address inTermsOf) external view returns (uint) {
        uint[] memory prices = new uint[](sources.length);
        for (uint i = 0; i<sources.length; i++) {
            prices[i] = sources[i].getPrice(token, inTermsOf);
        }
        return _calculateMean(prices);
    }
}