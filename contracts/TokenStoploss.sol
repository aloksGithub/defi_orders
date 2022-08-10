// // SPDX-License-Identifier: UNLICENSED
// pragma solidity ^0.8.9;

// // Import this file to use console.log
// import "./interfaces/IBurner.sol";
// import "./libraries/Tree.sol";
// import "hardhat/console.sol";
// import "./interfaces/ILiquidator.sol";
// import "@openzeppelin/contracts/access/Ownable.sol";
// import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// contract TokenStoploss is Ownable {
//     using BST for BST.Tree;

//     struct LiquidationParam {
//         address token;
//         uint256 priceUSD;
//     }

//     struct Deposit {
//         address token;
//         address liquidateTo;
//         uint256 amount;
//         uint256 timestamp;
//         string protocol;
//         mapping(uint256 => LiquidationParam) liquidationPoints;
//         uint256 numLiquidationPoints;
//     }

//     struct DepositWithArray {
//         address token;
//         address liquidateTo;
//         uint256 amount;
//         uint256 timestamp;
//         string protocol;
//         LiquidationParam[] liquidationPoints;
//     }

//     struct LiquidationThreshold {
//         address user;
//         address tokenToLiquidate;
//         uint256 prevPrice;
//         uint256 nextPrice;
//     }

//     struct ReceivingToken {
//         address tokenAddress;
//         uint256 amount;
//     }

//     event AdminFeeWithdrawal(uint256 amount);

//     mapping(string => address) public burners;
//     mapping(address => mapping(address => mapping(address => uint256)))
//         public balanceIndices;
//     mapping(address => mapping(uint256 => Deposit)) balances;
//     mapping(address => uint256) numDepositsForUser;
//     mapping(address => BST.Tree) public liquidationThresholds;
//     mapping(address => mapping(address => bool)) acceptedLiquidations;
//     mapping(address => uint256) adminFees;
//     address[] liquidators;
//     uint256 public FEE_PER_SECOND;
//     address public DEFAULT_LIQUIDATION_TOKEN;

//     constructor(
//         address _liqduiateTo,
//         uint256 feePerSecond,
//         address[] memory _liquidators
//     ) {
//         DEFAULT_LIQUIDATION_TOKEN = _liqduiateTo;
//         FEE_PER_SECOND = feePerSecond;
//         for (uint256 i = 0; i < _liquidators.length; i++) {
//             liquidators.push(_liquidators[i]);
//         }
//     }

//     function setBurner(string memory protocol, address burner) external {
//         burners[protocol] = burner;
//     }

//     function balanceOf(
//         address tokenAddress,
//         address user,
//         address liquidateTo
//     ) public view returns (uint256) {
//         uint256 balanceIndex = balanceIndices[tokenAddress][user][liquidateTo];
//         if (balanceIndex != 0) {
//             Deposit storage existingDeposit = balances[user][balanceIndex];
//             uint256 elapsedTime = block.timestamp - existingDeposit.timestamp;
//             uint256 fee = (elapsedTime *
//                 FEE_PER_SECOND *
//                 existingDeposit.amount) / 10000;
//             return existingDeposit.amount - fee;
//         }
//         return 0;
//     }

//     function getUserDeposits(address user)
//         public
//         view
//         returns (DepositWithArray[] memory)
//     {
//         if (numDepositsForUser[user] == 0) {
//             return new DepositWithArray[](0);
//         }
//         DepositWithArray[] memory userDeposits = new DepositWithArray[](
//             numDepositsForUser[user] - 1
//         );
//         for (uint256 i = 0; i < userDeposits.length; i++) {
//             Deposit storage currentlyCopying = balances[user][i + 1];
//             LiquidationParam[]
//                 memory liquidationPoints = new LiquidationParam[](
//                     currentlyCopying.numLiquidationPoints
//                 );
//             for (
//                 uint256 j = 0;
//                 j < currentlyCopying.numLiquidationPoints;
//                 j++
//             ) {
//                 liquidationPoints[j] = LiquidationParam(
//                     currentlyCopying.liquidationPoints[j].token,
//                     currentlyCopying.liquidationPoints[j].priceUSD
//                 );
//             }
//             userDeposits[i] = DepositWithArray(
//                 currentlyCopying.token,
//                 currentlyCopying.liquidateTo,
//                 currentlyCopying.amount,
//                 currentlyCopying.timestamp,
//                 currentlyCopying.protocol,
//                 liquidationPoints
//             );
//         }
//         return userDeposits;
//     }

//     function _calculateAdminFee(uint256 amount, uint256 timestamp)
//         private
//         view
//         returns (uint256)
//     {
//         uint256 elapsedTime = block.timestamp - timestamp;
//         uint256 fee = (elapsedTime * FEE_PER_SECOND * amount) / 1000000000;
//         return fee;
//     }

//     function _burnLPToken(
//         address tokenAddress,
//         string memory protocol,
//         uint256 amount
//     )
//         private
//         returns (
//             address[] memory receivedTokens,
//             uint256[] memory receivedTokenAmounts
//         )
//     {
//         require(
//             burners[protocol] != address(0),
//             "Burner for LP token not found"
//         );
//         IBurner burner = IBurner(burners[protocol]);
//         ERC20 lpToken = ERC20(tokenAddress);
//         lpToken.approve(burners[protocol], amount);
//         (receivedTokens, receivedTokenAmounts) = burner.burn(
//             tokenAddress,
//             amount,
//             address(this)
//         );
//     }

//     function _liquidateToken(
//         address tokenAddress,
//         uint256 amount,
//         address liquidateTo
//     ) private returns (uint256 receivedTokens) {
//         for (uint256 j = 0; j < liquidators.length; j++) {
//             ILiquidator liquidator = ILiquidator(liquidators[j]);
//             bool liquidable = liquidator.checkLiquidable(
//                 tokenAddress,
//                 liquidateTo
//             );
//             if (!liquidable) continue;
//             ERC20 toLiquidate = ERC20(tokenAddress);
//             toLiquidate.transfer(liquidators[j], amount);
//             receivedTokens = liquidator.liquidate(
//                 tokenAddress,
//                 amount,
//                 liquidateTo,
//                 address(this)
//             );
//             return receivedTokens;
//         }
//     }

//     function _willBurnAndLiquidateSuccessfully(
//         address tokenAddress,
//         uint256 amount,
//         address liquidateTo,
//         string memory protocol
//     ) private returns (bool) {
//         IBurner burner = IBurner(burners[protocol]);
//         if (burners[protocol] == address(0)) {
//             return (_willLiquidate(tokenAddress, amount, liquidateTo));
//         }
//         (
//             bool willBurn,
//             address[] memory receivedTokens,
//             uint256[] memory receivedTokenAmounts
//         ) = burner.checkBurnable(tokenAddress, amount);
//         if (!willBurn) return false;
//         for (uint256 i = 0; i < receivedTokens.length; i++) {
//             bool willLiquidate = _willLiquidate(
//                 receivedTokens[i],
//                 receivedTokenAmounts[i],
//                 liquidateTo
//             );
//             if (!willLiquidate) return false;
//         }
//         return true;
//     }

//     function _burnAndLiquidate(
//         address tokenAddress,
//         uint256 amount,
//         address liquidateTo,
//         address receiver,
//         string memory protocol
//     ) private returns (uint256) {
//         uint256 totalLiquidation = 0;
//         (
//             address[] memory receivedTokens,
//             uint256[] memory receivedTokenAmounts
//         ) = _burnLPToken(tokenAddress, protocol, amount);
//         for (uint256 i = 0; i < receivedTokens.length; i++) {
//             totalLiquidation += _liquidateToken(
//                 receivedTokens[i],
//                 receivedTokenAmounts[i],
//                 liquidateTo
//             );
//         }
//         ERC20 liquidateToToken = ERC20(liquidateTo);
//         liquidateToToken.transfer(receiver, totalLiquidation);
//         return totalLiquidation;
//     }

//     function _withdrawAdminFee(
//         address tokenAddress,
//         uint256 adminFee,
//         string memory protocol
//     ) private {
//         if (
//             _willBurnAndLiquidateSuccessfully(
//                 tokenAddress,
//                 adminFees[tokenAddress] + adminFee,
//                 DEFAULT_LIQUIDATION_TOKEN,
//                 protocol
//             )
//         ) {
//             _burnAndLiquidate(
//                 tokenAddress,
//                 adminFee,
//                 DEFAULT_LIQUIDATION_TOKEN,
//                 owner(),
//                 protocol
//             );
//             adminFees[tokenAddress] = 0;
//         } else {
//             console.log("NO ADMIN FEE THIS TIME");
//             adminFees[tokenAddress] += adminFee;
//         }
//     }

//     function _willLiquidate(
//         address toLiquidate,
//         uint256 amount,
//         address liquidateTo
//     ) private returns (bool) {
//         bool willLiquidate = false;
//         for (uint256 j = 0; j < liquidators.length; j++) {
//             ILiquidator liquidator = ILiquidator(liquidators[j]);
//             willLiquidate = liquidator.checkWillLiquidate(
//                 toLiquidate,
//                 amount,
//                 liquidateTo
//             );
//             if (willLiquidate) {
//                 break;
//             }
//         }
//         return willLiquidate;
//     }

//     function _createDeposit(
//         address user,
//         address _token,
//         address _liquidateTo,
//         uint256 _amount,
//         uint256 _timestamp,
//         string memory _protocol,
//         LiquidationParam[] memory _liquidationParams,
//         Deposit storage depositToInitialize
//     ) private {
//         depositToInitialize.token = _token;
//         depositToInitialize.liquidateTo = _liquidateTo;
//         depositToInitialize.amount = _amount;
//         depositToInitialize.timestamp = _timestamp;
//         depositToInitialize.protocol = _protocol;
//         for (uint256 i = 0; i < _liquidationParams.length; i++) {
//             liquidationThresholds[_liquidationParams[i].token].insert(
//                 user,
//                 _token,
//                 _liquidateTo,
//                 _liquidationParams[i].priceUSD
//             );
//             depositToInitialize.liquidationPoints[i].token = _liquidationParams[
//                 i
//             ].token;
//             depositToInitialize
//                 .liquidationPoints[i]
//                 .priceUSD = _liquidationParams[i].priceUSD;
//         }
//         depositToInitialize.numLiquidationPoints = _liquidationParams.length;
//     }

//     function _clearLiquidationThresholds(
//         address user,
//         address tokenAddress,
//         address liquidateTo
//     ) private {
//         uint256 balanceIndex = balanceIndices[tokenAddress][user][liquidateTo];
//         Deposit storage existingDeposit = balances[user][balanceIndex];
//         for (uint256 i = 0; i < existingDeposit.numLiquidationPoints; i++) {
//             LiquidationParam storage liquidationPoint = existingDeposit
//                 .liquidationPoints[i];
//             liquidationThresholds[liquidationPoint.token].remove(
//                 user,
//                 tokenAddress,
//                 liquidateTo,
//                 liquidationPoint.priceUSD
//             );
//         }
//     }

//     function _updateLiquidationThresholds(
//         address tokenAddress,
//         address user,
//         address liquidateTo,
//         LiquidationParam[] calldata liquidationParams
//     ) private {
//         uint256 balanceIndex = balanceIndices[tokenAddress][user][liquidateTo];
//         Deposit storage existingDeposit = balances[user][balanceIndex];
//         _clearLiquidationThresholds(user, tokenAddress, liquidateTo);
//         for (uint256 j = 0; j < liquidationParams.length; j++) {
//             liquidationThresholds[liquidationParams[j].token].insert(
//                 user,
//                 tokenAddress,
//                 liquidateTo,
//                 liquidationParams[j].priceUSD
//             );
//             existingDeposit.liquidationPoints[j].token = liquidationParams[j]
//                 .token;
//             existingDeposit.liquidationPoints[j].priceUSD = liquidationParams[j]
//                 .priceUSD;
//         }
//         existingDeposit.numLiquidationPoints = liquidationParams.length;
//     }

//     function _deposit(
//         address tokenAddress,
//         address user,
//         uint256 amount,
//         address liquidateTo,
//         string memory protocol,
//         LiquidationParam[] calldata liquidationParams
//     ) private {
//         ERC20 token = ERC20(tokenAddress);
//         token.transferFrom(user, address(this), amount);
//         uint256 balanceIndex = balanceIndices[tokenAddress][user][liquidateTo];
//         if (balanceIndex != 0) {
//             Deposit storage existingDeposit = balances[user][balanceIndex];
//             uint256 adminFee = _calculateAdminFee(
//                 existingDeposit.amount,
//                 existingDeposit.timestamp
//             );
//             uint256 withdrawableBalance = existingDeposit.amount - adminFee;
//             existingDeposit.amount = withdrawableBalance + amount;
//             existingDeposit.timestamp = block.timestamp;
//             _withdrawAdminFee(tokenAddress, adminFee, protocol);
//             _updateLiquidationThresholds(
//                 tokenAddress,
//                 user,
//                 liquidateTo,
//                 liquidationParams
//             );
//         } else {
//             require(
//                 _willBurnAndLiquidateSuccessfully(
//                     tokenAddress,
//                     amount,
//                     liquidateTo,
//                     protocol
//                 ),
//                 "Failed liquidation check"
//             );
//             if (numDepositsForUser[user] == 0) {
//                 numDepositsForUser[user]++;
//             }
//             Deposit storage newDeposit = balances[user][
//                 numDepositsForUser[user]
//             ];
//             _createDeposit(
//                 user,
//                 tokenAddress,
//                 liquidateTo,
//                 amount,
//                 block.timestamp,
//                 protocol,
//                 liquidationParams,
//                 newDeposit
//             );
//             balanceIndices[tokenAddress][user][
//                 liquidateTo
//             ] = numDepositsForUser[user];
//             numDepositsForUser[user]++;
//         }
//     }

//     function _removeDeposit(
//         address tokenAddress,
//         address user,
//         address liquidateTo
//     ) private {
//         _clearLiquidationThresholds(user, tokenAddress, liquidateTo);
//         uint256 balanceIndex = balanceIndices[tokenAddress][user][liquidateTo];
//         Deposit storage toRemove = balances[user][balanceIndex];
//         toRemove = balances[user][numDepositsForUser[user] - 1];
//         numDepositsForUser[user]--;
//         balanceIndices[tokenAddress][user][liquidateTo] = 0;
//     }

//     function _withdraw(
//         address tokenAddress,
//         address user,
//         uint256 amount,
//         bool completeWithdraw,
//         address liquidateTo,
//         bool liquidate
//     ) private {
//         uint256 balanceIndex = balanceIndices[tokenAddress][user][liquidateTo];
//         require(balanceIndex != 0, "Deposit not found");
//         Deposit storage existingDeposit = balances[user][balanceIndex];
//         uint256 adminFee = _calculateAdminFee(
//             existingDeposit.amount,
//             existingDeposit.timestamp
//         );
//         uint256 withdrawableBalance = existingDeposit.amount - adminFee;
//         if (completeWithdraw) {
//             amount = withdrawableBalance;
//         }
//         if (withdrawableBalance >= amount) {
//             string memory protocol = existingDeposit.protocol;
//             _withdrawAdminFee(tokenAddress, adminFee, protocol);
//             existingDeposit.amount -= adminFee + amount;
//             existingDeposit.timestamp = block.timestamp;
//             if (!liquidate) {
//                 ERC20 token = ERC20(tokenAddress);
//                 token.transfer(user, amount);
//             } else {
//                 _burnAndLiquidate(
//                     tokenAddress,
//                     amount,
//                     liquidateTo,
//                     user,
//                     protocol
//                 );
//             }
//             if (withdrawableBalance == amount) {
//                 _removeDeposit(tokenAddress, user, liquidateTo);
//             }
//         } else {
//             revert("Requested more funds than available");
//         }
//     }

//     function deposit(
//         address tokenAddress,
//         uint256 amount,
//         address liquidateTo,
//         string memory protocol,
//         LiquidationParam[] calldata liquidationparams
//     ) external {
//         _deposit(
//             tokenAddress,
//             msg.sender,
//             amount,
//             liquidateTo,
//             protocol,
//             liquidationparams
//         );
//     }

//     function botLiquidate(address watchedToken, uint256 priceUSD) external {
//         BST.Tree storage liquidationTree = liquidationThresholds[watchedToken];
//         uint256 currentThreshold = liquidationTree.last();
//         while (currentThreshold >= priceUSD) {
//             uint256 numUsers;
//             (, , , , numUsers, ) = liquidationTree.getNode(currentThreshold);
//             for (uint256 i = 0; i < numUsers; i++) {
//                 (
//                     address user,
//                     address toLiquidate,
//                     address liquidateTo
//                 ) = liquidationTree.valueKeyAtIndex(currentThreshold, i);
//                 _withdraw(toLiquidate, user, 0, true, liquidateTo, true);
//             }
//             currentThreshold = liquidationTree.last();
//         }
//     }

//     function withdraw(
//         address tokenAddress,
//         uint256 amount,
//         address liquidateTo,
//         bool completeWithdraw,
//         bool liquidate
//     ) external {
//         _withdraw(
//             tokenAddress,
//             msg.sender,
//             amount,
//             completeWithdraw,
//             liquidateTo,
//             liquidate
//         );
//     }
// }
