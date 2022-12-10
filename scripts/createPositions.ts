import { ethers } from "hardhat";
import {deployAndInitializeManager, addresses, getNetworkToken, getLPToken, depositNew, isRoughlyEqual, getNFT, depositNewNFT} from "../utils"
import deployments from "../constants/deployments.json"
import hre from 'hardhat'
require('dotenv').config();


async function main() {
  const [owner] = await ethers.getSigners()
  // @ts-ignore
  const networkAddresses = addresses[hre.network.name]
  const liquidationPoints = [{liquidateTo: networkAddresses.networkToken, watchedToken: ethers.constants.AddressZero, lessThan:true, liquidationPoint: '100000000000000000000'}]
  const {wethContract} = await getNetworkToken(owner, '10.0')
  // @ts-ignore
  const positionManager = await ethers.getContractAt("PositionsManager", deployments[hre.network.name].positionsManager)
  const universalSwapAddress = await positionManager.universalSwap()
  const universalSwap = await ethers.getContractAt("UniversalSwap", universalSwapAddress)
  await wethContract.connect(owner).approve(universalSwapAddress, ethers.utils.parseEther("1000"))

  console.log("Deploying ERC-20 bank positions")
  const lpTokens = networkAddresses.erc20BankLps
  for (const lpToken of lpTokens) {
    const {lpBalance, lpTokenContract} = await getLPToken(lpToken, universalSwap, "1", owner)
    await depositNew(positionManager, lpToken, lpBalance.toString(), liquidationPoints, owner)
  }

  console.log("Deploying Uniswap-V3 positions")
  const pools = networkAddresses.nftBasaedPairs
  for (const pool of pools) {
    const nftManagerAddress = networkAddresses.NFTManagers[0]
    const id = await getNFT(universalSwap, "10", nftManagerAddress, pool, owner)
    await depositNewNFT(positionManager, nftManagerAddress, id, liquidationPoints, owner)
  }

  console.log("Deploying MasterChef bank positions")
  const masterChefLpTokens = networkAddresses.masterChefLps
  for (const lpToken of masterChefLpTokens) {
    const {lpBalance, lpTokenContract} = await getLPToken(lpToken, universalSwap, "1", owner)
    await lpTokenContract.connect(owner).approve(positionManager.address, lpBalance)
    await depositNew(positionManager, lpToken, lpBalance.toString(), liquidationPoints, owner)
  }
  await ethers.provider.send("hardhat_mine", ["0x93A80", "0x3"]);
  // const fetchPositions = async () => {
  //   const numPositions = await positionManager.numPositions()
  //   console.log(`Testing time to fetch ${numPositions} positions`)
  //   const startTime = performance.now()
  //   for (let i = 0; i<numPositions.toNumber(); i++) {
  //       await positionManager.connect(owner).getPosition(i)
  //       console.log(`Position ${i}`)
  //   }
  //   for (let i = 0; i<numPositions.toNumber(); i++) {
  //     console.log("Liquidating")
  //     positionManager.callStatic.botLiquidate(i, 0, 0).then((amount) => {
  //       const endTime = performance.now()
  //       console.log(`Position ${i} fetched in ${(endTime-startTime)/1000} seconds`)
  //     })
  //   }
  // }
  // await fetchPositions()
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
