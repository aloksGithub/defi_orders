// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "../interfaces/IPoolInteractor.sol";
import "../interfaces/AAVE/ILendingPool.sol";
import "../interfaces/AAVE/IAToken.sol";

interface IAToken {
    function UNDERLYING_ASSET_ADDRESS() external view returns (address);
    function underlyingAssetAddress() external view returns (address);
}

contract AaveV2PoolInteractor is IPoolInteractor {
    using strings for *;
    using SafeERC20 for IERC20;

    address public lendingPool1;
    address public lendingPool2;
    address public lendingPool3;

    constructor(address _lendingPool1, address _lendingPool2, address _lendingPool3) {
        lendingPool1 = _lendingPool1;
        lendingPool2 = _lendingPool2;
        lendingPool3 = _lendingPool3;
    }

    function _getVersion(address lpTokenAddress) internal returns (uint) {
        address underlyingAddress = getUnderlyingTokens(lpTokenAddress)[0];
        if (lendingPool2!=address(0)) {
            if (ILendingPool2(lendingPool2).getReserveData(underlyingAddress).aTokenAddress==lpTokenAddress) return 2;
        }
        if (lendingPool3!=address(0)) {
            if (ILendingPool3(lendingPool3).getReserveData(underlyingAddress).aTokenAddress==lpTokenAddress) return 3;
        }
        // if (lendingPool1!=address(0)) {
        //     (,,,,,,,,,,,address aToken,) = ILendingPool1(lendingPool1).getReserveData(underlyingAddress);
        //     if (aToken==lpTokenAddress) return 1;
        // }
        return 1;
    }

    function burn(
        address lpTokenAddress,
        uint256 amount
    ) external returns (address[] memory, uint256[] memory) {
        IERC20 lpTokenContract = IERC20(lpTokenAddress);
        lpTokenContract.transferFrom(msg.sender, address(this), amount);
        address underlyingAddress = getUnderlyingTokens(lpTokenAddress)[0];
        uint balanceBefore = ERC20(underlyingAddress).balanceOf(address(this));

        uint version = _getVersion(lpTokenAddress);
        if (version==1) {
            IAToken1(lpTokenAddress).redeem(amount);
            // ILendingPool1(lendingPool1).redeemUnderlying(underlyingAddress, payable(address(this)), amount, 0);
        } else if (version==2) {
            lpTokenContract.approve(lendingPool2, amount);
            ILendingPool2(lendingPool2).withdraw(underlyingAddress, amount, address(this));
        } else if (version==3) {
            lpTokenContract.approve(lendingPool3, amount);
            ILendingPool3(lendingPool3).withdraw(underlyingAddress, amount, address(this));
        }

        uint tokensGained = ERC20(underlyingAddress).balanceOf(address(this))-balanceBefore;
        require(tokensGained>0, "Failed to burn LP tokens");
        (bool success,) = underlyingAddress.call(abi.encodeWithSignature("transfer(address,uint256)", msg.sender, tokensGained));
        if (!success) revert("Failed to transfer underlying token");
        address[] memory receivedTokens = new address[](1);
        receivedTokens[0] = underlyingAddress;
        uint256[] memory receivedTokenAmounts = new uint256[](1);
        receivedTokenAmounts[0] = tokensGained;
        return (receivedTokens, receivedTokenAmounts);
    }

    function mint(address toMint, address[] memory underlyingTokens, uint[] memory underlyingAmounts) external returns(uint) {
        IERC20 lpTokenContract = IERC20(toMint);
        uint lpBalance = lpTokenContract.balanceOf(msg.sender);
        address underlyingAddress = getUnderlyingTokens(toMint)[0];
        require(underlyingAddress==underlyingTokens[0], "Supplied token doesn't match pool underlying");

        (bool success,) = underlyingTokens[0].call(abi.encodeWithSignature("transferFrom(address,address,uint256)",msg.sender, address(this), underlyingAmounts[0]));
        if (!success) revert("Failed to transfer underlying token");

        uint version = _getVersion(toMint);
        if (version==1) {
            (success,) = underlyingTokens[0].call(abi.encodeWithSignature("approve(address,uint256)", ILendingPool1(lendingPool1).core(), underlyingAmounts[0]));
            if (!success) revert("Failed to approve underlying token");
            ILendingPool1(lendingPool1).deposit(underlyingAddress, underlyingAmounts[0], 0);
            uint tokensGained = lpTokenContract.balanceOf(address(this))-lpBalance;
            lpTokenContract.transfer(msg.sender, tokensGained);
        } else if (version==2) {
            (success,) = underlyingTokens[0].call(abi.encodeWithSignature("approve(address,uint256)", lendingPool2, underlyingAmounts[0]));
            if (!success) revert("Failed to approve underlying token");
            ILendingPool2(lendingPool2).deposit(underlyingAddress, underlyingAmounts[0], msg.sender, 0);
        } else if (version==3) {
            (success,) = underlyingTokens[0].call(abi.encodeWithSignature("approve(address,uint256)", lendingPool3, underlyingAmounts[0]));
            if (!success) revert("Failed to approve underlying token");
            ILendingPool3(lendingPool3).supply(underlyingAddress, underlyingAmounts[0], msg.sender, 0);
        }

        uint minted = lpTokenContract.balanceOf(msg.sender)-lpBalance;
        require(minted>0, "Failed to mint LP tokens");
        return minted;
    }
    
    function testSupported(address token) external override returns (bool) {
        string memory name = ERC20(token).name();
        if (name.toSlice().startsWith("Aave".toSlice())) {
            getUnderlyingTokens(token);
            return true;
        }
        return false;
    }

    function getUnderlyingTokens(address lpTokenAddress)
        public
        returns (address[] memory)
    {
        (bool success, bytes memory returnData) = lpTokenAddress.call(abi.encodeWithSignature("UNDERLYING_ASSET_ADDRESS()"));
        if (!success) {
            (success, returnData) = lpTokenAddress.call(abi.encodeWithSignature("underlyingAssetAddress()"));
            if (!success) {
                revert("Failed to get underlying");
            }
        }
        (address underlyingAddress) = abi.decode(returnData, (address));
        address[] memory receivedTokens = new address[](1);
        receivedTokens[0] = underlyingAddress;
        return receivedTokens;
    }
}
