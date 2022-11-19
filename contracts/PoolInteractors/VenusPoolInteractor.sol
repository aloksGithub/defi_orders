// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "../interfaces/IPoolInteractor.sol";
import "../interfaces/Venus/IVToken.sol";
import "hardhat/console.sol";

contract VenusPoolInteractor is IPoolInteractor {
    using strings for *;
    using SafeERC20 for IERC20;

    function burn(
        address lpTokenAddress,
        uint256 amount,
        address self
    ) payable external returns (address[] memory, uint256[] memory) {
        IVToken lpTokenContract = IVToken(lpTokenAddress);
        address underlying = lpTokenContract.underlying();
        lpTokenContract.approve(lpTokenAddress, amount);
        uint balanceStart = IERC20(underlying).balanceOf(address(this));
        lpTokenContract.redeem(amount);
        uint balanceEnd = IERC20(underlying).balanceOf(address(this));
        address[] memory receivedTokens = new address[](1);
        receivedTokens[0] = underlying;
        uint256[] memory receivedTokenAmounts = new uint256[](1);
        receivedTokenAmounts[0] = balanceEnd-balanceStart;
        return (receivedTokens, receivedTokenAmounts);
    }

    function mint(address toMint, address[] memory underlyingTokens, uint[] memory underlyingAmounts, address receiver, address self) payable external returns(uint) {
        IVToken lpTokenContract = IVToken(toMint);
        for (uint i = 0; i<underlyingTokens.length; i++) {
            ERC20 tokenContract = ERC20(underlyingTokens[i]);
            tokenContract.approve(toMint, underlyingAmounts[i]);
        }
        uint minted = lpTokenContract.mintBehalf(receiver, underlyingAmounts[0]);
        return minted;
    }
    
    function testSupported(address token) external view override returns (bool) {
        string memory name = ERC20(token).name();
        if (name.toSlice().startsWith("Venus".toSlice())) {
            getUnderlyingTokens(token);
            return true;
        }
        return false;
    }

    function getUnderlyingTokens(address lpTokenAddress)
        public
        view
        returns (address[] memory, uint[] memory)
    {
        IVToken lpTokenContract = IVToken(lpTokenAddress);
        address underlyingAddress = lpTokenContract.underlying();
        address[] memory receivedTokens = new address[](1);
        receivedTokens[0] = underlyingAddress;
        uint[] memory ratios = new uint[](1);
        ratios[0] = 1;
        return (receivedTokens, ratios);
    }
}
