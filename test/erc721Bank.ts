import { expect } from "chai";
import { ethers } from "hardhat";
import hre from "hardhat";
import { IWETH, PositionsManager, UniversalSwap } from "../typechain-types";
import {
  deployAndInitializeManager,
  addresses,
  getNetworkToken,
  checkNFTLiquidity,
  depositNew,
  isRoughlyEqual,
  getNFT,
  depositNewNFT,
} from "../utils";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
require("dotenv").config();

const NETWORK = hre.network.name;
// @ts-ignore
const networkAddresses = addresses[NETWORK];
const liquidationPoints = [
  {
    liquidateTo: networkAddresses.networkToken,
    watchedToken: ethers.constants.AddressZero,
    lessThan: true,
    liquidationPoint: "100000000000000000000",
    slippage: ethers.utils.parseUnits("1", 17),
  },
];

async function getTimestamp() {
  const now = new Date().getTime();
  return Math.floor(now / 1000) + 1000;
}

describe("ERC721Bank tests", function () {
  let manager: PositionsManager;
  let owners: any[];
  let networkTokenContract: IWETH;
  let universalSwap: UniversalSwap;
  before(async function () {
    manager = await deployAndInitializeManager();
    owners = await ethers.getSigners();
    const universalSwapAddress = await manager.universalSwap();
    for (const owner of owners) {
      const { wethContract } = await getNetworkToken(owner, "1000.0");
      await wethContract.connect(owner).approve(universalSwapAddress, ethers.utils.parseEther("1000"));
    }
    networkTokenContract = await ethers.getContractAt("IWETH", networkAddresses.networkToken);
    universalSwap = await ethers.getContractAt("UniversalSwap", universalSwapAddress);
  });
  // it("Creates and closes nft position", async function () {
  //     const test = async (pool: string) => {
  //         const startingBalance = await networkTokenContract.balanceOf(owners[0].address)
  //         const nftManagerAddress = networkAddresses.NFTManagers[0]
  //         const id = await getNFT(universalSwap, "10", nftManagerAddress, pool, owners[0])
  //         const nftManager = await ethers.getContractAt("INonfungiblePositionManager", nftManagerAddress)
  //         const {positionId, rewardContracts} = await depositNewNFT(manager, nftManagerAddress, id, liquidationPoints, owners[0])
  //         await manager.connect(owners[0]).close(positionId)
  //         const balances = []
  //         for (const reward of rewardContracts) {
  //             const balance = await reward.balanceOf(owners[0].address)
  //             balances.push(balance)
  //             reward.approve(universalSwap.address, balance)
  //         }
  //         await universalSwap.connect(owners[0]).swap(rewardContracts.map(r=>r.address), balances, networkAddresses.networkToken)
  //         const endingbalance = await networkTokenContract.balanceOf(owners[0].address)
  //         isRoughlyEqual(startingBalance, endingbalance)
  //     }
  //     const pools = networkAddresses.nftBasaedPairs
  //     for (const pool of pools) {
  //         await test(pool)
  //     }
  // })
  it("Creates, harvests, recompounds and liquidates nft position", async function () {
    const checkRewards = async (user: any, positionId: any) => {
      const [rewards, rewardAmounts] = await manager.connect(user).callStatic.harvestRewards(positionId);
      const { rewards: rewardsComputed, rewardAmounts: rewardAmountsComputed } = await manager.getPositionRewards(
        positionId
      );
      await manager.connect(user).harvestRewards(positionId);
      for (let i = 0; i < rewards.length; i++) {
        expect(rewards[i]).to.equal(rewardsComputed[i]);
        expect(rewardAmounts[i]).to.equal(rewardAmountsComputed[i]);
      }
    };
    const test = async (pool: string) => {
      const startingBalance = await networkTokenContract.balanceOf(owners[0].address);
      const nftManagerAddress = networkAddresses.NFTManagers[0];
      const id = await getNFT(universalSwap, "100", nftManagerAddress, pool, owners[0]);
      const nftManager = await ethers.getContractAt("INonfungiblePositionManager", nftManagerAddress);
      const { positionId, rewardContracts } = await depositNewNFT(
        manager,
        nftManagerAddress,
        id,
        liquidationPoints,
        owners[0]
      );
      const liquidity1 = (await manager.getPosition(positionId)).position.amount;
      expect(liquidity1).to.greaterThan(0);
      const poolContract = await ethers.getContractAt("IUniswapV3Pool", pool);
      const token0 = await poolContract.token0();
      const token1 = await poolContract.token1();
      const token0Contract = await ethers.getContractAt("IERC20", token0);
      const token1Contract = await ethers.getContractAt("IERC20", token1);
      const fee = await poolContract.fee();
      let tempBalance = await networkTokenContract.balanceOf(owners[1].address);
      await networkTokenContract.connect(owners[1]).approve(universalSwap.address, tempBalance);
      await universalSwap
        .connect(owners[1])
        .swap(
          { tokens: [networkAddresses.networkToken], amounts: [tempBalance], nfts: [] },
          [],
          [],
          { outputERC20s: [token0], outputERC721s: [], ratios: [1], minAmountsOut: [0] },
          owners[1].address
        );
      const router = await ethers.getContractAt("ISwapRouter", networkAddresses.uniswapV3Routers[0]);

      for (let i = 0; i < 5; i++) {
        const balance0 = await token0Contract.balanceOf(owners[1].address);
        await token0Contract.connect(owners[1]).approve(router.address, balance0);
        await router.connect(owners[1]).exactInputSingle({
          tokenIn: token0,
          tokenOut: token1,
          fee,
          recipient: owners[1].address,
          deadline: await getTimestamp(),
          amountIn: balance0,
          amountOutMinimum: 1,
          sqrtPriceLimitX96: 0,
        });
        const balance1 = await token1Contract.balanceOf(owners[1].address);
        await token1Contract.connect(owners[1]).approve(router.address, balance1);
        await router.connect(owners[1]).exactInputSingle({
          tokenIn: token1,
          tokenOut: token0,
          fee,
          recipient: owners[1].address,
          deadline: await getTimestamp(),
          amountIn: balance1,
          amountOutMinimum: 0,
          sqrtPriceLimitX96: 0,
        });
        await ethers.provider.send("hardhat_mine", ["0x10"]);
      }
      await checkRewards(owners[0], positionId);
      for (const reward of rewardContracts) {
        const balance = await reward.balanceOf(owners[0].address);
        expect(balance).to.greaterThan(0);
        await reward.approve(universalSwap.address, balance);
        await universalSwap
          .connect(owners[0])
          .swap(
            { tokens: [reward.address], amounts: [balance], nfts: [] },
            [],
            [],
            { outputERC20s: [networkAddresses.networkToken], outputERC721s: [], ratios: [1], minAmountsOut: [0] },
            owners[0].address
          );
      }

      for (let i = 0; i < 5; i++) {
        const balance0 = await token0Contract.balanceOf(owners[1].address);
        await token0Contract.connect(owners[1]).approve(router.address, balance0);
        await router.connect(owners[1]).exactInputSingle({
          tokenIn: token0,
          tokenOut: token1,
          fee,
          recipient: owners[1].address,
          deadline: await getTimestamp(),
          amountIn: balance0,
          amountOutMinimum: 1,
          sqrtPriceLimitX96: 0,
        });
        const balance1 = await token1Contract.balanceOf(owners[1].address);
        await token1Contract.connect(owners[1]).approve(router.address, balance1);
        await router.connect(owners[1]).exactInputSingle({
          tokenIn: token1,
          tokenOut: token0,
          fee,
          recipient: owners[1].address,
          deadline: await getTimestamp(),
          amountIn: balance1,
          amountOutMinimum: 1,
          sqrtPriceLimitX96: 0,
        });
        await ethers.provider.send("hardhat_mine", ["0x10"]);
      }
      await manager.connect(owners[0]).harvestAndRecompound(positionId, [], [], [0, 0]);
      const liquidity2 = (await manager.getPosition(positionId)).position.amount;
      expect(liquidity2).to.greaterThan(liquidity1);

      await manager.connect(owners[0]).close(positionId);
      for (const reward of rewardContracts) {
        const balance = await reward.balanceOf(owners[0].address);
        expect(balance).to.greaterThan(0);
        await reward.approve(universalSwap.address, balance);
        await universalSwap
          .connect(owners[0])
          .swap(
            { tokens: [reward.address], amounts: [balance], nfts: [] },
            [],
            [],
            { outputERC20s: [networkAddresses.networkToken], outputERC721s: [], ratios: [1], minAmountsOut: [0] },
            owners[0].address
          );
      }
      const endingbalance = await networkTokenContract.balanceOf(owners[0].address);
      isRoughlyEqual(startingBalance, endingbalance);
      tempBalance = await token0Contract.balanceOf(owners[1].address);
      await token0Contract.connect(owners[1]).approve(universalSwap.address, tempBalance);
      await universalSwap
        .connect(owners[1])
        .swap(
          { tokens: [token0], amounts: [tempBalance], nfts: [] },
          [],
          [],
          { outputERC20s: [networkAddresses.networkToken], outputERC721s: [], ratios: [1], minAmountsOut: [0] },
          owners[1].address
        );
    };
    const pools = networkAddresses.nftBasaedPairs;
    for (const pool of pools) {
      await test(pool);
    }
  });
  it("Creates, increases, decreases and liquidates nft position", async function () {
    const test = async (pool: string) => {
      const startingBalance = await networkTokenContract.balanceOf(owners[0].address);
      const nftManagerAddress = networkAddresses.NFTManagers[0];
      const id = await getNFT(universalSwap, "10", nftManagerAddress, pool, owners[0]);
      const nftManager = await ethers.getContractAt("INonfungiblePositionManager", nftManagerAddress);
      const { positionId, rewardContracts } = await depositNewNFT(
        manager,
        nftManagerAddress,
        id,
        liquidationPoints,
        owners[0]
      );
      const liquidity1 = (await manager.getPosition(positionId)).position.amount;
      let liquidityInNFT = await checkNFTLiquidity(nftManagerAddress, id);
      expect(liquidityInNFT).to.equal(liquidity1);
      expect(liquidityInNFT).to.greaterThan(1);
      await networkTokenContract.connect(owners[0]).approve(manager.address, ethers.utils.parseEther("10"));
      await manager
        .connect(owners[0])
        .depositInExisting(
          positionId,
          { tokens: [networkAddresses.networkToken], amounts: [ethers.utils.parseEther("10")], nfts: [] },
          [],
          [],
          [0, 0]
        );
      const liquidity2 = (await manager.getPosition(positionId)).position.amount;
      liquidityInNFT = await checkNFTLiquidity(nftManagerAddress, id);
      expect(liquidityInNFT).to.equal(liquidity2);
      isRoughlyEqual(liquidity2, liquidity1.mul("2"));
      await manager.connect(owners[0]).withdraw(positionId, liquidity1);
      const liquidity3 = (await manager.getPosition(positionId)).position.amount;
      isRoughlyEqual(liquidity1, liquidity3);
      for (const reward of rewardContracts) {
        const balance = await reward.balanceOf(owners[0].address);
        expect(balance).to.greaterThan(0);
      }
      await manager.connect(owners[0]).botLiquidate(positionId, 0, [], []);
      // const balances = []
      // for (const reward of rewardContracts) {
      //     const balance = await reward.balanceOf(owners[0].address)
      //     expect(balance).to.greaterThan(0)
      //     balances.push(balance)
      //     reward.approve(universalSwap.address, balance)
      // }
      // await universalSwap.connect(owners[0]).swap(rewardContracts.map(r=>r.address), balances, networkAddresses.networkToken)
      const endingbalance = await networkTokenContract.balanceOf(owners[0].address);
      isRoughlyEqual(startingBalance, endingbalance);
    };
    const pools = networkAddresses.nftBasaedPairs;
    for (const pool of pools) {
      await test(pool);
    }
  });
});
