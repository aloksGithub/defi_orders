// SPDX-License-Identifier: BUSL 1.1
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./Banks/BankBase.sol";
import "./interfaces/IPositionsManager.sol";
import "./interfaces/IUniversalSwap.sol";
import "./libraries/AddressArray.sol";
import "./libraries/UintArray.sol";
import "./libraries/StringArray.sol";

contract ManagerHelper {
    using AddressArray for address[];
    using UintArray for uint256[];

    function estimateValue(
        uint positionId,
        Position memory position,
        address universalSwap,
        address inTermsOf
    ) public view returns (uint256) {
        BankBase bank = BankBase(payable(position.bank));
        (
            address[] memory underlyingTokens,
            uint256[] memory underlyingAmounts
        ) = bank.getPositionTokens(position.bankToken, address(uint160(positionId)));
        (address[] memory rewardTokens, uint256[] memory rewardAmounts) = bank
            .getPendingRewardsForUser(position.bankToken, position.user);
        Provided memory assets = Provided(
            underlyingTokens.concat(rewardTokens),
            underlyingAmounts.concat(rewardAmounts),
            new Asset[](0)
        );
        return IUniversalSwap(universalSwap).estimateValue(assets, inTermsOf);
    }

    function checkLiquidate(
        uint positionId,
        Position memory position,
        address universalSwap,
        address stableToken
    ) public view returns (uint256 index, bool liquidate) {
        for (uint256 i = 0; i < position.liquidationPoints.length; i++) {
            LiquidationCondition memory condition = position.liquidationPoints[
                i
            ];
            address token = condition.watchedToken;
            uint256 currentPrice;
            if (token == address(0)) {
                currentPrice = estimateValue(
                    positionId,
                    position,
                    universalSwap,
                    stableToken
                );
                currentPrice =
                    (currentPrice * 10**18) /
                    10**ERC20(stableToken).decimals();
            } else {
                currentPrice = IUniversalSwap(universalSwap).estimateValueERC20(
                        token,
                        10**ERC20(token).decimals(),
                        stableToken
                    );
                currentPrice =
                    (currentPrice * 10**18) /
                    10**ERC20(stableToken).decimals();
            }
            if (
                condition.lessThan && currentPrice < condition.liquidationPoint
            ) {
                index = i;
                liquidate = true;
                break;
            }
            if (
                !condition.lessThan && currentPrice > condition.liquidationPoint
            ) {
                index = i;
                liquidate = true;
                break;
            }
        }
    }

    function getPositionTokens(
        uint positionId,
        Position memory position,
        address universalSwap,
        address stableToken
    )
        public
        view
        returns (
            address[] memory tokens,
            uint256[] memory amounts,
            uint256[] memory values
        )
    {
        BankBase bank = BankBase(payable(position.bank));
        (tokens, amounts) = bank.getPositionTokens(
            position.bankToken,
            address(uint160(positionId))
        );
        (tokens, amounts) = IUniversalSwap(universalSwap).getUnderlying(
            Provided(
                tokens,
                amounts,
                new Asset[](0)
            )
        );
        values = new uint256[](tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            uint256 value = IUniversalSwap(universalSwap).estimateValueERC20(
                tokens[i],
                amounts[i],
                stableToken
            );
            values[i] = value;
        }
        if (tokens.length == 0) {
            (tokens, ) = bank.getUnderlyingForRecurringDeposit(
                position.bankToken
            );
            amounts = new uint256[](tokens.length);
            values = new uint256[](tokens.length);
        }
    }

    function getPositionRewards(
        uint positionId,
        Position memory position,
        address universalSwap,
        address stableToken
    )
        public
        view
        returns (
            address[] memory rewards,
            uint256[] memory rewardAmounts,
            uint256[] memory rewardValues
        )
    {
        BankBase bank = BankBase(payable(position.bank));
        (rewards, rewardAmounts) = bank.getPendingRewardsForUser(
            position.bankToken,
            address(uint160(positionId))
        );
        rewardValues = new uint256[](rewards.length);
        for (uint256 i = 0; i < rewards.length; i++) {
            uint256 value = IUniversalSwap(universalSwap).estimateValueERC20(
                rewards[i],
                rewardAmounts[i],
                stableToken
            );
            rewardValues[i] = value;
        }
    }

    function getPosition(
        uint positionId,
        Position memory position,
        address universalSwap,
        address stableToken
    ) external view returns (PositionData memory) {
        (address lpToken, address manager, uint256 id) = BankBase(
            payable(position.bank)
        ).decodeId(position.bankToken);
        (
            address[] memory tokens,
            uint256[] memory amounts,
            uint256[] memory underlyingValues
        ) = getPositionTokens(positionId, position, universalSwap, stableToken);
        (
            address[] memory rewards,
            uint256[] memory rewardAmounts,
            uint256[] memory rewardValues
        ) = getPositionRewards(positionId, position, universalSwap, stableToken);
        return
            PositionData(
                position,
                BankTokenInfo(lpToken, manager, id),
                tokens,
                amounts,
                underlyingValues,
                rewards,
                rewardAmounts,
                rewardValues,
                underlyingValues.sum() + rewardValues.sum()
            );
    }
}
