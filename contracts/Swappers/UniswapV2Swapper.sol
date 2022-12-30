// SPDX-License-Identifier: BUSL 1.1
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/access/Ownable.sol";
import "../interfaces/UniswapV2/IUniswapV2Router02.sol";
import "../interfaces/UniswapV2/IUniswapV2Pair.sol";
import "../interfaces/UniswapV2/IUniswapV2Factory.sol";
import "../interfaces/ISwapper.sol";
import "../libraries/SaferERC20.sol";
import "hardhat/console.sol";

contract UniswapV2Swapper is ISwapper, Ownable {
    using SaferERC20 for IERC20;

    IUniswapV2Router02 public router;
    address[] public commonPoolTokens; // Common pool tokens are used to test different swap paths with commonly used pool tokens to find the best swaps

    constructor(address _router, address[] memory _commonPoolTokens) {
        router = IUniswapV2Router02(_router);
        commonPoolTokens = _commonPoolTokens;
    }

    function getCommonPoolTokens() external view returns (address[] memory) {
        return commonPoolTokens;
    }

    function swap(uint256 amount, address[] memory path, address self) external payable returns (uint256 obtained) {
        if (path.length == 0 || path[0] == path[path.length - 1] || amount == 0) {
            return amount;
        }
        IUniswapV2Router02 routerContract = IUniswapV2Router02(UniswapV2Swapper(self).router());
        IERC20(path[0]).safeIncreaseAllowance(address(routerContract), amount);
        try routerContract.getAmountsOut(amount, path) returns (uint256[] memory amountsOut) {
            if (amountsOut[amountsOut.length - 1] == 0) return 0;
            routerContract.swapExactTokensForTokens(amount, 0, path, address(this), block.timestamp);
            return amountsOut[amountsOut.length - 1];
        } catch {
            return 0;
        }
    }

    function _findBestPool(address token, IUniswapV2Router02 routerContract) internal view returns (address) {
        address bestPairToken;
        uint256 maxTokenAmount;
        IUniswapV2Factory factory = IUniswapV2Factory(routerContract.factory());
        for (uint256 i = 0; i < commonPoolTokens.length; i++) {
            address pairAddress = factory.getPair(token, commonPoolTokens[i]);
            if (pairAddress != address(0)) {
                IUniswapV2Pair pair = IUniswapV2Pair(pairAddress);
                (uint256 r0, uint256 r1, ) = pair.getReserves();
                uint256 tokenAvailable = pair.token0() == token ? r0 : r1;
                if (tokenAvailable > maxTokenAmount) {
                    maxTokenAmount = tokenAvailable;
                    bestPairToken = pair.token0() == token ? pair.token1() : pair.token0();
                }
            }
        }
        return bestPairToken;
    }

    function getAmountOut(
        address inToken,
        uint256 amount,
        address outToken
    ) external view returns (uint256, address[] memory) {
        IUniswapV2Router02 routerContract = router;
        address bestInTokenPair = _findBestPool(inToken, routerContract);
        address bestOutTokenPair = _findBestPool(outToken, routerContract);
        uint256 amountOutSingleSwap;
        address[] memory pathSingle = new address[](2);
        {
            pathSingle[0] = inToken;
            pathSingle[1] = outToken;
            try routerContract.getAmountsOut(amount, pathSingle) returns (uint256[] memory amountsOut) {
                amountOutSingleSwap = amountsOut[amountsOut.length - 1];
            } catch {}
        }
        uint256 amountOutMultiHop;
        address[] memory pathMultiHop;
        {
            pathMultiHop = new address[](4);
            pathMultiHop[0] = inToken;
            pathMultiHop[1] = bestInTokenPair;
            pathMultiHop[2] = bestOutTokenPair;
            pathMultiHop[3] = outToken;
            try routerContract.getAmountsOut(amount, pathMultiHop) returns (uint256[] memory amountsOut) {
                amountOutMultiHop = amountsOut[amountsOut.length - 1];
            } catch {}
            address[] memory tripplePath = new address[](3);
            tripplePath[0] = inToken;
            tripplePath[1] = bestInTokenPair;
            tripplePath[2] = outToken;
            try routerContract.getAmountsOut(amount, tripplePath) returns (uint256[] memory amountsOut) {
                if (amountsOut[amountsOut.length - 1] > amountOutMultiHop) {
                    amountOutMultiHop = amountsOut[amountsOut.length - 1];
                    pathMultiHop = tripplePath;
                }
            } catch {}
            tripplePath = new address[](3);
            tripplePath[0] = inToken;
            tripplePath[1] = bestOutTokenPair;
            tripplePath[2] = outToken;
            try routerContract.getAmountsOut(amount, tripplePath) returns (uint256[] memory amountsOut) {
                if (amountsOut[amountsOut.length - 1] > amountOutMultiHop) {
                    amountOutMultiHop = amountsOut[amountsOut.length - 1];
                    pathMultiHop = tripplePath;
                }
            } catch {}
        }
        // uint amountOutNetworkToken;
        // address[] memory pathNetworkToken;
        // {
        //     pathNetworkToken = new address[](3);
        //     pathNetworkToken[0] = inToken;
        //     pathNetworkToken[1] = commonPoolTokens[0];
        //     pathNetworkToken[2] = outToken;
        //     try routerContract.getAmountsOut(amount, pathNetworkToken) returns (uint256[] memory amountsOut) {
        //         amountOutNetworkToken = amountsOut[amountsOut.length - 1];
        //     } catch{}

        // }
        if (amountOutMultiHop > amountOutSingleSwap) {
            return (amountOutMultiHop, pathMultiHop);
        } else {
            return (amountOutSingleSwap, pathSingle);
        }
        // if (amountOutNetworkToken>=amountOutMultiHop && amountOutNetworkToken>=amountOutSingleSwap) {
        //     return (amountOutNetworkToken, pathNetworkToken);
        // } else if (amountOutMultiHop>=amountOutNetworkToken && amountOutMultiHop>=amountOutSingleSwap) {
        //     return (amountOutMultiHop, pathMultiHop);
        // } else {
        //     return (amountOutSingleSwap, pathSingle);
        // }
    }

    function _calculateAmountsUsed(
        address tokenIn,
        address pathAddress,
        uint[][][] memory amountsForSwaps,
        SwapPoint[] memory priorSwaps
    ) internal view returns (uint tokenInAmount, uint tokenOutAmount) {
        for (uint priorSwapIndex = 0; priorSwapIndex < priorSwaps.length; priorSwapIndex++) {
            SwapPoint memory priorSwap = priorSwaps[priorSwapIndex];
            for (uint priorSwapperIndex = 0; priorSwapperIndex < priorSwap.swappers.length; priorSwapperIndex++) {
                if (priorSwap.swappers[priorSwapperIndex] == address(this)) {
                    for (
                        uint priorSwapperPathIndex = 1;
                        priorSwapperPathIndex < priorSwap.paths[priorSwapperIndex].length;
                        priorSwapperPathIndex++
                    ) {
                        address tokenInPrior = priorSwap.paths[priorSwapperIndex][priorSwapperPathIndex - 1];
                        address tokenOutPrior = priorSwap.paths[priorSwapperIndex][priorSwapperPathIndex];
                        if (tokenInPrior == tokenIn && tokenOutPrior == pathAddress) {
                            tokenInAmount += amountsForSwaps[priorSwapIndex][priorSwapperIndex][
                                priorSwapperPathIndex - 1
                            ];
                        } else if (tokenInPrior == pathAddress && tokenOutPrior == tokenIn) {
                            tokenOutAmount += amountsForSwaps[priorSwapIndex][priorSwapperIndex][
                                priorSwapperPathIndex - 1
                            ];
                        }
                    }
                }
            }
        }
    }

    function _calculateAmountOut(
        address tokenIn,
        address tokenOut,
        uint amountIn,
        uint tokenInAmount,
        uint tokenOutAmount
    ) internal view returns (uint amountOut) {
        IUniswapV2Factory factory = IUniswapV2Factory(router.factory());
        IUniswapV2Pair pair = IUniswapV2Pair(factory.getPair(tokenIn, tokenOut));
        uint rIn;
        uint rOut;
        if (pair.token0() == tokenIn) {
            (rIn, rOut, ) = pair.getReserves();
        } else {
            (rOut, rIn, ) = pair.getReserves();
        }
        try router.getAmountOut(tokenInAmount, rIn, rOut) returns (uint256 amount) {
            rIn += tokenInAmount;
            rOut -= amount;
        } catch {}
        try router.getAmountOut(tokenOutAmount, rOut, rIn) returns (uint256 amount) {
            rOut += tokenOutAmount;
            rIn -= amount;
        } catch {}
        try router.getAmountOut(amountIn, rIn, rOut) returns (uint256 amount) {
            return amount;
        } catch {
            return 0;
        }
    }

    function getAmountsOutWithPath(
        uint256 amount,
        address[] memory path,
        uint[][][] memory amountsForSwaps,
        SwapPoint[] memory priorSwaps
    ) external view returns (uint256[] memory amountsOut) {
        if (path.length == 0 || path[0] == path[path.length - 1] || amount == 0) {
            amountsOut = new uint[](2);
            amountsOut[0] = amount;
            amountsOut[1] = amount;
            return amountsOut;
        }
        amountsOut = new uint[](path.length);
        amountsOut[0] = amount;
        for (uint i = 1; i < path.length; i++) {
            (uint tokenInAmount, uint tokenOutAmount) = _calculateAmountsUsed(
                path[i - 1],
                path[i],
                amountsForSwaps,
                priorSwaps
            );
            amountsOut[i] = _calculateAmountOut(path[i - 1], path[i], amountsOut[i - 1], tokenInAmount, tokenOutAmount);
            address[] memory tempPath = new address[](2);
            tempPath[0] = path[i - 1];
            tempPath[1] = path[i];
        }
        // try router.getAmountsOut(amount, path) returns (
        //     uint256[] memory amountsOut
        // ) {
        //     amounts = amountsOut;
        //     return amounts;
        // } catch {
        //     amounts = new uint[](1);
        //     amounts[0] = 0;
        //     return amounts;
        // }
    }

    function getAmountOut2(uint256 amount, address[] memory path) public view returns (uint256) {
        try router.getAmountsOut(amount, path) returns (uint256[] memory amountsOut) {
            return amountsOut[amountsOut.length - 1];
        } catch {
            return 0;
        }
    }

    function getPrice(address token, address inTermsOf) public view returns (uint256) {
        if (token == inTermsOf) return (uint256(10) ** ERC20(token).decimals());
        IUniswapV2Factory factory = IUniswapV2Factory(router.factory());
        address poolAddress = factory.getPair(token, inTermsOf);
        if (poolAddress != address(0)) {
            IUniswapV2Pair pair = IUniswapV2Pair(poolAddress);
            (uint256 r0, uint256 r1, ) = pair.getReserves();
            if (token == pair.token0()) {
                return ((r1 * uint256(10) ** ERC20(token).decimals()) / r0);
            } else {
                return ((r0 * uint256(10) ** ERC20(token).decimals()) / r1);
            }
        }
        return 0;
    }

    function checkSwappable(address inToken) external view returns (bool) {
        address factoryAddress = router.factory();
        IUniswapV2Factory factory = IUniswapV2Factory(factoryAddress);
        for (uint256 i = 0; i < commonPoolTokens.length; i++) {
            if (inToken == commonPoolTokens[i]) return true;
            uint256 tokenWorth = getPrice(commonPoolTokens[i], commonPoolTokens[1]);
            address pair = factory.getPair(inToken, commonPoolTokens[i]);
            if (pair == address(0)) continue;
            uint256 bal = IERC20(commonPoolTokens[i]).balanceOf(pair);
            uint256 poolUsd = (bal * tokenWorth) /
                (10 ** ERC20(commonPoolTokens[i]).decimals() * 10 ** ERC20(commonPoolTokens[1]).decimals());
            if (poolUsd > 1000) {
                return true;
            }
        }
        // if (inToken == commonPoolTokens[0]) return true;
        // address pair = factory.getPair(inToken, commonPoolTokens[0]);
        // if (pair!=address(0)) {
        //     (uint r0, uint r1,) = IUniswapV2Pair(pair).getReserves();
        //     if (IUniswapV2Pair(pair).token0()==commonPoolTokens[0]) {

        //     }
        //     return true;
        // }
        return false;
    }
}
