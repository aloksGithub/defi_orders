// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./Banks/BankBase.sol";
import "./interfaces/IPositionsManager.sol";
import "./interfaces/IFeeModel.sol";
import "./UniversalSwap.sol";
import "./DefaultFeeModel.sol";
import "./interfaces/IPoolInteractor.sol";

contract PositionsManager is IPositionsManager, Ownable {
    using SafeERC20 for IERC20;

    Position[] positions;
    mapping (uint=>bool) public positionClosed; // Is position open
    // mapping (uint=>uint[]) public positionInteractions;
    mapping (uint=>uint[3][]) public positionInteractions; // Mapping from position Id to block numbers and interaction types for all position interactions
    mapping (address=>uint) public numUserPositions; // Number of positions for user
    mapping (address=>uint[]) public userPositions; // Mapping from user address to a list of position IDs belonging to the user
    mapping (uint=>address) public feeModels; // Mapping from position ID to fee model used for that position
    address defaultFeeModel;
    address[] public banks;
    address public universalSwap;
    address networkToken;
    address usdc;
    mapping (address=>bool) keepers;

    constructor(address _universalSwap, address _usdc, address _defaultFeeModel) {
        universalSwap = _universalSwap;
        usdc = _usdc;
        defaultFeeModel = _defaultFeeModel;
        networkToken = UniversalSwap(_universalSwap).networkToken();
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
    function deposit(uint positionId, address[] memory suppliedTokens, uint[] memory suppliedAmounts, uint[] memory minAmountsUsed) payable external {
        claimDevFee(positionId);
        Position storage position = positions[positionId];
        BankBase bank = BankBase(banks[position.bankId]);
        (address[] memory underlying, uint[] memory ratios) = bank.getUnderlyingForRecurringDeposit(position.bankToken);
        for (uint i = 0; i<suppliedTokens.length; i++) {
            IERC20(suppliedTokens[i]).safeTransferFrom(msg.sender, address(this), suppliedAmounts[i]);
        }
        uint ethSupplied = _getWETH();
        if (ethSupplied>0) {
            bool found = false;
            for (uint i = 0; i<suppliedTokens.length; i++) {
                if (suppliedTokens[i]==networkToken) {
                    suppliedAmounts[i]+=ethSupplied;
                    found = true;
                    break;
                }
            }
            if (!found) {
                address[] memory newTokens = new address[](suppliedTokens.length+1);
                newTokens[0] = networkToken;
                uint[] memory newAmounts = new uint[](suppliedAmounts.length+1);
                newAmounts[0] = ethSupplied;
                for (uint i = 0; i<suppliedTokens.length; i++) {
                    newTokens[i+1] = suppliedTokens[i];
                    newAmounts[i+1] = suppliedAmounts[i];
                }
                suppliedAmounts = newAmounts;
                suppliedTokens = newTokens;
            }
        }
        if (!_checkArraysMatch(underlying, suppliedTokens) || ratios.length>1) {
            for (uint i = 0; i<suppliedTokens.length; i++) {
                IERC20(suppliedTokens[i]).safeApprove(universalSwap, suppliedAmounts[i]);
            }
            suppliedAmounts = _swap(suppliedTokens, suppliedAmounts, underlying, ratios, minAmountsUsed);
            suppliedTokens = underlying;
        }
        for (uint i = 0; i<suppliedTokens.length; i++) {
            IERC20(suppliedTokens[i]).safeTransfer(address(bank), suppliedAmounts[i]);
        }
        uint minted = bank.mintRecurring(position.bankToken, position.user, suppliedTokens, suppliedAmounts);
        position.amount+=minted;
        positionInteractions[positionId].push([block.number, block.timestamp, 0]);
        emit IncreasePosition(positionId, minted);
    }

    /// @inheritdoc IPositionsManager
    function deposit(Position memory position, address[] memory suppliedTokens, uint[] memory suppliedAmounts) payable external returns (uint) {
        BankBase bank = BankBase(banks[position.bankId]);
        // TODO: Decide if isSupported check stays
        // address lpToken = bank.getLPToken(position.bankToken);
        // require(UniversalSwap(universalSwap).isSupported(lpToken), "Asset is not currently supported");
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
        claimDevFee(positionId);
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
        claimDevFee(positionId);
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
        claimDevFee(positionId);
        address[] memory tokens;
        uint[] memory tokenAmounts;
        Position storage position = positions[positionId];
        {
            BankBase bank = BankBase(banks[position.bankId]);
            require(keepers[msg.sender] || msg.sender==owner() || position.user==msg.sender, "Unauthorized");
            (address[] memory rewardAddresses, uint[] memory rewardAmounts) = bank.harvest(position.bankToken, position.user, address(this));
            (address[] memory outTokens, uint[] memory outTokenAmounts) = bank.burn(position.bankToken, position.user, position.amount, address(this));
            tokens = new address[](rewardAddresses.length+outTokens.length);
            tokenAmounts = new uint[](rewardAmounts.length+outTokenAmounts.length);
            for (uint i = 0; i<rewardAddresses.length; i++) {
                tokens[i] = rewardAddresses[i];
                tokenAmounts[i] = rewardAmounts[i];
            }
            for (uint j = 0; j<outTokens.length; j++) {
                tokens[j+rewardAddresses.length] = outTokens[j];
                tokenAmounts[j+rewardAddresses.length] = outTokenAmounts[j];
            }
            for (uint i = 0; i<tokens.length; i++) {
                IERC20(tokens[i]).safeApprove(universalSwap, tokenAmounts[i]);
            }
        }
        address[] memory wanted = new address[](1);
        uint[] memory ratios = new uint[](1);
        uint[] memory slippage = new uint[](1);
        wanted[0] = usdc;
        ratios[0] = 1;
        uint[] memory toReturn = _swap(tokens, tokenAmounts, wanted, ratios, slippage);
        IERC20(usdc).safeTransfer(position.user, toReturn[0]);
        position.amount = 0;
        positionClosed[positionId] = true;
        emit PositionClose(positionId);
        positionInteractions[positionId].push([block.number, block.timestamp, 1]);
        return toReturn[0];
    }

    /// @inheritdoc IPositionsManager
    function harvestRewards(uint positionId) external returns (address[] memory rewards, uint[] memory rewardAmounts) {
        require(positions[positionId].user==msg.sender, "Unauthorized");
        claimDevFee(positionId);
        Position storage position = positions[positionId];
        BankBase bank = BankBase(banks[position.bankId]);
        (rewards, rewardAmounts) = bank.harvest(position.bankToken, position.user, position.user);
        positionInteractions[positionId].push([block.number, block.timestamp, 2]);
        emit Harvest(positionId, rewards, rewardAmounts);
    }

    /// @inheritdoc IPositionsManager
    function harvestAndRecompound(uint positionId, uint[] memory minAmountsUsed) external returns (uint newLpTokens) {
        require(positions[positionId].user==msg.sender, "Unauthorized");
        claimDevFee(positionId);
        Position storage position = positions[positionId];
        BankBase bank = BankBase(banks[position.bankId]);
        (address[] memory underlying, uint[] memory ratios) = bank.getUnderlyingForRecurringDeposit(position.bankToken);
        (address[] memory rewards, uint[] memory rewardAmounts) = bank.harvest(position.bankToken, position.user, address(this));
        if (!_checkArraysMatch(underlying, rewards) || ratios.length>1) {
            for (uint i = 0; i<rewards.length; i++) {
                IERC20(rewards[i]).safeApprove(universalSwap, rewardAmounts[i]);
            }
            rewardAmounts = _swap(rewards, rewardAmounts, underlying, ratios, minAmountsUsed);
        }
        for (uint i = 0; i<underlying.length; i++) {
            IERC20(underlying[i]).safeTransfer(address(bank), rewardAmounts[i]);
        }
        uint minted = bank.mintRecurring(position.bankToken, position.user, underlying, rewardAmounts);
        position.amount+=minted;
        positionInteractions[positionId].push([block.number, block.timestamp, 3]);
        emit HarvestRecompound(positionId, newLpTokens);
    }

    /// @inheritdoc IPositionsManager
    function botLiquidate(uint positionId, uint liquidationIndex, uint minAmountOut) external {
        claimDevFee(positionId);
        Position storage position = positions[positionId];
        BankBase bank = BankBase(banks[position.bankId]);
        address[] memory tokens;
        uint[] memory tokenAmounts;
        {
            require(keepers[msg.sender] || msg.sender==owner(), "Unauthorized");
            (address[] memory rewardAddresses, uint[] memory rewardAmounts) = bank.harvest(position.bankToken, position.user, address(this));
            (address[] memory outTokens, uint[] memory outTokenAmounts) = bank.burn(position.bankToken, position.user, position.amount, address(this));
            tokens = new address[](rewardAddresses.length+outTokens.length);
            tokenAmounts = new uint[](rewardAmounts.length+outTokenAmounts.length);
            for (uint i = 0; i<rewardAddresses.length; i++) {
                tokens[i] = rewardAddresses[i];
                tokenAmounts[i] = rewardAmounts[i];
            }
            for (uint j = 0; j<outTokens.length; j++) {
                tokens[j+rewardAddresses.length] = outTokens[j];
                tokenAmounts[j+rewardAddresses.length] = outTokenAmounts[j];
            }
            for (uint i = 0; i<tokens.length; i++) {
                IERC20(tokens[i]).safeApprove(universalSwap, tokenAmounts[i]);
            }
        }
        {
            address[] memory wanted = new address[](1);
            uint[] memory ratios = new uint[](1);
            uint[] memory slippage = new uint[](1);
            wanted[0] = position.liquidationPoints[liquidationIndex].liquidateTo;
            ratios[0] = 1;
            slippage[0] = minAmountOut;
            console.log("_____");
            for (uint i = 0; i<tokens.length; i++) {
                console.log(tokens[i], tokenAmounts[i]);
            }
            console.log("_____");
            uint[] memory toReturn = _swap(tokens, tokenAmounts, wanted, ratios, slippage);
            IERC20(position.liquidationPoints[liquidationIndex].liquidateTo).safeTransfer(position.user, toReturn[0]);
        }
        position.amount = 0;
        positionClosed[positionId] = true;
        positionInteractions[positionId].push([block.number, block.timestamp, 4]);
        emit PositionClose(positionId);
    }

    /// @inheritdoc IPositionsManager
    function claimDevFee(uint positionId) public {
        Position storage position = positions[positionId];
        uint[3][] memory interactions = positionInteractions[positionId];
        IFeeModel feeModel;
        if (feeModels[positionId]==address(0)) {
            feeModel = IFeeModel(defaultFeeModel);
        } else {
            feeModel = IFeeModel(feeModels[positionId]);
        }
        uint fee = feeModel.calculateFee(position.amount, interactions);
        if (fee>0) {
            BankBase bank = BankBase(banks[position.bankId]);
            position.amount-=fee;
            (address[] memory tokens, uint[] memory tokenAmounts) = bank.burn(position.bankToken, position.user, fee, address(this));
            address[] memory wanted = new address[](1);
            uint[] memory ratios = new uint[](1);
            uint[] memory slippage = new uint[](1);
            wanted[0] = usdc;
            ratios[0] = 1;
            slippage[0] = 0;
            uint[] memory received = _swap(tokens, tokenAmounts, wanted, ratios, slippage);
            IERC20(usdc).safeTransfer(owner(), received[0]);
            emit FeeClaimed(positionId, received[0]);
        }
    }

    // Internal helper functions
    function _checkArraysMatch(address[] memory array1, address[] memory array2) internal pure returns (bool) {
        if (array1.length!=array2.length) return false;
        for (uint i = 0; i<array1.length; i++) {
            bool matchFound = false;
            for (uint j = 0; j<array2.length; j++) {
                if (array1[i]==array2[j]) {
                    matchFound = true;
                    break;
                }
            }
            if (!matchFound) {
                return false;
            }
        }
        return true;
    }

    function _getWETH() internal returns (uint networkTokenObtained){
        uint startingBalance = IERC20(networkToken).balanceOf(address(this));
        if (msg.value>0) {
            IWETH(payable(networkToken)).deposit{value:msg.value}();
        }
        networkTokenObtained = IERC20(networkToken).balanceOf(address(this))-startingBalance;
    }

    function _swap(address[] memory tokens, uint[] memory tokenAmounts, address[] memory wanted, uint[] memory ratios, uint[] memory slippage) internal returns (uint[] memory) {
        Asset[] memory temp;
        return UniversalSwap(universalSwap).swapV2(tokens, tokenAmounts, temp, wanted, temp, ratios, slippage);
    }
}