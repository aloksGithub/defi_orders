import { expect } from "chai";
import { ethers, deployments, getNamedAccounts } from "hardhat";
import hre from "hardhat";
import { IWETH, ManagerHelper, PositionsManager, UniversalSwap } from "../typechain-types";
import {
  addresses,
  getNetworkToken,
  getLPToken,
  depositNew,
  isRoughlyEqual,
  botliquidate,
} from "../utils";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { constants } from "ethers";

require("dotenv").config();

const NETWORK = hre.network.name;
// @ts-ignore
const networkAddresses = addresses[NETWORK];
const liquidationPoints = [
  {
    liquidateTo: networkAddresses.commonPoolTokens[2],
    watchedToken: ethers.constants.AddressZero,
    lessThan: true,
    liquidationPoint: "100000000000000000000",
    slippage: ethers.utils.parseUnits("1", 17),
  },
];

describe("Bot liquidation tests", function () {
  let manager: PositionsManager;
  let helper: ManagerHelper;
  let owners: SignerWithAddress[];
  let universalSwap: UniversalSwap;
  before(async function () {
    await deployments.fixture()
    const managerAddress = (await deployments.get('PositionsManager')).address;
    manager = await ethers.getContractAt("PositionsManager", managerAddress)
    const helperAddress = (await deployments.get('ManagerHelper')).address;
    helper = await ethers.getContractAt("ManagerHelper", helperAddress)
    owners = await ethers.getSigners();
    const universalSwapAddress = await manager.universalSwap();
    universalSwap = await ethers.getContractAt("UniversalSwap", universalSwapAddress);
    for (const owner of owners) {
      const { wethContract } = await getNetworkToken(owner, "1000.0");
      await wethContract.connect(owner).approve(universalSwapAddress, ethers.utils.parseEther("1000"));
    }
  });
  it("Bot liquidates position and gets fee", async function () {
    const lpTokens = networkAddresses.erc20BankLps;
    for (const [index, lpToken] of lpTokens.entries()) {
      const { lpBalance } = await getLPToken(lpToken, universalSwap, "10", owners[0]);

      const { positionId: positionId } = await depositNew(
        manager,
        lpToken,
        lpBalance,
        [
          {
            liquidateTo: index%2===0?networkAddresses.networkToken:ethers.constants.AddressZero,
            watchedToken: manager.address,
            lessThan: true,
            liquidationPoint: "100000000000000000000",
            slippage: ethers.utils.parseUnits("1", 18),
          },
        ],
        owners[0]
      );
      
      const balanceBefore = await ethers.provider.getBalance(owners[0].address)
      await botliquidate(manager, helper, positionId.toNumber(), 0)
      const balanceAfter = await ethers.provider.getBalance(owners[0].address)
      expect(balanceAfter).greaterThan(balanceBefore)
    }
  });
});
