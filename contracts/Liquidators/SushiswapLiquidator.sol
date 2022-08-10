// // SPDX-License-Identifier: UNLICENSED
// pragma solidity ^0.8.9;

// import "./interfaces/ILiquidator.sol";
// import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
// import "./interfaces/IUniswapV2Router02.sol";
// import "./interfaces/IUniswapV2Factory.sol";
// import "hardhat/console.sol";

// contract SushiswapLiquidator is ILiquidator {
//     address routerAddress;
//     address factoryAddress;

//     constructor(address _routerAddress, address _factoryAddress) {
//         routerAddress = _routerAddress;
//         factoryAddress = _factoryAddress;
//     }

//     function liquidate(
//         address toLiquidate,
//         uint256 amount,
//         address liquidateTo,
//         address receiver
//     ) external returns (uint256) {
//         if (toLiquidate == liquidateTo) {
//             ERC20(liquidateTo).transfer(receiver, amount);
//             return amount;
//         }
//         ERC20 token = ERC20(toLiquidate);
//         token.approve(routerAddress, amount);
//         IUniswapV2Router02 router = IUniswapV2Router02(routerAddress);
//         address[] memory path = new address[](2);
//         path[0] = toLiquidate;
//         path[1] = liquidateTo;
//         uint256[] memory amountsOut = router.getAmountsOut(amount, path);
//         uint256[] memory amountReturned = router.swapExactTokensForTokens(
//             amount,
//             amountsOut[amountsOut.length - 1],
//             path,
//             address(this),
//             block.timestamp + 60
//         );
//         ERC20 liquidateToToken = ERC20(liquidateTo);
//         liquidateToToken.transfer(
//             receiver,
//             amountReturned[amountReturned.length - 1]
//         );
//         return amountReturned[amountReturned.length - 1];
//     }

//     function checkWillLiquidate(
//         address toLiquidate,
//         uint256 amount,
//         address liquidateTo
//     ) external returns (bool) {
//         if (toLiquidate == liquidateTo) {
//             return true;
//         }
//         ERC20 token = ERC20(toLiquidate);
//         token.approve(routerAddress, amount);
//         IUniswapV2Router02 router = IUniswapV2Router02(routerAddress);
//         address[] memory path = new address[](2);
//         path[0] = toLiquidate;
//         path[1] = liquidateTo;
//         uint256[] memory amountsOut = router.getAmountsOut(amount, path);
//         return amountsOut[amountsOut.length - 1] > 0;
//     }

//     function checkLiquidable(address toLiquidate, address liquidateTo)
//         external
//         view
//         returns (bool)
//     {
//         IUniswapV2Factory factory = IUniswapV2Factory(factoryAddress);
//         address pair = factory.getPair(toLiquidate, liquidateTo);
//         if (pair == address(0)) {
//             return false;
//         }
//         return true;
//     }
// }
