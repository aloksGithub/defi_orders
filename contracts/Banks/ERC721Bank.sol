// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import '@openzeppelin/contracts/token/ERC721/IERC721.sol';
import "./ERC721Wrappers.sol";
import "./BankBase.sol";

contract ERC721Bank is BankBase {
    using Address for address;

    struct PoolInfo {
        address user;
        uint liquidity;
        // mapping(address=>mapping(uint=>bool)) userShares;
    }

    address[] nftManagers;
    mapping(address=>address) erc721Wrappers;

    mapping (uint=>PoolInfo) poolInfo;

    constructor(address _positionsManager) BankBase(_positionsManager) {}

    function addManager(address nftManager) external onlyOwner {
        nftManagers.push(nftManager);
    }

    function setWrapper(address nftManager, address wrapper) external onlyOwner {
        erc721Wrappers[nftManager] = wrapper;
    }

    function encodeId(uint id, address nftManager) public view returns (uint) {
        for (uint i = 0; i<nftManagers.length; i++) {
            if (nftManagers[i]==nftManager) {
                return (i << 240) | uint240(id);
            }
        }
        revert("NFT manager not supported");
    }

    function decodeId(uint id) public override view returns (address poolAddress, address nftManager, uint pos_id) {
        nftManager = nftManagers[id>>240];
        pos_id = uint240(id & ((1 << 240) - 1));
        poolAddress = IERC721Wrapper(erc721Wrappers[nftManager]).getPoolAddress(nftManager, pos_id);
    }

    function getLPToken(uint id) override public view returns (address managerAddress) {
        (,managerAddress,) = decodeId(id);
    }
    
    function getIdFromLpToken(address manager) override public view returns (bool, uint) {
        for (uint i = 0; i<nftManagers.length; i++) {
            if (nftManagers[i]==manager) {
                return (true, uint160(nftManagers[i]));
            }
        }
        return (false, 0);
    }

    function name() override public pure returns (string memory) {
        return "ERC721 Bank";
    }

    function mint(uint tokenId, address userAddress, address[] memory suppliedTokens, uint[] memory suppliedAmounts) onlyAuthorized override public returns (uint) {
        (,,,,,,,uint minted,,,,) = INonfungiblePositionManager(suppliedTokens[0]).positions(suppliedAmounts[0]);
        poolInfo[tokenId] = PoolInfo(userAddress, minted);
        return minted;
    }

    function mintRecurring(uint tokenId, address userAddress, address[] memory suppliedTokens, uint[] memory suppliedAmounts) onlyAuthorized override external returns (uint) {
        require(poolInfo[tokenId].user==userAddress, "User doesn't own the asset");
        (,address manager, uint id) = decodeId(tokenId);
        address wrapper = erc721Wrappers[manager];

        bytes memory returnData = wrapper.functionDelegateCall(abi.encodeWithSelector(IERC721Wrapper.deposit.selector, manager, id, suppliedTokens, suppliedAmounts));
        (uint minted) = abi.decode(returnData, (uint));
        poolInfo[tokenId].liquidity+=minted;
        return minted;
    }

    function burn(uint tokenId, address userAddress, uint amount, address receiver) onlyAuthorized override external returns (address[] memory outTokens, uint[] memory tokenAmounts) {
        require(poolInfo[tokenId].user==userAddress, "User doesn't own the asset");
        (,address manager, uint id) = decodeId(tokenId);
        address wrapper = erc721Wrappers[manager];
        bytes memory returnData = wrapper.functionDelegateCall(abi.encodeWithSelector(IERC721Wrapper.withdraw.selector, manager, id, amount, receiver));
        (outTokens, tokenAmounts) = abi.decode(returnData, (address[], uint[]));
        // (outTokens, tokenAmounts) = withdraw(manager, id, amount, receiver);
        (,,,,,,,uint liquidity,,,,) = INonfungiblePositionManager(manager).positions(id);
        poolInfo[tokenId].liquidity = liquidity;
    }

    function harvest(uint tokenId, address userAddress, address receiver) onlyAuthorized override external returns (address[] memory rewardAddresses, uint[] memory rewardAmounts) {
        require(poolInfo[tokenId].user==userAddress, "User doesn't own the asset");
        (,address manager, uint id) = decodeId(tokenId);
        address wrapper = erc721Wrappers[manager];
        bytes memory returnData = wrapper.functionDelegateCall(abi.encodeWithSelector(IERC721Wrapper.harvest.selector, manager, id, receiver));
        (,,,,,,,uint liquidity,,,,) = INonfungiblePositionManager(manager).positions(id);
        poolInfo[tokenId].liquidity = liquidity;
        (rewardAddresses, rewardAmounts) = abi.decode(returnData, (address[], uint[]));
        return (rewardAddresses, rewardAmounts);
    }
    
    function getUnderlyingForFirstDeposit(uint tokenId) override view public returns (address[] memory underlying, uint[] memory ratios) {
        (,address manager,) = decodeId(tokenId);
        underlying = new address[](1);
        underlying[0] = manager;
        ratios = new uint[](1);
        ratios[0] = 1;
    }

    function getUnderlyingForRecurringDeposit(uint tokenId) override view public returns (address[] memory, uint[] memory ratios) {
        (, address manager, uint pos_id) = decodeId(tokenId);
        IERC721Wrapper wrapper = IERC721Wrapper(erc721Wrappers[manager]);
        return wrapper.getRatio(manager, pos_id);
        // return wrapper.getERC20Base(pool);
    }
    
    function getRewards(uint tokenId) override external view returns (address[] memory rewardsArray) {
        (rewardsArray,) = getUnderlyingForRecurringDeposit(tokenId);
    }

    function getPendingRewardsForUser(uint tokenId, address user) override external view returns (address[] memory rewards, uint[] memory amounts) {
        (, address manager, uint pos_id) = decodeId(tokenId);
        IERC721Wrapper wrapper = IERC721Wrapper(erc721Wrappers[manager]);
        return wrapper.getRewardsForPosition(manager, pos_id);
    }

    function getPositionTokens(uint tokenId, address userAddress) override external view returns (address[] memory outTokens, uint[] memory tokenAmounts) {
        (, address manager, uint pos_id) = decodeId(tokenId);
        IERC721Wrapper wrapper = IERC721Wrapper(erc721Wrappers[manager]);
        return wrapper.getPositionUnderlying(manager, pos_id);
    }

    function isUnderlyingERC721() override external pure returns (bool) {
        return true;
    }
}