import { ethers, network } from "hardhat";
import {deployAndInitializeManager} from '../utils'
import hre from 'hardhat'
require('dotenv').config();
import deployments from "../constants/deployments.json"
const FileSystem = require("fs");

async function main() {
  const owners = await ethers.getSigners()
  const adminBalanceBegin = await owners[0].getBalance()
  console.log(`Deploying contracts to ${hre.network.name}`)
  const positionsManager = await deployAndInitializeManager(network.name!='localhost', true)
  const universalSwap = await positionsManager.universalSwap()
  const deploymentAddresses = {
    positionsManager: positionsManager.address,
    universalSwap
  }
  const newJson = {...deployments, [hre.network.name]: deploymentAddresses}
  FileSystem.writeFile('constants/deployments.json', JSON.stringify(newJson), (error: Error) => {
    if (error) throw error;
  })
  const deploymentGas = adminBalanceBegin.sub(await owners[0].getBalance())
  console.log(`Gas cost for deployment ${ethers.utils.formatEther(deploymentGas)}`)
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
