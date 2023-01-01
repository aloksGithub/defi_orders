import { ethers } from "hardhat"

export const verify = async (positionManagerAddress: string) => {
  const positionManager = await ethers.getContractAt("PositionsManager", positionManagerAddress)
  const universalSwap = await ethers.getContractAt("UniversalSwap", await positionManager.universalSwap())
  const managerHelper = await ethers.getContractAt("ManagerHelper", await positionManager.helper())
  const providedHelper = await universalSwap.providedHelper()
  const conversionhelper = await universalSwap.conversionHelper()
  const swapHelper = await universalSwap.swapHelper()
  const oracle = await universalSwap.oracle()
  const swappers = await universalSwap.getSwappers()
  const poolInteractors = await universalSwap.getPoolInteractors()
  const nftPoolInteractors = await universalSwap.getNFTPoolInteractors()
  const banks = await positionManager.getBanks()
  const ecr20Bank = banks[0]
  const erc721Bank = banks[1]
  // const erc721BankWrapper = (await ethers.getContractAt("ERC721Bank", erc721Bank))
}