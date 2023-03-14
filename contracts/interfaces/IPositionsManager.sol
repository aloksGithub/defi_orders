// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.17;

import "./IUniversalSwap.sol";

/// @notice Structure representing a liquidation condition
/// @param watchedToken The token whose price needs to be watched
/// @param liquidateTo The token that the position will be converted into
/// @param lessThan Wether liquidation will happen when price is below or above liquidationPoint
/// @param liquidationPoint Price of watchedToken in usd*10**18 at which liquidation should be trigerred
struct LiquidationCondition {
    address watchedToken;
    address liquidateTo;
    bool lessThan;
    uint liquidationPoint;
    uint slippage;
}

/// @notice Structure representing a position
/// @param user The user that owns this position
/// @param bankId Bank ID in which the assets are deposited
/// @param bankToken Token ID for the assets in the bank
/// @param amount Size of the position
/// @param liquidationPoints A list of conditions, where if any is not met, the position will be liquidated
struct Position {
    address user;
    address bank;
    uint bankToken;
    uint amount;
    LiquidationCondition[] liquidationPoints;
}

struct BankTokenInfo {
    address lpToken;
    address manager;
    uint idInManager;
}

struct PositionData {
    Position position; // Position data such as bankId, bankToken, positionSize, etc.
    BankTokenInfo bankTokenInfo; // The information about the banktoken from the bank
    address[] underlyingTokens; // The underlying tokens for the token first deposited
    uint[] underlyingAmounts; // Amounts for the aforementioned underlying tokens
    uint[] underlyingValues; // The USD values of the underlying tokens
    address[] rewardTokens; // Reward tokens generated for the position
    uint[] rewardAmounts; // Amount of reward tokens that can be harvested
    uint[] rewardValues; // Value of the reward tokens in USD
    uint usdValue; // Combined net worth of the position
}

interface IPositionsManager {
    event Deposit(uint indexed positionId, uint amount, uint usdValue);
    event IncreasePosition(uint indexed positionId, uint amount, uint usdValue);
    event Withdraw(uint indexed positionId, uint amount, uint usdValue);
    event PositionClose(uint indexed positionId, uint amount, uint usdValue);
    event BotLiquidate(uint indexed positionId, uint amount, uint usdValue, uint liquidationIndex);
    event Refund(uint indexed positionId, uint amount, uint usdValue, string reason);
    event Harvest(uint indexed positionId, uint amount, uint usdValue);
    event HarvestRecompound(uint indexed positionId, uint amount, uint usdValue);
    
    /// @notice Returns the address of universal swap
    function universalSwap() external view returns (address networkToken);

    /// @notice Returns the address of the wrapped network token
    function networkToken() external view returns (address networkToken);

    /// @notice Returns the address of the preferred stable token for the network
    function stableToken() external view returns (address stableToken);

    /// @notice Returns number of positions that have been opened
    /// @return positions Number of positions that have been opened
    function numPositions() external view returns (uint positions);

    /// @notice Returns number of banks
    /// @return banks Addresses of banks
    function getBanks() external view returns (address payable[] memory banks);

    /// @notice Returns a list of position ids for the user
    function getPositions(address user) external view returns (uint[] memory userPositions);

    /// @notice Get position data for position id
    function getPosition(uint positionId) external view returns (Position memory position);

    /// @notice Set the address for the EOA that can be used to trigger liquidations
    function setKeeper(address keeperAddress, bool active) external;

    /// @notice Updates bank addresses
    function setBanks(address payable[] memory _banks) external;
    
    /// @notice Update minimum deposit required for limit orders to be executed
    /// @dev This limit is placed to ensure that the gas fees for the transaction can be covered
    function setMinDepositAmount(uint _minDepositAmount) external;

    /// @notice Specify a reason as to why a position can't be liquidated. Such a position should be closed by user
    function setLiquidationFailure(uint positionId, string memory reason) external;

    // /// @notice Get a position
    // /// @param positionId position ID
    // /// @return data Position details
    // function getPosition(uint positionId) external returns (PositionData memory data);

    /// @notice Get a list of banks and bank tokens that support the provided token
    /// @dev bankToken for ERC721 banks is not supported and will always be 0
    /// @param token The token for which to get supported banks
    /// @return banks List of banks that support the token
    /// @return bankTokens token IDs corresponding to the provided token for each of the banks
    function recommendBank(address token) external view returns (address[] memory banks, uint[] memory bankTokens);

    /// @notice Change the liquidation conditions for a position
    /// @param positionId position ID
    /// @param _liquidationPoints New list of liquidation conditions
    function adjustLiquidationPoints(uint positionId, LiquidationCondition[] memory _liquidationPoints) external;

    /// @notice Deposit into existing position
    /// @dev Before calling, make sure PositionsManager contract has approvals according to suppliedAmounts
    /// @param positionId position ID
    /// @param provided Assets provided to deposit into position
    /// @param swaps Swaps to conduct if provided assets do not match underlying for position
    /// @param conversions Conversions to conduct if provided assets do not match underlying for position
    /// @param minAmounts Slippage control, used when provided assets don't match the positions underlying
    function depositInExisting(
        uint positionId,
        Provided memory provided,
        SwapPoint[] memory swaps,
        Conversion[] memory conversions,
        uint[] memory minAmounts
    ) external payable;

    /// @notice Create new position and deposit into it
    /// @dev Before calling, make sure PositionsManager contract has approvals according to suppliedAmounts
    /// @dev For creating an ERC721Bank position, suppliedTokens will contain the ERC721 contract and suppliedAmounts will contain the tokenId
    /// @param position position details
    /// @param suppliedTokens list of tokens supplied to increase the positions value
    /// @param suppliedAmounts amounts supplied for each of the supplied tokens
    function deposit(
        Position memory position,
        address[] memory suppliedTokens,
        uint[] memory suppliedAmounts
    ) external payable returns (uint);

    /// @notice Withdraw from a position
    /// @dev In case of ERC721Bank position, amount should be liquidity to withdraw like in UniswapV3PositionsManager
    /// @param positionId position ID
    /// @param amount amount to withdraw
    function withdraw(uint positionId, uint amount) external;

    /// @notice Withdraws all funds from a position
    /// @dev Called by position owner or keepers or admin
    /// @param positionId Position ID
    /// @param reason In case admin is calling close to refund user, reason needs to be specified
    function close(uint positionId, string memory reason) external;

    // /// @notice Estimates the net worth of the position in terms of another token
    // /// @param positionId Position ID
    // /// @return value Value of the position in terms of inTermsOf
    // function estimateValue(uint positionId, address inTermsOf) external view returns (uint value);

    // /// @notice Get the underlying tokens, amounts and corresponding usd values for a position
    // function getPositionTokens(
    //     uint positionId
    // ) external view returns (address[] memory tokens, uint[] memory amounts, uint256[] memory values);

    // /// @notice Get the rewards, rewad amounts and corresponding usd values that have been generated for a position
    // function getPositionRewards(
    //     uint positionId
    // ) external view returns (address[] memory tokens, uint[] memory amounts, uint256[] memory rewardValues);

    /// @notice Harvest and receive the rewards for a position
    /// @param positionId Position ID
    /// @return rewards List of tokens obtained as rewards
    /// @return rewardAmounts Amount of tokens received as reward
    function harvestRewards(uint positionId) external returns (address[] memory rewards, uint[] memory rewardAmounts);

    /// @notice Harvest rewards for position and deposit them back to increase position value
    /// @param positionId Position ID
    /// @param swaps Swaps to conduct if harvested assets do not match underlying for position
    /// @param conversions Conversions to conduct if harvested assets do not match underlying for position
    /// @param minAmounts Slippage control, used when harvested assets don't match the positions underlying
    /// @return newLpTokens Amount of new tokens added/increase in liquidity for position
    function harvestAndRecompound(
        uint positionId,
        SwapPoint[] memory swaps,
        Conversion[] memory conversions,
        uint[] memory minAmounts
    ) external returns (uint newLpTokens);

    /// @notice Liquidate a position that has violated some liquidation condition
    /// @notice Can only be called by a keeper
    /// @param positionId Position ID
    /// @param liquidationIndex index of liquidation condition being triggered
    /// @param liquidationFee ETH to be refunded to bot that triggered the liquidation
    /// @param swaps Swaps to conduct to get desired asset from position
    /// @param conversions Conversions to conduct to get desired asset from position
    /// @param liquidationIndex Index of liquidation condition that is no longer satisfied
    function botLiquidate(
        uint positionId,
        uint liquidationIndex,
        uint liquidationFee,
        SwapPoint[] memory swaps,
        Conversion[] memory conversions
    ) external;

    // /// @notice Check wether one of the liquidation conditions has become true
    // /// @param positionId Position ID
    // /// @return index Index of the liquidation condition that has become true
    // /// @return liquidate Flag used to tell wether liquidation should be performed
    // function checkLiquidate(uint positionId) external view returns (uint index, bool liquidate);
}
