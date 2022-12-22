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
import "./ManagerHelper.sol";

contract PositionsManager is IPositionsManager, Ownable {
    using SafeERC20 for IERC20;
    using UintArray for uint256[];
    using StringArray for string[];
    using AddressArray for address[];

    Position[] public positions;
    mapping(uint256 => bool) public positionClosed; // Is position open
    mapping(uint256 => PositionInteraction[]) public positionInteractions; // Mapping from position Id to block numbers and interaction types for all position interactions
    mapping(address => uint256[]) public userPositions; // Mapping from user address to a list of position IDs belonging to the user
    address payable[] public banks;
    address public universalSwap;
    address public networkToken;
    address public stableToken; // Stable token such as USDC or BUSD is used to measure the value of the position using the function closeToUSDC
    ManagerHelper public helper; // A few view functions have been delegated to a helper contract to minimize the size of the main contract
    mapping(address => bool) public keepers;

    constructor(address _universalSwap, address _stableToken) {
        universalSwap = _universalSwap;
        stableToken = _stableToken;
        networkToken = IUniversalSwap(_universalSwap).networkToken();
        helper = new ManagerHelper();
    }

    ///-------------Public view functions-------------
    /// @inheritdoc IPositionsManager
    function numPositions() external view returns (uint256) {
        return positions.length;
    }

    /// @inheritdoc IPositionsManager
    function getPositionInteractions(uint256 positionId)
        external
        view
        returns (PositionInteraction[] memory)
    {
        return positionInteractions[positionId];
    }

    /// @inheritdoc IPositionsManager
    function getBanks() external view returns (address payable[] memory) {
        return banks;
    }

    /// @inheritdoc IPositionsManager
    function getPositions(address user)
        external
        view
        returns (uint256[] memory)
    {
        return userPositions[user];
    }

    /// @inheritdoc IPositionsManager
    function checkLiquidate(uint256 positionId)
        external
        view
        returns (uint256 index, bool liquidate)
    {
        return
            helper.checkLiquidate(
                positions[positionId],
                universalSwap,
                stableToken
            );
    }

    /// @inheritdoc IPositionsManager
    function estimateValue(uint256 positionId, address inTermsOf)
        public
        view
        returns (uint256)
    {
        return
            helper.estimateValue(
                positions[positionId],
                universalSwap,
                inTermsOf
            );
    }

    /// @inheritdoc IPositionsManager
    function getPositionTokens(uint256 positionId)
        public
        view
        returns (
            address[] memory tokens,
            uint256[] memory amounts,
            uint256[] memory values
        )
    {
        return
            helper.getPositionTokens(
                positions[positionId],
                universalSwap,
                stableToken
            );
    }

    /// @inheritdoc IPositionsManager
    function getPositionRewards(uint256 positionId)
        public
        view
        returns (
            address[] memory rewards,
            uint256[] memory rewardAmounts,
            uint256[] memory rewardValues
        )
    {
        return
            helper.getPositionRewards(
                positions[positionId],
                universalSwap,
                stableToken
            );
    }

    /// @inheritdoc IPositionsManager
    function getPosition(uint256 positionId)
        external
        view
        returns (PositionData memory data)
    {
        return
            helper.getPosition(
                positions[positionId],
                universalSwap,
                stableToken
            );
    }

    /// @inheritdoc IPositionsManager
    function recommendBank(address lpToken)
        external
        view
        returns (address[] memory, uint256[] memory)
    {
        uint256[] memory tokenIds;
        address[] memory supportedBanks;
        for (uint256 i = 0; i < banks.length; i++) {
            (bool success, uint256 tokenId) = BankBase(banks[i])
                .getIdFromLpToken(lpToken);
            if (success) {
                supportedBanks = supportedBanks.append(banks[i]);
                tokenIds = tokenIds.append(tokenId);
            }
        }
        return (supportedBanks, tokenIds);
    }

    ///-------------Core logic-------------
    /// @inheritdoc IPositionsManager
    function adjustLiquidationPoints(
        uint256 positionId,
        LiquidationCondition[] memory _liquidationPoints
    ) external {
        require(msg.sender == positions[positionId].user, "1");
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
    ) external payable {
        Position storage position = positions[positionId];
        BankBase bank = BankBase(payable(position.bank));
        uint256[] memory amountsUsed;
        (address[] memory underlying, uint256[] memory ratios) = bank
            .getUnderlyingForRecurringDeposit(position.bankToken);
        if (minAmounts.length > 0) {
            for (uint256 i = 0; i < provided.tokens.length; i++) {
                IERC20(provided.tokens[i]).safeTransferFrom(
                    msg.sender,
                    universalSwap,
                    provided.amounts[i]
                );
            }
            for (uint256 i = 0; i < provided.nfts.length; i++) {
                IERC721(provided.nfts[i].manager).safeTransferFrom(
                    msg.sender,
                    universalSwap,
                    provided.nfts[i].tokenId
                );
            }
            amountsUsed = IUniversalSwap(universalSwap).swapAfterTransfer{
                value: msg.value
            }(
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
                IERC20(provided.tokens[i]).safeTransferFrom(
                    msg.sender,
                    address(bank),
                    provided.amounts[i]
                );
            }
            if (msg.value > 0) {
                provided.tokens = provided.tokens.append(address(0));
                provided.amounts = provided.amounts.append(msg.value);
                payable(address(bank)).transfer(msg.value);
            }
            amountsUsed = provided.amounts;
        }
        uint256 minted = bank.mintRecurring(
            position.bankToken,
            position.user,
            underlying,
            amountsUsed
        );
        position.amount += minted;
        PositionInteraction memory interaction = PositionInteraction(
            "deposit",
            block.timestamp,
            block.number,
            provided,
            IUniversalSwap(universalSwap).estimateValue(provided, stableToken),
            minted
        );
        _addPositionInteraction(interaction, positionId);
        emit IncreasePosition(positionId, minted);
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
        require(
            (msg.value > 0 && suppliedTokens.length == 0) ||
                (msg.value == 0 && suppliedTokens.length > 0),
            "6"
        );
        for (uint256 i = 0; i < suppliedTokens.length; i++) {
            IERC20(suppliedTokens[i]).safeTransferFrom(
                msg.sender,
                address(bank),
                suppliedAmounts[i]
            );
        }
        if (msg.value > 0) {
            suppliedTokens = new address[](1);
            suppliedAmounts = new uint256[](1);
            suppliedTokens[0] = address(0);
            suppliedAmounts[0] = msg.value;
            payable(address(bank)).transfer(msg.value);
        }
        uint256 minted = bank.mint(
            position.bankToken,
            position.user,
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
            Asset memory asset = Asset(
                address(0),
                suppliedTokens[0],
                suppliedAmounts[0],
                minted,
                ""
            );
            Asset[] memory assets = new Asset[](1);
            assets[0] = asset;
            provided = Provided(new address[](0), new uint256[](0), assets);
        } else {
            provided = Provided(
                suppliedTokens,
                suppliedAmounts,
                new Asset[](0)
            );
        }
        PositionInteraction memory interaction = PositionInteraction(
            "deposit",
            block.timestamp,
            block.number,
            provided,
            IUniversalSwap(universalSwap).estimateValue(provided, stableToken),
            minted
        );
        _addPositionInteraction(interaction, positions.length - 1);
        emit Deposit(
            positions.length - 1,
            newPosition.bank,
            newPosition.bankToken,
            newPosition.user,
            newPosition.amount,
            newPosition.liquidationPoints
        );
        return positions.length - 1;
    }

    /// @inheritdoc IPositionsManager
    function withdraw(uint256 positionId, uint256 amount) external {
        Provided memory withdrawn = _withdraw(positionId, amount);
        PositionInteraction memory interaction = PositionInteraction(
            "withdraw",
            block.timestamp,
            block.number,
            withdrawn,
            IUniversalSwap(universalSwap).estimateValue(withdrawn, stableToken),
            amount
        );
        _addPositionInteraction(interaction, positionId);
        emit Withdraw(positionId, amount);
    }

    /// @inheritdoc IPositionsManager
    function close(uint256 positionId) external {
        Position storage position = positions[positionId];
        Provided memory harvested = _harvest(positionId, position.user);
        Provided memory withdrawn = _withdraw(positionId, position.amount);
        withdrawn.tokens = withdrawn.tokens.concat(harvested.tokens);
        withdrawn.amounts = withdrawn.amounts.concat(harvested.amounts);
        PositionInteraction memory interaction = PositionInteraction(
            "close",
            block.timestamp,
            block.number,
            withdrawn,
            IUniversalSwap(universalSwap).estimateValue(withdrawn, stableToken),
            position.amount
        );
        _addPositionInteraction(interaction, positionId);
        position.amount = 0;
        positionClosed[positionId] = true;
        emit PositionClose(positionId);
    }

    /// @inheritdoc IPositionsManager
    function harvestRewards(uint256 positionId)
        external
        returns (address[] memory, uint256[] memory)
    {
        Provided memory harvested = _harvest(
            positionId,
            positions[positionId].user
        );
        PositionInteraction memory interaction = PositionInteraction(
            "harvest",
            block.timestamp,
            block.number,
            harvested,
            IUniversalSwap(universalSwap).estimateValue(harvested, stableToken),
            0
        );
        _addPositionInteraction(interaction, positionId);
        emit Harvest(positionId, harvested.tokens, harvested.amounts);
        return (harvested.tokens, harvested.amounts);
    }

    /// @inheritdoc IPositionsManager
    function harvestAndRecompound(
        uint256 positionId,
        SwapPoint[] memory swaps,
        Conversion[] memory conversions,
        uint256[] memory minAmounts
    ) external returns (uint256) {
        require(positions[positionId].user == msg.sender, "1");
        Position storage position = positions[positionId];
        BankBase bank = BankBase(payable(position.bank));
        address receiver = minAmounts.length > 0
            ? universalSwap
            : address(bank);
        Provided memory harvested = _harvest(positionId, receiver);
        (address[] memory underlying, uint256[] memory ratios) = bank
            .getUnderlyingForRecurringDeposit(position.bankToken);
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
            newLpTokens = bank.mintRecurring(
                position.bankToken,
                position.user,
                underlying,
                amounts
            );
            position.amount += newLpTokens;
        }
        PositionInteraction memory interaction = PositionInteraction(
            "reinvest",
            block.timestamp,
            block.number,
            harvested,
            IUniversalSwap(universalSwap).estimateValue(harvested, stableToken),
            newLpTokens
        );
        _addPositionInteraction(interaction, positionId);
        emit HarvestRecompound(positionId, newLpTokens);
        return newLpTokens;
    }

    /// @inheritdoc IPositionsManager
    function botLiquidate(
        uint256 positionId,
        uint256 liquidationIndex,
        SwapPoint[] memory swaps,
        Conversion[] memory conversions
    ) external {
        Position storage position = positions[positionId];
        BankBase bank = BankBase(payable(position.bank));
        address[] memory tokens;
        uint256[] memory tokenAmounts;
        Provided memory positionAssets;
        uint256 positionValue;
        uint256 desiredTokenObtained;
        {
            require(
                keepers[msg.sender] || msg.sender == owner(),
                "1"
            );
            (
                address[] memory rewardAddresses,
                uint256[] memory rewardAmounts
            ) = bank.harvest(position.bankToken, position.user, universalSwap);
            (
                address[] memory outTokens,
                uint256[] memory outTokenAmounts
            ) = bank.burn(
                    position.bankToken,
                    position.user,
                    position.amount,
                    universalSwap
                );
            tokens = rewardAddresses.concat(outTokens);
            tokenAmounts = rewardAmounts.concat(outTokenAmounts);
            positionAssets = Provided(tokens, tokenAmounts, new Asset[](0));
        }
        {
            address[] memory wanted = new address[](1);
            uint256[] memory ratios = new uint256[](1);
            wanted[0] = position
                .liquidationPoints[liquidationIndex]
                .liquidateTo;
            ratios[0] = 1;
            uint256[] memory valuesOut = IUniversalSwap(universalSwap)
                .swapAfterTransfer(
                    Provided(tokens, tokenAmounts, new Asset[](0)),
                    swaps,
                    conversions,
                    Desired(wanted, new Asset[](0), ratios, new uint256[](1)),
                    position.user
                );
            desiredTokenObtained = valuesOut[0];
        }
        {
            positionValue = IUniversalSwap(universalSwap).estimateValue(
                positionAssets,
                stableToken
            );
            uint256 minUsdOut = (positionValue *
                (10**18 -
                    position.liquidationPoints[liquidationIndex].slippage)) /
                10**18;
            uint256 usdOut = IUniversalSwap(universalSwap).estimateValueERC20(
                position.liquidationPoints[liquidationIndex].liquidateTo,
                desiredTokenObtained,
                stableToken
            );
            require(usdOut > minUsdOut, "3");
        }
        PositionInteraction memory interaction = PositionInteraction(
            "liquidate",
            block.timestamp,
            block.number,
            positionAssets,
            positionValue,
            position.amount
        );
        _addPositionInteraction(interaction, positionId);
        position.amount = 0;
        positionClosed[positionId] = true;
        emit PositionClose(positionId);
    }

    receive() external payable {}

    ///-------------Permissioned functions-------------
    /// @inheritdoc IPositionsManager
    function setKeeper(address keeperAddress, bool active) external onlyOwner {
        keepers[keeperAddress] = active;
        emit KeeperUpdate(keeperAddress, active);
    }

    /// @inheritdoc IPositionsManager
    function setUniversalSwap(address _universalSwap) external onlyOwner {
        universalSwap = _universalSwap;
    }

    /// @inheritdoc IPositionsManager
    function addBank(address bank) external onlyOwner {
        banks.push(payable(bank));
    }

    ///-------------Internal logic-------------
    function _addPositionInteraction(
        PositionInteraction memory interaction,
        uint256 positionId
    ) internal {
        positionInteractions[positionId].push();
        uint256 idx = positionInteractions[positionId].length - 1;
        positionInteractions[positionId][idx].action = interaction.action;
        positionInteractions[positionId][idx].timestamp = interaction.timestamp;
        positionInteractions[positionId][idx].blockNumber = interaction
            .blockNumber;
        positionInteractions[positionId][idx].usdValue = interaction.usdValue;
        positionInteractions[positionId][idx].positionSizeChange = interaction
            .positionSizeChange;
        positionInteractions[positionId][idx].assets.tokens = interaction
            .assets
            .tokens;
        positionInteractions[positionId][idx].assets.amounts = interaction
            .assets
            .amounts;
        for (uint256 i = 0; i < interaction.assets.nfts.length; i++) {
            positionInteractions[positionId][idx].assets.nfts.push(
                interaction.assets.nfts[i]
            );
        }
    }

    function _harvest(uint256 positionId, address receiver)
        internal
        returns (Provided memory harvested)
    {
        require(positions[positionId].user == msg.sender, "1");
        Position storage position = positions[positionId];
        BankBase bank = BankBase(payable(position.bank));
        (address[] memory rewards, uint256[] memory rewardAmounts) = bank
            .harvest(position.bankToken, position.user, receiver);
        harvested = Provided(rewards, rewardAmounts, new Asset[](0));
    }

    function _withdraw(uint256 positionId, uint256 amount)
        internal
        returns (Provided memory withdrawn)
    {
        Position storage position = positions[positionId];
        BankBase bank = BankBase(payable(position.bank));
        require(
            position.amount >= amount,
            "7"
        );
        require(position.user == msg.sender, "1");
        position.amount -= amount;
        (address[] memory tokens, uint256[] memory amounts) = bank.burn(
            position.bankToken,
            position.user,
            amount,
            msg.sender
        );
        withdrawn = Provided(tokens, amounts, new Asset[](0));
        return withdrawn;
    }
}
