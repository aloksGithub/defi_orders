// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "../interfaces/IPoolInteractor.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../interfaces/ILendingPool.sol";
import "../interfaces/IAToken.sol";
import "hardhat/console.sol";

contract AaveV2PoolInteractor is IPoolInteractor {
    address lendingPool;

    constructor(address _lendingPool) {
        lendingPool = _lendingPool;
    }

    function burn(
        address lpTokenAddress,
        uint256 amount
    ) external returns (address[] memory, uint256[] memory) {
        ILendingPool lendingPoolContract = ILendingPool(lendingPool);
        IAToken lpTokenContract = IAToken(lpTokenAddress);
        lpTokenContract.transferFrom(msg.sender, address(this), amount);
        lpTokenContract.approve(lendingPool, amount);
        address underlyingAddress = lpTokenContract.UNDERLYING_ASSET_ADDRESS();
        lendingPoolContract.withdraw(underlyingAddress, amount, msg.sender);
        address[] memory receivedTokens = new address[](1);
        receivedTokens[0] = underlyingAddress;
        uint256[] memory receivedTokenAmounts = new uint256[](1);
        receivedTokenAmounts[0] = amount;
        return (receivedTokens, receivedTokenAmounts);
    }

    function mint(address toMint, address[] memory underlyingTokens, uint[] memory underlyingAmounts) external returns(uint) {
        for (uint i = 0; i<underlyingTokens.length; i++) {
            ERC20 tokenContract = ERC20(underlyingTokens[i]);
            tokenContract.transferFrom(msg.sender, address(this), underlyingAmounts[i]);
            tokenContract.approve(lendingPool, underlyingAmounts[i]);
        }
        ILendingPool lendingPoolContract = ILendingPool(lendingPool);
        IAToken lpTokenContract = IAToken(toMint);
        uint lpBalance = lpTokenContract.balanceOf(address(this));
        address underlyingAddress = lpTokenContract.UNDERLYING_ASSET_ADDRESS();
        require(underlyingAddress==underlyingTokens[0], "Supplied token doesn't match pool underlying");
        lendingPoolContract.deposit(underlyingAddress, underlyingAmounts[0], msg.sender, 0);
        uint minted = lpTokenContract.balanceOf(address(this))-lpBalance;
        return minted;
    }

    function getUnderlyingTokens(address lpTokenAddress)
        public
        view
        returns (address[] memory, uint[] memory balances)
    {
        IAToken lpTokenContract = IAToken(lpTokenAddress);
        address underlyingAddress = lpTokenContract.UNDERLYING_ASSET_ADDRESS();
        address[] memory receivedTokens = new address[](1);
        receivedTokens[0] = underlyingAddress;
        balances = new uint[](1);
        balances[0] = IERC20(underlyingAddress).balanceOf(lpTokenAddress);
        return (receivedTokens, balances);
    }
}
