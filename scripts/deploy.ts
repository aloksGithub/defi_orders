import { ethers } from "hardhat";
import {deployAndInitializeManager} from '../utils'
require('dotenv').config();

async function main() {
  deployAndInitializeManager(process.env.NETWORK!)
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
