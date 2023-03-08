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
import { PositionStruct } from "../typechain-types/contracts/ManagerHelper";
import { constants } from "ethers";
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
    slippage: ethers.utils.parseUnits("3", 17),
  },
];
const ethUsed = "1";

describe("Error codes", function () {
  let manager: PositionsManager;
  let helper: ManagerHelper;
  let owners: SignerWithAddress[];
  let networkTokenContract: IWETH;
  let universalSwap: UniversalSwap;
  let stableDecimals: number
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
    const stableToken = await ethers.getContractAt("ERC20", await universalSwap.stableToken())
    stableDecimals = await stableToken.decimals()
  });

  it("Rejects insufficient deposits", async function() {
    const owner = owners[0]
    for (const lpToken of networkAddresses.masterChefLps) {
      const networkTokenPrice = await universalSwap.estimateValueERC20(networkTokenContract.address, ethers.utils.parseEther("1"), await universalSwap.stableToken())
      const amountUsed = (ethers.utils.parseEther("1").mul(ethers.utils.parseUnits("1", stableDecimals)).div(networkTokenPrice)).mul(5)
      const { lpBalance, lpTokenContract } = await getLPToken(lpToken, universalSwap, ethers.utils.formatUnits(amountUsed, 18), owners[0]);
      
      const [banks, tokenIds] = await manager.recommendBank(lpToken);
      const bankAddress = banks.slice(-1)[0];
      const tokenId = tokenIds.slice(-1)[0];
      await lpTokenContract?.connect(owner).approve(manager.address, lpBalance);
      const bank = await ethers.getContractAt("BankBase", bankAddress);
      const rewards = await bank.getRewards(tokenId);
      const position: PositionStruct = {
        user: owner.address,
        bank: bankAddress,
        bankToken: tokenId,
        amount: lpBalance,
        liquidationPoints,
      };
      const tokens = lpToken != constants.AddressZero ? [lpToken] : [];
      const amounts = lpToken != constants.AddressZero ? [lpBalance] : [];
      await expect(manager
        .connect(owner)
        .deposit(position, tokens, amounts, { value: lpToken === constants.AddressZero ? lpBalance : "0" })).to.be.revertedWith("14")
    }
  })
  
  it("Rejects withdrawals that leave position with insufficient funds", async function() {
    const owner = owners[0]
    for (const lpToken of networkAddresses.masterChefLps) {
      const networkTokenPrice = await universalSwap.estimateValueERC20(networkTokenContract.address, ethers.utils.parseEther("1"), await universalSwap.stableToken())
      const amountUsed = (ethers.utils.parseEther("1").mul(ethers.utils.parseUnits("1", stableDecimals)).div(networkTokenPrice)).mul(15)
      const { lpBalance, lpTokenContract } = await getLPToken(lpToken, universalSwap, ethers.utils.formatUnits(amountUsed, 18), owners[0]);
      const { positionId } = await depositNew(
        manager,
        lpToken,
        lpBalance,
        liquidationPoints,
        owners[0]
      );
      
      const positionSize = (await helper.getPosition(positionId)).position.amount
      await expect(manager.withdraw(positionId, positionSize.div(2))).to.be.revertedWith("14")
    }
  })

  it("Rejects order that is unable to cover liquidation fee", async function() {
    const owner = owners[0]
    for (const lpToken of networkAddresses.masterChefLps) {
      const { lpBalance, lpTokenContract } = await getLPToken(lpToken, universalSwap, ethUsed, owners[0]);
      const { positionId } = await depositNew(
        manager,
        lpToken,
        lpBalance,
        liquidationPoints,
        owners[0]
      );
      
      await expect(manager.botLiquidate(positionId, 0, ethers.utils.parseEther("10"), [], [])).to.be.revertedWith("13")
    }
  })

  it("Rejects excessive withdrawal", async function() {
    const owner = owners[0]
    for (const lpToken of networkAddresses.masterChefLps) {
      const { lpBalance, lpTokenContract } = await getLPToken(lpToken, universalSwap, "10", owners[0]);
      const { positionId } = await depositNew(
        manager,
        lpToken,
        lpBalance,
        liquidationPoints,
        owners[0]
      );
      
      const positionSize = (await helper.getPosition(positionId)).position.amount
      await expect(manager.withdraw(positionId, positionSize.mul(2))).to.be.revertedWith("7")
    }
  })

  it("Rejects transactions for a closed position", async function() {
    for (const lpToken of networkAddresses.masterChefLps) {
      const { lpBalance, lpTokenContract } = await getLPToken(lpToken, universalSwap, "1", owners[0]);
      const { positionId } = await depositNew(
        manager,
        lpToken,
        lpBalance,
        liquidationPoints,
        owners[0]
      );
      await manager.close(positionId, "")
      await expect(manager.depositInExisting(
        positionId, {tokens: [networkAddresses.networkToken], amounts: [ethers.utils.parseEther("1")], nfts: []}, [], [], [0]
      )).to.be.revertedWith("12")
      await expect(manager.harvestAndRecompound(positionId, [], [], [0])).to.be.revertedWith("12")
      await expect(manager.harvestRewards(positionId)).to.be.revertedWith("12")
      await expect(manager.close(positionId, "")).to.be.revertedWith("12")
    }
  })

  it("Rejects unauthorized access", async function() {
    for (const lpToken of networkAddresses.masterChefLps) {
      const { lpBalance, lpTokenContract } = await getLPToken(lpToken, universalSwap, ethUsed, owners[0]);
      const { positionId } = await depositNew(
        manager,
        lpToken,
        lpBalance,
        liquidationPoints,
        owners[0]
      );
      
      await expect(manager.connect(owners[2]).depositInExisting(
        positionId, {tokens: [networkAddresses.networkToken], amounts: [ethers.utils.parseEther("1")], nfts: []}, [], [], [0]
      )).to.be.revertedWith("1")
      await expect(manager.connect(owners[2]).harvestAndRecompound(positionId, [], [], [0])).to.be.revertedWith("1")
      await expect(manager.connect(owners[2]).harvestRewards(positionId)).to.be.revertedWith("1")
      await expect(manager.connect(owners[2]).close(positionId, "")).to.be.revertedWith("1")
    }
  })

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

  it("Rejects swap because of slippage", async function() {
    await expect(universalSwap.swap(
      {tokens: [ethers.constants.AddressZero], amounts: [ethers.utils.parseEther("1")], nfts: []},
      [], [],
      {
        outputERC20s: [await universalSwap.stableToken()],
        outputERC721s: [],
        minAmountsOut: [ethers.utils.parseEther("1000")],
        ratios: [1]
      }, await owners[0].getAddress(),
      {value: ethers.utils.parseEther("1")})).to.be.revertedWith("3")
  })

  it("Rejects swap with no tokens", async function() {
    await expect(universalSwap.swap(
      {tokens: [], amounts: [], nfts: []},
      [], [],
      {
        outputERC20s: [await universalSwap.stableToken()],
        outputERC721s: [],
        minAmountsOut: [ethers.utils.parseEther("1000")],
        ratios: [1]
      }, await owners[0].getAddress())).to.be.revertedWith("4")
  })
})