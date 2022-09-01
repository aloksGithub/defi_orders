// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./Banks/BankBase.sol";
import "./UniversalSwap.sol";
import "./libraries/Strings.sol";

contract PositionsManager is Ownable {
    using strings for *;
    using SafeERC20 for IERC20;

    event KeeperUpdate(address keeper, bool active);
    event BankAdded(address bank, uint bankId);
    event BankUpdated(address newBankAddress, address oldBankAddress, uint bankId);
    event Deposit(uint positionId, uint bankId, uint bankToken, address user, uint amount, LiquidationCondition[] liquidationPoints);
    event IncreasePosition(uint positionId, uint amount);
    event Withdraw(uint positionId, uint amount);
    event PositionClose(uint positionId);
    event LiquidationPointsUpdate(uint positionId, LiquidationCondition[] liquidationPoints);
    event Harvest(uint positionId, address[] rewards, uint[] rewardAmounts);
    event HarvestRecompound(uint positionId, uint lpTokens);

    struct Position {
        address user;
        uint bankId;
        uint bankToken;
        uint amount;
        LiquidationCondition[] liquidationPoints;
    }

    struct LiquidationCondition {
        address watchedToken;
        address liquidateTo;
        bool lessThan;
        uint liquidationPoint;
    }

    Position[] positions;
    address[] public banks;
    address public universalSwap;
    mapping (address=>bool) keepers;

    constructor(address _universalSwap) {
        universalSwap = _universalSwap;
    }

    function numPositions() external view returns (uint) {
        return positions.length;
    }

    function setKeeper(address keeperAddress, bool active) external onlyOwner {
        keepers[keeperAddress] = active;
        emit KeeperUpdate(keeperAddress, active);
    }

    function addBank(address bank) external onlyOwner {
        banks.push(bank);
        emit BankAdded(bank, banks.length-1);
    }

    function migrateBank(uint bankId, address newBankAddress) external onlyOwner {
        emit BankUpdated(newBankAddress, banks[bankId], bankId);
        banks[bankId] = newBankAddress;
    }

    function getPosition(uint positionId) external view returns (Position memory position) {
        position = positions[positionId];
    }

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

    function _swapAssets(address[] memory tokens, uint[] memory tokenAmounts, address liquidateTo) internal returns (uint) {
        for (uint i = 0; i<tokens.length; i++) {
            IERC20(tokens[i]).safeApprove(universalSwap, tokenAmounts[i]);
        }
        uint toReturn = UniversalSwap(universalSwap).swap(tokens, tokenAmounts, liquidateTo);
        return toReturn;
    }

    function _swapForMultiple(address[] memory inTokens, uint[] memory tokenAmounts, address[] memory outTokens) internal returns (uint[] memory) {
        for (uint i = 0; i<inTokens.length; i++) {
            IERC20(inTokens[i]).safeApprove(universalSwap, tokenAmounts[i]);
        }
        address networkToken = UniversalSwap(universalSwap).networkToken();
        uint networkTokenMinted = UniversalSwap(universalSwap).swap(inTokens, tokenAmounts, networkToken);
        IERC20(networkToken).safeApprove(universalSwap, networkTokenMinted);
        uint[] memory outTokenAmounts = new uint[](outTokens.length);
        address[] memory temp = new address[](1);
        uint[] memory tempAmount = new uint[](1);
        temp[0] = networkToken;
        tempAmount[0] = networkTokenMinted/outTokens.length;
        for (uint j = 0; j<outTokens.length; j++) {
            outTokenAmounts[j] = UniversalSwap(universalSwap).swap(temp, tempAmount, outTokens[j]);
        }
        return outTokenAmounts;
    }

    function adjustLiquidationPoints(uint positionId, LiquidationCondition[] memory _liquidationPoints) external {
        require(msg.sender==positions[positionId].user);
        Position storage position = positions[positionId];
        delete position.liquidationPoints;
        for (uint i = 0; i<_liquidationPoints.length; i++) {
            position.liquidationPoints.push(_liquidationPoints[i]);
        }
        emit LiquidationPointsUpdate(positionId, _liquidationPoints);
    }

    function deposit(uint positionId, address[] memory suppliedTokens, uint[] memory suppliedAmounts) public {
        Position storage position = positions[positionId];
        BankBase bank = BankBase(banks[position.bankId]);
        address[] memory underlying = bank.getUnderlyingForRecurringDeposit(position.bankToken);
        for (uint i = 0; i<suppliedTokens.length; i++) {
            IERC20(suppliedTokens[i]).safeTransferFrom(msg.sender, address(this), suppliedAmounts[i]);
        }
        if (!_checkArraysMatch(underlying, suppliedTokens)) {
            suppliedAmounts = _swapForMultiple(suppliedTokens, suppliedAmounts, underlying);
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

    function deposit(Position memory position, address[] memory suppliedTokens, uint[] memory suppliedAmounts) public returns (uint) {
        BankBase bank = BankBase(banks[position.bankId]);
        // Maybe remove this check for uniswap v3
        // address lpToken = bank.getLPToken(position.bankToken);
        // require(UniversalSwap(universalSwap).isSupported(lpToken), "Asset is not currently supported");
        address[] memory underlying = bank.getUnderlyingForFirstDeposit(position.bankToken);
        if (!_checkArraysMatch(underlying, suppliedTokens)) {
            suppliedAmounts = _swapForMultiple(suppliedTokens, suppliedAmounts, underlying);
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

    function withdraw(uint positionId, uint amount) external {
        Position storage position = positions[positionId];
        BankBase bank = BankBase(banks[position.bankId]);
        require(position.amount>=amount, "Withdrawing more funds than available");
        require(position.user==msg.sender, "Can't withdraw for another user");
        position.amount-=amount;
        bank.burn(position.bankToken, position.user, amount, msg.sender);
        emit Withdraw(positionId, amount);
    }

    function close(uint positionId) external {
        Position storage position = positions[positionId];
        BankBase bank = BankBase(banks[position.bankId]);
        require(position.user==msg.sender || keepers[msg.sender] || msg.sender==owner(), "Can't withdraw for another user");
        bank.harvest(position.bankToken, position.user, position.user);
        bank.burn(position.bankToken, position.user, position.amount, position.user);
        position.amount = 0;
        emit PositionClose(positionId);
    }

    function harvestRewards(uint positionId) external returns (address[] memory rewards, uint[] memory rewardAmounts) {
        Position storage position = positions[positionId];
        BankBase bank = BankBase(banks[position.bankId]);
        (rewards, rewardAmounts) = bank.harvest(position.bankToken, position.user, position.user);
        emit Harvest(positionId, rewards, rewardAmounts);
    }

    function harvestAndRecompound(uint positionId) external returns (uint newLpTokens) {
        Position storage position = positions[positionId];
        BankBase bank = BankBase(banks[position.bankId]);
        address[] memory underlying = bank.getUnderlyingForRecurringDeposit(position.bankToken);
        (address[] memory rewards, uint[] memory rewardAmounts) = bank.harvest(position.bankToken, position.user, address(this));
        if (!_checkArraysMatch(underlying, rewards)) {
            rewardAmounts = _swapForMultiple(rewards, rewardAmounts, underlying);
        }
        for (uint i = 0; i<underlying.length; i++) {
            IERC20(underlying[i]).safeTransfer(address(bank), rewardAmounts[i]);
        }
        uint minted = bank.mintRecurring(position.bankToken, position.user, underlying, rewardAmounts);
        position.amount+=minted;
        emit HarvestRecompound(positionId, newLpTokens);
    }

    function botLiquidate(uint positionId, uint liquidationIndex) external {
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
        uint toReturn = _swapAssets(tokens, tokenAmounts, position.liquidationPoints[liquidationIndex].liquidateTo);
        IERC20(position.liquidationPoints[liquidationIndex].liquidateTo).safeTransfer(position.user, toReturn);
        position.amount = 0;
        emit PositionClose(positionId);
    }
}