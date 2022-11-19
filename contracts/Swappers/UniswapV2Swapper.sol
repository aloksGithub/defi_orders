// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "../interfaces/UniswapV2/IUniswapV2Router02.sol";
import "../interfaces/UniswapV2/IUniswapV2Pair.sol";
import "../interfaces/UniswapV2/IUniswapV2Factory.sol";
import "../interfaces/ISwapper.sol";
import "hardhat/console.sol";

contract UniswapV2Swapper is ISwapper, Ownable {
    using SafeERC20 for IERC20;

    address public router;
    address[] public commonPoolTokens; // Common pool tokens are used to test different swap paths with commonly used pool tokens to find the best swaps

    constructor(address _router, address[] memory _commonPoolTokens) {
        router = _router;
        commonPoolTokens = _commonPoolTokens;
    }

    function getNumCommonPoolTokens() external view returns (uint) {
        return commonPoolTokens.length;
    }

    function swap(
        uint256 amount,
        address[] memory path,
        address self
    ) payable external returns (uint256 obtained) {
        if (path.length==0 || path[0] == path[path.length-1] || amount==0) {
            return amount;
        }
        IUniswapV2Router02 routerContract = IUniswapV2Router02(UniswapV2Swapper(self).router());
        IERC20(path[0]).safeIncreaseAllowance(address(routerContract), amount);
        uint[] memory amountsOut = routerContract.getAmountsOut(amount, path);
        if (amountsOut[amountsOut.length-1]==0) return 0;
        routerContract.swapExactTokensForTokens(amount, 0, path, address(this), block.timestamp);
        return amountsOut[amountsOut.length-1];
    }

    function _findBestPool(address token, IUniswapV2Router02 routerContract) internal view returns (address) {
        address bestPairToken;
        uint maxTokenAmount;
        IUniswapV2Factory factory = IUniswapV2Factory(routerContract.factory());
        for (uint i = 0; i<commonPoolTokens.length; i++) {
            address pairAddress = factory.getPair(token, commonPoolTokens[i]);
            if (pairAddress!=address(0)) {
                IUniswapV2Pair pair = IUniswapV2Pair(pairAddress);
                (uint r0, uint r1,) = pair.getReserves();
                uint tokenAvailable = pair.token0()==token?r0:r1;
                if (tokenAvailable>maxTokenAmount) {
                    maxTokenAmount = tokenAvailable;
                    bestPairToken = pair.token0()==token?pair.token1():pair.token0();
                }
            }
        }
        return bestPairToken;
    }

    function getAmountOut(address inToken, uint amount, address outToken) external view returns (uint, address[] memory) {
        IUniswapV2Router02 routerContract = IUniswapV2Router02(router);
        // Note: Finish code to use pool reserves to determine which path to take
        address bestInTokenPair = _findBestPool(inToken, routerContract);
        address bestOutTokenPair = _findBestPool(outToken, routerContract);
        uint amountOutSingleSwap;
        address[] memory pathSingle = new address[](2);
        {
            pathSingle[0] = inToken;
            pathSingle[1] = outToken;
            try routerContract.getAmountsOut(amount, pathSingle) returns (uint256[] memory amountsOut) {
                amountOutSingleSwap = amountsOut[amountsOut.length - 1];
            } catch{}
        }
        uint amountOutMultiHop;
        address[] memory pathMultiHop;
        {
            if (bestInTokenPair!=bestOutTokenPair) {
                pathMultiHop = new address[](4);
                pathMultiHop[0] = inToken;
                pathMultiHop[1] = bestInTokenPair;
                pathMultiHop[2] = bestOutTokenPair;
                pathMultiHop[3] = outToken;
            } else {
                pathMultiHop = new address[](3);
                pathMultiHop[0] = inToken;
                pathMultiHop[1] = bestInTokenPair;
                pathMultiHop[2] = outToken;

            }
            try routerContract.getAmountsOut(amount, pathMultiHop) returns (uint256[] memory amountsOut) {
                amountOutMultiHop = amountsOut[amountsOut.length - 1];
            } catch{}

        }
        uint amountOutNetworkToken;
        address[] memory pathNetworkToken;
        {
            pathNetworkToken = new address[](3);
            pathNetworkToken[0] = inToken;
            pathNetworkToken[1] = commonPoolTokens[0];
            pathNetworkToken[2] = outToken;
            try routerContract.getAmountsOut(amount, pathNetworkToken) returns (uint256[] memory amountsOut) {
                amountOutNetworkToken = amountsOut[amountsOut.length - 1];
            } catch{}

        }
        if (amountOutNetworkToken>amountOutMultiHop && amountOutNetworkToken>amountOutSingleSwap) {
            return (amountOutNetworkToken, pathNetworkToken);
        } else if (amountOutMultiHop>amountOutNetworkToken && amountOutMultiHop>amountOutSingleSwap) {
            return (amountOutMultiHop, pathMultiHop);
        } else {
            return (amountOutSingleSwap, pathSingle);
        }
        // address[] memory bestPath;
        // address[] memory path = new address[](2);
        // path[0] = inToken;
        // path[1] = outToken;
        // try routerContract.getAmountsOut(amount, path) returns (uint256[] memory amountsOut) {
        //     if (amountsOut[amountsOut.length - 1]>maxAmountOut) {
        //         maxAmountOut = amountsOut[amountsOut.length - 1];
        //         bestPath = path;
        //     }
        // } catch{}
        // for (uint j = 0; j<commonPoolTokens.length; j++) {
        //     path = new address[](3);
        //     path[0] = inToken;
        //     path[1] = commonPoolTokens[j];
        //     path[2] = outToken;
        //     try routerContract.getAmountsOut(amount, path) returns (uint256[] memory amountsOut) {
        //         if (amountsOut[amountsOut.length - 1]>maxAmountOut) {
        //             maxAmountOut = amountsOut[amountsOut.length - 1];
        //             bestPath = path;
        //         }
        //     } catch{}
        // }
        // return (maxAmountOut, bestPath);
    }

    function checkSwappable(address inToken, address outToken)
        external
        view
        returns (bool)
    {
        if (inToken == outToken) return true;
        address factoryAddress = IUniswapV2Router02(router).factory();
        IUniswapV2Factory factory = IUniswapV2Factory(factoryAddress);
        address pair = factory.getPair(inToken, outToken);
        if (pair!=address(0)) {
            return true;
        }
        return false;
    }
}
