// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "../interfaces/IPoolInteractor.sol";
import "../interfaces/UniswapV3/INonfungiblePositionManager.sol";
import "../interfaces/UniswapV3/IUniswapV3Pool.sol";
import "../libraries/Strings.sol";
import "hardhat/console.sol";

interface INFTPoolInteractor {
    function setSupportedProtocols(string[] memory _supportedProtocols) external;
    function burn(Asset memory asset) external returns (address[] memory receivedTokens, uint256[] memory receivedTokenAmounts);
    function mint(Asset memory toMint, address[] memory underlyingTokens, uint256[] memory underlyingAmounts) external returns (uint256);
    function testSupported(address token) external view returns (bool);
    function getUnderlyingTokens(address lpTokenAddress) external view returns (address[] memory);
}

struct Asset {
    address pool;
    address manager;
    uint tokenId;
    bytes data;
}

contract UniswapV3PoolInteractor is INFTPoolInteractor, Ownable {
    using strings for *;
    using SafeERC20 for IERC20;

    string[] supportedProtocols;

    constructor(string[] memory _supportedProtocols) {
        supportedProtocols = _supportedProtocols;
    }

    function setSupportedProtocols(string[] memory _supportedProtocols) external onlyOwner {
        supportedProtocols = _supportedProtocols;
    }
    
    function burn(Asset memory asset) external returns (address[] memory receivedTokens, uint256[] memory receivedTokenAmounts) {
        (,,address token0, address token1,,,,uint128 liquidity,,,,) = INonfungiblePositionManager(asset.manager).positions(asset.tokenId);
        INonfungiblePositionManager.DecreaseLiquidityParams memory withdrawParams = INonfungiblePositionManager.DecreaseLiquidityParams(
            asset.tokenId,
            liquidity,
            0, 0, block.timestamp
        );
        (uint token0Amount, uint token1Amount) = INonfungiblePositionManager(asset.manager).decreaseLiquidity(withdrawParams);
        INonfungiblePositionManager.CollectParams memory params = INonfungiblePositionManager.CollectParams(
            asset.tokenId,
            address(this),
            2**128 - 1,
            2**128 - 1
        );
        INonfungiblePositionManager(asset.manager).collect(params);
        receivedTokens = new address[](2);
        receivedTokens[0] = token0;
        receivedTokens[1] = token1;
        receivedTokenAmounts = new uint[](2);
        receivedTokenAmounts[0] = token0Amount;
        receivedTokenAmounts[1] = token1Amount;
        IERC20(token0).safeTransfer(msg.sender, token0Amount);
        IERC20(token1).safeTransfer(msg.sender, token1Amount);
    }

    function mint(Asset memory toMint, address[] memory underlyingTokens, uint256[] memory underlyingAmounts) external returns (uint256) {
        IUniswapV3Pool pool = IUniswapV3Pool(toMint.pool);
        address token0 = pool.token0();
        address token1 = pool.token1();
        require((token0==underlyingTokens[0] && token1==underlyingTokens[1]), "Invalid input");
        for (uint i=0; i<underlyingAmounts.length; i++) {
            IERC20(underlyingTokens[i]).safeIncreaseAllowance(toMint.manager, underlyingAmounts[i]);
        }
        uint24 fees = pool.fee();
        (int24 tick0, int24 tick1) = abi.decode(toMint.data, (int24, int24));
        INonfungiblePositionManager.MintParams memory mintParams = INonfungiblePositionManager.MintParams(
            token0, token1, fees,
            tick0, tick1,
            underlyingAmounts[0], underlyingAmounts[1],
            0, 0,
            msg.sender, block.timestamp
        );
        (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1) = INonfungiblePositionManager(toMint.manager).mint(mintParams);
        return tokenId;
    }

    function testSupported(address token) external view returns (bool) {
        string memory name = ERC20(token).name();
        for (uint i = 0; i<supportedProtocols.length; i++) {
            if (name.toSlice().startsWith(supportedProtocols[i].toSlice())) {
                return true;
            }
        }
        return false;
    }

    function getUnderlyingTokens(address lpTokenAddress) public view returns (address[] memory) {
        IUniswapV3Pool pool = IUniswapV3Pool(lpTokenAddress);
        address[] memory receivedTokens = new address[](2);
        receivedTokens[0] = pool.token0();
        receivedTokens[1] = pool.token1();
        return receivedTokens;
    }
}