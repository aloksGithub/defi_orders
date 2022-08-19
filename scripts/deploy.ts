import { ethers } from "hardhat";
import {deployAndInitializeManager} from '../utils'
import hre from 'hardhat'
require('dotenv').config();

async function main() {
  const owners = await ethers.getSigners()
  const adminBalanceBegin = await owners[0].getBalance()
  console.log(`Deploying contracts to ${hre.network.name}`)
  await deployAndInitializeManager(false, true)
  const deploymentGas = adminBalanceBegin.sub(await owners[0].getBalance())
  console.log(`Gas used for deployment ${deploymentGas}`)
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
