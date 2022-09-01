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
const NUM_INITIALIZE_MASTERCHEFS = 10

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
  const uniswapPoolInteractor = await uniswapPoolInteractorContract.deploy(["Uniswap V2", "SushiSwap LP Token"])
  const aaveV2PoolInteractorFactory = await ethers.getContractFactory('AaveV2PoolInteractor')
  const aaveV2PoolInteractor = await aaveV2PoolInteractorFactory.deploy(addresses['mainnet'].aaveV1LendingPool, addresses['mainnet'].aaveV2LendingPool, addresses['mainnet'].aaveV3LendingPool)
  if (verify) {
    await hre.run("verify:verify", {
      address: uniswapPoolInteractor.address,
      constructorArguments: [["Uniswap V2", "SushiSwap LP Token"]],
      network: 'mainnet'
    })
    await hre.run("verify:verify", {
      address: aaveV2PoolInteractor.address,
      constructorArguments: [addresses['mainnet'].aaveV1LendingPool, addresses['mainnet'].aaveV2LendingPool, addresses['mainnet'].aaveV3LendingPool],
      network: 'mainnet'
    })
  }
  if (log) {
    logDeployment('UniswapV2PoolInteractor', uniswapPoolInteractor)
    logDeployment('AaveV2PoolInteractor', aaveV2PoolInteractor)
  }
  return [uniswapPoolInteractor.address, uniswapPoolInteractor.address, aaveV2PoolInteractor.address]
}

const ethereumSwappers = async (verify:boolean=false, log:boolean=false) => {
  const uniswapV2SwapperFactory = await ethers.getContractFactory("UniswapV2Swapper")
  const uniswapV2Swapper = await uniswapV2SwapperFactory.deploy(addresses['mainnet'].uniswapV2Routers)
  if (verify) {
    await hre.run("verify:verify", {
      address: uniswapV2Swapper.address,
      constructorArguments: [addresses['mainnet'].uniswapV2Routers],
      network: 'mainnet'
    })
  }
  if (log) {
    logDeployment('UniswapV2Swapper', uniswapV2Swapper)
  }
  return [uniswapV2Swapper.address]
}

const bscPoolInteractors = async (verify:boolean=false, log:boolean=false) => {
  const venusPoolInteractorFactory = await ethers.getContractFactory("VenusPoolInteractor")
  const venusPoolInteractor = await venusPoolInteractorFactory.deploy()
  const pancakePoolInteractorFactory = await ethers.getContractFactory("UniswapV2PoolInteractor")
  const pancakePoolInteractor = await pancakePoolInteractorFactory.deploy(['Pancake LPs', 'Biswap LPs'])
  if (verify) {
    await hre.run("verify:verify", {
      address: venusPoolInteractor.address,
      constructorArguments: [],
      network: 'bsc'
    })
    await hre.run("verify:verify", {
      address: pancakePoolInteractor.address,
      constructorArguments: [['Pancake LPs', 'Biswap LPs']],
      network: 'bsc'
    })
  }
  if (log) {
    logDeployment('VenusPoolInteractor', venusPoolInteractor)
    logDeployment('UniswapV2PoolInteractor', pancakePoolInteractor)
  }
  return [venusPoolInteractor.address, pancakePoolInteractor.address, pancakePoolInteractor.address]
}

const bscSwappers = async(verify:boolean=false, log:boolean=false) => {
  const uniswapV2SwapperFactory = await ethers.getContractFactory("UniswapV2Swapper")
  const uniswapV2Swapper = await uniswapV2SwapperFactory.deploy(addresses['bsc'].uniswapV2Routers)
  if (verify) {
    await hre.run("verify:verify", {
      address: uniswapV2Swapper.address,
      constructorArguments: [addresses['bsc'].uniswapV2Routers],
      network: 'bsc'
    })
  }
  if (log) {
    logDeployment('UniswapV2Swapper', uniswapV2Swapper)
  }
  return [uniswapV2Swapper.address]
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

const nftPoolInteractors = async (verify:boolean=false, log:boolean=false) => {
  const network = hre.network.name
  const factory = await ethers.getContractFactory("UniswapV3PoolInteractor")
  const interactor = await factory.deploy(["Uniswap V3 Positions NFT-V1"])
  
  if (verify) {
    await hre.run("verify:verify", {
      address: interactor.address,
      constructorArguments: [["Uniswap V3 Positions NFT-V1"]],
      network
    })
  }
  if (log) {
    logDeployment('UniswapV3PoolInteractor', interactor)
  }
  return [interactor.address]
}

const getSwappers = async (verify:boolean=false, log:boolean=false) => {
  const network = hre.network.name
  let swapperFunctions = {
    mainnet: ethereumSwappers,
    bsc: bscSwappers,
    localhost: undefined,
    hardhat: undefined
  }
  // @ts-ignore
  swapperFunctions.localhost = swapperFunctions[CURRENTLY_FORKING]
  // @ts-ignore
  swapperFunctions.hardhat = swapperFunctions[CURRENTLY_FORKING]
  // @ts-ignore
  const swappers = await swapperFunctions[network](verify, log)
  return swappers

}

export const getUniversalSwap = async (verify:boolean=false, log:boolean=false) => {
  const network = hre.network.name
  const universalSwapContract = await ethers.getContractFactory('UniversalSwap')
  const swappers = await getSwappers(verify, log)
  const poolInteractors = await getPoolInteractors(verify, log)
  const nftInteractors = await nftPoolInteractors(verify, log)
  // @ts-ignore
  const universalSwap = await universalSwapContract.deploy(poolInteractors, nftInteractors, addresses[network].networkToken, swappers)
  if (verify) {
    await hre.run("verify:verify", {
      address: universalSwap.address,
      // @ts-ignore
      constructorArguments: [poolInteractors, addresses[network].networkToken, swappers],
      network
    })
  }
  if (log) {
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
      constructorArguments: [positionsManager],
      network
    })
  }
  if (log) {
    logDeployment('ERC20Bank', erc20Bank)
  }
  return erc20Bank
}

const deployERC721Bank = async (positionsManager: string, verify:boolean=false, log:boolean=false) => {
  const network = hre.network.name
  const bankFactory = await ethers.getContractFactory("ERC721Bank")
  const erc721Bank = await bankFactory.deploy(positionsManager)
  const wrapperFactory = await ethers.getContractFactory("UniswapV3Wrapper")
  const wrapper = await wrapperFactory.deploy()
  // @ts-ignore
  for (const manager of addresses[network].NFTManagers) {
    await erc721Bank.addManager(manager)
    await erc721Bank.setWrapper(manager, wrapper.address)
  }
  if (verify) {
    await hre.run("verify:verify", {
      address: erc721Bank.address,
      constructorArguments: [positionsManager],
      network
    })
    await hre.run("verify:verify", {
      address: wrapper.address,
      // @ts-ignore
      constructorArguments: [],
      network
    })
  }
  if (log) {
    logDeployment('erc721Bank', erc721Bank)
    logDeployment('UniswapV3Wrapper', wrapper)
  }
  return erc721Bank
}

const masterChefV1Wrapper = async (verify:boolean=false, log:boolean=false) => {
  const network = hre.network.name
  const wrapperV1Factory = await ethers.getContractFactory("MasterChefV1Wrapper")
  const wrapperV1 = await wrapperV1Factory.deploy()
  // @ts-ignore
  for (const masterChef of addresses[network].v1MasterChefs) {
    await wrapperV1.addMasterChef(masterChef.address, masterChef.rewardGetter, masterChef.hasExtraRewards)
    const masterChefContract = await ethers.getContractAt("IMasterChefV1", masterChef.address)
    const numPools = ENVIRONMENT==='prod'?(await masterChefContract.poolLength()).toNumber():NUM_INITIALIZE_MASTERCHEFS
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
    const numPools = ENVIRONMENT==='prod'?(await masterChefContract.poolLength()).toNumber():NUM_INITIALIZE_MASTERCHEFS
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
  const numPools = ENVIRONMENT==='prod'?(await masterChefContract.poolLength()).toNumber():NUM_INITIALIZE_MASTERCHEFS
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
  const erc721Bank = await deployERC721Bank(positionsManager.address, verify, log)
  const masterChefBank = await deployMasterChefBank(positionsManager.address, verify, log)
  await positionsManager.addBank(erc20Bank.address)
  await positionsManager.addBank(erc721Bank.address)
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

export const depositNew = async (manager:PositionsManager, lpToken: string, amount:string, liquidationPoints: any[], owner:any) => {
  const lpTokenContract = await ethers.getContractAt("ERC20", lpToken)
  const [bankIds, tokenIds] = await manager.recommendBank(lpToken)
  const bankId = bankIds.slice(-1)[0]
  const tokenId = tokenIds.slice(-1)[0]
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
    liquidationPoints
  }
  await manager.connect(owner)["deposit((address,uint256,uint256,uint256,(address,address,bool,uint256)[]),address[],uint256[])"](position, [lpToken], [amount])
  return {positionId: numPositions, rewards, rewardContracts}
}

export const getNFT = async (universalSwap:UniversalSwap, etherAmount:string, manager:string, pool:string, owner:any) => {
  const network = hre.network.name
  // @ts-ignore
  const networkToken = addresses[network].networkToken
  const networkTokenContract = await ethers.getContractAt("IERC20", networkToken)
  await networkTokenContract.connect(owner).approve(universalSwap.address, ethers.utils.parseEther(etherAmount))
  const abi = ethers.utils.defaultAbiCoder;
  const data = abi.encode(
    ["int24","int24"], // encode as address array
    [-887000, 887000]);
  const tx = await universalSwap.connect(owner).swapForNFT([networkToken], [ethers.utils.parseEther(etherAmount)], {pool, manager, tokenId: 0, data})
  const rc = await tx.wait()
  const event = rc.events?.find(event => event.event === 'NFTMinted')
  // @ts-ignore
  const [managerAddress, id] = event?.args
  return id;
}

export const depositNewNFT = async (manager:PositionsManager, nftManager:string, id:string, liquidationPoints: any[], owner:any) => {
  const [bankIds] = await manager.recommendBank(nftManager)
  const bankId = bankIds.slice(-1)[0]
  const managerContract = await ethers.getContractAt("IERC721", nftManager)
  await managerContract.connect(owner).approve(manager.address, id)
  const numPositions = await manager.numPositions()
  const bankAddress = await manager.banks(bankId)
  const bank = await ethers.getContractAt("ERC721Bank", bankAddress)
  const bankToken = await bank.encodeId(id, nftManager)
  const rewards = await bank.getRewards(bankToken)
  const rewardContracts = await Promise.all(rewards.map(async (r)=> await ethers.getContractAt("ERC20", r)))
  const position = {
    user: owner.address,
    bankId,
    bankToken,
    amount:0,
    liquidationPoints
  }
  await manager.connect(owner)["deposit((address,uint256,uint256,uint256,(address,address,bool,uint256)[]),address[],uint256[])"](position, [nftManager], [id])
  return {positionId: numPositions, rewards, rewardContracts}
}

export const checkNFTLiquidity = async (manager:string, id:string) => {
  const nftManager = await ethers.getContractAt("INonfungiblePositionManager", manager)
  const data = await nftManager.positions(id)
  return data.liquidity
}

export const isRoughlyEqual = (a:BigNumber, b:BigNumber) => {
  expect(a).to.lessThan(b.mul("105").div("100"))
  expect(a).to.greaterThan(b.mul("95").div("100"))
}