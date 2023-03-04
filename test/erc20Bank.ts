import { expect } from "chai";
import { ethers, deployments } from "hardhat";
import hre from "hardhat";
import { IWETH, ManagerHelper, PositionsManager, UniversalSwap } from "../typechain-types";
import {
  addresses,
  getNetworkToken,
  getLPToken,
  depositNew,
  isRoughlyEqual,
  getBalance,
} from "../utils";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { BigNumber, constants } from "ethers";

require("dotenv").config();

const equalsPlusMinusOne = (a:BigNumber, b: BigNumber) => {
  if (a.gt(b)) {
    expect(a.sub(1)).to.equal(b)
    return
  } else if (a.lt(b)) {
    expect(a.add(1)).to.equal(b)
    return
  } else {
    expect(a).to.equal(b)
  }
}

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
  let helper: ManagerHelper;
  let owners: SignerWithAddress[];
  let networkTokenContract: IWETH;
  let universalSwap: UniversalSwap;
  before(async function () {
    await deployments.fixture()
    const managerAddress = (await deployments.get('PositionsManager')).address;
    manager = await ethers.getContractAt("PositionsManager", managerAddress)
    const helperAddress = (await deployments.get('ManagerHelper')).address;
    helper = await ethers.getContractAt("ManagerHelper", helperAddress)
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

      const user0StartBalance = await getBalance(lpToken, owners[0])
      const user1StartBalance = await getBalance(lpToken, owners[1])
      const user0LiquidateToBalnaceStart =
        (await liquidateToContract?.balanceOf(owners[0].address)) || (await owners[0].getBalance());

      const { positionId: positionId0 } = await depositNew(
        manager,
        lpToken,
        lpBalance0.div("2"),
        liquidationPoints,
        owners[0]
      );
      const { positionId: positionId1 } = await depositNew(
        manager,
        lpToken,
        lpBalance1,
        liquidationPoints,
        owners[1]
      );

      let user0PositionBalance = (await helper.getPosition(positionId0)).position.amount;
      let user0lpBalance = await getBalance(lpToken, owners[0])
      let user1PositionBalance = (await helper.getPosition(positionId1)).position.amount;
      let user1lpBalance = await getBalance(lpToken, owners[1])

      const getUsersBalances = async () => {
        user0PositionBalance = (await helper.getPosition(positionId0)).position.amount;
        user0lpBalance = await getBalance(lpToken, owners[0])
        user1PositionBalance = (await helper.getPosition(positionId1)).position.amount;
        user1lpBalance = await getBalance(lpToken, owners[1])
      }

      expect(user0PositionBalance).to.equal(lpBalance0.div("2"));
      if (lpToken!=ethers.constants.AddressZero) {
        equalsPlusMinusOne(user0lpBalance.add(lpBalance0.div("2")), user0StartBalance);
      } else {
        isRoughlyEqual(user0lpBalance.add(lpBalance0.div("2")), user0StartBalance);
      }
      expect(user1PositionBalance).to.equal(lpBalance1);
      if (lpToken!=ethers.constants.AddressZero) {
        equalsPlusMinusOne(user1lpBalance.add(lpBalance1), user1StartBalance);
      } else {
        isRoughlyEqual(user1lpBalance.add(lpBalance1), user1StartBalance);
      }

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
      await getUsersBalances()
      if (lpToken!=ethers.constants.AddressZero) {
        equalsPlusMinusOne(user0lpBalance.add(lpBalance0), user0StartBalance);
      } else {
        isRoughlyEqual(user0lpBalance.add(lpBalance0), user0StartBalance);
      }
      if (lpToken!=ethers.constants.AddressZero) {
        equalsPlusMinusOne(user0PositionBalance, lpBalance0);
      } else {
        isRoughlyEqual(user0PositionBalance, lpBalance0);
      }

      await manager.connect(owners[0]).withdraw(positionId0, lpBalance0.div("2"));
      await manager.connect(owners[1]).withdraw(positionId1, lpBalance1.div("2"));
      await getUsersBalances()
      if (lpToken!=ethers.constants.AddressZero) {
        equalsPlusMinusOne(user0PositionBalance, lpBalance0.div("2"));
      } else {
        isRoughlyEqual(user0PositionBalance, lpBalance0.div("2"));
      }
      if (lpToken!=ethers.constants.AddressZero) {
        equalsPlusMinusOne(user0lpBalance, user0StartBalance.sub(lpBalance0.div("2")));
      } else {
        isRoughlyEqual(user0lpBalance, user0StartBalance.sub(lpBalance0.div("2")));
      }
      await getUsersBalances()
      if (lpToken!=ethers.constants.AddressZero) {
        equalsPlusMinusOne(user1PositionBalance, lpBalance1.div("2"));
      } else {
        isRoughlyEqual(user1PositionBalance, lpBalance1.div("2"));
      }
      if (lpToken!=ethers.constants.AddressZero) {
        equalsPlusMinusOne(user1lpBalance, user1StartBalance.sub(lpBalance1.div("2")));
      } else {
        isRoughlyEqual(user1lpBalance, user1StartBalance.sub(lpBalance1.div("2")));
      }

      await manager.connect(owners[1]).close(positionId1, '');
      await manager.connect(owners[0]).botLiquidate(positionId0, 0, 0, [], []);
      const liquidatedExpected = await universalSwap.estimateValueERC20(
        lpTokenContract?.address || constants.AddressZero,
        user0PositionBalance,
        liquidationPoints[0].liquidateTo
      );
      await getUsersBalances()
      const user0LiquidateToBalance =
        (await liquidateToContract?.balanceOf(owners[0].address)) || (await owners[0].getBalance());
      isRoughlyEqual(user0LiquidateToBalnaceStart.add(liquidatedExpected), user0LiquidateToBalance);
      expect(user0PositionBalance).to.equal(0);
      isRoughlyEqual(
        user0lpBalance,
        user0StartBalance.sub(liquidationPoints[0].liquidateTo != lpToken ? lpBalance0.div("2") : "0")
      );
      await getUsersBalances()
      expect(user1PositionBalance).to.equal(0);
      if (lpToken!=ethers.constants.AddressZero) {
        equalsPlusMinusOne(user1lpBalance, user1StartBalance);
      } else {
        isRoughlyEqual(user1lpBalance, user1StartBalance);
      }
    };
    const lpTokens = networkAddresses.erc20BankLps;
    for (const lpToken of lpTokens) {
      await test(lpToken);
    }
  });
  it("Reverts bot liquidate on slippage fail", async function () {
    const test = async (lpToken: string) => {
      const { lpBalance: lpBalance0 } = await getLPToken(lpToken, universalSwap, "1", owners[0]);
      const { lpBalance: lpBalance1 } = await getLPToken(lpToken, universalSwap, "1", owners[1]);
      expect(lpBalance0).to.greaterThan(0);
      expect(lpBalance1).to.greaterThan(0);

      const { positionId: positionId } = await depositNew(
        manager,
        lpToken,
        lpBalance0.div("2"),
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
        await expect(manager.connect(owners[0]).botLiquidate(positionId, 0, 0, [], [])).to.be.revertedWith("3");
      }
    };
    const lpTokens = networkAddresses.erc20BankLps;
    for (const lpToken of lpTokens) {
      await test(lpToken);
    }
  });
});
