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
    networkTokenContract = await ethers.getContractAt("IERC20", networkAddresses.networkToken);
    await networkTokenContract.transfer(owners[1].address, networkTokenContract.balanceOf(owners[0].address));
    const { wethContract } = await getNetworkToken(owners[0], "10.0");
    await wethContract.connect(owners[0]).approve(universalSwap.address, ethers.utils.parseEther("100"));
  });

  it("Sends 0.1% fee to treasury", async function() {
    for (const token of networkAddresses.commonPoolTokens.slice(1)) {
        const {lpBalance, lpTokenContract} = await getLPToken(token, universalSwap, "1", owners[0])
        // @ts-ignore
        await lpTokenContract.approve(universalSwap.address, lpBalance)
        await universalSwap.swap(
            {tokens: [token], amounts: [lpBalance], nfts: []},
            [], [],
            {outputERC20s: [networkAddresses.networkToken], outputERC721s: [], minAmountsOut: [0], ratios: [1]}, await owners[0].getAddress()
        )
        const treasury = await universalSwap.treasury()
        // @ts-ignore
        expect(await lpTokenContract.balanceOf(treasury)).to.equal(lpBalance.div(1000))
    }
  })
});
