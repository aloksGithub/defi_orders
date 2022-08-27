import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { ethers } from "hardhat";
import hre from 'hardhat'
import { PositionsManager, UniversalSwap } from "../typechain-types";
import { BigNumber, Contract } from "ethers";
import { expect } from "chai";
import {addresses as ethereumAddresses} from "../constants/ethereum_addresses.json"
import {addresses as bscAddresses} from "../constants/bsc_addresses.json"
var fs = require('fs');

const ENVIRONMENT = process.env.ENVIRONMENT!
const CURRENTLY_FORKING = process.env.CURRENTLY_FORKING!

export const addresses = {
  mainnet: ethereumAddresses,
  bsc: bscAddresses,
  localhost: undefined,
  hardhat: undefined
}
// @ts-ignore
addresses.localhost = addresses[CURRENTLY_FORKING]
// @ts-ignore
addresses.hardhat = addresses[CURRENTLY_FORKING]

export async function getNetworkToken (signer:any, ether:string) {
  const network = hre.network.name
  // @ts-ignore
  const wethContract = await ethers.getContractAt("IWETH", addresses[network].networkToken)
  await wethContract.connect(signer).deposit({value: ethers.utils.parseEther(ether)})
  const balance = await wethContract.balanceOf(signer.address)
  return {balance, wethContract}
}

const logDeployment = (contractName: string, contract:Contract) => {
  const network = hre.network.name
  const filePath = `deployments/${network}`
  fs.appendFile(
    filePath,
    `Deployed ${contractName} at address ${contract.address} in transaction ${contract.deployTransaction.hash}\n`,
    ()=>console.log(`Deployed ${contractName} at address ${contract.address} in transaction ${contract.deployTransaction.hash}`)
  )
}

const ethereumPoolInteractors = async (verify:boolean=false, log:boolean=false) => {
  const uniswapPoolInteractorContract = await ethers.getContractFactory('UniswapV2PoolInteractor')
  const uniswapPoolInteractor = await uniswapPoolInteractorContract.deploy()
  const aaveV2PoolInteractorFactory = await ethers.getContractFactory('AaveV2PoolInteractor')
  const aaveV2PoolInteractor = await aaveV2PoolInteractorFactory.deploy(addresses['mainnet'].aaveV1LendingPool, addresses['mainnet'].aaveV2LendingPool, addresses['mainnet'].aaveV3LendingPool)
  aaveV2PoolInteractor.deployTransaction.hash
  const balancerPoolInteractorFactory = await ethers.getContractFactory('BalancerPoolInteractor')
  const balancerPoolInteractor = await balancerPoolInteractorFactory.deploy(addresses['mainnet'].balancerVault)
  if (verify) {
    await hre.run("verify:verify", {
      address: uniswapPoolInteractor.address,
      constructorArguments: [],
      network: 'mainnet'
    })
    await hre.run("verify:verify", {
      address: aaveV2PoolInteractor.address,
      constructorArguments: [addresses['mainnet'].aaveV2LendingPool],
      network: 'mainnet'
    })
    await hre.run("verify:verify", {
      address: balancerPoolInteractor.address,
      constructorArguments: [addresses['mainnet'].balancerVault],
      network: 'mainnet'
    })
  }
  if (log) {
    logDeployment('UniswapV2PoolInteractor', uniswapPoolInteractor)
    logDeployment('AaveV2PoolInteractor', aaveV2PoolInteractor)
    logDeployment('BalancerPoolInteractor', balancerPoolInteractor)
  }
  return {names: ["Uniswap", "SushiSwap", "Aave", "Balancer"], addresses: [uniswapPoolInteractor.address, uniswapPoolInteractor.address, aaveV2PoolInteractor.address, balancerPoolInteractor.address]}
}

const bscPoolInteractors = async (verify:boolean=false, log:boolean=false) => {
  const venusPoolInteractorFactory = await ethers.getContractFactory("VenusPoolInteractor")
  const venusPoolInteractor = await venusPoolInteractorFactory.deploy()
  const pancakePoolInteractorFactory = await ethers.getContractFactory("UniswapV2PoolInteractor")
  const pancakePoolInteractor = await pancakePoolInteractorFactory.deploy()
  if (verify) {
    await hre.run("verify:verify", {
      address: venusPoolInteractor.address,
      constructorArguments: [],
      network: 'bsc'
    })
    await hre.run("verify:verify", {
      address: pancakePoolInteractor.address,
      constructorArguments: [],
      network: 'bsc'
    })
  }
  if (log) {
    logDeployment('VenusPoolInteractor', venusPoolInteractor)
    logDeployment('UniswapV2PoolInteractor', pancakePoolInteractor)
  }
  return {names: ["Venus", "Pancake LP", "Biswap LP"], addresses: [venusPoolInteractor.address, pancakePoolInteractor.address, pancakePoolInteractor.address]}
}

export const getPoolInteractors = async (verify:boolean=false, log:boolean=false) => {
  const network = hre.network.name
  
  let poolInteractorFunctions = {
    mainnet: ethereumPoolInteractors,
    bsc: bscPoolInteractors,
    localhost: undefined,
    hardhat: undefined
  }
  // @ts-ignore
  poolInteractorFunctions.localhost = poolInteractorFunctions[CURRENTLY_FORKING]
  // @ts-ignore
  poolInteractorFunctions.hardhat = poolInteractorFunctions[CURRENTLY_FORKING]
  // @ts-ignore
  const poolInteractors = await poolInteractorFunctions[network](verify, log)
  return poolInteractors
}

export const getUniversalSwap = async (verify:boolean=false, log:boolean=false) => {
  const network = hre.network.name
  const universalSwapContract = await ethers.getContractFactory('UniversalSwap')
  const swapperFactory = await ethers.getContractFactory('UniswapV2Swapper')
  const swapper = await swapperFactory.deploy()
  const {names, addresses: poolInteractors} = await getPoolInteractors(verify, log)
  // @ts-ignore
  const universalSwap = await universalSwapContract.deploy(names, poolInteractors, addresses[network].networkToken, addresses[network].uniswapV2Routers, swapper.address)
  // const owner = (await ethers.getSigners())[0]
  // const {wethContract} = await getNetworkToken(owner, '1000.0')
  // await wethContract.connect(owner).approve(universalSwap.address, ethers.utils.parseEther("1000"))
  // const {lpBalance: lpBalance0, lpTokenContract} = await getLPToken("0xdAC17F958D2ee523a2206206994597C13D831ec7", universalSwap, "1", owner)
  // await lpTokenContract.transfer(swapper.address, lpBalance0)
  // await swapper.swap("0xdAC17F958D2ee523a2206206994597C13D831ec7", lpBalance0, "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2", "0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F")
  // console.log("SUCCESS")
  if (verify) {
    await hre.run("verify:verify", {
      address: swapper.address,
      constructorArguments: [],
      network
    })
    await hre.run("verify:verify", {
      address: universalSwap.address,
      // @ts-ignore
      constructorArguments: [names, poolInteractors, addresses[network].networkToken, addresses[network].uniswapV2Routers, swapper.address],
      network
    })
  }
  if (log) {
    logDeployment('UniswapV2Swapper', swapper)
    logDeployment('UniversalSwap', universalSwap)
  }
  return universalSwap
}

const deployPositionsManager = async (verify:boolean=false, log:boolean=false) => {
  const network = hre.network.name
  const positionsManagerFactory = await ethers.getContractFactory("PositionsManager")
  const universalSwap = await getUniversalSwap(verify, log)
  const positionsManager = await positionsManagerFactory.deploy(universalSwap.address)
  if (verify) {
    await hre.run("verify:verify", {
      address: positionsManager.address,
      constructorArguments: [universalSwap.address],
      network
    })
  }
  if (log) {
    logDeployment('PositionsManager', positionsManager)
  }
  return positionsManager
}

const deployERC20Bank = async (positionsManager: string, verify:boolean=false, log:boolean=false) => {
  const network = hre.network.name
  const bankFactory = await ethers.getContractFactory("ERC20Bank")
  const erc20Bank = await bankFactory.deploy(positionsManager)
  if (verify) {
    await hre.run("verify:verify", {
      address: erc20Bank.address,
      constructorArguments: [],
      network
    })
  }
  if (log) {
    logDeployment('ERC20Bank', erc20Bank)
  }
  return erc20Bank
}

const masterChefV1Wrapper = async (verify:boolean=false, log:boolean=false) => {
  const network = hre.network.name
  const wrapperV1Factory = await ethers.getContractFactory("MasterChefV1Wrapper")
  const wrapperV1 = await wrapperV1Factory.deploy()
  // @ts-ignore
  for (const masterChef of addresses[network].v1MasterChefs) {
    await wrapperV1.addMasterChef(masterChef.address, masterChef.rewardGetter, masterChef.hasExtraRewards)
    const masterChefContract = await ethers.getContractAt("IMasterChefV1", masterChef.address)
    const numPools = ENVIRONMENT==='prod'?(await masterChefContract.poolLength()).toNumber():10
    for (let i = 0; i<numPools; i++) {
      await wrapperV1.setSupportedLp(masterChef.address, i)
    }
  }
  if (verify) {
    await hre.run("verify:verify", {
      address: wrapperV1.address,
      constructorArguments: [],
      network
    })
  }
  if (log) {
    logDeployment('MasterChefV1Wrapper', wrapperV1)
  }
  return wrapperV1
}

const masterChefV2Wrapper = async (verify:boolean=false, log:boolean=false) => {
  const network = hre.network.name
  const wrapperV2Factory = await ethers.getContractFactory("MasterChefV2Wrapper")
  const wrapperV2 = await wrapperV2Factory.deploy()
  // @ts-ignore
  for (const masterChef of addresses[network].v2MasterChefs) {
    await wrapperV2.addMasterChef(masterChef.address, masterChef.rewardGetter, masterChef.hasExtraRewards)
    const masterChefContract = await ethers.getContractAt("ISushiSwapMasterChefV2", masterChef.address)
    const numPools = ENVIRONMENT==='prod'?(await masterChefContract.poolLength()).toNumber():10
    for (let i = 0; i<numPools; i++) {
      await wrapperV2.setSupportedLp(masterChef.address, i)
    }
  }
  if (verify) {
    await hre.run("verify:verify", {
      address: wrapperV2.address,
      constructorArguments: [],
      network
    })
  }
  if (log) {
    logDeployment('MasterChefV2Wrapper', wrapperV2)
  }
  return wrapperV2
}

const pancakeMasterChefWrapper = async (verify:boolean=false, log:boolean=false) => {
  const factory = await ethers.getContractFactory("PancakeSwapMasterChefV2Wrapper")
  const wrapper = await factory.deploy()
  const masterChef = addresses['bsc'].pancakeV2MasterChef
  await wrapper.addMasterChef(masterChef.address, masterChef.rewardGetter, masterChef.hasExtraRewards)
  const masterChefContract = await ethers.getContractAt("IPancakeSwapMasterChefV2", masterChef.address)
  const numPools = ENVIRONMENT==='prod'?(await masterChefContract.poolLength()).toNumber():10
  for (let i = 0; i<numPools; i++) {
    await wrapper.setSupportedLp(masterChef.address, i)
  }
  if (verify) {
    await hre.run("verify:verify", {
      address: wrapper.address,
      constructorArguments: [],
      network: 'bsc'
    })
  }
  if (log) {
    logDeployment('PancakeSwapMasterChefV2Wrapper', wrapper)
  }
  return wrapper
}

const deployMasterChefBank = async (positionsManager: string, verify:boolean=false, log:boolean=false) => {
  const network = hre.network.name
  const wrapperV1 = await masterChefV1Wrapper(verify, log)
  const wrapperV2 = await masterChefV2Wrapper(verify, log)
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
  if (network=='bsc' || ((network=='localhost' || network=='hardhat') && CURRENTLY_FORKING=='bsc')) {
    const pancakeWrapper = await pancakeMasterChefWrapper(verify, log)
    const masterChef = addresses['bsc'].pancakeV2MasterChef
    await masterChefBank.setMasterChefWrapper(masterChef.address, pancakeWrapper.address)
  }
  if (verify) {
    await hre.run("verify:verify", {
      address: masterChefBank.address,
      constructorArguments: [positionsManager],
      network
    })
  }
  if (log) {
    logDeployment('MasterChefBank', masterChefBank)
  }
  return masterChefBank
}

export const deployAndInitializeManager = async (verify:boolean=false, log:boolean=false) => {
  const network = hre.network.name
  if (log) {
    const filePath = `deployments/${network}`
    if (fs.existsSync(filePath)) {
      fs.unlinkSync(filePath)
    }
    fs.writeFileSync(filePath, `Contracts deployed at ${new Date()}\n\n`)
  }
  const positionsManager = await deployPositionsManager(verify, log)
  const erc20Bank = await deployERC20Bank(positionsManager.address, verify, log)
  const masterChefBank = await deployMasterChefBank(positionsManager.address, verify, log)
  await positionsManager.addBank(erc20Bank.address)
  await positionsManager.addBank(masterChefBank.address)
  return positionsManager
}

export const getLPToken = async (lpToken: string, universalSwap: UniversalSwap, etherAmount: string, owner:SignerWithAddress) => {
  const network = hre.network.name
  const lpTokenContract = await ethers.getContractAt("ERC20", lpToken)
  // @ts-ignore
  await universalSwap.connect(owner).swap([addresses[network].networkToken], [ethers.utils.parseEther(etherAmount)], lpToken)
  const lpBalance = await lpTokenContract.balanceOf(owner.address)
  return {lpBalance, lpTokenContract}
}

export const depositNew = async (manager:PositionsManager, lpToken: string, amount:string, liquidateTo:string, watchedTokens: string[], lessThan: boolean[], liquidationPoints: number[], owner:any) => {
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