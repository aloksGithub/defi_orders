import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { ethers } from "hardhat";
import { PositionsManager, UniversalSwap } from "../typechain-types";
import { BigNumber } from "ethers";
import { expect } from "chai";

const uniswapRouterV2 = "0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D"
const sushiRouterV2 = "0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F"
const uniswapFactoryV2 = "0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f"
const sushiFactoryV2 = "0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac"
const aaveV2LendingPool = "0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9"
const balancerLiquidityGaugeFactory = "0x4E7bBd911cf1EFa442BC1b2e9Ea01ffE785412EC"
const usdc = "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48"
const usdt = "0xdAC17F958D2ee523a2206206994597C13D831ec7"
const dai = "0x6B175474E89094C44Da98b954EedeAC495271d0F"
const weth = "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2"

export const addresses = {
  ethereum: {
    usdc: "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48",
    usdt: "0xdAC17F958D2ee523a2206206994597C13D831ec7",
    dai: "0x6B175474E89094C44Da98b954EedeAC495271d0F",
    bal: "0xba100000625a3754423978a60c9317c58a424e3D",
    sushi: "0x6B3595068778DD592e39A122f4f5a5cF09C90fE2",
    networkToken: "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2",
    uniswapRouterV2: "0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D",
    uniswapFactoryV2: "0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f",
    sushiRouterV2: "0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F",
    sushiFactoryV2: "0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac",
    aaveV2LendingPool: "0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9",
    balancerLiquidityGaugeFactory: "0x4E7bBd911cf1EFa442BC1b2e9Ea01ffE785412EC",
    balancerVault: "0xBA12222222228d8Ba445958a75a0704d566BF2C8",
    sushiMasterChefV1: "0xc2EdaD668740f1aA35E4D8f227fB8E17dcA888Cd",
    sushiMasterChefV2: "0xEF0881eC094552b2e128Cf945EF17a6752B4Ec5d",
    v1MasterChefs: [{address: "0xc2EdaD668740f1aA35E4D8f227fB8E17dcA888Cd", rewardGetter: "sushi()"}],
    sushiV2MasterChefs: [{address: "0xEF0881eC094552b2e128Cf945EF17a6752B4Ec5d", rewardGetter: "SUSHI()"}]
  }
}

export async function getTimestamp() {
  const now = new Date().getTime()
  return Math.floor(now/1000)
}

export async function getToken (token: string, signer:any, ether:string) {
  const routerV2Conctract = await ethers.getContractAt("IUniswapV2Router02", uniswapRouterV2, signer)
  const nextMinute = Math.floor((new Date()).getTime()/1000)+60
  await routerV2Conctract.swapExactETHForTokens(1, [weth, token], signer.address, nextMinute, {from: signer.address, value: ethers.utils.parseEther(ether)})
  const tokenContract = await ethers.getContractAt("IERC20", token)
  const tokenBalance = await tokenContract.functions.balanceOf(signer.address);
  return {tokenBalance, tokenContract}
}

export async function getNetworkToken (network: string, signer:any, ether:string) {
  // @ts-ignore
  const wethContract = await ethers.getContractAt("IWETH", addresses[network].networkToken)
  await wethContract.connect(signer).deposit({value: ethers.utils.parseEther(ether)})
  const balance = await wethContract.balanceOf(signer.address)
  return {balance, wethContract}
}

async function getUnderlyingAave (atoken:string) {
  const aTokenContract = await ethers.getContractAt("IAToken", atoken)
  const underlying = await aTokenContract.UNDERLYING_ASSET_ADDRESS();
  return [underlying]
}

async function getUnderlyingUniswapv2 (lpToken:string) {
  const pool = await ethers.getContractAt("IUniswapV2Pair", lpToken)
  const token0 = pool.token0()
  const token1 = pool.token1()
  return [token0, token1]
}

export const getUnderlyingTokens = {
  aave: getUnderlyingAave,
  uniswapv2: getUnderlyingUniswapv2,
  sushiswap: getUnderlyingUniswapv2
}

async function getLpTokenAave (underlyingTokens: string[], tokenBalances: any[], owner:any) {
  const lendingPool = await ethers.getContractAt("ILendingPool", aaveV2LendingPool, owner)
  const underlyingTokenContract = await ethers.getContractAt("ERC20", underlyingTokens[0], owner)
  await underlyingTokenContract.approve(lendingPool.address, tokenBalances[0].toString())
  lendingPool.deposit(underlyingTokens[0], tokenBalances[0].toString(), owner.address, "0")
  const aTokenAddress = await lendingPool.getReserveData(underlyingTokens[0])
  const aTokenContract = await ethers.getContractAt("IAToken", aTokenAddress.aTokenAddress)
  const lpBalance = await aTokenContract.balanceOf(owner.address)
  return lpBalance.toString()
}

async function getLpTokenUniswapv2 (underlyingTokens: string[], tokenBalances: any[], owner:any) {
  const routerV2Conctract = await ethers.getContractAt("IUniswapV2Router02", uniswapRouterV2)
  const timeStamp = await getTimestamp()+100
  const token0Contract = await ethers.getContractAt("ERC20", underlyingTokens[0])
  const token1Contract = await ethers.getContractAt("ERC20", underlyingTokens[1])
  await token0Contract.approve(uniswapRouterV2, tokenBalances[0])
  await token1Contract.approve(uniswapRouterV2, tokenBalances[1])
  await routerV2Conctract.addLiquidity(underlyingTokens[0], underlyingTokens[1], tokenBalances[0], tokenBalances[1], "0", "0", owner.address, timeStamp, {from:owner.address})
  const factoryV2Contract = await ethers.getContractAt("IUniswapV2Factory", uniswapFactoryV2)
  const pairAddress = await factoryV2Contract.getPair(underlyingTokens[0], underlyingTokens[1])
  const pairContract = await ethers.getContractAt("IUniswapV2Pair", pairAddress)
  const lpBalance = await pairContract.balanceOf(owner.address)
  return lpBalance.toString()
}

async function getLpTokenSushiswap (underlyingTokens: string[], tokenBalances: any[], owner:any) {
  const routerV2Conctract = await ethers.getContractAt("IUniswapV2Router02", sushiRouterV2)
  const timeStamp = await getTimestamp()+100
  const token0Contract = await ethers.getContractAt("ERC20", underlyingTokens[0])
  const token1Contract = await ethers.getContractAt("ERC20", underlyingTokens[1])
  await token0Contract.approve(sushiRouterV2, tokenBalances[0])
  await token1Contract.approve(sushiRouterV2, tokenBalances[1])
  await routerV2Conctract.addLiquidity(underlyingTokens[0], underlyingTokens[1], tokenBalances[0], tokenBalances[1], "0", "0", owner.address, timeStamp, {from:owner.address})
  const factoryV2Contract = await ethers.getContractAt("IUniswapV2Factory", sushiFactoryV2)
  const pairAddress = await factoryV2Contract.getPair(underlyingTokens[0], underlyingTokens[1])
  const pairContract = await ethers.getContractAt("IUniswapV2Pair", pairAddress)
  const lpBalance = await pairContract.balanceOf(owner.address)
  return lpBalance.toString()
}

export const getLPTokens = {
  aave: getLpTokenAave,
  uniswapv2: getLpTokenUniswapv2,
  sushiswap: getLpTokenSushiswap
}

export const getLiqudiators = async () => {
  const uniswapLiquidatorContract = await ethers.getContractFactory('UniswapV2Liquidator')
  const sushiswapLiquidatorFactory = await ethers.getContractFactory('UniswapV2Liquidator')
  const uniswapLiquidator = await uniswapLiquidatorContract.deploy(uniswapRouterV2, uniswapFactoryV2)
  const sushiswapLiquidator = await sushiswapLiquidatorFactory.deploy(sushiRouterV2, sushiFactoryV2)
  return [uniswapLiquidator.address, sushiswapLiquidator.address]
}

export const getPoolInteractors = async (network: string) => {
  const uniswapPoolInteractorContract = await ethers.getContractFactory('UniswapV2PoolInteractor')
  const uniswapPoolInteractor = await uniswapPoolInteractorContract.deploy()
  const aaveV2PoolInteractorFactory = await ethers.getContractFactory('AaveV2PoolInteractor')
  // @ts-ignore
  const aaveV2PoolInteractor = await aaveV2PoolInteractorFactory.deploy(addresses[network].aaveV2LendingPool)
  const balancerPoolInteractorFactory = await ethers.getContractFactory('BalancerPoolInteractor')
  // @ts-ignore
  const balancerPoolInteractor = await balancerPoolInteractorFactory.deploy(addresses[network].balancerVault)
  return {names: ["Uniswap", "SushiSwap", "Aave", "Balancer"], addresses: [uniswapPoolInteractor.address, uniswapPoolInteractor.address, aaveV2PoolInteractor.address, balancerPoolInteractor.address]}
}

export const getUniversalSwap = async () => {
  const universalSwapContract = await ethers.getContractFactory('UniversalSwap')
  const universalSwap = await universalSwapContract.deploy()
  const liquidators = await getLiqudiators()
  const {names, addresses} = await getPoolInteractors('ethereum')
  await universalSwap.init(liquidators, names, addresses, weth)
  return universalSwap
}

const deployPositionsManager = async () => {
  const positionsManagerFactory = await ethers.getContractFactory("PositionsManager")
  const universalSwap = await getUniversalSwap()
  const positionsManager = positionsManagerFactory.deploy(universalSwap.address)
  return positionsManager
}

const deployERC20Bank = async (positionsManager: string) => {
  const [owner] = await ethers.getSigners()
  const bankFactory = await ethers.getContractFactory("ERC20Bank", owner)
  const erc20Bank = await bankFactory.deploy(positionsManager)
  return erc20Bank
}

const masterChefV1Wrapper = async (network: string) => {
  const wrapperV1Factory = await ethers.getContractFactory("MasterChefV1Wrapper")
  const wrapperV1 = await wrapperV1Factory.deploy()
  // @ts-ignore
  for (const masterChef of addresses[network].v1MasterChefs) {
    await wrapperV1.initializeMasterChef(masterChef.address, masterChef.rewardGetter)
  }
  return wrapperV1
}

const sushiMasterChefV2Wrapper = async (network: string) => {
  const wrapperV2Factory = await ethers.getContractFactory("SushiSwapMasterChefV2Wrapper")
  const wrapperV2 = await wrapperV2Factory.deploy()
  // @ts-ignore
  for (const masterChef of addresses[network].sushiV2MasterChefs) {
    await wrapperV2.initializeMasterChef(masterChef.address, masterChef.rewardGetter)
  }
  return wrapperV2
}

const deployMasterChefBank = async (positionsManager: string, network:string) => {
  const [owner] = await ethers.getSigners()
  const wrapperV1 = await masterChefV1Wrapper(network)
  const wrapperV2 = await sushiMasterChefV2Wrapper(network)
  const bankFactory = await ethers.getContractFactory("MasterChefBank", owner)
  const masterChefBank = await bankFactory.deploy(positionsManager)
  // @ts-ignore
  for (const masterChef of addresses[network].sushiV2MasterChefs) {
    await masterChefBank.setMasterChefWrapper(masterChef.address, wrapperV2.address)
  }
  // @ts-ignore
  for (const masterChef of addresses[network].v1MasterChefs) {
    await masterChefBank.setMasterChefWrapper(masterChef.address, wrapperV1.address)
  }
  return masterChefBank
}

const deployLiquidityGaugeBank = async (positionsManager: string) => {
  const [owner] = await ethers.getSigners()
  const bankFactory = await ethers.getContractFactory("BalancerLiquidityGaugeBank", owner)
  const balancerBank = await bankFactory.deploy(positionsManager, balancerLiquidityGaugeFactory, addresses.ethereum.bal)
  return balancerBank
}

export const deployAndInitializeManager = async (network: string) => {
  const positionsManager = await deployPositionsManager()
  const erc20Bank = await deployERC20Bank(positionsManager.address)
  const masterChefBank = await deployMasterChefBank(positionsManager.address, network)
  const balancerBank = await deployLiquidityGaugeBank(positionsManager.address)
  await positionsManager.addBank(erc20Bank.address)
  await positionsManager.addBank(masterChefBank.address)
  await positionsManager.addBank(balancerBank.address)
  return positionsManager
}

export const getLPToken = async (lpToken: string, network: string, universalSwap: UniversalSwap, etherAmount: string, owner:SignerWithAddress) => {
  const lpTokenContract = await ethers.getContractAt("ERC20", lpToken)
  // @ts-ignore
  await universalSwap.connect(owner).swap([addresses[network].networkToken], [ethers.utils.parseEther(etherAmount)], lpToken)
  const lpBalance = await lpTokenContract.balanceOf(owner.address)
  return {lpBalance, lpTokenContract}
}

export const depositNew = async (manager:PositionsManager, lpToken: string, amount:string, liquidateTo:string, watchedTokens: string[], liquidationPoints: number[], owner:SignerWithAddress) => {
  const lpTokenContract = await ethers.getContractAt("ERC20", lpToken)
  const [bankId, tokenId] = await manager.recommendBank(lpToken)
  await lpTokenContract.connect(owner).approve(manager.address, amount)
  const position = {
    user: owner.address,
    bankId,
    bankToken: tokenId,
    amount,
    liquidateTo,
    watchedTokens,
    liquidationPoints
  }
  await manager.connect(owner)["deposit((address,uint256,uint256,uint256,address,address[],uint256[]))"](position)
}

export const isRoughlyEqual = (a:BigNumber, b:BigNumber) => {
  expect(a).to.lessThan(b.mul("105").div("100"))
  expect(a).to.greaterThan(b.mul("95").div("100"))
}