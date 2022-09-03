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
        uint256 amount
    ) external returns (address[] memory, uint256[] memory) {
        IVToken lpTokenContract = IVToken(lpTokenAddress);
        address underlying = lpTokenContract.underlying();
        lpTokenContract.transferFrom(msg.sender, address(this), amount);
        lpTokenContract.approve(lpTokenAddress, amount);
        uint balanceStart = IERC20(underlying).balanceOf(address(this));
        lpTokenContract.redeem(amount);
        uint balanceEnd = IERC20(underlying).balanceOf(address(this));
        address[] memory receivedTokens = new address[](1);
        receivedTokens[0] = underlying;
        uint256[] memory receivedTokenAmounts = new uint256[](1);
        receivedTokenAmounts[0] = balanceEnd-balanceStart;
        IERC20(underlying).transfer(msg.sender, receivedTokenAmounts[0]);
        return (receivedTokens, receivedTokenAmounts);
    }

    function mint(address toMint, address[] memory underlyingTokens, uint[] memory underlyingAmounts) external returns(uint) {
        IVToken lpTokenContract = IVToken(toMint);
        address underlyingAddress = lpTokenContract.underlying();
        require(underlyingAddress==underlyingTokens[0] && underlyingTokens.length==1, "Invalid input token");
        for (uint i = 0; i<underlyingTokens.length; i++) {
            ERC20 tokenContract = ERC20(underlyingTokens[i]);
            tokenContract.transferFrom(msg.sender, address(this), underlyingAmounts[i]);
            tokenContract.approve(toMint, underlyingAmounts[i]);
        }
        uint vBalanceBefore = lpTokenContract.balanceOf(address(this));
        lpTokenContract.mint(underlyingAmounts[0]);
        uint mitned = lpTokenContract.balanceOf(address(this))-vBalanceBefore;
        lpTokenContract.transfer(msg.sender, mitned);
        return mitned;
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
        returns (address[] memory)
    {
        IVToken lpTokenContract = IVToken(lpTokenAddress);
        address underlyingAddress = lpTokenContract.underlying();
        address[] memory receivedTokens = new address[](1);
        receivedTokens[0] = underlyingAddress;
        return receivedTokens;
    }
}
