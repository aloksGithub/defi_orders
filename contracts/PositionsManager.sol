// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/IERC721Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "./utils/OwnableUpgradeable.sol";
import "./Banks/BankBase.sol";
import "./interfaces/IPositionsManager.sol";
import "./interfaces/IUniversalSwap.sol";
import "./libraries/AddressArray.sol";
import "./libraries/UintArray.sol";
import "./libraries/StringArray.sol";
import "./libraries/SaferERC20.sol";
import "./ManagerHelper.sol";
import "./interfaces/IWETH.sol";

contract PositionsManager is IPositionsManager, Initializable, OwnableUpgradeable {
    using SaferERC20 for IERC20;
    using UintArray for uint256[];
    using AddressArray for address[];

    Position[] public positions;
    mapping(uint256 => bool) public positionClosed; // Is position open
    mapping(address => uint256[]) public userPositions; // Mapping from user address to a list of position IDs belonging to the user
    address payable[] public banks;
    address public universalSwap;
    address public networkToken;
    address public stableToken; // Stable token such as USDC or BUSD is used to measure the value of the position using the function closeToUSDC
    mapping(address => bool) public keepers;
    uint256 minDepositAmount;

    function initialize(address _universalSwap, address _stableToken) public initializer {
        universalSwap = _universalSwap;
        stableToken = _stableToken;
        networkToken = IUniversalSwap(_universalSwap).networkToken();
        positions.push();
        minDepositAmount = 10*10**ERC20(stableToken).decimals();
        __Ownable_init();
    }

    ///-------------Modifiers-------------
    modifier notClosed(uint positionId) {
        require(positionClosed[positionId]!=true, "12");
        _;
    }

    modifier onlyPositionOwner(uint positionId) {
        require(positions[positionId].user == msg.sender, "1");
        _;
    }

    ///-------------Public view functions-------------
    /// @inheritdoc IPositionsManager
    function numPositions() external view returns (uint256) {
        return positions.length;
    }

    /// @inheritdoc IPositionsManager
    function getBanks() external view returns (address payable[] memory) {
        return banks;
    }

    /// @inheritdoc IPositionsManager
    function getPositions(address user) external view returns (uint256[] memory) {
        return userPositions[user];
    }

    /// @inheritdoc IPositionsManager
    function getPosition(uint256 positionId) external view returns (Position memory position) {
        return positions[positionId];
    }

    /// @inheritdoc IPositionsManager
    function recommendBank(address lpToken) external view returns (address[] memory, uint256[] memory) {
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

    ///-------------Core logic-------------
    /// @inheritdoc IPositionsManager
    function adjustLiquidationPoints(uint256 positionId, LiquidationCondition[] memory _liquidationPoints) external notClosed(positionId) onlyPositionOwner(positionId) {
        Position storage position = positions[positionId];
        delete position.liquidationPoints;
        for (uint256 i = 0; i < _liquidationPoints.length; i++) {
            position.liquidationPoints.push(_liquidationPoints[i]);
        }
    }

    /// @inheritdoc IPositionsManager
    function depositInExisting(
        uint256 positionId,
        Provided memory provided,
        SwapPoint[] memory swaps,
        Conversion[] memory conversions,
        uint256[] memory minAmounts
    ) external payable notClosed(positionId) onlyPositionOwner(positionId) {
        Position storage position = positions[positionId];
        BankBase bank = BankBase(payable(position.bank));
        uint256[] memory amountsUsed;
        (address[] memory underlying, uint256[] memory ratios) = bank.getUnderlyingForRecurringDeposit(
            position.bankToken
        );
        if (minAmounts.length > 0) {
            for (uint256 i = 0; i < provided.tokens.length; i++) {
                IERC20(provided.tokens[i]).safeTransferFrom(msg.sender, universalSwap, provided.amounts[i]);
            }
            for (uint256 i = 0; i < provided.nfts.length; i++) {
                IERC721Upgradeable(provided.nfts[i].manager).safeTransferFrom(msg.sender, universalSwap, provided.nfts[i].tokenId);
            }
            amountsUsed = IUniversalSwap(universalSwap).swapAfterTransfer{value: msg.value}(
                provided,
                swaps,
                conversions,
                Desired(underlying, new Asset[](0), ratios, minAmounts),
                address(bank)
            );
            if (msg.value > 0) {
                provided.tokens = provided.tokens.append(address(0));
                provided.amounts = provided.amounts.append(msg.value);
            }
        } else {
            for (uint256 i = 0; i < provided.tokens.length; i++) {
                IERC20(provided.tokens[i]).safeTransferFrom(msg.sender, address(bank), provided.amounts[i]);
            }
            if (msg.value > 0) {
                provided.tokens = provided.tokens.append(address(0));
                provided.amounts = provided.amounts.append(msg.value);
                (bool success,) = payable(address(bank)).call{ value: msg.value }("");
                require(success, "Transfer Failed");
            }
            amountsUsed = provided.amounts;
        }
        uint256 minted = bank.mintRecurring(position.bankToken, address(uint160(positionId)), underlying, amountsUsed);
        position.amount += minted;
        emit IncreasePosition(positionId, minted, IUniversalSwap(universalSwap).estimateValue(provided, stableToken));
    }

    /// @inheritdoc IPositionsManager
    function deposit(
        Position memory position,
        address[] memory suppliedTokens,
        uint256[] memory suppliedAmounts
    ) external payable returns (uint256) {
        BankBase bank = BankBase(payable(position.bank));
        address lpToken = bank.getLPToken(position.bankToken);
        require(IUniversalSwap(universalSwap).isSupported(lpToken), "2"); // UnsupportedToken
        require((msg.value > 0 && suppliedTokens.length == 0) || (msg.value == 0 && suppliedTokens.length > 0), "6");
        for (uint256 i = 0; i < suppliedTokens.length; i++) {
            IERC20(suppliedTokens[i]).safeTransferFrom(msg.sender, address(bank), suppliedAmounts[i]);
        }
        if (msg.value > 0) {
            suppliedTokens = new address[](1);
            suppliedAmounts = new uint256[](1);
            suppliedTokens[0] = address(0);
            suppliedAmounts[0] = msg.value;
            (bool success,) = payable(address(bank)).call{ value: msg.value }("");
            require(success, "Transfer Failed");
        }
        uint256 minted = bank.mint(
            position.bankToken,
            address(uint160(positions.length)),
            suppliedTokens,
            suppliedAmounts
        );
        positions.push();
        Position storage newPosition = positions[positions.length - 1];
        newPosition.user = position.user;
        newPosition.bank = position.bank;
        newPosition.bankToken = position.bankToken;
        newPosition.amount = minted;
        for (uint256 i = 0; i < position.liquidationPoints.length; i++) {
            newPosition.liquidationPoints.push(position.liquidationPoints[i]);
        }
        userPositions[position.user].push(positions.length - 1);
        Provided memory provided;
        if (bank.isUnderlyingERC721()) {
            Asset memory asset = Asset(address(0), suppliedTokens[0], suppliedAmounts[0], minted, "");
            Asset[] memory assets = new Asset[](1);
            assets[0] = asset;
            provided = Provided(new address[](0), new uint256[](0), assets);
        } else {
            provided = Provided(suppliedTokens, suppliedAmounts, new Asset[](0));
        }
        uint positionValue = IUniversalSwap(universalSwap).estimateValue(provided, stableToken);
        require(positionValue>minDepositAmount, "14");
        emit Deposit(
            positions.length - 1,
            newPosition.amount,
            positionValue
        );
        return positions.length - 1;
    }

    /// @inheritdoc IPositionsManager
    function withdraw(uint256 positionId, uint256 amount) external notClosed(positionId) onlyPositionOwner(positionId) {
        Position storage position = positions[positionId];
        BankBase bank = BankBase(payable(position.bank));
        require(position.amount >= amount, "7");
        position.amount -= amount;
        (address[] memory tokens, uint256[] memory amounts) = bank.burn(
            position.bankToken,
            address(uint160(positionId)),
            amount,
            msg.sender
        );
        Provided memory withdrawn = Provided(tokens, amounts, new Asset[](0));
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
        uint usdValueLeft = IUniversalSwap(universalSwap).estimateValue(assets, stableToken);
        require(usdValueLeft>minDepositAmount, "14");
        emit Withdraw(positionId, amount, IUniversalSwap(universalSwap).estimateValue(withdrawn, stableToken));
    }

    /// @inheritdoc IPositionsManager
    function close(uint256 positionId, string memory reason) external notClosed(positionId) {
        Position storage position = positions[positionId];
        require(keepers[msg.sender] || position.user == msg.sender || msg.sender == currentOwner(), "1");
        Provided memory withdrawn = _close(positionId, position.user);
        uint usdValue = IUniversalSwap(universalSwap).estimateValue(withdrawn, stableToken);
        if (msg.sender==position.user) {
            emit PositionClose(positionId, position.amount, usdValue);
        } else {
            emit Refund(positionId, position.amount, usdValue, reason);
        }
        position.amount = 0;
        positionClosed[positionId] = true;
    }

    /// @inheritdoc IPositionsManager
    function harvestRewards(uint256 positionId) external notClosed(positionId) onlyPositionOwner(positionId) returns (address[] memory, uint256[] memory) {
        Provided memory harvested = _harvest(positionId, positions[positionId].user);
        emit Harvest(positionId, 0, IUniversalSwap(universalSwap).estimateValue(harvested, stableToken));
        return (harvested.tokens, harvested.amounts);
    }

    /// @inheritdoc IPositionsManager
    function harvestAndRecompound(
        uint256 positionId,
        SwapPoint[] memory swaps,
        Conversion[] memory conversions,
        uint256[] memory minAmounts
    ) external notClosed(positionId) onlyPositionOwner(positionId) returns (uint256) {
        Position storage position = positions[positionId];
        BankBase bank = BankBase(payable(position.bank));
        Provided memory harvested = _harvest(positionId, minAmounts.length > 0 ? universalSwap : address(bank));
        (address[] memory underlying, uint256[] memory ratios) = bank.getUnderlyingForRecurringDeposit(
            position.bankToken
        );
        uint256[] memory amounts;
        if (minAmounts.length > 0) {
            if (harvested.amounts.sum() > 0) {
                amounts = IUniversalSwap(universalSwap).swapAfterTransfer(
                    harvested,
                    swaps,
                    conversions,
                    Desired(underlying, new Asset[](0), ratios, minAmounts),
                    address(bank)
                );
            }
        } else {
            amounts = harvested.amounts;
        }
        uint256 newLpTokens;
        if (amounts.sum() > 0) {
            newLpTokens = bank.mintRecurring(position.bankToken, address(uint160(positionId)), underlying, amounts);
            position.amount += newLpTokens;
        }
        emit HarvestRecompound(positionId, newLpTokens, IUniversalSwap(universalSwap).estimateValue(harvested, stableToken));
        return newLpTokens;
    }

    /// @inheritdoc IPositionsManager
    function botLiquidate(
        uint256 positionId,
        uint256 liquidationIndex,
        uint256 liquidationFee,
        SwapPoint[] memory swaps,
        Conversion[] memory conversions
    ) external notClosed(positionId) {
        Position storage position = positions[positionId];
        require(keepers[msg.sender] || position.user == msg.sender || msg.sender == currentOwner(), "1");
        Provided memory positionAssets = _close(positionId, universalSwap);
        uint256 positionValue = IUniversalSwap(universalSwap).estimateValue(positionAssets, networkToken);
        uint256 desiredTokenObtained;
        uint256 usdOut;
        {
            address[] memory wanted = new address[](2);
            uint256[] memory ratios = new uint256[](2);
            wanted[0] = position.liquidationPoints[liquidationIndex].liquidateTo;
            wanted[1] = address(0);
            ratios[0] = positionValue;
            ratios[1] = liquidationFee;
            uint256[] memory valuesOut = IUniversalSwap(universalSwap).swapAfterTransfer(
                Provided(positionAssets.tokens, positionAssets.amounts, new Asset[](0)),
                swaps,
                conversions,
                Desired(wanted, new Asset[](0), ratios, new uint256[](2)),
                address(this)
            );
            desiredTokenObtained = valuesOut[0];
            if (position.liquidationPoints[liquidationIndex].liquidateTo!=address(0)) {
                IERC20(position.liquidationPoints[liquidationIndex].liquidateTo).safeTransfer(position.user, desiredTokenObtained);
            } else {
                payable(position.user).transfer(desiredTokenObtained);
            }
            require(address(this).balance>=liquidationFee/2, "13"); // 50% slippage for liquidation fee
            usdOut = IUniversalSwap(universalSwap).estimateValueERC20(networkToken, address(this).balance, stableToken);
            payable(msg.sender).transfer(address(this).balance);
        }
        {
            positionValue = IUniversalSwap(universalSwap).estimateValue(positionAssets, stableToken);
            uint256 minUsdOut = (positionValue * (10 ** 18 - position.liquidationPoints[liquidationIndex].slippage)) /
                10 ** 18;
            usdOut+=IUniversalSwap(universalSwap).estimateValueERC20(
                position.liquidationPoints[liquidationIndex].liquidateTo,
                desiredTokenObtained,
                stableToken
            );
            require(usdOut >= minUsdOut, "3");
        }
        emit BotLiquidate(positionId, position.amount, positionValue, liquidationIndex);
        position.amount = 0;
        positionClosed[positionId] = true;
    }

    ///-------------Permissioned functions-------------
    /// @inheritdoc IPositionsManager
    function setKeeper(address keeperAddress, bool active) external onlyOwner {
        keepers[keeperAddress] = active;
    }

    /// @inheritdoc IPositionsManager
    function setBanks(address payable[] memory _banks) external onlyOwner {
        banks = _banks;
    }

    /// @inheritdoc IPositionsManager
    function setMinDepositAmount(uint _minDepositAmount) external onlyOwner {
        minDepositAmount = _minDepositAmount;
    }

    ///-------------Internal logic-------------

    function _harvest(uint256 positionId, address receiver) internal returns (Provided memory harvested) {
        Position storage position = positions[positionId];
        BankBase bank = BankBase(payable(position.bank));
        (address[] memory rewards, uint256[] memory rewardAmounts) = bank.harvest(
            position.bankToken,
            address(uint160(positionId)),
            receiver
        );
        harvested = Provided(rewards, rewardAmounts, new Asset[](0));
    }

    function _close(uint positionId, address receiver) internal returns (Provided memory assets) {
        Position storage position = positions[positionId];
        BankBase bank = BankBase(payable(position.bank));
        address[] memory tokens;
        uint256[] memory tokenAmounts;
        Provided memory positionAssets;
        (address[] memory rewardAddresses, uint256[] memory rewardAmounts) = bank.harvest(
            position.bankToken,
            address(uint160(positionId)),
            receiver
        );
        (address[] memory outTokens, uint256[] memory outTokenAmounts) = bank.burn(
            position.bankToken,
            address(uint160(positionId)),
            position.amount,
            receiver
        );
        tokens = rewardAddresses.concat(outTokens);
        tokenAmounts = rewardAmounts.concat(outTokenAmounts);
        positionAssets = Provided(tokens, tokenAmounts, new Asset[](0));
        return positionAssets;
    }

    receive() external payable {}
}
