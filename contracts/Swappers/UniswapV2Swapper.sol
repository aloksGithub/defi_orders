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
    ) payable external returns (uint256) {
        if (inToken == outToken) {
            return amount;
        }
        uint numRouters = UniswapV2Swapper(self).getNumRouters();
        bool isSignificant = false;
        for (uint i = 0; i<numRouters; i++) {
            address _routerAddress = UniswapV2Swapper(self).routers(i);
            IERC20(inToken).safeApprove(_routerAddress, amount);
            IUniswapV2Router02 router = IUniswapV2Router02(_routerAddress);
            address[] memory path = new address[](2);
            path[0] = inToken;
            path[1] = outToken;
            uint256[] memory amountsOut = router.getAmountsOut(amount, path);
            if (amountsOut[amountsOut.length - 1]>0) {
                isSignificant = true;
            }
            try router.swapExactTokensForTokens(amount, amountsOut[amountsOut.length - 1], path, address(this), block.timestamp) returns (uint256[] memory amountReturned) {
                return amountReturned[amountReturned.length - 1];
            } catch {continue;}
        }
        if (!isSignificant) {
            return 0;
        }
        revert("Failed to convert");
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
