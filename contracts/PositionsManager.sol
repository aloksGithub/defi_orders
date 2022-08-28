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
    event HarvestRecompount(uint positionId, uint lpTokens);

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
        return toReturn;
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

    function deposit(uint positionId, uint amount) public {
        Position storage position = positions[positionId];
        BankBase bank = BankBase(banks[position.bankId]);
        address lpToken = bank.getLPToken(position.bankToken);
        IERC20(lpToken).transferFrom(msg.sender, address(bank), amount);
        bank.mint(position.bankToken, position.user, amount);
        position.amount+=amount;
        emit IncreasePosition(positionId, amount);
    }

    function deposit(Position memory position) public returns (uint) {
        BankBase bank = BankBase(banks[position.bankId]);
        address lpToken = bank.getLPToken(position.bankToken);
        require(UniversalSwap(universalSwap).isSupported(lpToken), "Asset is not currently supported");
        IERC20(lpToken).transferFrom(position.user, address(bank), position.amount);
        bank.mint(position.bankToken, position.user, position.amount);
        positions.push();
        Position storage newPosition = positions[positions.length-1];
        newPosition.user = position.user;
        newPosition.bankId = position.bankId;
        newPosition.bankToken = position.bankToken;
        newPosition.amount = position.amount;
        for (uint i = 0; i<position.liquidationPoints.length; i++) {
            newPosition.liquidationPoints.push(position.liquidationPoints[i]);
        }
        emit Deposit(positions.length-1, position.bankId, position.bankToken, position.user, position.amount, position.liquidationPoints);
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

    function close(uint positionId) public {
        Position storage position = positions[positionId];
        BankBase bank = BankBase(banks[position.bankId]);
        require(position.user==msg.sender || keepers[msg.sender] || msg.sender==owner(), "Can't withdraw for another user");
        position.amount = 0;
        bank.harvest(position.bankToken, position.user, position.user);
        bank.burn(position.bankToken, position.user, position.amount, position.user);
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
        address lpToken = bank.getLPToken(position.bankToken);
        (address[] memory rewards, uint[] memory rewardAmounts) = bank.harvest(position.bankToken, position.user, address(this));
        for (uint i = 0; i<rewards.length; i++) {
            (bool success, ) = rewards[i].call(abi.encodeWithSignature("approve(address,uint256)", universalSwap, rewardAmounts[i]));
            if (!success) {
                revert("Failed to approve token");
            }
        }
        newLpTokens = _swapAssets(rewards, rewardAmounts, lpToken);
        IERC20(lpToken).transfer(address(bank), newLpTokens);
        bank.mint(position.bankToken, position.user, newLpTokens);
        position.amount+=newLpTokens;
        emit HarvestRecompount(positionId, newLpTokens);
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
            console.log(rewardAmounts[i]);
            IERC20(rewardAddresses[i]).safeApprove(universalSwap, rewardAmounts[i]);
        }
        for (uint j = 0; j<outTokens.length; j++) {
            tokens[j+rewardAddresses.length] = outTokens[j];
            tokenAmounts[j+rewardAddresses.length] = outTokenAmounts[j];
            IERC20(outTokens[j]).safeApprove(universalSwap, outTokenAmounts[j]);
        }
        uint toReturn = _swapAssets(tokens, tokenAmounts, position.liquidationPoints[liquidationIndex].liquidateTo);
        IERC20(position.liquidationPoints[liquidationIndex].liquidateTo).transfer(position.user, toReturn);
        position.amount = 0;
        emit PositionClose(positionId);
    }
}