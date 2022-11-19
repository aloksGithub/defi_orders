// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "../interfaces/IPoolInteractor.sol";
import "../interfaces/UniswapV2/IUniswapV2Pair.sol";

contract UniswapV2PoolInteractor is IPoolInteractor, Ownable {
    using strings for *;
    using SafeERC20 for IERC20;

    string[] supportedProtocols;

    constructor(string[] memory _supportedProtocols) {
        supportedProtocols = _supportedProtocols;
    }

    function setSupportedProtocols(string[] memory _supportedProtocols) external onlyOwner {
        supportedProtocols = _supportedProtocols;
    }

    function burn(address lpTokenAddress, uint256 amount, address self)
        payable
        external
        returns (address[] memory, uint256[] memory)
    {
        IUniswapV2Pair pair = IUniswapV2Pair(lpTokenAddress);
        address[] memory receivedTokens = new address[](2);
        receivedTokens[0] = pair.token0();
        receivedTokens[1] = pair.token1();
        uint256[] memory receivedTokenAmounts = new uint256[](2);
        if (amount==0) {
            receivedTokenAmounts[0] = 0;
            receivedTokenAmounts[1] = 0;
        } else {
            pair.transfer(lpTokenAddress, amount);
            (uint amount0, uint amount1) = pair.burn(address(this));
            receivedTokenAmounts[0] = amount0;
            receivedTokenAmounts[1] = amount1;
            emit Burn(lpTokenAddress, amount);
        }
        return (receivedTokens, receivedTokenAmounts);
    }

    function mint(
        address toMint,
        address[] memory underlyingTokens,
        uint256[] memory underlyingAmounts,
        address receiver,
        address self
    ) payable external returns (uint256) {
        IUniswapV2Pair poolContract = IUniswapV2Pair(toMint);
        for (uint256 i = 0; i < underlyingTokens.length; i++) {
            IERC20(underlyingTokens[i]).safeTransfer(toMint, underlyingAmounts[i]);
        }
        uint256 minted = poolContract.mint(receiver);
        return minted;
    }

    function testSupported(address token) external view override returns (bool) {
        string memory name = ERC20(token).name();
        for (uint i = 0; i<supportedProtocols.length; i++) {
            if (name.toSlice().startsWith(supportedProtocols[i].toSlice())) {
                IUniswapV2Pair(token).token0();
                IUniswapV2Pair(token).token1();
                return true;
            }
        }
        return false;
    }

    function getUnderlyingTokens(address lpTokenAddress)
        external
        view
        returns (address[] memory, uint[] memory)
    {
        IUniswapV2Pair poolContract = IUniswapV2Pair(lpTokenAddress);
        address[] memory receivedTokens = new address[](2);
        receivedTokens[0] = poolContract.token0();
        receivedTokens[1] = poolContract.token1();
        uint[] memory ratios = new uint[](2);
        ratios[0] = 1;
        ratios[1] = 1;
        return (receivedTokens, ratios);
    }
}
