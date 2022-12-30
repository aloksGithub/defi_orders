import { ethers } from "hardhat";
require("dotenv").config();

async function main() {
  await ethers.provider.send("hardhat_mine", ["0x93A80", "0x3"]);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
