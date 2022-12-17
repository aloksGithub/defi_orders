// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import '@openzeppelin/contracts/token/ERC721/IERC721.sol';
import "./BankBase.sol";
import "../interfaces/IPositionsManager.sol";
import "hardhat/console.sol";

contract ERC20Bank is ERC1155('ERC20Bank'), BankBase {
    using SafeERC20 for IERC20;

    struct PoolInfo {
        mapping(address=>uint) userShares;
    }

    mapping (uint=>PoolInfo) poolInfo;
    mapping (address=>uint) balances;

    constructor(address _positionsManager) BankBase(_positionsManager) {}

    function encodeId(address tokenAddress) public pure returns (uint) {
        return uint256(uint160(tokenAddress));
    }

    function decodeId(uint id) public override pure returns (address, address, uint) {
        return (address(uint160(id)), address(0), 0);
    }

    function getLPToken(uint id) override public pure returns (address tokenAddress) {
        (tokenAddress,,) = decodeId(id);
    }
    
    function getIdFromLpToken(address lpToken) override external view returns (bool, uint) {
        if (lpToken==address(0) || lpToken==IPositionsManager(positionsManager).networkToken()) return (true, encodeId(lpToken));
        try ERC20(lpToken).name() {} catch {return (false, 0);}
        try ERC20(lpToken).totalSupply() {} catch {return (false, 0);}
        try ERC20(lpToken).balanceOf(address(0)) {} catch {return (false, 0);}
        try ERC20(lpToken).decimals() {} catch {return (false, 0);}
        return (true, encodeId(lpToken));
    }

    function name() override public pure returns (string memory) {
        return "ERC20 Bank";
    }

    function getPositionTokens(uint tokenId, address userAddress) override external view returns (address[] memory outTokens, uint[] memory tokenAmounts) {
        (address lpToken,,) = decodeId(tokenId);
        uint amount = balanceOf(userAddress, tokenId);
        outTokens = new address[](1);
        tokenAmounts = new uint[](1);
        outTokens[0] = lpToken;
        tokenAmounts[0] = amount;
    }

    function mint(uint tokenId, address userAddress, address[] memory suppliedTokens, uint[] memory suppliedAmounts) onlyAuthorized override public returns(uint) {
        PoolInfo storage pool = poolInfo[tokenId];
        pool.userShares[userAddress]+=suppliedAmounts[0];
        _mint(userAddress, tokenId, suppliedAmounts[0], '');

        // Sanity check
        if (suppliedTokens[0]!=address(0)) {
            require(balances[suppliedTokens[0]]+suppliedAmounts[0]<=IERC20(suppliedTokens[0]).balanceOf(address(this)), "INSANITY");
        } else {
            require(balances[suppliedTokens[0]]+suppliedAmounts[0]<=address(this).balance, "INSANITY");
        }
        balances[suppliedTokens[0]]+=suppliedAmounts[0];
        return suppliedAmounts[0];
    }

    function burn(uint tokenId, address userAddress, uint amount, address receiver) onlyAuthorized override external returns (address[] memory outTokens, uint[] memory tokenAmounts){
        (address lpToken,,) = decodeId(tokenId);
        PoolInfo storage pool = poolInfo[tokenId];
        pool.userShares[userAddress]-=amount;
        if (lpToken!=address(0)) {
            IERC20(lpToken).safeTransfer(receiver, amount);
        } else {
            console.log(address(this).balance, amount);
            payable(receiver).transfer(amount);
        }
        _burn(userAddress, tokenId, amount);
        outTokens = new address[](1);
        tokenAmounts = new uint[](1);
        outTokens[0] = lpToken;
        tokenAmounts[0] = amount;

        // Sanity check
        require(balances[lpToken]-amount<=IERC20(lpToken).balanceOf(address(this)), "INSANITY");
        balances[lpToken]-=amount;
    }
}