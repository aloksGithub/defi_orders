// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../interfaces/IWETH.sol";

/// @notice UniversalSwap is an upgradeable contract and can't receive ETH via regular transfer
/// @dev UniversalSwap sends WETH to this contract, to be unwrapped and sent back as ETH
contract ETHWithdrawer {
    function withdraw(address networkToken, uint amount) external {
        IWETH(payable(networkToken)).withdraw(amount);
        (bool success,) = payable(msg.sender).call{ value: amount }("");
        require(success, "Transfer Failed");
    }

    receive() external payable {}
}