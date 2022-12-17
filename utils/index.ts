import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { ethers, upgrades } from "hardhat";
import hre from 'hardhat'
import { PositionsManager, UniversalSwap } from "../typechain-types";
import { BigNumber, Contract } from "ethers";
import { expect } from "chai";
import {addresses as ethereumAddresses} from "../constants/ethereum_addresses.json"
import {addresses as bscAddresses} from "../constants/bsc_addresses.json"
import {addresses as bscTestnetAddresses} from "../constants/bsc_testnet_addresses.json"
import { getAssets } from "./protocolDataGetter";
var fs = require('fs');

const ENVIRONMENT = process.env.ENVIRONMENT!
const CURRENTLY_FORKING = process.env.CURRENTLY_FORKING!

const delay = (ms:number) => new Promise(res => setTimeout(res, ms));

export const addresses = {
  mainnet: ethereumAddresses,
  bsc: bscAddresses,
  bscTestnet: bscTestnetAddresses,
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
  if (verify) {
    await delay(10000)
    try {
    await hre.run("verify:verify", {
      address: uniswapPoolInteractor.address,
      constructorArguments: [],
      network: 'mainnet'
    })
    } catch (e) {
      console.log(e)
    }
    try {
    await hre.run("verify:verify", {
      address: aaveV2PoolInteractor.address,
      constructorArguments: [addresses['mainnet'].aaveV1LendingPool, addresses['mainnet'].aaveV2LendingPool, addresses['mainnet'].aaveV3LendingPool],
      network: 'mainnet'
    })
    } catch (e) {
      console.log(e)
    }
  }
  if (log) {
    logDeployment('UniswapV2PoolInteractor', uniswapPoolInteractor)
    logDeployment('AaveV2PoolInteractor', aaveV2PoolInteractor)
  }
  return [uniswapPoolInteractor.address, aaveV2PoolInteractor.address]
}

const swappers = async(verify:boolean=false, log:boolean=false) => {
  const network = hre.network.name
  const uniswapV2SwapperFactory = await ethers.getContractFactory("UniswapV2Swapper")
  const swappers = []
  // @ts-ignore
  for (const router of addresses[network].uniswapV2Routers) {
    // @ts-ignore
    const swapper = await uniswapV2SwapperFactory.deploy(router, addresses[network].commonPoolTokens)
    swappers.push(swapper.address)
    if (verify) {
      await delay(10000)
      try {
      await hre.run("verify:verify", {
        address: swapper.address,
        // @ts-ignore
        constructorArguments: [router, addresses[network].commonPoolTokens],
        network: network
      })
      } catch (e) {
        console.log(e)
      }
    }
    if (log) {
      logDeployment('UniswapV2Swapper', swapper)
    }
  }
  return swappers
}

const bscPoolInteractors = async (verify:boolean=false, log:boolean=false) => {
  const venusPoolInteractorFactory = await ethers.getContractFactory("VenusPoolInteractor")
  const venusPoolInteractor = await venusPoolInteractorFactory.deploy()
  const pancakePoolInteractorFactory = await ethers.getContractFactory("UniswapV2PoolInteractor")
  const pancakePoolInteractor = await pancakePoolInteractorFactory.deploy()
  if (verify) {
    await delay(10000)
    try {
    await hre.run("verify:verify", {
      address: venusPoolInteractor.address,
      constructorArguments: [],
      network: 'bsc'
    })
    } catch (e) {
      console.log(e)
    }
    try {
    await hre.run("verify:verify", {
      address: pancakePoolInteractor.address,
      constructorArguments: [],
      network: 'bsc'
    })
    } catch (e) {
      console.log(e)
    }
  }
  if (log) {
    logDeployment('VenusPoolInteractor', venusPoolInteractor)
    logDeployment('UniswapV2PoolInteractor', pancakePoolInteractor)
  }
  return [venusPoolInteractor.address, pancakePoolInteractor.address]
}

const bscTestnetPoolInteractors = async (verify:boolean=false, log:boolean=false) => {
  const pancakePoolInteractorFactory = await ethers.getContractFactory("UniswapV2PoolInteractor")
  const pancakePoolInteractor = await pancakePoolInteractorFactory.deploy()
  if (verify) {
    await delay(10000)
    try {
    await hre.run("verify:verify", {
      address: pancakePoolInteractor.address,
      constructorArguments: [],
      network: 'bsc'
    })
    } catch (e) {
      console.log(e)
    }
  }
  if (log) {
    logDeployment('UniswapV2PoolInteractor', pancakePoolInteractor)
  }
  return [pancakePoolInteractor.address]
}

export const getPoolInteractors = async (verify:boolean=false, log:boolean=false) => {
  const network = hre.network.name
  
  let poolInteractorFunctions = {
    mainnet: ethereumPoolInteractors,
    bsc: bscPoolInteractors,
    bscTestnet: bscTestnetPoolInteractors,
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
  const interactors = []
  // @ts-ignore
  for (const manager of addresses[network].NFTManagers) {
    const interactor = await factory.deploy(manager)
    interactors.push(interactor.address)
    if (verify) {
      await delay(10000)
      try {
      await hre.run("verify:verify", {
        address: interactor.address,
        constructorArguments: [manager],
        network
      })
      } catch (e) {
        console.log(e)
      }
    }
    if (log) {
      logDeployment('UniswapV3PoolInteractor', interactor)
    }
  }
  return interactors
}

const getSwappers = async (verify:boolean=false, log:boolean=false) => {
  const network = hre.network.name
  let swapperFunctions = {
    mainnet: swappers,
    bsc: swappers,
    bscTestNet: swappers,
    localhost: undefined,
    hardhat: undefined
  }
  // @ts-ignore
  swapperFunctions.localhost = swapperFunctions[CURRENTLY_FORKING]
  // @ts-ignore
  swapperFunctions.hardhat = swapperFunctions[CURRENTLY_FORKING]
  // @ts-ignore
  return (await swapperFunctions[network](verify, log))
}

export const deployOracle = async (verify:boolean=false, log:boolean=false) => {
  const network = hre.network.name
  const uniswapV2OracleFactory = await ethers.getContractFactory("UniswapV2Source")
  const uniswapV3OracleFactory = await ethers.getContractFactory("UniswapV3Source")
  const oracleFactory = await ethers.getContractFactory("BasicOracle")
  const sources = []
  // @ts-ignore
  for (const factory of addresses[network].uniswapV2Factories) {
    const source = await uniswapV2OracleFactory.deploy(factory)
    sources.push(source.address)
    if (verify) {
      await delay(10000)
      try {
        await hre.run("verify:verify", {
          address: source.address,
          constructorArguments: [factory],
          network
        })
      } catch (e) {
        console.log(e)
      }
    }
    if (log) {
      logDeployment('UniswapV2Oracle', source)
    }
  }
  // @ts-ignore
  for (const factory of addresses[network].uniswapV3Factories) {
    const source = await uniswapV3OracleFactory.deploy(factory)
    sources.push(source.address)
    if (verify) {
      await delay(10000)
      try {
        await hre.run("verify:verify", {
          address: source.address,
          constructorArguments: [factory],
          network
        })
      } catch (e) {
        console.log(e)
      }
    }
    if (log) {
      logDeployment('UniswapV3Oracle', source)
    }
  }
  const oracle = await oracleFactory.deploy(sources)
  if (verify) {
    await delay(10000)
    try {
      await hre.run("verify:verify", {
        address: oracle.address,
        constructorArguments: [sources],
        network
      })
    } catch (e) {
      console.log(e)
    }
  }
  if (log) {
    logDeployment('BasicOracle', oracle)
  }
  return oracle
}

export const getUniversalSwap = async (verify:boolean=false, log:boolean=false) => {
  const network = hre.network.name
  const universalSwapContract = await ethers.getContractFactory('UniversalSwap')
  const swappers2 = await swappers(verify, log)
  const poolInteractors = await getPoolInteractors(verify, log)
  const nftInteractors = await nftPoolInteractors(verify, log)
  const oracle = await deployOracle(verify, log)
  // @ts-ignore
  const universalSwap = await universalSwapContract.deploy(poolInteractors, nftInteractors, addresses[network].networkToken, addresses[network].preferredStable, swappers2, oracle.address)
  if (verify) {
    await delay(10000)
    try {
    await hre.run("verify:verify", {
      address: universalSwap.address,
      // @ts-ignore
      constructorArguments: [poolInteractors, nftInteractors, addresses[network].networkToken, addresses[network].preferredStable, swappers2, oracle.address, addresses[network].commonPoolTokens],
      network
    })
    } catch (e) {
      console.log(e)
    }
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
  // @ts-ignore
  const positionsManager = await positionsManagerFactory.deploy(universalSwap.address, addresses[network].usdc)
  if (verify) {
    await delay(10000)
    try {
    await hre.run("verify:verify", {
      address: positionsManager.address,
      // @ts-ignore
      constructorArguments: [universalSwap.address, addresses[network].usdc],
      network
    })
    } catch (e) {
      console.log(e)
    }
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
    await delay(10000)
    try {
    await hre.run("verify:verify", {
      address: erc20Bank.address,
      constructorArguments: [positionsManager],
      network
    })
    } catch (e) {
      console.log(e)
    }
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
    await delay(10000)
    try {
    await hre.run("verify:verify", {
      address: erc721Bank.address,
      constructorArguments: [positionsManager],
      network
    })
    } catch (e) {
      console.log(e)
    }
    try {
    await hre.run("verify:verify", {
      address: wrapper.address,
      constructorArguments: [],
      network
    })
    } catch (e) {
      console.log(e)
    }
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
  const wrappers = []
  // @ts-ignore
  for (const masterChef of addresses[network].v1MasterChefs) {
    const wrapperV1 = await wrapperV1Factory.deploy(masterChef.address, masterChef.reward, masterChef.pendingRewardsGetter)
    wrappers.push(wrapperV1.address)
    const masterChefContract = await ethers.getContractAt("IMasterChefV1", masterChef.address)
    if (verify) {
      await delay(10000)
      try {
      await hre.run("verify:verify", {
        address: wrapperV1.address,
        constructorArguments: [masterChef.address, masterChef.reward, masterChef.pendingRewardsGetter],
        network
      })
      } catch (e) {
        console.log(e)
      }
    }
    if (log) {
      logDeployment('MasterChefV1Wrapper', wrapperV1)
    }
  }
  return wrappers
}

const masterChefV2Wrapper = async (verify:boolean=false, log:boolean=false) => {
  const network = hre.network.name
  const wrapperV2Factory = await ethers.getContractFactory("MasterChefV2Wrapper")
  const wrappers = []
  // @ts-ignore
  for (const masterChef of addresses[network].v2MasterChefs) {
    const wrapperV2 = await wrapperV2Factory.deploy(masterChef.address, masterChef.reward, masterChef.pendingRewardsGetter)
    wrappers.push(wrapperV2.address)
    const masterChefContract = await ethers.getContractAt("ISushiSwapMasterChefV2", masterChef.address)
    if (verify) {
      await delay(10000)
      try{
      await hre.run("verify:verify", {
        address: wrapperV2.address,
        constructorArguments: [],
        network
      })
    } catch (e) {
      console.log(e)
    }
    }
    if (log) {
      logDeployment('MasterChefV2Wrapper', wrapperV2)
    }
  }
  return wrappers
}

const pancakeMasterChefWrapper = async (verify:boolean=false, log:boolean=false) => {
  const factory = await ethers.getContractFactory("PancakeSwapMasterChefV2Wrapper")
  const masterChef = addresses['bsc'].pancakeV2MasterChef
  const wrapper = await factory.deploy(masterChef.address, masterChef.reward, masterChef.pendingRewardsGetter)
  const masterChefContract = await ethers.getContractAt("IPancakeSwapMasterChefV2", masterChef.address)
  if (verify) {
    await delay(10000)
    try {
      await hre.run("verify:verify", {
        address: wrapper.address,
        constructorArguments: [masterChef.address, masterChef.rewardGetter, masterChef.pendingRewardsGetter],
        network: 'bsc'
      })
    } catch (e) {
      console.log(e)
    }
  }
  if (log) {
    logDeployment('PancakeSwapMasterChefV2Wrapper', wrapper)
  }
  return wrapper
}

const deployMasterChefBank = async (positionsManager: string, verify:boolean=false, log:boolean=false) => {
  const network = hre.network.name
  const wrappersV1 = await masterChefV1Wrapper(verify, log)
  const wrappersV2 = await masterChefV2Wrapper(verify, log)
  const bankFactory = await ethers.getContractFactory("MasterChefBank")
  const masterChefBank = await bankFactory.deploy(positionsManager)
  // @ts-ignore
  for (const [i, masterChef] of addresses[network].v2MasterChefs.entries()) {
    await masterChefBank.setMasterChefWrapper(masterChef.address, wrappersV2[i])
  }
  // @ts-ignore
  for (const [i, masterChef] of addresses[network].v1MasterChefs.entries()) {
    await masterChefBank.setMasterChefWrapper(masterChef.address, wrappersV1[i])
  }
  if (network=='bsc' || ((network=='localhost' || network=='hardhat') && CURRENTLY_FORKING=='bsc')) {
    const pancakeWrapper = await pancakeMasterChefWrapper(verify, log)
    const masterChef = addresses['bsc'].pancakeV2MasterChef
    await masterChefBank.setMasterChefWrapper(masterChef.address, pancakeWrapper.address)
  }
  if (verify) {
    await delay(10000)
    try {
      await hre.run("verify:verify", {
        address: masterChefBank.address,
        constructorArguments: [positionsManager],
        network
      })
    } catch (e) {
      console.log(e)
    }
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
  // @ts-ignore
  const wethContract = await ethers.getContractAt("IWETH", addresses[network].networkToken)
  await wethContract.connect(owner).approve(universalSwap.address, ethers.utils.parseEther(etherAmount))
  const lpTokenContract = await ethers.getContractAt("ERC20", lpToken)
  // @ts-ignore
  await universalSwap.connect(owner).swap({tokens: [addresses[network].networkToken], amounts: [ethers.utils.parseEther(etherAmount)], nfts: []}, [], [],
  {outputERC20s:[lpToken], outputERC721s: [], ratios: [1], minAmountsOut: [0]}, owner.address)
  const lpBalance = await lpTokenContract.balanceOf(owner.address)
  return {lpBalance, lpTokenContract}
}

export const depositNew = async (manager:PositionsManager, lpToken: string, amount:string, liquidationPoints: any[], owner:any) => {
  const lpTokenContract = await ethers.getContractAt("ERC20", lpToken)
  const [bankIds, bankNames, tokenIds] = await manager.recommendBank(lpToken)
  const bankId = bankIds.slice(-1)[0]
  const tokenId = tokenIds.slice(-1)[0]
  await lpTokenContract.connect(owner).approve(manager.address, amount)
  const numPositions = await manager.numPositions()
  const bankAddress = await manager.banks(bankId)
  const bank = await ethers.getContractAt("BankBase", bankAddress)
  const rewards = await bank.getRewards(tokenId)
  const rewardContracts = await Promise.all(rewards.map(async (r:any)=> await ethers.getContractAt("ERC20", r)))
  const position = {
    user: owner.address,
    bankId,
    bankToken: tokenId,
    amount,
    liquidationPoints
  }
  await manager.connect(owner).deposit(position, [lpToken], [amount])
  return {positionId: numPositions, rewards, rewardContracts}
}

export const getNearestUsableTick = (currentTick: number, space: number) => {
  // 0 is always a valid tick
  if(currentTick == 0){
      return 0
  }
  // Determines direction
  const direction = (currentTick >= 0) ? 1 : -1
  // Changes direction
  currentTick *= direction
  // Calculates nearest tick based on how close the current tick remainder is to space / 2
  let nearestTick = (currentTick%space <= space/2) ? currentTick - (currentTick%space) : currentTick + (space-(currentTick%space))
  // Changes direction back
  nearestTick *= direction
  
  return nearestTick
}

export const getNFT = async (universalSwap:UniversalSwap, etherAmount:string, manager:string, pool:string, owner:any) => {
  const network = hre.network.name
  // @ts-ignore
  const networkToken = addresses[network].networkToken
  const networkTokenContract = await ethers.getContractAt("IERC20", networkToken)
  await networkTokenContract.connect(owner).approve(universalSwap.address, ethers.utils.parseEther(etherAmount))
  const abi = ethers.utils.defaultAbiCoder;
  const poolContract = await ethers.getContractAt("IUniswapV3Pool", pool)
  const {tick} = await poolContract.slot0()
  const tickSpacing = await poolContract.tickSpacing()
  const nearestTick = getNearestUsableTick(tick, tickSpacing)
  const data = abi.encode(
    ["int24","int24","uint256","uint256"],
    [nearestTick-2500*tickSpacing, nearestTick+20*tickSpacing, 0, 0]);
  const tx = await universalSwap.connect(owner).swap(
    {tokens: [networkToken], amounts: [ethers.utils.parseEther((+etherAmount).toString())], nfts: []}, [], [],
    {outputERC20s: [], outputERC721s: [{pool, manager, tokenId: 0, liquidity: 0, data}], ratios: [1], minAmountsOut: []}, owner.address)
  const rc = await tx.wait()
  const event = rc.events?.find((event:any) => event.event === 'NFTMinted')
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
  const rewardContracts = await Promise.all(rewards.map(async (r:any)=> await ethers.getContractAt("ERC20", r)))
  const position = {
    user: owner.address,
    bankId,
    bankToken,
    amount:0,
    liquidationPoints
  }
  await manager.connect(owner).deposit(position, [nftManager], [id])
  return {positionId: numPositions, rewards, rewardContracts}
}

export const checkNFTLiquidity = async (manager:string, id:string) => {
  const nftManager = await ethers.getContractAt("INonfungiblePositionManager", manager)
  const data = await nftManager.positions(id)
  return data.liquidity
}

export const isRoughlyEqual = (a:BigNumber, b:BigNumber, percentage:number = 500) => {
  expect(a).to.lessThanOrEqual(b.mul(10000+percentage).div("10000"))
  expect(a).to.greaterThanOrEqual(b.mul(10000-percentage).div("10000"))
}

export {getAssets}