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

    constructor(address[] memory _routers) {
        routers = _routers;
    }

    function setRouters(address[] memory _routers) external onlyOwner {
        routers = _routers;
    }

    function getNumRouters() external view returns (uint) {
        return routers.length;
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
        uint balanceBefore = IERC20(outToken).balanceOf(address(this));
        uint numRouters = UniswapV2Swapper(self).getNumRouters();
        address[] memory path = new address[](2);
        path[0] = inToken;
        path[1] = outToken;
        IUniswapV2Router02 bestRouter;
        uint maxAmountOut = 0;
        for (uint i = 0; i<numRouters; i++) {
            address _routerAddress = UniswapV2Swapper(self).routers(i);
            IUniswapV2Router02 router = IUniswapV2Router02(_routerAddress);
            try router.getAmountsOut(amount, path) returns (uint256[] memory amountsOut) {
                if (amountsOut[amountsOut.length - 1]>maxAmountOut) {
                    maxAmountOut = amountsOut[amountsOut.length - 1];
                    bestRouter = router;
                }
            } catch{continue;}
        }
        IERC20(inToken).safeApprove(address(bestRouter), amount);
        bestRouter.swapExactTokensForTokens(amount, maxAmountOut, path, address(this), block.timestamp);
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
            } catch{continue;}
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
