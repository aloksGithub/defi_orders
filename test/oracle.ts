import { deployments, ethers } from "hardhat";
import { BasicOracle } from "../typechain-types";
import { addresses, isRoughlyEqual } from "../utils";
import hre from "hardhat";

const networkAddresses = addresses[hre.network.name];

describe("Oracle tests", function () {
  let oracle: BasicOracle;
  before(async function () {
    await deployments.fixture()
    const oracleAddress = (await deployments.get('BasicOracle')).address;
    oracle = await ethers.getContractAt("BasicOracle", oracleAddress);
  });
  it("Oracle works correctly", async function () {
    const price = await oracle.getPrice(networkAddresses.preferredStable, networkAddresses.networkToken);
    const price2 = await oracle.getPrice(networkAddresses.networkToken, networkAddresses.preferredStable);
    const usdc = await ethers.getContractAt("ERC20", networkAddresses.preferredStable);
    const usdcDecimals = await usdc.decimals();
    const networkToken = await ethers.getContractAt("ERC20", networkAddresses.networkToken);
    const networkTokenDecimals = await networkToken.decimals();
    isRoughlyEqual(price.mul(price2), ethers.utils.parseUnits("1", usdcDecimals + networkTokenDecimals));
  });
});
