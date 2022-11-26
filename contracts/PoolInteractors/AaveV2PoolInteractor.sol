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
    using SafeERC20 for IERC20;

    address public lendingPool1;
    address public lendingPool2;
    address public lendingPool3;

    constructor(address _lendingPool1, address _lendingPool2, address _lendingPool3) {
        lendingPool1 = _lendingPool1;
        lendingPool2 = _lendingPool2;
        lendingPool3 = _lendingPool3;
    }

    function _getVersion(address lpTokenAddress, address self) internal view returns (uint) {
        (address[] memory underlying, ) = getUnderlyingTokens(lpTokenAddress);
        address lendingPool2Address = AaveV2PoolInteractor(self).lendingPool2();
        address lendingPool3Address = AaveV2PoolInteractor(self).lendingPool3();
        if (lendingPool2Address!=address(0)) {
            if (ILendingPool2(lendingPool2Address).getReserveData(underlying[0]).aTokenAddress==lpTokenAddress) return 2;
        }
        if (lendingPool3Address!=address(0)) {
            if (ILendingPool3(lendingPool3Address).getReserveData(underlying[0]).aTokenAddress==lpTokenAddress) return 3;
        }
        // if (lendingPool1Address!=address(0)) {
        //     (,,,,,,,,,,,address aToken,) = ILendingPool1(lendingPool1Address).getReserveData(underlyingAddress);
        //     if (aToken==lpTokenAddress) return 1;
        // }
        return 1;
    }

    function burn(
        address lpTokenAddress,
        uint256 amount,
        address self
    ) payable external returns (address[] memory, uint256[] memory) {
        IERC20 lpTokenContract = IERC20(lpTokenAddress);
        // lpTokenContract.transferFrom(msg.sender, address(this), amount);
        (address[] memory underlying, ) = getUnderlyingTokens(lpTokenAddress);
        uint balanceBefore = ERC20(underlying[0]).balanceOf(address(this));
        address lendingPool2Address = AaveV2PoolInteractor(self).lendingPool2();
        address lendingPool3Address = AaveV2PoolInteractor(self).lendingPool3();

        uint version = _getVersion(lpTokenAddress, self);
        if (version==1) {
            IAToken1(lpTokenAddress).redeem(amount);
            // IERC20(underlying[0]).safeTransfer(msg.sender, ERC20(underlying[0]).balanceOf(address(this)));
            // ILendingPool1(lendingPool1Address).redeemUnderlying(underlyingAddress, payable(address(this)), amount, 0);
        } else if (version==2) {
            lpTokenContract.approve(lendingPool2Address, amount);
            ILendingPool2(lendingPool2Address).withdraw(underlying[0], amount, address(this));
        } else if (version==3) {
            lpTokenContract.approve(lendingPool3Address, amount);
            ILendingPool3(lendingPool3Address).withdraw(underlying[0], amount, address(this));
        }

        uint tokensGained = ERC20(underlying[0]).balanceOf(address(this))-balanceBefore;
        require(tokensGained>0, "Failed to burn LP tokens");
        address[] memory receivedTokens = new address[](1);
        receivedTokens[0] = underlying[0];
        uint256[] memory receivedTokenAmounts = new uint256[](1);
        receivedTokenAmounts[0] = tokensGained;
        return (receivedTokens, receivedTokenAmounts);
    }

    function mint(address toMint, address[] memory underlyingTokens, uint[] memory underlyingAmounts, address receiver, address self) payable external returns(uint) {
        IERC20 lpTokenContract = IERC20(toMint);
        uint lpBalance = lpTokenContract.balanceOf(receiver);
        (address[] memory underlying, ) = getUnderlyingTokens(toMint);
        require(underlying[0]==underlyingTokens[0], "Supplied token doesn't match pool underlying");
        address lendingPool1Address = AaveV2PoolInteractor(self).lendingPool1();
        address lendingPool2Address = AaveV2PoolInteractor(self).lendingPool2();
        address lendingPool3Address = AaveV2PoolInteractor(self).lendingPool3();

        uint version = _getVersion(toMint, self);
        if (version==1) {
            IERC20(underlyingTokens[0]).safeIncreaseAllowance(ILendingPool1(lendingPool1Address).core(), underlyingAmounts[0]);
            ILendingPool1(lendingPool1Address).deposit(underlying[0], underlyingAmounts[0], 0);
            lpTokenContract.transfer(receiver, lpTokenContract.balanceOf(address(this)));
        } else if (version==2) {
            IERC20(underlyingTokens[0]).safeIncreaseAllowance(lendingPool2Address, underlyingAmounts[0]);
            ILendingPool2(lendingPool2Address).deposit(underlying[0], underlyingAmounts[0], receiver, 0);
        } else if (version==3) {
            IERC20(underlyingTokens[0]).safeIncreaseAllowance(lendingPool3Address, underlyingAmounts[0]);
            ILendingPool3(lendingPool3Address).supply(underlying[0], underlyingAmounts[0], receiver, 0);
        }

        uint minted = lpTokenContract.balanceOf(receiver)-lpBalance;
        require(minted>0, "Failed to mint LP tokens");
        return minted;
    }
    
    function testSupported(address token) external view override returns (bool) {
        try IAToken(token).UNDERLYING_ASSET_ADDRESS() returns (address) {return true;} catch {
            try IAToken(token).underlyingAssetAddress() returns (address) {return true;} catch {
                return false;
            }
        }
        // string memory name = ERC20(token).name();
        // if (name.toSlice().startsWith("Aave".toSlice())) {
        //     getUnderlyingTokens(token);
        //     return true;
        // }
        // return false;
    }

    function getUnderlyingAmount(address aTokenAddress, uint amount) external view returns (address[] memory underlying, uint[] memory amounts) {
        (underlying,) = getUnderlyingTokens(aTokenAddress);
        amounts = new uint[](1);
        amounts[0] = amount;
    }

    function getUnderlyingTokens(address lpTokenAddress)
        public view
        returns (address[] memory, uint[] memory)
    {
        address underlyingAddress;
        try IAToken(lpTokenAddress).UNDERLYING_ASSET_ADDRESS() returns (address underlying) {underlyingAddress = underlying;} catch {
            try IAToken(lpTokenAddress).underlyingAssetAddress() returns (address underlying) {underlyingAddress = underlying;} catch {
                revert("Failed to get underlying");
            }
        }
        // (bool success, bytes memory returnData) = lpTokenAddress.call(abi.encodeWithSignature("UNDERLYING_ASSET_ADDRESS()"));
        // if (!success) {
        //     (success, returnData) = lpTokenAddress.call(abi.encodeWithSignature("underlyingAssetAddress()"));
        //     if (!success) {
        //         revert("Failed to get underlying");
        //     }
        // }
        // (address underlyingAddress) = abi.decode(returnData, (address));
        address[] memory receivedTokens = new address[](1);
        receivedTokens[0] = underlyingAddress;
        uint[] memory ratios = new uint[](1);
        ratios[0] = 1;
        return (receivedTokens, ratios);
    }
}
