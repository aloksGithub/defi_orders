// // SPDX-License-Identifier: UNLICENSED
// pragma solidity ^0.8.9;

// import "../interfaces/IPoolInteractor.sol";
// import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
// import "../interfaces/ILendingPool.sol";
// import "../interfaces/IAToken.sol";
// import "hardhat/console.sol";

// interface CurvePool {
//     function coins(uint256 index) view external returns (address);
//     function add_liquidity(uint256[] calldata _amounts, uint256 _min_mint_amount) external returns (uint256);
//     function remove_liquidity(uint256 _amount, uint256[] calldata _min_amounts) external returns (uint256[] memory);
// }

// contract CurvePoolInteractor is IPoolInteractor {

//     mapping (address => address) pools;

//     mapping (address => address[]) underlying;

//     constructor(address[] memory lpTokens, address[] memory _pools) {
//         for (uint i = 0; i<lpTokens.length; i++) {
//             pools[lpTokens[i]] = _pools[i];
//         }
//     }

//     function burn(
//         address lpTokenAddress,
//         uint256 amount
//     ) external returns (address[] memory, uint256[] memory) {
//         address pool = pools[lpTokenAddress];
//         CurvePool poolContract = CurvePool(pool);
//         address[] memory underlyingTokens = getUnderlyingTokens(lpTokenAddress);
//         uint256[] memory minAmounts = new uint256[](underlyingTokens.length);
//         uint256[] memory returnedAmounts = poolContract.remove_liquidity(amount, minAmounts);
//         for (uint i = 0; i<underlyingTokens.length; i++) {
//             ERC20 tokenContract = ERC20(underlyingTokens[i]);
//             tokenContract.transfer(msg.sender, returnedAmounts[i]);
//         }
//         return (underlyingTokens, returnedAmounts);
//     }

//     function mint(address toMint, address[] memory underlyingTokens, uint[] memory underlyingAmounts) external returns(uint) {
//         address pool = pools[toMint];
//         for (uint i = 0; i<underlyingTokens.length; i++) {
//             ERC20 tokenContract = ERC20(underlyingTokens[i]);
//             tokenContract.transferFrom(msg.sender, address(this), underlyingAmounts[i]);
//             tokenContract.approve(pool, underlyingAmounts[i]);
//         }
//         CurvePool poolContract = CurvePool(pool);
//         uint minted = poolContract.add_liquidity(underlyingAmounts, 0);
//         ERC20(toMint).transfer(msg.sender, minted);
//         return minted;
//     }

//     function getUnderlyingTokens(address lpTokenAddress)
//         public
//         view
//         returns (address[] memory underlyingTokens)
//     {
//         address pool = pools[lpTokenAddress];
//         CurvePool poolContract = CurvePool(pool);
//         if (underlying[pool].length!=0) {
//             return underlying[pool];
//         }
//         uint i = 0;
//         while (true) {
//             try poolContract.coins(i) {
//                 i++;
//             } catch {
//                 break;
//             }
//         }
//         underlyingTokens = new address[](i);
//         for (uint j = 0;j<i;j++) {
//             underlyingTokens[j] = CurvePool(lpTokenAddress).coins(j);
//         }
//     }
// }
