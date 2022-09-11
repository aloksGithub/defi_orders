// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./Banks/BankBase.sol";
import "./interfaces/IPositionsManager.sol";
import "./UniversalSwap.sol";

contract PositionsManager is IPositionsManager, Ownable {
    using SafeERC20 for IERC20;

    Position[] positions;
    address[] public banks;
    address public universalSwap;
    mapping (address=>bool) keepers;

    constructor(address _universalSwap) {
        universalSwap = _universalSwap;
    }

    /// @inheritdoc IPositionsManager
    function numPositions() external view returns (uint) {
        return positions.length;
    }

    /// @inheritdoc IPositionsManager
    function setKeeper(address keeperAddress, bool active) external onlyOwner {
        keepers[keeperAddress] = active;
        emit KeeperUpdate(keeperAddress, active);
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
    function recommendBank(address lpToken) external view returns (uint[] memory, uint[] memory) {
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
        uint[] memory tokenIds2 = new uint[](numSupported);
        uint idx = 0;
        for (uint j = 0; j<banks.length; j++) {
            if (supportedBank[j]) {
                bankIds[idx] = j;
                tokenIds2[idx] = tokenIds[j];
                idx+=1;
            }
        }
        return (bankIds, tokenIds2);
    }

    /// @inheritdoc IPositionsManager
    function adjustLiquidationPoints(uint positionId, LiquidationCondition[] memory _liquidationPoints) external {
        require(msg.sender==positions[positionId].user);
        Position storage position = positions[positionId];
        delete position.liquidationPoints;
        for (uint i = 0; i<_liquidationPoints.length; i++) {
            position.liquidationPoints.push(_liquidationPoints[i]);
        }
        emit LiquidationPointsUpdate(positionId, _liquidationPoints);
    }

    /// @inheritdoc IPositionsManager
    function deposit(uint positionId, address[] memory suppliedTokens, uint[] memory suppliedAmounts, uint[] memory minAmountsUsed) public {
        Position storage position = positions[positionId];
        BankBase bank = BankBase(banks[position.bankId]);
        address[] memory underlying = bank.getUnderlyingForRecurringDeposit(position.bankToken);
        for (uint i = 0; i<suppliedTokens.length; i++) {
            IERC20(suppliedTokens[i]).safeTransferFrom(msg.sender, address(this), suppliedAmounts[i]);
        }
        if (!_checkArraysMatch(underlying, suppliedTokens)) {
            for (uint i = 0; i<suppliedTokens.length; i++) {
                IERC20(suppliedTokens[i]).safeApprove(universalSwap, suppliedAmounts[i]);
            }
            suppliedAmounts = UniversalSwap(universalSwap).swap(suppliedTokens, suppliedAmounts, underlying, minAmountsUsed);
            suppliedTokens = underlying;
        }
        for (uint i = 0; i<suppliedTokens.length; i++) {
            IERC20(suppliedTokens[i]).safeTransfer(address(bank), suppliedAmounts[i]);
        }
        uint minted = bank.mintRecurring(position.bankToken, position.user, suppliedTokens, suppliedAmounts);
        position.amount+=minted;
        emit IncreasePosition(positionId, minted);
    }

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

    /// @inheritdoc IPositionsManager
    function deposit(Position memory position, address[] memory suppliedTokens, uint[] memory suppliedAmounts, uint[] memory minAmountsUsed) public returns (uint) {
        BankBase bank = BankBase(banks[position.bankId]);
        // TODO: Decide if isSupported check stays
        // address lpToken = bank.getLPToken(position.bankToken);
        // require(UniversalSwap(universalSwap).isSupported(lpToken), "Asset is not currently supported");
        address[] memory underlying = bank.getUnderlyingForFirstDeposit(position.bankToken);
        if (!_checkArraysMatch(underlying, suppliedTokens)) {
            for (uint i = 0; i<suppliedTokens.length; i++) {
                IERC20(suppliedTokens[i]).safeApprove(universalSwap, suppliedAmounts[i]);
            }
            suppliedAmounts = UniversalSwap(universalSwap).swap(suppliedTokens, suppliedAmounts, underlying, minAmountsUsed);
            suppliedTokens = underlying;
        }
        for (uint i = 0; i<suppliedTokens.length; i++) {
            (bool success, ) = suppliedTokens[i].call(abi.encodeWithSignature("transferFrom(address,address,uint256)", msg.sender, address(bank), suppliedAmounts[i]));
            require(success, "Failed to transfer asset to bank");
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
        emit Deposit(positions.length-1, newPosition.bankId, newPosition.bankToken, newPosition.user, newPosition.amount, newPosition.liquidationPoints);
        return positions.length-1;
    }

    /// @inheritdoc IPositionsManager
    function withdraw(uint positionId, uint amount) external {
        Position storage position = positions[positionId];
        BankBase bank = BankBase(banks[position.bankId]);
        require(position.amount>=amount, "Withdrawing more funds than available");
        require(position.user==msg.sender, "Can't withdraw for another user");
        position.amount-=amount;
        bank.burn(position.bankToken, position.user, amount, msg.sender);
        emit Withdraw(positionId, amount);
    }

    /// @inheritdoc IPositionsManager
    function close(uint positionId) external {
        Position storage position = positions[positionId];
        BankBase bank = BankBase(banks[position.bankId]);
        require(position.user==msg.sender || keepers[msg.sender] || msg.sender==owner(), "Can't withdraw for another user");
        bank.harvest(position.bankToken, position.user, position.user);
        bank.burn(position.bankToken, position.user, position.amount, position.user);
        position.amount = 0;
        emit PositionClose(positionId);
    }

    /// @inheritdoc IPositionsManager
    function harvestRewards(uint positionId) external returns (address[] memory rewards, uint[] memory rewardAmounts) {
        Position storage position = positions[positionId];
        BankBase bank = BankBase(banks[position.bankId]);
        (rewards, rewardAmounts) = bank.harvest(position.bankToken, position.user, position.user);
        emit Harvest(positionId, rewards, rewardAmounts);
    }

    /// @inheritdoc IPositionsManager
    function harvestAndRecompound(uint positionId) external returns (uint newLpTokens) {
        Position storage position = positions[positionId];
        BankBase bank = BankBase(banks[position.bankId]);
        address[] memory underlying = bank.getUnderlyingForRecurringDeposit(position.bankToken);
        (address[] memory rewards, uint[] memory rewardAmounts) = bank.harvest(position.bankToken, position.user, address(this));
        if (!_checkArraysMatch(underlying, rewards)) {
            uint[] memory minAmountsUsed = new uint[](rewards.length);
            for (uint i = 0; i<rewards.length; i++) {
                IERC20(rewards[i]).safeApprove(universalSwap, rewardAmounts[i]);
            }
            rewardAmounts = UniversalSwap(universalSwap).swap(rewards, rewardAmounts, underlying, minAmountsUsed);
        }
        for (uint i = 0; i<underlying.length; i++) {
            IERC20(underlying[i]).safeTransfer(address(bank), rewardAmounts[i]);
        }
        uint minted = bank.mintRecurring(position.bankToken, position.user, underlying, rewardAmounts);
        position.amount+=minted;
        emit HarvestRecompound(positionId, newLpTokens);
    }

    /// @inheritdoc IPositionsManager
    function botLiquidate(uint positionId, uint liquidationIndex, uint minAmountOut) external {
        Position storage position = positions[positionId];
        BankBase bank = BankBase(banks[position.bankId]);
        require(keepers[msg.sender] || msg.sender==owner(), "Unauthorized");
        (address[] memory rewardAddresses, uint[] memory rewardAmounts) = bank.harvest(position.bankToken, position.user, address(this));
        (address[] memory outTokens, uint[] memory outTokenAmounts) = bank.burn(position.bankToken, position.user, position.amount, address(this));
        address[] memory tokens = new address[](rewardAddresses.length+outTokens.length);
        uint[] memory tokenAmounts = new uint[](rewardAmounts.length+outTokenAmounts.length);
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
        uint toReturn = UniversalSwap(universalSwap).swap(tokens, tokenAmounts, position.liquidationPoints[liquidationIndex].liquidateTo, minAmountOut);
        IERC20(position.liquidationPoints[liquidationIndex].liquidateTo).safeTransfer(position.user, toReturn);
        position.amount = 0;
        emit PositionClose(positionId);
    }
}