import { expect } from "chai";
import { deployments, ethers } from "hardhat";
import { UniversalSwap, IERC20 } from "../typechain-types";
import {
  addresses,
  getNetworkToken,
  getLPToken,
} from "../utils";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";

// @ts-ignore
const networkAddresses = addresses[hre.network.name];

describe("Swap fee", async function () {
  let universalSwap: UniversalSwap;
  let owners: SignerWithAddress[];
  let networkTokenContract: IERC20;

  before(async function () {
    await deployments.fixture()
    const universalSwapAddress = (await deployments.get('UniversalSwap')).address;
    universalSwap = await ethers.getContractAt("UniversalSwap", universalSwapAddress)
    owners = await ethers.getSigners();
    const { wethContract } = await getNetworkToken(owners[1], "10.0");
    await wethContract.connect(owners[1]).approve(universalSwap.address, ethers.utils.parseEther("100"));
  });

  it("Sends 0.1% fee to treasury", async function() {
    for (const token of networkAddresses.commonPoolTokens.slice(1)) {
      const {lpBalance, lpTokenContract} = await getLPToken(token, universalSwap, "1", owners[1])
      const treasury = await universalSwap.treasury()
      // @ts-ignore
      const treasuryBalanceBefore = await lpTokenContract.balanceOf(treasury)
      // @ts-ignore
      await lpTokenContract.connect(owners[1]).approve(universalSwap.address, lpBalance)
      await universalSwap.connect(owners[1]).swap(
          {tokens: [token], amounts: [lpBalance], nfts: []},
          [], [],
          {outputERC20s: [networkAddresses.networkToken], outputERC721s: [], minAmountsOut: [0], ratios: [1]}, await owners[1].getAddress()
      )
      // @ts-ignore
      const treasuryBalanceAfter = await lpTokenContract.balanceOf(treasury)
      expect(treasuryBalanceAfter.sub(treasuryBalanceBefore)).to.equal(lpBalance.div(1000))
    }
  })
});
