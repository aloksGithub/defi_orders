// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "../interfaces/UniswapV2/IUniswapV2Router02.sol";
import "../interfaces/UniswapV2/IUniswapV2Factory.sol";
import "../interfaces/ISwapper.sol";
import "hardhat/console.sol";

contract UniswapV2Swapper is ISwapper, Ownable {
    using SafeERC20 for IERC20;

    address[] public routers;
    address[] public commonPoolTokens; // Common pool tokens are used to test different swap paths with commonly used pool tokens to find the best swaps

    constructor(address[] memory _routers, address[] memory _commonPoolTokens) {
        routers = _routers;
        commonPoolTokens = _commonPoolTokens;
    }

    function setRouters(address[] memory _routers) external onlyOwner {
        routers = _routers;
    }

    function getNumRouters() external view returns (uint) {
        return routers.length;
    }

    function getNumCommonPoolTokens() external view returns (uint) {
        return commonPoolTokens.length;
    }

    function swap(
        address inToken,
        uint256 amount,
        address outToken,
        address self
    ) payable external returns (uint256 obtained) {
        if (inToken == outToken) {
            return amount;
        }
        address[] memory bestPath;
        IUniswapV2Router02 bestRouter;
        uint balanceBefore = IERC20(outToken).balanceOf(address(this));
        {
            uint numCommonPools = UniswapV2Swapper(self).getNumCommonPoolTokens();
            uint maxAmountOut = 0;
            for (uint i = 0; i<UniswapV2Swapper(self).getNumRouters(); i++) {
                address[] memory path = new address[](2);
                path[0] = inToken;
                path[1] = outToken;
                IUniswapV2Router02 router = IUniswapV2Router02(UniswapV2Swapper(self).routers(i));
                try router.getAmountsOut(amount, path) returns (uint256[] memory amountsOut) {
                    if (amountsOut[amountsOut.length - 1]>maxAmountOut) {
                        maxAmountOut = amountsOut[amountsOut.length - 1];
                        bestRouter = router;
                        bestPath = new address[](path.length);
                        for (uint x = 0; x<path.length; x++) {
                            bestPath[x] = path[x];
                        }
                    }
                } catch{}
                for (uint j = 0; j<numCommonPools; j++) {
                    path = new address[](3);
                    path[0] = inToken;
                    path[1] = UniswapV2Swapper(self).commonPoolTokens(j);
                    path[2] = outToken;
                    try router.getAmountsOut(amount, path) returns (uint256[] memory amountsOut) {
                        if (amountsOut[amountsOut.length - 1]>maxAmountOut) {
                            maxAmountOut = amountsOut[amountsOut.length - 1];
                            bestRouter = router;
                            bestPath = new address[](path.length);
                            for (uint x = 0; x<path.length; x++) {
                                bestPath[x] = path[x];
                            }
                        }
                    } catch{}
                }
            }
        }
        IERC20(inToken).safeApprove(address(bestRouter), amount);
        bestRouter.swapExactTokensForTokens(amount, 0, bestPath, address(this), block.timestamp);
        // console.log(inToken, amount, outToken, IERC20(outToken).balanceOf(address(this))-balanceBefore);
        // for (uint i = 0; i<bestPath.length; i++) {
        //     console.log(bestPath[i]);
        // }
        return IERC20(outToken).balanceOf(address(this))-balanceBefore;
    }

    function getAmountOut(address inToken, uint amount, address outToken) external view returns (uint) {
        address bestRouter = address(0);
        uint maxAmountOut = 0;
        for (uint i = 0; i<routers.length; i++) {
            IUniswapV2Router02 router = IUniswapV2Router02(routers[i]);
            address[] memory path = new address[](2);
            path[0] = inToken;
            path[1] = outToken;
            try router.getAmountsOut(amount, path) returns (uint256[] memory amountsOut) {
                if (amountsOut[amountsOut.length - 1]>maxAmountOut) {
                    maxAmountOut = amountsOut[amountsOut.length - 1];
                    bestRouter = routers[i];
                }
            } catch{}
            for (uint j = 0; j<commonPoolTokens.length; j++) {
                path = new address[](3);
                path[0] = inToken;
                path[1] = commonPoolTokens[j];
                path[2] = outToken;
                try router.getAmountsOut(amount, path) returns (uint256[] memory amountsOut) {
                    if (amountsOut[amountsOut.length - 1]>maxAmountOut) {
                        maxAmountOut = amountsOut[amountsOut.length - 1];
                        bestRouter = routers[i];
                    }
                } catch{}
            }
        }
        return maxAmountOut;
    }

    function checkSwappable(address inToken, address outToken)
        external
        view
        returns (bool)
    {
        if (inToken == outToken) return true;
        for (uint i = 0; i<routers.length; i++) {
            address factoryAddress = IUniswapV2Router02(routers[i]).factory();
            IUniswapV2Factory factory = IUniswapV2Factory(factoryAddress);
            address pair = factory.getPair(inToken, outToken);
            if (pair!=address(0)) {
                return true;
            }
        }
        return false;
    }
}
