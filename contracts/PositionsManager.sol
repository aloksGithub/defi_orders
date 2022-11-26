// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./Banks/BankBase.sol";
import "./interfaces/IPositionsManager.sol";
import "./interfaces/IFeeModel.sol";
import "./UniversalSwap.sol";
import "./interfaces/IUniversalSwap.sol";
import "./DefaultFeeModel.sol";
import "./interfaces/IPoolInteractor.sol";
import "./libraries/AddressArray.sol";
import "./libraries/UintArray.sol";

contract PositionsManager is IPositionsManager, Ownable {
    using SafeERC20 for IERC20;
    using UintArray for uint[];
    using AddressArray for address[];

    Position[] positions;
    mapping (uint=>bool) public positionClosed; // Is position open
    // mapping (uint=>uint[]) public positionInteractions;
    mapping (uint=>uint[3][]) public positionInteractions; // Mapping from position Id to block numbers and interaction types for all position interactions
    mapping (address=>uint) public numUserPositions; // Number of positions for user
    mapping (address=>uint[]) public userPositions; // Mapping from user address to a list of position IDs belonging to the user
    mapping (uint=>address) public feeModels; // Mapping from position ID to fee model used for that position
    mapping (uint=>uint) public devShare; // Mapping from position ID to share of the position that can be claimed as dev fee
    address defaultFeeModel;
    address[] public banks;
    address public universalSwap;
    address networkToken;
    address stableToken; // Stable token such as USDC or BUSD is used to measure the value of the position using the function closeToUSDC
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
    function getPositionInteractions(uint positionId) external view returns (uint[3][] memory) {
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
        banks.push(bank);
        emit BankAdded(bank, banks.length-1);
    }

    /// @inheritdoc IPositionsManager
    function migrateBank(uint bankId, address newBankAddress) external onlyOwner {
        emit BankUpdated(newBankAddress, banks[bankId], bankId);
        banks[bankId] = newBankAddress;
    }

    /// @inheritdoc IPositionsManager
    function getPosition(uint positionId) external view returns (Position memory position) {
        position = positions[positionId];
    }

    /// @inheritdoc IPositionsManager
    function recommendBank(address lpToken) external view returns (uint[] memory, string[] memory, uint[] memory) {
        if (lpToken==address(0)) {
            lpToken = networkToken;
        }
        bool[] memory supportedBank = new bool[](banks.length);
        uint[] memory tokenIds = new uint[](banks.length);
        uint numSupported = 0;
        for (uint i = 0; i<banks.length; i++) {
            (bool success, uint tokenId) = BankBase(banks[i]).getIdFromLpToken(lpToken);
            if (success) {
                numSupported+=1;
                supportedBank[i] = true;
                tokenIds[i] = tokenId;
            }
        }
        uint[] memory bankIds = new uint[](numSupported);
        string[] memory bankNames = new string[](numSupported);
        uint[] memory tokenIds2 = new uint[](numSupported);
        uint idx = 0;
        for (uint j = 0; j<banks.length; j++) {
            if (supportedBank[j]) {
                bankIds[idx] = j;
                bankNames[idx] = BankBase(banks[j]).name();
                tokenIds2[idx] = tokenIds[j];
                idx+=1;
            }
        }
        return (bankIds, bankNames, tokenIds2);
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
        (address[] memory underlying, uint[] memory ratios) = bank.getUnderlyingForRecurringDeposit(position.bankToken);
        uint ethSupplied = _getWETH();
        if (ethSupplied>0) {
            provided.tokens = provided.tokens.append(networkToken);
            provided.amounts = provided.amounts.append(ethSupplied);
            (provided.tokens, provided.amounts) = provided.tokens.shrink(provided.amounts);
        }
        if (minAmounts.length>0) {
            for (uint i = 0; i<provided.tokens.length; i++) {
                IERC20(provided.tokens[i]).safeTransferFrom(msg.sender, universalSwap, provided.amounts[i]);
            }
            for (uint i = 0; i<provided.nfts.length; i++) {
                IERC721(provided.nfts[i].manager).safeTransferFrom(msg.sender, universalSwap, provided.nfts[i].tokenId);
            }
            provided.amounts = IUniversalSwap(universalSwap).swapAfterTransfer(
                provided,
                swaps, conversions,
                Desired(underlying, new Asset[](0), ratios, minAmounts),
                address(bank)
            );
            provided.tokens = underlying;
        } else {
            for (uint i = 0; i<provided.tokens.length; i++) {
                IERC20(provided.tokens[i]).safeTransferFrom(msg.sender, address(bank), provided.amounts[i]);
            }
        }
        uint minted = bank.mintRecurring(position.bankToken, position.user, provided.tokens, provided.amounts);
        position.amount+=minted;
        positionInteractions[positionId].push([block.number, block.timestamp, 0]);
        emit IncreasePosition(positionId, minted);
    }

    /// @inheritdoc IPositionsManager
    function deposit(Position memory position, address[] memory suppliedTokens, uint[] memory suppliedAmounts) payable external returns (uint) {
        BankBase bank = BankBase(banks[position.bankId]);
        address lpToken = bank.getLPToken(position.bankToken);
        require(IUniversalSwap(universalSwap).isSupported(lpToken), "UT1"); // UnsupportedToken
        uint ethSupplied = _getWETH();
        if (ethSupplied>0) {
            IERC20(networkToken).safeTransfer(address(bank), ethSupplied);
        }
        require(ethSupplied>0 && suppliedTokens.length==0 || ethSupplied==0 && suppliedTokens.length>0, "Invlid tokens supplied");
        for (uint i = 0; i<suppliedTokens.length; i++) {
            IERC20(suppliedTokens[i]).safeTransferFrom(msg.sender, address(bank), suppliedAmounts[i]);
        }
        if (ethSupplied>0) {
            suppliedTokens = new address[](1);
            suppliedAmounts = new uint[](1);
            suppliedTokens[0] = networkToken;
            suppliedAmounts[0] = ethSupplied;
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
        positionInteractions[positions.length-1].push([block.number, block.timestamp, 0]);
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
        bank.burn(position.bankToken, position.user, amount, msg.sender);
        positionInteractions[positionId].push([block.number, block.timestamp, 1]);
        emit Withdraw(positionId, amount);
    }

    /// @inheritdoc IPositionsManager
    function close(uint positionId) external {
        computeDevFee(positionId);
        Position storage position = positions[positionId];
        BankBase bank = BankBase(banks[position.bankId]);
        require(position.user==msg.sender || msg.sender==owner(), "Unauthorized");
        bank.harvest(position.bankToken, position.user, position.user);
        bank.burn(position.bankToken, position.user, position.amount, position.user);
        position.amount = 0;
        positionClosed[positionId] = true;
        positionInteractions[positionId].push([block.number, block.timestamp, 1]);
        emit PositionClose(positionId);
    }

    /// @inheritdoc IPositionsManager
    function closeToUSDC(uint positionId) external returns (uint) {
        // computeDevFee(positionId);
        address[] memory tokens;
        uint[] memory tokenAmounts;
        Position storage position = positions[positionId];
        {
            BankBase bank = BankBase(banks[position.bankId]);
            require(keepers[msg.sender] || msg.sender==owner() || position.user==msg.sender, "Unauthorized");
            (address[] memory rewardAddresses, uint[] memory rewardAmounts) = bank.harvest(position.bankToken, position.user, universalSwap);
            (address[] memory outTokens, uint[] memory outTokenAmounts) = bank.burn(position.bankToken, position.user, position.amount, universalSwap);
            tokens = rewardAddresses.concat(outTokens);
            tokenAmounts = rewardAmounts.concat(outTokenAmounts);
        }
        address[] memory wanted = new address[](1);
        uint[] memory ratios = new uint[](1);
        uint[] memory slippage = new uint[](1);
        wanted[0] = stableToken;
        ratios[0] = 1;
        uint[] memory toReturn = IUniversalSwap(universalSwap).swapAfterTransfer(
            Provided(tokens, tokenAmounts, new Asset[](0)),
            new SwapPoint[](0),
            new Conversion[](0),
            Desired(wanted, new Asset[](0), ratios, slippage),
            position.user
        );
        position.amount = 0;
        positionClosed[positionId] = true;
        emit PositionClose(positionId);
        positionInteractions[positionId].push([block.number, block.timestamp, 1]);
        return toReturn[0];
    }

    /// @inheritdoc IPositionsManager
    function harvestRewards(uint positionId) external returns (address[] memory rewards, uint[] memory rewardAmounts) {
        require(positions[positionId].user==msg.sender, "Unauthorized");
        computeDevFee(positionId);
        Position storage position = positions[positionId];
        BankBase bank = BankBase(banks[position.bankId]);
        (rewards, rewardAmounts) = bank.harvest(position.bankToken, position.user, position.user);
        positionInteractions[positionId].push([block.number, block.timestamp, 2]);
        emit Harvest(positionId, rewards, rewardAmounts);
    }

    /// @inheritdoc IPositionsManager
    function harvestAndRecompound(uint positionId, SwapPoint[] memory swaps, Conversion[] memory conversions, uint[] memory minAmounts) external returns (uint newLpTokens) {
        require(positions[positionId].user==msg.sender, "Unauthorized");
        computeDevFee(positionId);
        Position storage position = positions[positionId];
        BankBase bank = BankBase(banks[position.bankId]);
        (address[] memory underlying, uint[] memory ratios) = bank.getUnderlyingForRecurringDeposit(position.bankToken);
        uint[] memory rewardAmounts;
        if (minAmounts.length>0) {
            address[] memory rewards;
            (rewards, rewardAmounts) = bank.harvest(position.bankToken, position.user, universalSwap);
            rewardAmounts = IUniversalSwap(universalSwap).swapAfterTransfer(
                Provided(rewards, rewardAmounts, new Asset[](0)),
                swaps, conversions,
                Desired(underlying, new Asset[](0), ratios, minAmounts),
                address(bank)
            );
        } else {
            (, rewardAmounts) = bank.harvest(position.bankToken, position.user, address(bank));
        }
        uint minted = bank.mintRecurring(position.bankToken, position.user, underlying, rewardAmounts);
        position.amount+=minted;
        positionInteractions[positionId].push([block.number, block.timestamp, 3]);
        emit HarvestRecompound(positionId, newLpTokens);
    }

    /// @inheritdoc IPositionsManager
    function botLiquidate(uint positionId, uint liquidationIndex, SwapPoint[] memory swaps, Conversion[] memory conversions, uint minAmountOut) external {
        computeDevFee(positionId);
        Position storage position = positions[positionId];
        BankBase bank = BankBase(banks[position.bankId]);
        address[] memory tokens;
        uint[] memory tokenAmounts;
        {
            require(keepers[msg.sender] || msg.sender==owner(), "Unauthorized");
            (address[] memory rewardAddresses, uint[] memory rewardAmounts) = bank.harvest(position.bankToken, position.user, universalSwap);
            (address[] memory outTokens, uint[] memory outTokenAmounts) = bank.burn(position.bankToken, position.user, position.amount, universalSwap);
            tokens = rewardAddresses.concat(outTokens);
            tokenAmounts = rewardAmounts.concat(outTokenAmounts);
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
        position.amount = 0;
        positionClosed[positionId] = true;
        positionInteractions[positionId].push([block.number, block.timestamp, 4]);
        emit PositionClose(positionId);
    }

    /// @inheritdoc IPositionsManager
    function computeDevFee(uint positionId) public {
        Position storage position = positions[positionId];
        uint[3][] memory interactions = positionInteractions[positionId];
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
}