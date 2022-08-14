import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { ethers } from "hardhat";
import { PositionsManager, UniversalSwap } from "../typechain-types";
import { BigNumber } from "ethers";
import { expect } from "chai";
import {addresses as ethereumAddresses} from "../constants/ethereum_addresses.json"
import {addresses as bscAddresses} from "../constants/bsc_addresses.json"

export const addresses = {
  ethereum: ethereumAddresses,
  bsc: bscAddresses
}

export async function getTimestamp() {
  const now = new Date().getTime()
  return Math.floor(now/1000)
}

export async function getNetworkToken (network: string, signer:any, ether:string) {
  // @ts-ignore
  const wethContract = await ethers.getContractAt("IWETH", addresses[network].networkToken)
  await wethContract.connect(signer).deposit({value: ethers.utils.parseEther(ether)})
  const balance = await wethContract.balanceOf(signer.address)
  return {balance, wethContract}
}

const ethereumPoolInteractors = async () => {
  const uniswapPoolInteractorContract = await ethers.getContractFactory('UniswapV2PoolInteractor')
  const uniswapPoolInteractor = await uniswapPoolInteractorContract.deploy()
  const aaveV2PoolInteractorFactory = await ethers.getContractFactory('AaveV2PoolInteractor')
  const aaveV2PoolInteractor = await aaveV2PoolInteractorFactory.deploy(addresses['ethereum'].aaveV2LendingPool)
  const balancerPoolInteractorFactory = await ethers.getContractFactory('BalancerPoolInteractor')
  const balancerPoolInteractor = await balancerPoolInteractorFactory.deploy(addresses['ethereum'].balancerVault)
  return {names: ["Uniswap", "SushiSwap", "Aave", "Balancer"], addresses: [uniswapPoolInteractor.address, uniswapPoolInteractor.address, aaveV2PoolInteractor.address, balancerPoolInteractor.address]}
}

const bscPoolInteractors = async () => {
  const venusPoolInteractorFactory = await ethers.getContractFactory("VenusPoolInteractor")
  const venusPoolInteractor = await venusPoolInteractorFactory.deploy()
  const pancakePoolInteractorFactory = await ethers.getContractFactory("UniswapV2PoolInteractor")
  const pancakePoolInteractor = await pancakePoolInteractorFactory.deploy()
  return {names: ["Venus", "Pancake LP", "Biswap LP"], addresses: [venusPoolInteractor.address, pancakePoolInteractor.address, pancakePoolInteractor.address]}
}

export const getPoolInteractors = async (network: string) => {
  const poolInteractorFunctions = {
    ethereum: ethereumPoolInteractors,
    bsc: bscPoolInteractors
  }
  // @ts-ignore
  const poolInteractors = await poolInteractorFunctions[network]()
  return poolInteractors
}

export const getUniversalSwap = async (network:string) => {
  const universalSwapContract = await ethers.getContractFactory('UniversalSwap')
  const swapperFactory = await ethers.getContractFactory('UniswapV2Swapper')
  const swapper = await swapperFactory.deploy()
  const {names, addresses: poolInteractors} = await getPoolInteractors(network)
  // @ts-ignore
  const universalSwap = await universalSwapContract.deploy(names, poolInteractors, addresses[network].networkToken, addresses[network].uniswapV2Routers, swapper.address)
  return universalSwap
}

const deployPositionsManager = async (network:string) => {
  const positionsManagerFactory = await ethers.getContractFactory("PositionsManager")
  const universalSwap = await getUniversalSwap(network)
  const positionsManager = positionsManagerFactory.deploy(universalSwap.address)
  return positionsManager
}

const deployERC20Bank = async (positionsManager: string) => {
  const bankFactory = await ethers.getContractFactory("ERC20Bank")
  const erc20Bank = await bankFactory.deploy(positionsManager)
  return erc20Bank
}

const masterChefV1Wrapper = async (network: string) => {
  const wrapperV1Factory = await ethers.getContractFactory("MasterChefV1Wrapper")
  const wrapperV1 = await wrapperV1Factory.deploy()
  // @ts-ignore
  for (const masterChef of addresses[network].v1MasterChefs) {
    await wrapperV1.initializeMasterChef(masterChef.address, masterChef.rewardGetter, masterChef.hasExtraRewards)
  }
  return wrapperV1
}

const masterChefV2Wrapper = async (network: string) => {
  const wrapperV2Factory = await ethers.getContractFactory("MasterChefV2Wrapper")
  const wrapperV2 = await wrapperV2Factory.deploy()
  // @ts-ignore
  for (const masterChef of addresses[network].v2MasterChefs) {
    await wrapperV2.initializeMasterChef(masterChef.address, masterChef.rewardGetter, masterChef.hasExtraRewards)
  }
  return wrapperV2
}

const pancakeMasterChefWrapper = async () => {
  const factory = await ethers.getContractFactory("PancakeSwapMasterChefV2Wrapper")
  const wrapper = await factory.deploy()
  const masterChef = addresses['bsc'].pancakeV2MasterChef
  await wrapper.initializeMasterChef(masterChef.address, masterChef.rewardGetter, masterChef.hasExtraRewards)
  return wrapper
}

const deployMasterChefBank = async (positionsManager: string, network:string) => {
  const wrapperV1 = await masterChefV1Wrapper(network)
  const wrapperV2 = await masterChefV2Wrapper(network)
  const bankFactory = await ethers.getContractFactory("MasterChefBank")
  const masterChefBank = await bankFactory.deploy(positionsManager)
  // @ts-ignore
  for (const masterChef of addresses[network].v2MasterChefs) {
    await masterChefBank.setMasterChefWrapper(masterChef.address, wrapperV2.address)
  }
  // @ts-ignore
  for (const masterChef of addresses[network].v1MasterChefs) {
    await masterChefBank.setMasterChefWrapper(masterChef.address, wrapperV1.address)
  }
  if (network=='bsc') {
    const pancakeWrapper = await pancakeMasterChefWrapper()
    const masterChef = addresses['bsc'].pancakeV2MasterChef
    await masterChefBank.setMasterChefWrapper(masterChef.address, pancakeWrapper.address)
  }
  return masterChefBank
}

export const deployAndInitializeManager = async (network: string) => {
  const positionsManager = await deployPositionsManager(network)
  const erc20Bank = await deployERC20Bank(positionsManager.address)
  const masterChefBank = await deployMasterChefBank(positionsManager.address, network)
  await positionsManager.addBank(erc20Bank.address)
  await positionsManager.addBank(masterChefBank.address)
  return positionsManager
}

export const getLPToken = async (lpToken: string, network: string, universalSwap: UniversalSwap, etherAmount: string, owner:SignerWithAddress) => {
  const lpTokenContract = await ethers.getContractAt("ERC20", lpToken)
  // @ts-ignore
  await universalSwap.connect(owner).swap([addresses[network].networkToken], [ethers.utils.parseEther(etherAmount)], lpToken)
  const lpBalance = await lpTokenContract.balanceOf(owner.address)
  return {lpBalance, lpTokenContract}
}

export const depositNew = async (manager:PositionsManager, lpToken: string, amount:string, liquidateTo:string, watchedTokens: string[], lessThan: boolean[], liquidationPoints: number[], owner:SignerWithAddress) => {
  const lpTokenContract = await ethers.getContractAt("ERC20", lpToken)
  const [bankId, tokenId] = await manager.recommendBank(lpToken)
  await lpTokenContract.connect(owner).approve(manager.address, amount)
  const numPositions = await manager.numPositions()
  const bankAddress = await manager.banks(bankId)
  const bank = await ethers.getContractAt("BankBase", bankAddress)
  const rewards = await bank.getRewards(tokenId)
  const rewardContracts = await Promise.all(rewards.map(async (r)=> await ethers.getContractAt("ERC20", r)))
  const position = {
    user: owner.address,
    bankId,
    bankToken: tokenId,
    amount,
    liquidateTo,
    watchedTokens,
    lessThan,
    liquidationPoints
  }
  await manager.connect(owner)["deposit((address,uint256,uint256,uint256,address,address[],bool[],uint256[]))"](position)
  return {positionId: numPositions, rewards, rewardContracts}
}

export const isRoughlyEqual = (a:BigNumber, b:BigNumber) => {
  expect(a).to.lessThan(b.mul("105").div("100"))
  expect(a).to.greaterThan(b.mul("95").div("100"))
}