import { deployments, ethers } from "hardhat";
import hre from "hardhat";
import { PositionsManager, UniversalSwap } from "../typechain-types";
require("dotenv").config();

async function main() {
  const positionsManagerAddress = (await deployments.get("PositionsManager")).address
  const universalSwapAddress = (await deployments.get("UniversalSwap")).address
  const positionsManager: PositionsManager = await ethers.getContractAt("PositionsManager", positionsManagerAddress)
  const universalSwap: UniversalSwap = await ethers.getContractAt("UniversalSwap", universalSwapAddress)
  const helperAddress = (await deployments.get('ManagerHelper')).address;
  const managerHelper = await ethers.getContractAt("ManagerHelper", helperAddress)
  const swapHelper = await universalSwap.swapHelper()
  const providedHelper = await universalSwap.providedHelper()
  const conversionHelper = await universalSwap.conversionHelper()
  try {
    await hre.run("verify:verify", {
      address: managerHelper,
      constructorArguments: [],
      network: hre.network.name,
    });
  } catch (e) {
    console.log(e);
  }
  try {
    await hre.run("verify:verify", {
      address: swapHelper,
      constructorArguments: [conversionHelper],
      network: hre.network.name,
    });
  } catch (e) {
    console.log(e);
  }
  try {
    await hre.run("verify:verify", {
      address: providedHelper,
      constructorArguments: [],
      network: hre.network.name,
    });
  } catch (e) {
    console.log(e);
  }
  try {
    await hre.run("verify:verify", {
      address: conversionHelper,
      constructorArguments: [],
      network: hre.network.name,
    });
  } catch (e) {
    console.log(e);
  }
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
