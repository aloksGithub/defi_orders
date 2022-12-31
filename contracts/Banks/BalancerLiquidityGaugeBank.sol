// SPDX-License-Identifier: BUSL 1.1
pragma solidity ^0.8.17;

// import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
// import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
// import "../interfaces/IMasterChef.sol";
// import "./BankBase.sol";
// import "hardhat/console.sol";

// interface IBalancerLiquidityGaugeFactory {
//     function getPoolGauge(address pool) external returns (address);
// }

// interface BalancerLiquidityGauge {
//     function reward_count() external returns (uint);
//     function reward_tokens(uint arg0) external returns (address);
//     function claimable_reward(address _user, address _reward_token) external returns (uint);
//     function claim_rewards() external;
//     function balanceOf(address _user) external returns (uint);
//     function deposit(uint _value) external;
//     function deposit(uint _value, address _addr) external;
//     function withdraw(uint _value) external;
//     function withdraw(uint _value, bool _claim_rewards) external;
// }

// contract BalancerLiquidityGaugeBank is ERC1155('BalancerLiquidityGaugeBank'), BankBase {
//     struct PoolInfo {
//         uint totalSupply;
//         mapping(address=>uint) rewardAllocationsPerShare;
//         mapping(address=>uint) userShares;
//         mapping(address=>mapping(address=>int256)) rewardDebt;    // Mapping from user to reward to debt
//     }

//     uint PRECISION = 1e12;
//     mapping (uint=>address[]) rewards; // Rewards for a masterchef/gauge or some other reward giving contract
//     mapping (uint=>PoolInfo) poolInfo;
//     IBalancerLiquidityGaugeFactory liquidityGaugeFactory;
//     IERC20 bal;

//     constructor(address _positionsManager, address _liquidityGaugeFactory, address _bal) BankBase(_positionsManager) {
//         liquidityGaugeFactory = IBalancerLiquidityGaugeFactory(_liquidityGaugeFactory);
//         bal = IERC20(_bal);
//     }

//     function encodeId(address tokenAddress) public pure returns (uint) {
//         return uint256(uint160(tokenAddress));
//     }

//     function decodeId(uint id) public pure returns (address tokenAddress) {
//         return address(uint160(id));
//     }

//     function getLPToken(uint id) override public pure returns (address tokenAddress) {
//         tokenAddress = decodeId(id);
//     }

//     function getRewards(uint tokenId) override external pure returns (address[] memory rewardsArray) {
//         return rewardsArray;
//     }

//     function getIdFromLpToken(address lpToken) override external pure returns (bool, uint) {
//         return (false, 0);
//     }

//     function name() override public pure returns (string memory) {
//         return "Balancer Liquidity Gauge Bank";
//     }

//     function updateToken(uint tokenId) onlyAuthorized internal {
//         address lpToken = decodeId(tokenId);
//         BalancerLiquidityGauge gauge = BalancerLiquidityGauge(liquidityGaugeFactory.getPoolGauge(lpToken));
//         PoolInfo storage pool = poolInfo[tokenId];
//         uint lpSupply = pool.totalSupply;
//         uint claimable = gauge.claimable_reward(address(this), address(bal));
//         uint balance = gauge.balanceOf(address(this));
//         console.log(claimable, balance);
//         if (lpSupply>0) {
//             uint numRewards = gauge.reward_count();
//             uint[] memory initialRewardAmounts = new uint[](numRewards+1);
//             initialRewardAmounts[0] = bal.balanceOf(address(this));
//             for (uint i = 1; i<initialRewardAmounts.length; i++) {
//                 initialRewardAmounts[i] = IERC20(gauge.reward_tokens(i)).balanceOf(address(this));
//             }
//             gauge.claim_rewards();
//             uint balGained = bal.balanceOf(address(this))-initialRewardAmounts[0];
//             pool.rewardAllocationsPerShare[address(bal)]+=balGained*PRECISION/lpSupply;
//             for (uint i = 1; i<initialRewardAmounts.length; i++) {
//                 address rewardToken = gauge.reward_tokens(i);
//                 uint rewardGained = IERC20(rewardToken).balanceOf(address(this))-initialRewardAmounts[i];
//                 pool.rewardAllocationsPerShare[rewardToken]+=rewardGained*PRECISION/lpSupply;
//             }
//         }
//     }

//     function mint(uint tokenId, address userAddress, uint amount) onlyAuthorized override external {
//         address lpToken = decodeId(tokenId);
//         updateToken(tokenId);
//         BalancerLiquidityGauge gauge = BalancerLiquidityGauge(liquidityGaugeFactory.getPoolGauge(lpToken));
//         IERC20(lpToken).approve(address(gauge), amount);
//         gauge.deposit(amount, address(this));
//         PoolInfo storage pool = poolInfo[tokenId];
//         pool.userShares[userAddress]+=amount;
//         pool.totalSupply+=amount;
//         uint numRewards = gauge.reward_count();
//         for (uint i = 0; i<numRewards; i++) {
//             address reward = gauge.reward_tokens(i);
//             pool.rewardDebt[userAddress][reward]+=int(amount*pool.rewardAllocationsPerShare[reward]/PRECISION);
//         }
//         _mint(userAddress, tokenId, amount, '');
//     }

//     function burn(uint tokenId, address userAddress, uint amount, address receiver) onlyAuthorized override external {
//         address lpToken = decodeId(tokenId);
//         BalancerLiquidityGauge gauge = BalancerLiquidityGauge(liquidityGaugeFactory.getPoolGauge(lpToken));
//         updateToken(tokenId);
//         PoolInfo storage pool = poolInfo[tokenId];
//         uint numRewards = gauge.reward_count();
//         for (uint i = 0; i<numRewards; i++) {
//             address reward = gauge.reward_tokens(i);
//             pool.rewardDebt[userAddress][reward]-=int(amount*pool.rewardAllocationsPerShare[reward]/PRECISION);
//         }
//         pool.userShares[userAddress]-=amount;
//         pool.totalSupply-=amount;
//         gauge.withdraw(amount);
//         IERC20(lpToken).transfer(receiver, amount);
//         _burn(userAddress, tokenId, amount);
//     }

//     function harvest(uint tokenId, address userAddress, address receiver) onlyAuthorized override external returns (address[] memory rewardAddresses, uint[] memory rewardAmounts) {
//         address lpToken = decodeId(tokenId);
//         BalancerLiquidityGauge gauge = BalancerLiquidityGauge(liquidityGaugeFactory.getPoolGauge(lpToken));
//         updateToken(tokenId);
//         PoolInfo storage pool = poolInfo[tokenId];
//         uint numRewards = gauge.reward_count();
//         rewardAddresses = new address[](numRewards);
//         rewardAmounts = new uint[](numRewards);
//         for (uint i = 0; i<numRewards; i++) {
//             address reward = gauge.reward_tokens(i);
//             int256 accumulatedReward = int256(pool.userShares[userAddress]*pool.rewardAllocationsPerShare[reward]/PRECISION);
//             uint pendingReward = uint(accumulatedReward-pool.rewardDebt[userAddress][reward]);
//             pool.rewardDebt[userAddress][reward] = accumulatedReward;
//             if (pendingReward!=0) {
//                 IERC20(reward).transfer(receiver, pendingReward);
//             }
//             rewardAddresses[i] = reward;
//             rewardAmounts[i] = pendingReward;
//         }
//     }
// }
