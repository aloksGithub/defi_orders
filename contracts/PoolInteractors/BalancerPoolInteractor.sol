// SPDX-License-Identifier: BUSL 1.1
pragma solidity ^0.8.9;

// import "../interfaces/IPoolInteractor.sol";
// import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
// import "../interfaces/ILendingPool.sol";
// import "../interfaces/IAToken.sol";
// import "hardhat/console.sol";

// interface IAsset {
//     // solhint-disable-previous-line no-empty-blocks
// }

// interface IPool {
//     function getPoolId() external view returns (bytes32);
//     function getVault() external view returns (IVault vaultAddress);
// }

// interface IVault {
//     struct JoinPoolRequest {
//         IAsset[] assets;
//         uint256[] maxAmountsIn;
//         bytes userData;
//         bool fromInternalBalance;
//     }

//     function joinPool(
//         bytes32 poolId,
//         address sender,
//         address recipient,
//         JoinPoolRequest memory request
//     ) external payable;

//     struct ExitPoolRequest {
//         IAsset[] assets;
//         uint256[] minAmountsOut;
//         bytes userData;
//         bool toInternalBalance;
//     }

//     function exitPool(
//         bytes32 poolId,
//         address sender,
//         address payable recipient,
//         ExitPoolRequest memory request
//     ) external;

//     function getPoolTokens(bytes32 poolId)
//         external
//         view
//         returns (
//             IERC20[] memory tokens,
//             uint256[] memory balances,
//             uint256 lastChangeBlock
//         );
// }

// contract BalancerPoolInteractor is IPoolInteractor {

//     IVault vault;

//     constructor(address _balancerVault) {
//         vault = IVault(_balancerVault);
//     }

//     function burn(
//         address lpTokenAddress,
//         uint256 amount
//     ) external returns (address[] memory underlyingTokens, uint256[] memory receivedAmounts) {
//         IPool poolContract = IPool(lpTokenAddress);
//         bytes32 poolId = poolContract.getPoolId();
//         (IERC20[] memory tokens,,) = vault.getPoolTokens(poolId);
//         IAsset[] memory assets = new IAsset[](tokens.length);
//         receivedAmounts = new uint256[](tokens.length);
//         for (uint j = 0; j<tokens.length; j++) {
//             assets[j] = IAsset(address(tokens[j]));
//             receivedAmounts[j] = tokens[j].balanceOf(address(this));
//         }
//         uint256[] memory minAmounts = new uint256[](tokens.length);
//         bytes memory userData = abi.encode(1, amount);
//         IVault.ExitPoolRequest memory request = IVault.ExitPoolRequest(assets, minAmounts, userData, false);
//         vault.exitPool(poolId, address(this), payable(address(this)), request);
//         for (uint i = 0; i<tokens.length; i++) {
//             receivedAmounts[i] = tokens[i].balanceOf(address(this))-receivedAmounts[i];
//             underlyingTokens[i] = address(tokens[i]);
//         }
//     }

//     function mint(address lpTokenAddress, address[] memory underlyingTokens, uint[] memory underlyingAmounts) external returns(uint) {
//         uint startBalance = IERC20(lpTokenAddress).balanceOf(address(this));
//         IPool poolContract = IPool(lpTokenAddress);
//         bytes32 poolId = poolContract.getPoolId();
//         IAsset[] memory assets = new IAsset[](underlyingTokens.length);
//         for (uint j = 0; j<underlyingTokens.length; j++) {
//             IERC20(underlyingTokens[j]).transferFrom(msg.sender, address(this), underlyingAmounts[j]);
//             IERC20(underlyingTokens[j]).approve(address(vault), underlyingAmounts[j]);
//             assets[j] = IAsset(underlyingTokens[j]);
//         }
//         bytes memory userData = abi.encode(1, underlyingAmounts, 1);
//         IVault.JoinPoolRequest memory request = IVault.JoinPoolRequest(assets, underlyingAmounts, userData, false);
//         vault.joinPool(poolId, address(this), payable(address(this)), request);
//         uint lpGained = IERC20(lpTokenAddress).balanceOf(address(this))-startBalance;
//         IERC20(lpTokenAddress).transfer(msg.sender, lpGained);
//         return lpGained;
//     }

//     function getUnderlyingTokens(address lpTokenAddress)
//         public
//         view
//         returns (address[] memory)
//     {
//         IPool poolContract = IPool(lpTokenAddress);
//         bytes32 poolId = poolContract.getPoolId();
//         (IERC20[] memory tokens,,) = vault.getPoolTokens(poolId);
//         address[] memory underlyingTokens = new address[](tokens.length);
//         for (uint i = 0; i<tokens.length; i++) {
//             underlyingTokens[i] = address(tokens[i]);
//         }
//         return underlyingTokens;
//     }
// }
