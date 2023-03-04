import { expect } from "chai";
import { deployments, ethers } from "hardhat";
import hre from "hardhat";
import { IWETH, ManagerHelper, PositionsManager, UniversalSwap } from "../typechain-types";
import {
  addresses,
  getNetworkToken,
  getLPToken,
  depositNew,
  isRoughlyEqual,
} from "../utils";
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
    slippage: ethers.utils.parseUnits("3", 17),
  },
];
const ethUsed = "1";

describe("MasterChefBank tests", function () {
  let manager: PositionsManager;
  let helper: ManagerHelper;
  let owners: any[];
  let networkTokenContract: IWETH;
  let universalSwap: UniversalSwap;
  before(async function () {
    await deployments.fixture()
    owners = await ethers.getSigners();
    const managerAddress = (await deployments.get('PositionsManager')).address;
    manager = await ethers.getContractAt("PositionsManager", managerAddress)
    const helperAddress = (await deployments.get('ManagerHelper')).address;
    helper = await ethers.getContractAt("ManagerHelper", helperAddress)
    const universalSwapAddress = await manager.universalSwap();
    for (const owner of owners) {
      const { wethContract } = await getNetworkToken(owner, "1000.0");
      await wethContract.connect(owner).approve(universalSwapAddress, ethers.utils.parseEther("1000"));
    }
    networkTokenContract = await ethers.getContractAt("IWETH", networkAddresses.networkToken);
    universalSwap = await ethers.getContractAt("UniversalSwap", universalSwapAddress);
  });
  it("Opens recompounds and closes position", async function () {
    const test = async (lpToken: string) => {
      const { lpBalance: lpBalance0, lpTokenContract } = await getLPToken(lpToken, universalSwap, ethUsed, owners[0]);
      expect(lpBalance0).to.greaterThan(0);

      await lpTokenContract?.connect(owners[0]).approve(manager.address, lpBalance0);
      const { positionId, rewards, rewardContracts } = await depositNew(
        manager,
        lpToken,
        lpBalance0.toString(),
        liquidationPoints,
        owners[0]
      );
      const positionInfo1 = await helper.getPosition(positionId);
      await ethers.provider.send("hardhat_mine", ["0x100"]);
      await manager
        .connect(owners[0])
        .harvestAndRecompound(positionId, [], [], new Array(rewardContracts.length).fill(0));
      const positionValue = await helper.estimateValue(positionId, networkTokenContract.address);
      expect(positionValue).to.greaterThan(ethers.utils.parseEther(ethUsed).mul("95").div("100"));
      const positionInfo2 = await helper.getPosition(positionId);
      expect(positionInfo2.position.amount).to.greaterThanOrEqual(positionInfo1.position.amount);
      await manager.connect(owners[0]).close(positionId, '');
      const positionInfo3 = await helper.getPosition(positionId);
      expect(positionInfo3.position.amount).to.equal(0);
      const finalValue = await helper.estimateValue(positionId, networkTokenContract.address);
      expect(finalValue).to.equal("0");
      const finalLpBalance = await lpTokenContract?.balanceOf(owners[0].address);
      expect(finalLpBalance).to.greaterThanOrEqual(lpBalance0);
    };
    const lpTokens = networkAddresses.masterChefLps;
    for (const lpToken of lpTokens) {
      await test(lpToken);
    }
  });
  it("Handles multiple actions", async function () {
    const checkRewards = async (user: any, positionId: any) => {
      const [rewards, rewardAmounts] = await manager.connect(user).callStatic.harvestRewards(positionId);
      const { rewards: rewardsComputed, rewardAmounts: rewardAmountsComputed } = await helper.getPositionRewards(
        positionId
      );
      await manager.connect(user).harvestRewards(positionId);
      for (let i = 0; i < rewards.length; i++) {
        expect(rewards[i]).to.equal(rewardsComputed[i]);
        expect(rewardAmounts[i]).to.equal(rewardAmountsComputed[i]);
      }
    };
    const test = async (lpToken: string) => {
      const clearRewards = async (usersToClear: any[]) => {
        for (const user of usersToClear) {
          for (const rewardContract of rewardContracts) {
            const balance = await rewardContract.balanceOf(user.address);
            await rewardContract.connect(user).transfer(owners[0].address, balance);
          }
        }
      };
      const users = [owners[3], owners[4], owners[5], owners[6]];
      const { lpBalance: lpBalance0, lpTokenContract } = await getLPToken(lpToken, universalSwap, "1", owners[3]);
      const { lpBalance: lpBalance1 } = await getLPToken(lpToken, universalSwap, "1", owners[4]);
      const { lpBalance: lpBalance2 } = await getLPToken(lpToken, universalSwap, "1", owners[5]);
      const { lpBalance: lpBalance3 } = await getLPToken(lpToken, universalSwap, "1", owners[6]);
      const lpBalances = [lpBalance0, lpBalance1, lpBalance2, lpBalance3];

      const { positionId: position0, rewardContracts } = await depositNew(
        manager,
        lpToken,
        lpBalance0.toString(),
        liquidationPoints,
        users[0]
      );
      const { positionId: position1 } = await depositNew(
        manager,
        lpToken,
        lpBalance1.div("3").toString(),
        liquidationPoints,
        users[1]
      );
      await ethers.provider.send("hardhat_mine", ["0x10000"]);
      await checkRewards(users[0], position0);
      await checkRewards(users[1], position1);

      for (const rewardContract of rewardContracts) {
        const user0Bal = await rewardContract.balanceOf(users[0].address);
        const user1Bal = await rewardContract.balanceOf(users[1].address);
        if (user1Bal.div("1000000000000").toNumber() > 0) {
          isRoughlyEqual(
            user0Bal.mul("1000").div(user1Bal),
            lpBalances[0].mul("1000").div(lpBalances[1].div("3")),
            100
          );
        }
      }

      await clearRewards(users);

      const { positionId: position2 } = await depositNew(
        manager,
        lpToken,
        lpBalance2.toString(),
        liquidationPoints,
        users[2]
      );
      const { positionId: position3 } = await depositNew(
        manager,
        lpToken,
        lpBalance3.div("2").toString(),
        liquidationPoints,
        users[3]
      );
      await ethers.provider.send("hardhat_mine", ["0x10000"]);
      await checkRewards(users[2], position2);
      await checkRewards(users[3], position3);

      for (const rewardContract of rewardContracts) {
        const user2Bal = await rewardContract.balanceOf(users[2].address);
        const user3Bal = await rewardContract.balanceOf(users[3].address);
        if (user3Bal.div("1000000000000").toNumber() > 0) {
          isRoughlyEqual(
            user2Bal.mul("1000").div(user3Bal),
            lpBalances[2].mul("1000").div(lpBalances[3].div("2")),
            100
          );
        }
      }
      await clearRewards(users);

      await ethers.provider.send("hardhat_mine", ["0x10000"]);
      await checkRewards(users[0], position0);
      await checkRewards(users[1], position1);
      await checkRewards(users[2], position2);
      await checkRewards(users[3], position3);

      for (const rewardContract of rewardContracts) {
        const user0Bal = await rewardContract.balanceOf(users[0].address);
        const user1Bal = await rewardContract.balanceOf(users[1].address);
        const user2Bal = await rewardContract.balanceOf(users[2].address);
        const user3Bal = await rewardContract.balanceOf(users[3].address);
        if (user1Bal.div("1000000000000").toNumber() > 0) {
          isRoughlyEqual(user0Bal.mul("1000").div(user1Bal), lpBalance0.mul("1000").div(lpBalance1.div("3")), 100);
          isRoughlyEqual(user2Bal.mul("1000").div(user3Bal), lpBalance2.mul("1000").div(lpBalance3.div("2")), 100);
          isRoughlyEqual(user0Bal.mul("1000").div(user2Bal), lpBalance0.mul("1000").div(lpBalance2.div("2")), 100);
        }
      }

      await manager.connect(users[0]).withdraw(position0, lpBalance0.mul("2").div("3"));
      expect(lpBalance0.mul("2").div("3")).to.equal(await lpTokenContract?.balanceOf(users[0].address));
      await lpTokenContract?.connect(users[3]).approve(manager.address, lpBalance3.div("2"));
      await manager
        .connect(users[3])
        .depositInExisting(position3, { tokens: [lpToken], amounts: [lpBalance3.div("2")], nfts: [] }, [], [], []);
      await clearRewards(users);

      await ethers.provider.send("hardhat_mine", ["0x10000"]);
      await checkRewards(users[0], position0);
      await checkRewards(users[1], position1);
      await checkRewards(users[2], position2);
      await checkRewards(users[3], position3);

      for (const rewardContract of rewardContracts) {
        const user0Bal = await rewardContract.balanceOf(users[0].address);
        const user1Bal = await rewardContract.balanceOf(users[1].address);
        const user2Bal = await rewardContract.balanceOf(users[2].address);
        const user3Bal = await rewardContract.balanceOf(users[3].address);
        if (user1Bal.div("1000000000000").toNumber() > 0) {
          isRoughlyEqual(user0Bal.mul("1000").div(user1Bal), lpBalance0.mul("1000").div(lpBalance1), 100);
          isRoughlyEqual(user2Bal.mul("1000").div(user3Bal), lpBalance2.mul("1000").div(lpBalance3), 100);
        }
      }
      await clearRewards(users);
    };
    const lpTokens = networkAddresses.masterChefLps;
    for (const lpToken of lpTokens) {
      await test(lpToken);
    }
  });
  it("Handles bot liquidation", async function () {
    const test = async (lpToken: string) => {
      const owner = owners[7];
      const { lpBalance: lpBalance0, lpTokenContract } = await getLPToken(lpToken, universalSwap, "1", owner);
      expect(lpBalance0).to.greaterThan(0);

      await lpTokenContract?.connect(owner).approve(manager.address, lpBalance0);
      const { positionId, rewardContracts } = await depositNew(
        manager,
        lpToken,
        lpBalance0.toString(),
        liquidationPoints,
        owner
      );
      const positionInfo1 = await helper.getPosition(positionId);
      await ethers.provider.send("hardhat_mine", ["0x10000"]);
      await manager.connect(owner).harvestAndRecompound(positionId, [], [], new Array(rewardContracts.length).fill(0));
      const positionInfo2 = await helper.getPosition(positionId);
      expect(positionInfo2.position.amount).to.greaterThanOrEqual(positionInfo1.position.amount);
      await manager.connect(owners[0]).botLiquidate(positionId, 0, 0, [], []);
      const {underlyingTokens} = await helper.getPosition(positionId);
      expect(underlyingTokens.length).to.equal(2)
      const finalBalance = await networkTokenContract.balanceOf(owner.address);
      expect(finalBalance).to.greaterThan(ethers.utils.parseEther("1"));
    };
    const lpTokens = networkAddresses.masterChefLps;
    for (const lpToken of lpTokens) {
      await test(lpToken);
    }
  });
});
