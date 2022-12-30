import { expect } from "chai";
import { ethers } from "hardhat";
import hre from "hardhat";
import { IWETH, IPositionsManager, PositionsManager, UniversalSwap } from "../typechain-types";
import {
  deployAndInitializeManager,
  addresses,
  getNetworkToken,
  getLPToken,
  depositNew,
  isRoughlyEqual,
} from "../utils";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { constants } from "ethers";
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

describe("ERC20Bank tests", function () {
  let manager: PositionsManager;
  let owners: SignerWithAddress[];
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
  it("Opens, deposits, withdraws and closes position", async function () {
    const test = async (lpToken: string) => {
      const liquidateToContract =
        liquidationPoints[0].liquidateTo != constants.AddressZero
          ? await ethers.getContractAt("ERC20", liquidationPoints[0].liquidateTo)
          : undefined;
      const { lpBalance: lpBalance0, lpTokenContract } = await getLPToken(lpToken, universalSwap, "1", owners[0]);
      const { lpBalance: lpBalance1 } = await getLPToken(lpToken, universalSwap, "1", owners[1]);
      expect(lpBalance0).to.greaterThan(0);
      expect(lpBalance1).to.greaterThan(0);

      const user0StartBalance = (await lpTokenContract?.balanceOf(owners[0].address)) || (await owners[0].getBalance());
      const user1StartBalance = (await lpTokenContract?.balanceOf(owners[0].address)) || (await owners[0].getBalance());
      const user0LiquidateToBalnaceStart =
        (await liquidateToContract?.balanceOf(owners[0].address)) || (await owners[0].getBalance());

      const { positionId: positionId0 } = await depositNew(
        manager,
        lpToken,
        lpBalance0.div("2").toString(),
        liquidationPoints,
        owners[0]
      );
      const { positionId: positionId1 } = await depositNew(
        manager,
        lpToken,
        lpBalance1.toString(),
        liquidationPoints,
        owners[1]
      );

      let user0PositionBalance = (await manager.getPosition(positionId0)).position.amount;
      let user0lpBalance = (await lpTokenContract?.balanceOf(owners[0].address)) || (await owners[0].getBalance());
      expect(user0PositionBalance).to.equal(lpBalance0.div("2"));
      isRoughlyEqual(user0lpBalance.add(lpBalance0.div("2")), user0StartBalance);
      let user1PositionBalance = (await manager.getPosition(positionId1)).position.amount;
      let user1lpBalance = (await lpTokenContract?.balanceOf(owners[1].address)) || (await owners[1].getBalance());
      expect(user1PositionBalance).to.equal(lpBalance1);
      isRoughlyEqual(user1lpBalance.add(lpBalance1), user1StartBalance);

      await lpTokenContract?.connect(owners[0]).approve(manager.address, lpBalance0.div("2"));
      await manager.connect(owners[0]).depositInExisting(
        positionId0,
        {
          tokens: lpToken != constants.AddressZero ? [lpToken] : [],
          amounts: lpToken != constants.AddressZero ? [lpBalance0.div("2").toString()] : [],
          nfts: [],
        },
        [],
        [],
        [],
        { value: lpToken == constants.AddressZero ? lpBalance0.div("2").toString() : "0" }
      );
      user0PositionBalance = (await manager.getPosition(positionId0)).position.amount;
      user0lpBalance = (await lpTokenContract?.balanceOf(owners[0].address)) || (await owners[0].getBalance());
      isRoughlyEqual(user0lpBalance.add(lpBalance0), user0StartBalance);
      isRoughlyEqual(user0PositionBalance, lpBalance0);

      await manager.connect(owners[0]).withdraw(positionId0, lpBalance0.div("2"));
      await manager.connect(owners[1]).withdraw(positionId1, lpBalance1.div("2"));
      user0PositionBalance = (await manager.getPosition(positionId0)).position.amount;
      user0lpBalance = (await lpTokenContract?.balanceOf(owners[0].address)) || (await owners[0].getBalance());
      isRoughlyEqual(user0PositionBalance, lpBalance0.div("2"));
      isRoughlyEqual(user0lpBalance, user0StartBalance.sub(lpBalance0.div("2")));
      user1PositionBalance = (await manager.getPosition(positionId1)).position.amount;
      user1lpBalance = (await lpTokenContract?.balanceOf(owners[1].address)) || (await owners[1].getBalance());
      isRoughlyEqual(user1PositionBalance, lpBalance1.div("2"));
      isRoughlyEqual(user1lpBalance, user1StartBalance.sub(lpBalance1.div("2")));

      await manager.connect(owners[1]).close(positionId1);
      await manager.connect(owners[0]).botLiquidate(positionId0, 0, [], []);
      const liquidatedExpected = await universalSwap.estimateValueERC20(
        lpTokenContract?.address || constants.AddressZero,
        user0PositionBalance,
        liquidationPoints[0].liquidateTo
      );
      user0PositionBalance = (await manager.getPosition(positionId0)).position.amount;
      user0lpBalance = (await lpTokenContract?.balanceOf(owners[0].address)) || (await owners[0].getBalance());
      const user0LiquidateToBalance =
        (await liquidateToContract?.balanceOf(owners[0].address)) || (await owners[0].getBalance());
      isRoughlyEqual(user0LiquidateToBalnaceStart.add(liquidatedExpected), user0LiquidateToBalance);
      expect(user0PositionBalance).to.equal(0);
      isRoughlyEqual(
        user0lpBalance,
        user0StartBalance.sub(liquidationPoints[0].liquidateTo != lpToken ? lpBalance0.div("2") : "0")
      );
      user1PositionBalance = (await manager.getPosition(positionId1)).position.amount;
      user1lpBalance = (await lpTokenContract?.balanceOf(owners[1].address)) || (await owners[1].getBalance());
      expect(user1PositionBalance).to.equal(0);
      isRoughlyEqual(user1lpBalance, user1StartBalance);
    };
    const lpTokens = networkAddresses.erc20BankLps;
    for (const lpToken of lpTokens) {
      await test(lpToken);
    }
  });
  it.only("Reverts bot liquidate on slippage fail", async function () {
    const test = async (lpToken: string) => {
      const { lpBalance: lpBalance0 } = await getLPToken(lpToken, universalSwap, "1", owners[0]);
      const { lpBalance: lpBalance1 } = await getLPToken(lpToken, universalSwap, "1", owners[1]);
      expect(lpBalance0).to.greaterThan(0);
      expect(lpBalance1).to.greaterThan(0);

      const { positionId: positionId } = await depositNew(
        manager,
        lpToken,
        lpBalance0.div("2").toString(),
        [
          {
            liquidateTo: networkAddresses.networkToken,
            watchedToken: ethers.constants.AddressZero,
            lessThan: true,
            liquidationPoint: "100000000000000000000",
            slippage: ethers.utils.parseUnits("1", 10),
          },
        ],
        owners[0]
      );
      if (
        !(
          [networkAddresses.networkToken, constants.AddressZero].includes(liquidationPoints[0].liquidateTo) &&
          [networkAddresses.networkToken, constants.AddressZero].includes(lpToken)
        )
      ) {
        await expect(manager.connect(owners[0]).botLiquidate(positionId, 0, [], [])).to.be.revertedWith("3");
      }
    };
    const lpTokens = networkAddresses.erc20BankLps;
    for (const lpToken of lpTokens) {
      await test(lpToken);
    }
  });
});
