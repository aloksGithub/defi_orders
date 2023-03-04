// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "./Banks/BankBase.sol";
import "./PositionsManager.sol";
import "./interfaces/IUniversalSwap.sol";
import "./libraries/AddressArray.sol";
import "./libraries/UintArray.sol";

contract ManagerHelper is Initializable {
    using AddressArray for address[];
    using UintArray for uint256[];

    PositionsManager positionManager;

    function initialize(address _manager) public initializer {
        positionManager = PositionsManager(payable(_manager));
    }

    function estimateValue(
        uint positionId,
        address inTermsOf
    ) public view returns (uint256) {
        Position memory position = positionManager.getPosition(positionId);
        BankBase bank = BankBase(payable(position.bank));
        (address[] memory underlyingTokens, uint256[] memory underlyingAmounts) = bank.getPositionTokens(
            position.bankToken,
            address(uint160(positionId))
        );
        (address[] memory rewardTokens, uint256[] memory rewardAmounts) = bank.getPendingRewardsForUser(
            position.bankToken,
            position.user
        );
        Provided memory assets = Provided(
            underlyingTokens.concat(rewardTokens),
            underlyingAmounts.concat(rewardAmounts),
            new Asset[](0)
        );
        return IUniversalSwap(positionManager.universalSwap()).estimateValue(assets, inTermsOf);
    }

    function checkLiquidate(
        uint positionId
    ) public view returns (uint256 index, bool liquidate) {
        Position memory position = positionManager.getPosition(positionId);
        address stableToken = positionManager.stableToken();
        for (uint256 i = 0; i < position.liquidationPoints.length; i++) {
            LiquidationCondition memory condition = position.liquidationPoints[i];
            address token = condition.watchedToken;
            uint256 currentPrice;
            if (token == address(positionManager)) {
                currentPrice = estimateValue(positionId, stableToken);
                currentPrice = (currentPrice * 10 ** 18) / 10 ** ERC20Upgradeable(stableToken).decimals();
            } else {
                currentPrice = IUniversalSwap(positionManager.universalSwap()).estimateValueERC20(
                    token,
                    10 ** ERC20Upgradeable(token).decimals(),
                    stableToken
                );
                currentPrice = (currentPrice * 10 ** 18) / 10 ** ERC20Upgradeable(stableToken).decimals();
            }
            if (condition.lessThan && currentPrice < condition.liquidationPoint) {
                index = i;
                liquidate = true;
                break;
            }
            if (!condition.lessThan && currentPrice > condition.liquidationPoint) {
                index = i;
                liquidate = true;
                break;
            }
        }
    }

    function getPositionTokens(
        uint positionId
    ) public view returns (address[] memory tokens, uint256[] memory amounts, uint256[] memory values) {
        Position memory position = positionManager.getPosition(positionId);
        address universalSwap = positionManager.universalSwap();
        address stableToken = positionManager.stableToken();
        BankBase bank = BankBase(payable(position.bank));
        (tokens, amounts) = bank.getPositionTokens(position.bankToken, address(uint160(positionId)));
        if (amounts.sum()!=0) {
            (tokens, amounts) = IUniversalSwap(universalSwap).getUnderlying(Provided(tokens, amounts, new Asset[](0)));
            values = new uint256[](tokens.length);
            for (uint256 i = 0; i < tokens.length; i++) {
                uint256 value = IUniversalSwap(universalSwap).estimateValueERC20(tokens[i], amounts[i], stableToken);
                values[i] = value;
            }
        } else {
            for (uint i = 0; i<tokens.length; i++) {
                amounts[i] = 1e18;
            }
            (tokens,) = IUniversalSwap(universalSwap).getUnderlying(Provided(tokens, amounts, new Asset[](0)));
            amounts = new uint256[](tokens.length);
            values = new uint256[](tokens.length);
        }
    }

    function getPositionRewards(
        uint positionId
    ) public view returns (address[] memory rewards, uint256[] memory rewardAmounts, uint256[] memory rewardValues) {
        Position memory position = positionManager.getPosition(positionId);
        address universalSwap = positionManager.universalSwap();
        address stableToken = positionManager.stableToken();
        BankBase bank = BankBase(payable(position.bank));
        (rewards, rewardAmounts) = bank.getPendingRewardsForUser(position.bankToken, address(uint160(positionId)));
        rewardValues = new uint256[](rewards.length);
        for (uint256 i = 0; i < rewards.length; i++) {
            uint256 value = IUniversalSwap(universalSwap).estimateValueERC20(rewards[i], rewardAmounts[i], stableToken);
            rewardValues[i] = value;
        }
    }

    function getPosition(
        uint positionId
    ) external view returns (PositionData memory) {
        Position memory position = positionManager.getPosition(positionId);
        (address lpToken, address manager, uint256 id) = BankBase(payable(position.bank)).decodeId(position.bankToken);
        (address[] memory tokens, uint256[] memory amounts, uint256[] memory underlyingValues) = getPositionTokens(
            positionId
        );
        (address[] memory rewards, uint256[] memory rewardAmounts, uint256[] memory rewardValues) = getPositionRewards(
            positionId
        );
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

    function recommendBank(address lpToken) external view returns (address[] memory, uint256[] memory) {
        address payable[] memory banks = positionManager.getBanks();
        uint256[] memory tokenIds;
        address[] memory supportedBanks;
        for (uint256 i = 0; i < banks.length; i++) {
            (bool success, uint256 tokenId) = BankBase(banks[i]).getIdFromLpToken(lpToken);
            if (success) {
                supportedBanks = supportedBanks.append(banks[i]);
                tokenIds = tokenIds.append(tokenId);
            }
        }
        return (supportedBanks, tokenIds);
    }
}
