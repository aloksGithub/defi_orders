// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../interfaces/IUniswapV2Router02.sol";
import "../interfaces/IUniswapV2Factory.sol";
import "hardhat/console.sol";

contract UniswapV2Swapper {

    function swap(
        address inToken,
        uint256 amount,
        address outToken,
        address _routerAddress
    ) external returns (uint256) {
        if (inToken == outToken) {
            return amount;
        }
        (bool success, ) = inToken.call(
            abi.encodeWithSignature(
                "approve(address,uint256)",
                _routerAddress,
                amount
            )
        );
        if (!success) {
            revert("Failed to approve token");
        }
        IUniswapV2Router02 router = IUniswapV2Router02(_routerAddress);
        address[] memory path = new address[](2);
        path[0] = inToken;
        path[1] = outToken;
        uint256[] memory amountsOut = router.getAmountsOut(amount, path);
        uint256[] memory amountReturned = router.swapExactTokensForTokens(
            amount,
            amountsOut[amountsOut.length - 1],
            path,
            address(this),
            block.timestamp
        );
        return amountReturned[amountReturned.length - 1];
    }

    function checkWillSwap(
        address inToken,
        uint256 amount,
        address outToken,
        address routerAddress
    ) external view returns (bool) {
        if (inToken == outToken) {
            return true;
        }
        IUniswapV2Router02 router = IUniswapV2Router02(routerAddress);
        address[] memory path = new address[](2);
        path[0] = inToken;
        path[1] = outToken;
        uint256[] memory amountsOut = router.getAmountsOut(amount, path);
        return amountsOut[amountsOut.length - 1] > 0;
    }

    function checkSwappable(address inToken, address outToken, address routerAddress)
        external
        view
        returns (bool)
    {
        if (inToken == outToken) return true;
        address factoryAddress = IUniswapV2Router02(routerAddress).factory();
        IUniswapV2Factory factory = IUniswapV2Factory(factoryAddress);
        address pair = factory.getPair(inToken, outToken);
        if (pair == address(0)) {
            return false;
        }
        return true;
    }
}
