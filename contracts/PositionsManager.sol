// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./Banks/BankBase.sol";
import "./interfaces/IPositionsManager.sol";
import "./interfaces/IFeeModel.sol";
import "./interfaces/IUniversalSwap.sol";
import "./interfaces/IWETH.sol";
import "./DefaultFeeModel.sol";
import "./interfaces/IPoolInteractor.sol";
import "./libraries/AddressArray.sol";
import "./libraries/UintArray.sol";
import "./libraries/StringArray.sol";

contract PositionsManager is IPositionsManager, Ownable {
    using SafeERC20 for IERC20;
    using UintArray for uint[];
    using StringArray for string[];
    using AddressArray for address[];

    Position[] public positions;
    mapping (uint=>bool) public positionClosed; // Is position open
    // mapping (uint=>uint[]) public positionInteractions;
    mapping (uint=>PositionInteraction[]) public positionInteractions; // Mapping from position Id to block numbers and interaction types for all position interactions
    mapping (address=>uint) public numUserPositions; // Number of positions for user
    mapping (address=>uint[]) public userPositions; // Mapping from user address to a list of position IDs belonging to the user
    mapping (uint=>address) public feeModels; // Mapping from position ID to fee model used for that position
    mapping (uint=>uint) public devShare; // Mapping from position ID to share of the position that can be claimed as dev fee
    address defaultFeeModel;
    address payable[] public banks;
    address public universalSwap;
    address public networkToken;
    address public stableToken; // Stable token such as USDC or BUSD is used to measure the value of the position using the function closeToUSDC
    mapping (address=>bool) keepers;

    constructor(address _universalSwap, address _stableToken, address _defaultFeeModel) {
        universalSwap = _universalSwap;
        stableToken = _stableToken;
        defaultFeeModel = _defaultFeeModel;
        networkToken = IUniversalSwap(_universalSwap).networkToken();
    }

    /// @inheritdoc IPositionsManager
    function numPositions() external view returns (uint) {
        return positions.length;
    }

    /// @inheritdoc IPositionsManager
    function getPositionInteractions(uint positionId) external view returns (PositionInteraction[] memory) {
        return positionInteractions[positionId];
    }

    function numBanks() external view returns (uint) {
        return banks.length;
    }

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
    function setFeeModel(uint positionId, address feeModel) external onlyOwner {
        require(keepers[msg.sender] || msg.sender==owner(), "Unauthorized");
        feeModels[positionId] = feeModel;
    }

    /// @inheritdoc IPositionsManager
    function setDefaultFeeModel(address feeModel) external onlyOwner {
        defaultFeeModel = feeModel;
    }

    /// @inheritdoc IPositionsManager
    function addBank(address bank) external onlyOwner {
        banks.push(payable(bank));
        emit BankAdded(bank, banks.length-1);
    }

    /// @inheritdoc IPositionsManager
    function migrateBank(uint bankId, address newBankAddress) external onlyOwner {
        emit BankUpdated(newBankAddress, banks[bankId], bankId);
        banks[bankId] = payable(newBankAddress);
    }

    /// @inheritdoc IPositionsManager
    function getPosition(uint positionId) external view returns (PositionData memory data) {
        Position storage position = positions[positionId];
        BankBase bank = BankBase(banks[position.bankId]);
        (address[] memory tokens, uint[] memory amounts) = bank.getPositionTokens(position.bankToken, position.user);
        (tokens, amounts) = IUniversalSwap(universalSwap).getUnderlying(tokens, amounts);
        uint totalUsdValue;
        uint[] memory underlyingValues = new uint[](tokens.length);
        for (uint i = 0; i<tokens.length; i++) {
            uint value = IUniversalSwap(universalSwap).estimateValueERC20(tokens[i], amounts[i], stableToken);
            underlyingValues[i] = value;
            totalUsdValue+=value;
        }
        (address[] memory rewards, uint[] memory rewardAmounts) = bank.getPendingRewardsForUser(position.bankToken, position.user);
        uint[] memory rewardValues = new uint[](tokens.length);
        for (uint i = 0; i<rewards.length; i++) {
            uint value = IUniversalSwap(universalSwap).estimateValueERC20(rewards[i], rewardAmounts[i], stableToken);
            rewardValues[i] = value;
            totalUsdValue+=value;
        }
        (address lpToken, address manager, uint id) = bank.decodeId(position.bankToken);
        BankTokenInfo memory info = BankTokenInfo(lpToken, manager, id);
        data = PositionData(
            position, info, tokens, amounts, underlyingValues, rewards, rewardAmounts, rewardValues, totalUsdValue
        );
    }

    /// @inheritdoc IPositionsManager
    function recommendBank(address lpToken) external view returns (uint[] memory, string[] memory, uint[] memory) {
        uint[] memory tokenIds;
        uint[] memory bankIds;
        string[] memory bankNames;
        for (uint i = 0; i<banks.length; i++) {
            (bool success, uint tokenId) = BankBase(banks[i]).getIdFromLpToken(lpToken);
            if (success) {
                bankIds = bankIds.append(i);
                bankNames = bankNames.append(BankBase(banks[i]).name());
                tokenIds = tokenIds.append(tokenId);
            }
        }
        return (bankIds, bankNames, tokenIds);
    }

    /// @inheritdoc IPositionsManager
    function adjustLiquidationPoints(uint positionId, LiquidationCondition[] memory _liquidationPoints) external {
        require(msg.sender==positions[positionId].user, "Unauthorized");
        Position storage position = positions[positionId];
        delete position.liquidationPoints;
        for (uint i = 0; i<_liquidationPoints.length; i++) {
            position.liquidationPoints.push(_liquidationPoints[i]);
        }
        emit LiquidationPointsUpdate(positionId, _liquidationPoints);
    }

    /// @inheritdoc IPositionsManager
    function depositInExisting(uint positionId, Provided memory provided, SwapPoint[] memory swaps, Conversion[] memory conversions, uint[] memory minAmounts) payable external {
        computeDevFee(positionId);
        Position storage position = positions[positionId];
        BankBase bank = BankBase(banks[position.bankId]);
        uint[] memory amountsUsed;
        (address[] memory underlying, uint[] memory ratios) = bank.getUnderlyingForRecurringDeposit(position.bankToken);
        if (minAmounts.length>0) {
            for (uint i = 0; i<provided.tokens.length; i++) {
                IERC20(provided.tokens[i]).safeTransferFrom(msg.sender, universalSwap, provided.amounts[i]);
            }
            for (uint i = 0; i<provided.nfts.length; i++) {
                IERC721(provided.nfts[i].manager).safeTransferFrom(msg.sender, universalSwap, provided.nfts[i].tokenId);
            }
            amountsUsed = IUniversalSwap(universalSwap).swapAfterTransfer{value:msg.value}(
                provided,
                swaps, conversions,
                Desired(underlying, new Asset[](0), ratios, minAmounts),
                address(bank)
            );
            if (msg.value>0) {
                provided.tokens = provided.tokens.append(address(0));
                provided.amounts = provided.amounts.append(msg.value);
            }
        } else {
            for (uint i = 0; i<provided.tokens.length; i++) {
                IERC20(provided.tokens[i]).safeTransferFrom(msg.sender, address(bank), provided.amounts[i]);
            }
            if (msg.value>0) {
                provided.tokens = provided.tokens.append(address(0));
                provided.amounts = provided.amounts.append(msg.value);
                payable(address(bank)).transfer(msg.value);
            }
            amountsUsed = provided.amounts;
        }
        uint minted = bank.mintRecurring(position.bankToken, position.user, underlying, amountsUsed);
        position.amount+=minted;
        console.log(provided.tokens[0], provided.amounts[0]);
        PositionInteraction memory interaction = PositionInteraction(
            "deposit",
            block.timestamp, block.number,
            provided,
            IUniversalSwap(universalSwap).estimateValue(provided, stableToken),
            minted
        );
        _addPositionInteraction(interaction, positionId);
        emit IncreasePosition(positionId, minted);
    }

    /// @inheritdoc IPositionsManager
    function deposit(Position memory position, address[] memory suppliedTokens, uint[] memory suppliedAmounts) payable external returns (uint) {
        BankBase bank = BankBase(banks[position.bankId]);
        address lpToken = bank.getLPToken(position.bankToken);
        require(IUniversalSwap(universalSwap).isSupported(lpToken), "UT"); // UnsupportedToken
        require(msg.value>0 && suppliedTokens.length==0 || msg.value==0 && suppliedTokens.length>0, "Invlid tokens supplied");
        for (uint i = 0; i<suppliedTokens.length; i++) {
            IERC20(suppliedTokens[i]).safeTransferFrom(msg.sender, address(bank), suppliedAmounts[i]);
        }
        if (msg.value>0) {
            suppliedTokens = new address[](1);
            suppliedAmounts = new uint[](1);
            suppliedTokens[0] = address(0);
            suppliedAmounts[0] = msg.value;
            payable(address(bank)).transfer(msg.value);
        }
        uint minted = bank.mint(position.bankToken, position.user, suppliedTokens, suppliedAmounts);
        positions.push();
        Position storage newPosition = positions[positions.length-1];
        newPosition.user = position.user;
        newPosition.bankId = position.bankId;
        newPosition.bankToken = position.bankToken;
        newPosition.amount = minted;
        for (uint i = 0; i<position.liquidationPoints.length; i++) {
            newPosition.liquidationPoints.push(position.liquidationPoints[i]);
        }
        userPositions[position.user].push(positions.length-1);
        numUserPositions[position.user]+=1;
        Provided memory provided;
        if (bank.isUnderlyingERC721()) {
            Asset memory asset = Asset(address(0), suppliedTokens[0], suppliedAmounts[0], minted, '');
            Asset[] memory assets = new Asset[](1);
            assets[0] = asset;
            provided = Provided(new address[](0), new uint[](0), assets);
        } else {
            provided = Provided(suppliedTokens, suppliedAmounts, new Asset[](0));
        }
        PositionInteraction memory interaction = PositionInteraction(
            "deposit",
            block.timestamp,
            block.number,
            provided,
            IUniversalSwap(universalSwap).estimateValue(provided, stableToken),
            minted
        );
        _addPositionInteraction(interaction, positions.length-1);
        emit Deposit(positions.length-1, newPosition.bankId, newPosition.bankToken, newPosition.user, newPosition.amount, newPosition.liquidationPoints);
        return positions.length-1;
    }

    /// @inheritdoc IPositionsManager
    function withdraw(uint positionId, uint amount) external {
        computeDevFee(positionId);
        Position storage position = positions[positionId];
        BankBase bank = BankBase(banks[position.bankId]);
        require(position.amount>=amount, "Withdrawing more funds than available");
        require(position.user==msg.sender, "Unauthorized");
        position.amount-=amount;
        (address[] memory tokens, uint[] memory amounts) = bank.burn(position.bankToken, position.user, amount, msg.sender);
        Provided memory withdrawn = Provided(tokens, amounts, new Asset[](0));
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
    function close(uint positionId) external {
        computeDevFee(positionId);
        Position storage position = positions[positionId];
        BankBase bank = BankBase(banks[position.bankId]);
        require(position.user==msg.sender || msg.sender==owner(), "Unauthorized");
        bank.harvest(position.bankToken, position.user, position.user);
        (address[] memory tokens, uint[] memory amounts) = bank.burn(position.bankToken, position.user, position.amount, position.user);
        Provided memory withdrawn = Provided(tokens, amounts, new Asset[](0));
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
    // function closeToUSDC(uint positionId) external returns (uint) {
    //     // computeDevFee(positionId);
    //     address[] memory tokens;
    //     uint[] memory tokenAmounts;
    //     Position storage position = positions[positionId];
    //     {
    //         BankBase bank = BankBase(banks[position.bankId]);
    //         require(keepers[msg.sender] || msg.sender==owner() || position.user==msg.sender, "Unauthorized");
    //         (address[] memory rewardAddresses, uint[] memory rewardAmounts) = bank.harvest(position.bankToken, position.user, universalSwap);
    //         (address[] memory outTokens, uint[] memory outTokenAmounts) = bank.burn(position.bankToken, position.user, position.amount, universalSwap);
    //         tokens = rewardAddresses.concat(outTokens);
    //         tokenAmounts = rewardAmounts.concat(outTokenAmounts);
    //     }
    //     address[] memory wanted = new address[](1);
    //     uint[] memory ratios = new uint[](1);
    //     uint[] memory slippage = new uint[](1);
    //     wanted[0] = stableToken;
    //     ratios[0] = 1;
    //     uint[] memory toReturn = IUniversalSwap(universalSwap).swapAfterTransfer(
    //         Provided(tokens, tokenAmounts, new Asset[](0)),
    //         new SwapPoint[](0),
    //         new Conversion[](0),
    //         Desired(wanted, new Asset[](0), ratios, slippage),
    //         position.user
    //     );
    //     position.amount = 0;
    //     positionClosed[positionId] = true;
    //     emit PositionClose(positionId);
    //     positionInteractions[positionId].push([block.number, block.timestamp, 1]);
    //     return toReturn[0];
    // }

    /// @inheritdoc IPositionsManager
    function harvestRewards(uint positionId) external returns (address[] memory rewards, uint[] memory rewardAmounts) {
        require(positions[positionId].user==msg.sender, "Unauthorized");
        computeDevFee(positionId);
        Position storage position = positions[positionId];
        BankBase bank = BankBase(banks[position.bankId]);
        (rewards, rewardAmounts) = bank.harvest(position.bankToken, position.user, position.user);
        Provided memory harvested = Provided(rewards, rewardAmounts, new Asset[](0));
        PositionInteraction memory interaction = PositionInteraction(
            "harvest",
            block.timestamp,
            block.number,
            harvested,
            IUniversalSwap(universalSwap).estimateValue(harvested, stableToken),
            0
        );
        _addPositionInteraction(interaction, positionId);
        emit Harvest(positionId, rewards, rewardAmounts);
    }

    /// @inheritdoc IPositionsManager
    function harvestAndRecompound(uint positionId, SwapPoint[] memory swaps, Conversion[] memory conversions, uint[] memory minAmounts) external returns (uint newLpTokens) {
        require(positions[positionId].user==msg.sender, "Unauthorized");
        computeDevFee(positionId);
        Position storage position = positions[positionId];
        BankBase bank = BankBase(banks[position.bankId]);
        (address[] memory underlying, uint[] memory ratios) = bank.getUnderlyingForRecurringDeposit(position.bankToken);
        address[] memory rewards; uint[] memory rewardAmounts; Provided memory harvested;
        if (minAmounts.length>0) {
            (rewards, rewardAmounts) = bank.harvest(position.bankToken, position.user, universalSwap);
            harvested = Provided(rewards, rewardAmounts, new Asset[](0));
            rewardAmounts = IUniversalSwap(universalSwap).swapAfterTransfer(
                Provided(rewards, rewardAmounts, new Asset[](0)),
                swaps, conversions,
                Desired(underlying, new Asset[](0), ratios, minAmounts),
                address(bank)
            );
        } else {
            (rewards, rewardAmounts) = bank.harvest(position.bankToken, position.user, address(bank));
            harvested = Provided(rewards, rewardAmounts, new Asset[](0));
        }
        if (rewardAmounts.length>0) {
            newLpTokens = bank.mintRecurring(position.bankToken, position.user, underlying, rewardAmounts);
            position.amount+=newLpTokens;
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
    }

    /// @inheritdoc IPositionsManager
    function estimateValue(uint positionId, address inTermsOf) external view returns (uint) {
        Position storage position = positions[positionId];
        BankBase bank = BankBase(banks[position.bankId]);
        (address[] memory underlyingTokens, uint[] memory underlyingAmounts) = bank.getPositionTokens(position.bankToken, position.user);
        (address[] memory rewardTokens, uint[] memory rewardAmounts) = bank.getPendingRewardsForUser(position.bankToken, position.user);
        Provided memory assets = Provided(underlyingTokens.concat(rewardTokens), underlyingAmounts.concat(rewardAmounts), new Asset[](0));
        return IUniversalSwap(universalSwap).estimateValue(assets, inTermsOf);
    }

    /// @inheritdoc IPositionsManager
    function getPositionTokens(uint positionId) external view returns (address[] memory tokens, uint[] memory amounts) {
        Position storage position = positions[positionId];
        BankBase bank = BankBase(banks[position.bankId]);
        (tokens, amounts) = bank.getPositionTokens(position.bankToken, position.user);
        (tokens, amounts) = IUniversalSwap(universalSwap).getUnderlying(tokens, amounts);
    }

    /// @inheritdoc IPositionsManager
    function getPositionRewards(uint positionId) external view returns (address[] memory rewards, uint[] memory rewardAmounts) {
        Position storage position = positions[positionId];
        BankBase bank = BankBase(banks[position.bankId]);
        (rewards, rewardAmounts) = bank.getPendingRewardsForUser(position.bankToken, position.user);
    }

    /// @inheritdoc IPositionsManager
    function botLiquidate(uint positionId, uint liquidationIndex, SwapPoint[] memory swaps, Conversion[] memory conversions, uint minAmountOut) external {
        computeDevFee(positionId);
        Position storage position = positions[positionId];
        BankBase bank = BankBase(banks[position.bankId]);
        address[] memory tokens;
        uint[] memory tokenAmounts;
        Provided memory positionAssets;
        {
            require(keepers[msg.sender] || msg.sender==owner(), "Unauthorized");
            (address[] memory rewardAddresses, uint[] memory rewardAmounts) = bank.harvest(position.bankToken, position.user, universalSwap);
            (address[] memory outTokens, uint[] memory outTokenAmounts) = bank.burn(position.bankToken, position.user, position.amount, universalSwap);
            tokens = rewardAddresses.concat(outTokens);
            tokenAmounts = rewardAmounts.concat(outTokenAmounts);
            positionAssets = Provided(tokens, tokenAmounts, new Asset[](0));
        }
        {
            address[] memory wanted = new address[](1);
            uint[] memory ratios = new uint[](1);
            uint[] memory slippage = new uint[](1);
            wanted[0] = position.liquidationPoints[liquidationIndex].liquidateTo;
            ratios[0] = 1;
            slippage[0] = minAmountOut;
            IUniversalSwap(universalSwap).swapAfterTransfer(
                Provided(tokens, tokenAmounts, new Asset[](0)),
                swaps, conversions,
                Desired(wanted, new Asset[](0), ratios, slippage),
                position.user
            );
        }
        PositionInteraction memory interaction = PositionInteraction(
            "liquidate",
            block.timestamp,
            block.number,
            positionAssets,
            IUniversalSwap(universalSwap).estimateValue(positionAssets, stableToken),
            position.amount
        );
        _addPositionInteraction(interaction, positionId);
        position.amount = 0;
        positionClosed[positionId] = true;
        emit PositionClose(positionId);
    }

    /// @inheritdoc IPositionsManager
    function computeDevFee(uint positionId) public {
        Position storage position = positions[positionId];
        PositionInteraction[] memory interactions = positionInteractions[positionId];
        IFeeModel feeModel;
        if (feeModels[positionId]==address(0)) {
            feeModel = IFeeModel(defaultFeeModel);
        } else {
            feeModel = IFeeModel(feeModels[positionId]);
        }
        uint fee = feeModel.calculateFee(position.amount, interactions);
        devShare[positionId]+=fee;
    }

    receive() external payable {}

    // Internal helper functions
    function _getWETH() internal returns (uint networkTokenObtained){
        uint startingBalance = IERC20(networkToken).balanceOf(address(this));
        if (msg.value>0) {
            IWETH(payable(networkToken)).deposit{value:msg.value}();
        }
        networkTokenObtained = IERC20(networkToken).balanceOf(address(this))-startingBalance;
    }

    function _addPositionInteraction(PositionInteraction memory interaction, uint positionId) internal {
        positionInteractions[positionId].push();
        uint idx = positionInteractions[positionId].length-1;
        positionInteractions[positionId][idx].action = interaction.action;
        positionInteractions[positionId][idx].timestamp = interaction.timestamp;
        positionInteractions[positionId][idx].blockNumber = interaction.blockNumber;
        positionInteractions[positionId][idx].usdValue = interaction.usdValue;
        positionInteractions[positionId][idx].positionSizeChange = interaction.positionSizeChange;
        positionInteractions[positionId][idx].assets.tokens = interaction.assets.tokens;
        positionInteractions[positionId][idx].assets.amounts = interaction.assets.amounts;
        for (uint i = 0; i<interaction.assets.nfts.length; i++) {
            positionInteractions[positionId][idx].assets.nfts.push(interaction.assets.nfts[i]);
        }
    }
}