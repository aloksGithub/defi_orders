// import { time, loadFixture } from "@nomicfoundation/hardhat-network-helpers";
// import { anyValue } from "@nomicfoundation/hardhat-chai-matchers/withArgs";
// import { assert, expect } from "chai";
// import { ethers } from "hardhat";
// import { UniversalSwap } from "../typechain-types";
// import { ERC20, IUniswapV2Pair } from "../typechain-types";
// import {getUnderlyingTokens, getLPTokens, getToken, getTimestamp, getUniversalSwap} from "../utils"

// const usdc = "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48"
// const usdt = "0xdAC17F958D2ee523a2206206994597C13D831ec7"
// const dai = "0x6B175474E89094C44Da98b954EedeAC495271d0F"
// const weth = "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2"

// const supportedProtocols = ['aave', 'uniswapv2', 'sushiswap']
// const supportedPools = {
//   aave: ['0xd4937682df3C8aEF4FE912A96A74121C0829E664', '0x272F97b7a56a387aE942350bBC7Df5700f8a4576', '0x8dAE6Cb04688C62d939ed9B68d32Bc62e49970b1', '0xBcca60bB61934080951369a648Fb03DF4F96263C'],
//   uniswapv2: ['0xAE461cA67B15dc8dc81CE7615e0320dA1A9aB8D5', '0x3041cbd36888becc7bbcbc0045e3b1f144466f5f', '0xB4e16d0168e52d35CaCD2c6185b44281Ec28C9Dc', '0x21b8065d10f73EE2e260e5B47D3344d3Ced7596E', '0x9928e4046d7c6513326cCeA028cD3e7a91c7590A', '0xE1573B9D29e2183B1AF0e743Dc2754979A40D237'],
//   sushiswap: ['0x6a091a3406E0073C3CD6340122143009aDac0EDa', '0x397FF1542f962076d0BFE58eA045FfA2d347ACa0', '0x055475920a8c93CfFb64d039A8205F7AcC7722d3', '0xCEfF51756c56CeFFCA006cD410B03FFC46dd3a58']
// }
// const supportedLiquidationTokens = [usdc, dai, weth]

// describe("Swap uniswap LP for weth", function () {
//   let universalSwap: UniversalSwap
//   let lpObtained: string
//     it("deploys Universal Swap", async function () {
//       universalSwap = await getUniversalSwap()
//     })
//     it("Gets uniswap LP token", async function () {
//       const [owner] = await ethers.getSigners()
//       const lpToken = supportedPools['uniswapv2'][1]
//       const underlying = await Promise.all(await getUnderlyingTokens['uniswapv2'](lpToken))
//       const balances = []
//       for (const token of underlying) {
//         const {tokenBalance} = await getToken(token, owner, "1.0")
//         balances.push(tokenBalance.toString())
//       }
//       lpObtained = await getLPTokens['uniswapv2'](underlying, balances, owner)
//       expect(ethers.BigNumber.from(lpObtained)).to.greaterThan("0")
//     })
//     it("Swaps LP token for WETH", async function () {
//       const wethContract = await ethers.getContractAt("ERC20", weth)
//       const wethBalance = await wethContract.balanceOf(universalSwap.address)
//       const [owner] = await ethers.getSigners()
//       const lpTokenContract = await ethers.getContractAt("IUniswapV2Pair", supportedPools['uniswapv2'][1])
//       await lpTokenContract.transfer(universalSwap.address, lpObtained)
//       await universalSwap.swap([supportedPools['uniswapv2'][1]], [lpObtained], weth)
//       const wethBalance2 = await wethContract.balanceOf(universalSwap.address)
//       console.log(wethBalance2.sub(wethBalance))
//       expect(wethBalance2.sub(wethBalance)).to.greaterThan(0)
//     })
// })

// describe("Swap AAVE LP for usdc", function () {
//   let universalSwap: UniversalSwap
//   let lpObtained: string
//     it("deploys Universal Swap", async function () {
//       universalSwap = await getUniversalSwap()
//     })
//     it("Gets AAVE LP token", async function () {
//       const [owner] = await ethers.getSigners()
//       const lpToken = supportedPools['aave'][0]
//       const underlying = await Promise.all(await getUnderlyingTokens['aave'](lpToken))
//       const balances = []
//       for (const token of underlying) {
//         const {tokenBalance} = await getToken(token, owner, "1.0")
//         balances.push(tokenBalance.toString())
//       }
//       lpObtained = await getLPTokens['aave'](underlying, balances, owner)
//       expect(ethers.BigNumber.from(lpObtained)).to.greaterThan("0")
//     })
//     it("Swaps LP token for USDC", async function () {
//       const usdcContract = await ethers.getContractAt("ERC20", usdc)
//       const usdcBalance = await usdcContract.balanceOf(universalSwap.address)
//       const [owner] = await ethers.getSigners()
//       const lpTokenContract = await ethers.getContractAt("IAToken", supportedPools['aave'][0])
//       await lpTokenContract.transfer(universalSwap.address, lpObtained)
//       await universalSwap.swap([supportedPools['aave'][0]], [lpObtained], usdc)
//       const usdcBalance2 = await usdcContract.balanceOf(universalSwap.address)
//       console.log(usdcBalance2.sub(usdcBalance))
//       expect(usdcBalance2.sub(usdcBalance)).to.greaterThan(0)
//     })
// })

// describe("Swap Sushi LP for dai", function () {
//   let universalSwap: UniversalSwap
//   let lpObtained: string
//     it("deploys Universal Swap", async function () {
//       universalSwap = await getUniversalSwap()
//     })
//     it("Gets Sushi LP token", async function () {
//       const [owner] = await ethers.getSigners()
//       const lpToken = supportedPools['sushiswap'][2]
//       const underlying = await Promise.all(await getUnderlyingTokens['sushiswap'](lpToken))
//       const balances = []
//       for (const token of underlying) {
//         const {tokenBalance} = await getToken(token, owner, "1.0")
//         balances.push(tokenBalance.toString())
//       }
//       lpObtained = await getLPTokens['sushiswap'](underlying, balances, owner)
//       expect(ethers.BigNumber.from(lpObtained)).to.greaterThan("0")
//     })
//     it("Swaps LP token for USDC", async function () {
//       const usdcContract = await ethers.getContractAt("ERC20", usdc)
//       const usdcBalance = await usdcContract.balanceOf(universalSwap.address)
//       const [owner] = await ethers.getSigners()
//       const lpTokenContract = await ethers.getContractAt("IUniswapV2Pair", supportedPools['sushiswap'][2])
//       await lpTokenContract.transfer(universalSwap.address, lpObtained)
//       await universalSwap.swap([supportedPools['sushiswap'][2]], [lpObtained], usdc)
//       const usdcBalance2 = await usdcContract.balanceOf(universalSwap.address)
//       console.log(usdcBalance2.sub(usdcBalance))
//       expect(usdcBalance2.sub(usdcBalance)).to.greaterThan(0)
//     })
// })

// describe("Swap Sushi and Uniswap LP for dai", function () {
//   let universalSwap: UniversalSwap
//   let lpObtained1: string
//   let lpObtained2: string
//     it("deploys Universal Swap", async function () {
//       universalSwap = await getUniversalSwap()
//     })
//     it("Gets LP tokens", async function () {
//       const [owner] = await ethers.getSigners()
//       const lpToken = supportedPools['sushiswap'][2]
//       const underlying = await Promise.all(await getUnderlyingTokens['sushiswap'](lpToken))
//       const balances = []
//       for (const token of underlying) {
//         const {tokenBalance} = await getToken(token, owner, "1.0")
//         balances.push(tokenBalance.toString())
//       }
//       lpObtained1 = await getLPTokens['sushiswap'](underlying, balances, owner)
//       expect(ethers.BigNumber.from(lpObtained1)).to.greaterThan("0")
//       const lpToken2 = supportedPools['uniswapv2'][0]
//       const underlying2 = await Promise.all(await getUnderlyingTokens['uniswapv2'](lpToken2))
//       const balances2 = []
//       for (const token of underlying2) {
//         const {tokenBalance} = await getToken(token, owner, "1.0")
//         balances2.push(tokenBalance.toString())
//       }
//       lpObtained2 = await getLPTokens['uniswapv2'](underlying2, balances2, owner)
//       expect(ethers.BigNumber.from(lpObtained2)).to.greaterThan("0")
//     })
//     it("Swaps LP token for USDC", async function () {
//       const lpTokenContract1 = await ethers.getContractAt("IUniswapV2Pair", supportedPools['sushiswap'][2])
//       const lpTokenContract2 = await ethers.getContractAt("IUniswapV2Pair", supportedPools['uniswapv2'][0])
//       const usdcContract = await ethers.getContractAt("ERC20", usdc)
//       const usdcBalance = await usdcContract.balanceOf(universalSwap.address)
//       await lpTokenContract1.transfer(universalSwap.address, lpObtained1)
//       await lpTokenContract2.transfer(universalSwap.address, lpObtained2)
//       await universalSwap.swap([supportedPools['sushiswap'][2], supportedPools['uniswapv2'][0]], [lpObtained1, lpObtained2], usdc)
//       const usdcBalance2 = await usdcContract.balanceOf(universalSwap.address)
//       console.log(usdcBalance2.sub(usdcBalance))
//       expect(usdcBalance2.sub(usdcBalance)).to.greaterThan(0)
//     })
// })

// describe("Swap Sushi and Uniswap LP for AAVE LP", function () {
//   let universalSwap: UniversalSwap
//   let lpObtained1: string
//   let lpObtained2: string
//     it("deploys Universal Swap", async function () {
//       universalSwap = await getUniversalSwap()
//     })
//     it("Gets LP tokens", async function () {
//       const [owner] = await ethers.getSigners()
//       const lpToken = supportedPools['sushiswap'][2]
//       const underlying = await Promise.all(await getUnderlyingTokens['sushiswap'](lpToken))
//       const balances = []
//       for (const token of underlying) {
//         const {tokenBalance} = await getToken(token, owner, "1.0")
//         balances.push(tokenBalance.toString())
//       }
//       lpObtained1 = await getLPTokens['sushiswap'](underlying, balances, owner)
//       expect(ethers.BigNumber.from(lpObtained1)).to.greaterThan("0")
//       const lpToken2 = supportedPools['uniswapv2'][0]
//       const underlying2 = await Promise.all(await getUnderlyingTokens['uniswapv2'](lpToken2))
//       const balances2 = []
//       for (const token of underlying2) {
//         const {tokenBalance} = await getToken(token, owner, "1.0")
//         balances2.push(tokenBalance.toString())
//       }
//       lpObtained2 = await getLPTokens['uniswapv2'](underlying2, balances2, owner)
//       expect(ethers.BigNumber.from(lpObtained2)).to.greaterThan("0")
//     })
//     it("Swaps LP token for LP tokens", async function () {
//       const lpTokenContract1 = await ethers.getContractAt("IUniswapV2Pair", supportedPools['sushiswap'][2])
//       const lpTokenContract2 = await ethers.getContractAt("IUniswapV2Pair", supportedPools['uniswapv2'][0])
//       const wantContract = await ethers.getContractAt("IAToken", supportedPools['sushiswap'][1])
//       const balance1 = await wantContract.balanceOf(universalSwap.address)
//       await lpTokenContract1.transfer(universalSwap.address, lpObtained1)
//       await lpTokenContract2.transfer(universalSwap.address, lpObtained2)
//       await universalSwap.swap([supportedPools['sushiswap'][2], supportedPools['uniswapv2'][0]], [lpObtained1, lpObtained2], supportedPools['sushiswap'][1])
//       const balance2 = await wantContract.balanceOf(universalSwap.address)
//       console.log(balance2.sub(balance1))
//       expect(balance2.sub(balance1)).to.greaterThan(0)
//     })
// })