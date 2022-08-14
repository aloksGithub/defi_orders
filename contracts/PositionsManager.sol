// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./Banks/BankBase.sol";
import "./UniversalSwap.sol";
import "./libraries/Strings.sol";

contract PositionsManager is Ownable {
    using strings for *;

    event KeeperUpdate(address keeper, bool active);
    event BankAdded(address bank, uint bankId);
    event BankUpdated(address newBankAddress, address oldBankAddress, uint bankId);
    event Deposit(uint positionId, uint bankId, uint bankToken, address user, uint amount, address[] watchedTokens, bool[] lessThan, uint[] liquidationPoints);
    event IncreasePosition(uint positionId, uint amount);
    event Withdraw(uint positionId, uint amount, bool convert);
    event PositionClose(uint positionId, bool convert);
    event LiquidationPointsUpdate(uint positionId, address[] watchedTokens, uint[] liquidationPoints);
    event Harvest(uint positionId, address[] rewards, uint[] rewardAmounts);
    event HarvestRecompount(uint positionId, uint lpTokens);

    struct Position {
        address user;
        uint bankId;
        uint bankToken;
        uint amount;
        address liquidateTo;
        address[] watchedTokens;
        bool[] lessThan;
        uint[] liquidationPoints;
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

    function recommendBank(address lpToken) external view returns (uint, uint) {
        uint erc20BankId;
        uint erc20BankTokenId;
        for (uint i = 0; i<banks.length; i++) {
            string memory name = BankBase(banks[i]).name();
            if (name.toSlice().startsWith("ERC20 Bank".toSlice())) {
                (,erc20BankTokenId) = BankBase(banks[i]).getIdFromLpToken(lpToken);
                erc20BankId = i;
                continue;
            }
            (bool success, uint tokenId) = BankBase(banks[i]).getIdFromLpToken(lpToken);
            if (success) {
                return (i, tokenId);
            }
        }
        return (erc20BankId, erc20BankTokenId);
    }

    function _swapAssets(address[] memory tokens, uint[] memory tokenAmounts, address liquidateTo) internal returns (uint) {
        for (uint i = 0; i<tokens.length; i++) {
            IERC20(tokens[i]).approve(universalSwap, tokenAmounts[i]);
        }
        uint toReturn = UniversalSwap(universalSwap).swap(tokens, tokenAmounts, liquidateTo);
        // (bool success, bytes memory returnData) = universalSwap.delegatecall(abi.encodeWithSignature("swap(address[], uint[], address)", tokens, tokenAmounts, liquidateTo));
        // if (!success) {
        //     revert("Failed to convert tokens");
        // }
        // (uint toReturn) = abi.decode(returnData, (uint));
        return toReturn;
    }

    function adjustLiquidationPoints(uint positionId, address[] calldata watchedTokens, bool[] calldata lessThan, uint[] calldata liquidationPoints) external {
        require (watchedTokens.length==liquidationPoints.length && watchedTokens.length>0, "Invalid liquidation request");
        Position storage position = positions[positionId];
        position.watchedTokens = watchedTokens;
        position.lessThan = lessThan;
        position.liquidationPoints = liquidationPoints;
        emit LiquidationPointsUpdate(positionId, watchedTokens, liquidationPoints);
    }

    function deposit(uint positionId, uint amount) public {
        Position storage position = positions[positionId];
        BankBase bank = BankBase(banks[position.bankId]);
        address lpToken = bank.getLPToken(position.bankToken);
        ERC20(lpToken).transferFrom(msg.sender, address(bank), amount);
        bank.mint(position.bankToken, position.user, amount);
        position.amount+=amount;
        emit IncreasePosition(positionId, amount);
    }

    function deposit(Position memory position) public returns (uint) {
        require (position.watchedTokens.length==position.liquidationPoints.length && position.lessThan.length==position.watchedTokens.length && position.watchedTokens.length>0, "Invalid liquidation request");
        BankBase bank = BankBase(banks[position.bankId]);
        address lpToken = bank.getLPToken(position.bankToken);
        require(UniversalSwap(universalSwap).isSupported(lpToken), "Asset is not currently supported");
        ERC20(lpToken).transferFrom(position.user, address(bank), position.amount);
        bank.mint(position.bankToken, position.user, position.amount);
        positions.push(position);
        emit Deposit(positions.length-1, position.bankId, position.bankToken, position.user, position.amount, position.watchedTokens, position.lessThan, position.liquidationPoints);
        return positions.length-1;
    }

    function withdraw(uint positionId, uint amount, bool convert) external {
        Position storage position = positions[positionId];
        BankBase bank = BankBase(banks[position.bankId]);
        require(position.amount>=amount, "Withdrawing more funds than available");
        require(position.user==msg.sender, "Can't withdraw for another user");
        position.amount-=amount;
        if (!convert) {
            bank.burn(position.bankToken, position.user, amount, msg.sender);
            emit Withdraw(positionId, amount, convert);
            return;
        }
        bank.burn(position.bankToken, position.user, amount, address(this));
        address lpToken = bank.getLPToken(position.bankToken);
        address[] memory tokens = new address[](1);
        tokens[0] = lpToken;
        uint[] memory tokenAmounts = new uint[](1);
        tokenAmounts[0] = amount;
        uint toReturn = _swapAssets(tokens, tokenAmounts, position.liquidateTo);
        IERC20(position.liquidateTo).transfer(position.user, toReturn);
        emit Withdraw(positionId, amount, convert);
    }

    function close(uint positionId, bool convert) public {
        Position storage position = positions[positionId];
        BankBase bank = BankBase(banks[position.bankId]);
        require(position.user==msg.sender || keepers[msg.sender] || msg.sender==owner(), "Can't withdraw for another user");
        if (!convert) {
            position.amount = 0;
            bank.harvest(position.bankToken, position.user, position.user);
            bank.burn(position.bankToken, position.user, position.amount, position.user);
            return;
        }
        (address[] memory rewardAddresses, uint[] memory rewardAmounts) = bank.harvest(position.bankToken, position.user, address(this));
        bank.burn(position.bankToken, position.user, position.amount, address(this));
        address lpToken = bank.getLPToken(position.bankToken);
        // IERC20(lpToken).approve(universalSwap, position.amount);
        address[] memory tokens = new address[](rewardAddresses.length+1);
        uint[] memory tokenAmounts = new uint[](rewardAmounts.length+1);
        tokens[0] = lpToken;
        tokenAmounts[0] = position.amount;
        for (uint i = 0; i<rewardAddresses.length; i++) {
            tokens[i+1] = rewardAddresses[i];
            tokenAmounts[i+1] = rewardAmounts[i];
            IERC20(rewardAddresses[i]).approve(universalSwap, rewardAmounts[i]);
        }
        uint toReturn = _swapAssets(tokens, tokenAmounts, position.liquidateTo);
        IERC20(position.liquidateTo).transfer(position.user, toReturn);
        position.amount = 0;
        emit PositionClose(positionId, convert);
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
        address lpToken = bank.getLPToken(position.bankToken);
        (address[] memory rewards, uint[] memory rewardAmounts) = bank.harvest(position.bankToken, position.user, address(this));
        for (uint i = 0; i<rewards.length; i++) {
            (bool success, ) = rewards[i].call(abi.encodeWithSignature("approve(address,uint256)", universalSwap, rewardAmounts[i]));
        if (!success) {
            revert("Failed to approve token");
        }
        }
        newLpTokens = _swapAssets(rewards, rewardAmounts, lpToken);
        ERC20(lpToken).transfer(address(bank), newLpTokens);
        bank.mint(position.bankToken, position.user, newLpTokens);
        position.amount+=newLpTokens;
        emit HarvestRecompount(positionId, newLpTokens);
    }

    function botLiquidate(uint positionId) external {
        close(positionId, true);
    }
}