// import { time, loadFixture } from "@nomicfoundation/hardhat-network-helpers";
// import { anyValue } from "@nomicfoundation/hardhat-chai-matchers/withArgs";
// import { assert, expect } from "chai";
// import { ethers } from "hardhat";
// import { TokenStoploss } from "../typechain-types";
// import { ERC20, IUniswapV2Pair } from "../typechain-types";
// import {getUnderlyingTokens, getLPTokens, getToken, getTimestamp} from "../utils"

// type LiquidationPoint = {
//   token: string
//   priceUSD: number
// }

// type Deposit = {
//   user: string
//   pool: string
//   liquidateTo: string
//   amount: string
//   timestamp: number
//   protocol: string
//   liquidationPoints: LiquidationPoint[]
// }

// const uniswapRouterV2 = "0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D"
// const sushiRouterV2 = "0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F"
// const uniswapFactoryV2 = "0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f"
// const sushiFactoryV2 = "0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac"
// const aaveV2LendingPool = "0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9"
// const usdc = "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48"
// const usdt = "0xdAC17F958D2ee523a2206206994597C13D831ec7"
// const dai = "0x6B175474E89094C44Da98b954EedeAC495271d0F"
// const weth = "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2"
// const spool = "0x40803cEA2b2A32BdA1bE61d3604af6a814E70976"

// const supportedProtocols = ['aave']
// const supportedPools = {
//   aave: ['0xd4937682df3C8aEF4FE912A96A74121C0829E664', '0x272F97b7a56a387aE942350bBC7Df5700f8a4576', '0x8dAE6Cb04688C62d939ed9B68d32Bc62e49970b1', '0xBcca60bB61934080951369a648Fb03DF4F96263C'],
//   uniswapv2: ['0xAE461cA67B15dc8dc81CE7615e0320dA1A9aB8D5', '0xB4e16d0168e52d35CaCD2c6185b44281Ec28C9Dc', '0x21b8065d10f73EE2e260e5B47D3344d3Ced7596E', '0x9928e4046d7c6513326cCeA028cD3e7a91c7590A', '0xE1573B9D29e2183B1AF0e743Dc2754979A40D237'],
//   sushiswap: ['0x6a091a3406E0073C3CD6340122143009aDac0EDa', '0x397FF1542f962076d0BFE58eA045FfA2d347ACa0', '0x055475920a8c93CfFb64d039A8205F7AcC7722d3', '0xCEfF51756c56CeFFCA006cD410B03FFC46dd3a58']
// }
// const supportedLiquidationTokens = [usdc, dai, weth]

// async function deployTokenStopLoss () {
//   const StopLossContract = await ethers.getContractFactory('TokenStoploss')
//   const uniswapBurnerContract = await ethers.getContractFactory('UniswapV2Burner')
//   const uniswapBurner = await uniswapBurnerContract.deploy()
//   const aaveV2BurnerFactory = await ethers.getContractFactory('AaveV2Burner')
//   const aaveV2Burner = await aaveV2BurnerFactory.deploy(aaveV2LendingPool)
//   const uniswapLiquidatorContract = await ethers.getContractFactory('UniswapV2Liquidator')
//   const sushiswapLiquidatorFactory = await ethers.getContractFactory('SushiswapLiquidator')
//   const uniswapLiquidator = await uniswapLiquidatorContract.deploy(uniswapRouterV2, uniswapFactoryV2)
//   const sushiswapLiquidator = await sushiswapLiquidatorFactory.deploy(sushiRouterV2, sushiFactoryV2)
//   const stoploss = await StopLossContract.deploy(usdc, 1, [uniswapLiquidator.address, sushiswapLiquidator.address])
//   await stoploss.setBurner('uniswapv2', uniswapBurner.address)
//   await stoploss.setBurner('sushiswap', uniswapBurner.address)
//   await stoploss.setBurner('aave', aaveV2Burner.address)
//   return stoploss
// }

// async function deposit(stoploss:TokenStoploss, lpToken:string, amount:string, liquidateTo:string, protocol:string, liquidationParams:any, owner:any) {
//   stoploss = stoploss.connect(owner)
//   const balanceBefore1 = await stoploss.balanceOf(lpToken, owner.address, liquidateTo)
//   const pairContract = await ethers.getContractAt("ERC20", lpToken, owner)
//   const balanceBefore2 = await pairContract.balanceOf(owner.address)
//   await pairContract.approve(stoploss.address, amount)
//   // @ts-ignore
//   await stoploss.deposit(lpToken, amount, liquidateTo, protocol, liquidationParams, {from: owner.address})
//   const balanceAfter1 = await stoploss.balanceOf(lpToken, owner.address, liquidateTo)
//   const balanceAfter2 = await pairContract.balanceOf(owner.address)
//   return {deposited: balanceAfter1.sub(balanceBefore1), newBalance: balanceAfter1, tokenTaken: balanceBefore2.sub(balanceAfter2), tokenBalance: balanceAfter2}
// }

// function rand(a:number) {
//   return Math.floor(Math.random()*a)
// }

// async function generateRandomDeposit(user:any) {
//   const protocol = supportedProtocols[rand(supportedProtocols.length)]
//   // @ts-ignore
//   const pool = supportedPools[protocol][rand(supportedPools[protocol].length)]
//   const liquidateTo = supportedLiquidationTokens[rand(supportedLiquidationTokens.length)]
//   // @ts-ignore
//   const underlying = await getUnderlyingTokens[protocol](pool)
//   const liquidationPoints: LiquidationPoint[] = []
//   const tokenBalances:any[] = []
//   for (let i = 0; i<underlying.length; i+=1) {
//     liquidationPoints.push({token: underlying[i], priceUSD: rand(1000)})
//     const ether = 0.5+rand(1)
//     const {tokenBalance} = await getToken(underlying[i], user, ether.toString())
//     tokenBalances.push(tokenBalance)
//   }
//   // @ts-ignore
//   const lpTokenBalance = await getLPTokens[protocol](underlying, tokenBalances, user)
//   const deposit: Deposit = {
//     user: user.address,
//     pool,
//     liquidateTo,
//     amount: lpTokenBalance,
//     timestamp: await getTimestamp(),
//     protocol,
//     liquidationPoints
//   }
//   return deposit
// }

// async function withdraw(stoploss:TokenStoploss, lpToken:string, amount:string, liquidateTo:string, withdrawAll:boolean, liqudiate:boolean, owner:any) {
//   stoploss = stoploss.connect(owner)
//   let balanceBefore2, balanceAfter2, withdrawnToContract
//   const balanceBefore1 = await stoploss.balanceOf(lpToken, owner.address, liquidateTo)
//   if (liqudiate) {
//     withdrawnToContract = await ethers.getContractAt("ERC20", liquidateTo)
//   } else {
//     withdrawnToContract = await ethers.getContractAt("ERC20", lpToken)
//   }
//   balanceBefore2 = await withdrawnToContract.balanceOf(owner.address)
//   // @ts-ignore
//   await stoploss.withdraw(lpToken, amount, liquidateTo, withdrawAll, liquidateTo, {from:owner.address})
//   balanceAfter2 = await withdrawnToContract.balanceOf(owner.address)
//   const balanceAfter1 = await stoploss.balanceOf(lpToken, owner.address, liquidateTo)
//   return {withdrawn: balanceBefore1.sub(balanceAfter1), newBalance: balanceAfter1, tokenGiven: balanceAfter2.sub(balanceBefore2), tokenBalance: balanceAfter2}
// }

// async function liquidate(stoploss:TokenStoploss, token:string, price:number) {
//   await stoploss.botLiquidate(token, price)
// }

// // describe("Protocol LP tests", function () {
// //   it("Should get UniswapV2 LP tokens", async function () {
// //     const [owner] = await ethers.getSigners();
// //     const {lpBalance} = await getLPTokensForPair(dai, usdt, owner)
// //     expect((await lpBalance).toNumber()).greaterThan(0)
// //   })
// // })

// // describe("Stop Loss", function () {
// //   describe("Deployment", function () {
// //     it("Should deploy contract", async function () {
// //       const StopLossContract = await ethers.getContractFactory('TokenStoploss')
// //       const stoploss = await StopLossContract.deploy(usdc)
// //     });
// //   });

// //   describe("Basic Deposit and Withdraw", async function () {
// //     let stoploss: any
// //     let pairContract: IUniswapV2Pair
// //     let usdtContract: ERC20
// //     let daiContract: ERC20
// //     let usdcContract: ERC20
// //     let pairAddress: string

// //     before(async function () {
// //       const [owner] = await ethers.getSigners();
// //       stoploss = await deployTokenStopLoss();
// //       ({pairAddress} = await getLPTokensForPair(dai, usdc, owner));
// //       pairContract = await ethers.getContractAt("IUniswapV2Pair", pairAddress, owner)
// //       usdtContract = await ethers.getContractAt("ERC20", usdt)
// //       daiContract = await ethers.getContractAt("ERC20", dai)
// //       usdcContract = await ethers.getContractAt("ERC20", usdc)
// //     })

// //     it("Should deposit LP tokens", async function () {
// //       const [owner] = await ethers.getSigners();
// //       const lpBalance = await pairContract.balanceOf(owner.address)
// //       await deposit(stoploss, pairAddress, (lpBalance).div("2").toString(), weth, 'uniswapv2', [{token: usdt, priceUSD: 1}], owner)
// //       const userBalance1 = await stoploss.balanceOf(pairAddress, owner.address, weth)
// //       expect(userBalance1).to.equal((lpBalance).div("2"))
// //       await deposit(stoploss, pairAddress, (lpBalance).div("2").toString(), weth, 'uniswapv2', [{token: usdt, priceUSD: 1}], owner)
// //       const userBalance2 = await stoploss.balanceOf(pairAddress, owner.address, weth)
// //       expect(userBalance2).to.greaterThan((lpBalance).div("2"))
// //     })
// //     it("Should withdraw LP tokens completely", async function () {
// //       const [owner] = await ethers.getSigners();
// //       const liquidateTo = await ethers.getContractAt("ERC20", weth)
// //       const balanceBefore = await liquidateTo.balanceOf(owner.address)
// //       await stoploss.withdraw(pairContract.address, "0", weth, true, true, {from: owner.address});
// //       const balanceAfter = await liquidateTo.balanceOf(owner.address)
// //       const balanceInStopLoss = await stoploss.balanceOf(pairContract.address, owner.address, weth)
// //       const tokenGained = balanceAfter.sub(balanceBefore)
// //       expect(balanceInStopLoss).to.equal(0)
// //       expect(tokenGained).to.greaterThan(0)
// //     })
// //     it("Should liquidate a position", async function () {
// //       const [owner] = await ethers.getSigners();
// //       const {lpBalance, pairAddress} = await getLPTokensForPair(dai, usdc, owner)
// //       await deposit(stoploss, pairAddress, (await lpBalance).div("2").toString(), weth, 'uniswapv2', [{token: usdt, priceUSD: 20}], owner)
// //       const userBalance1 = await stoploss.balanceOf(pairAddress, owner.address, weth)
// //       expect(userBalance1).to.equal((await lpBalance).div("2"))
// //       await deposit(stoploss, pairAddress, (await lpBalance).div("2").toString(), weth, 'uniswapv2', [{token: usdt, priceUSD: 10}], owner)
// //       const userBalance2 = await stoploss.balanceOf(pairAddress, owner.address, weth)
// //       expect(userBalance2).to.greaterThan((await lpBalance).div("2"))
// //       await stoploss.botLiquidate(usdt, 15)

// //     })
// //   })
// // });

// async function matchModelToSmartContracts (deposits:Deposit[], stoploss: TokenStoploss, owners:any) {
//   for (const owner of owners) {
//     const ownerDepositsInModel = deposits.filter(deposit => deposit.user===owner.address)
//     const ownerDepositsInContract = await stoploss.getUserDeposits(owner.address)
//     if (ownerDepositsInContract.length===0 && ownerDepositsInModel.length===0) {continue}
//     expect(ownerDepositsInContract.length).to.equal(ownerDepositsInModel.length)
//     for (const deposit of ownerDepositsInModel) {
//       const matchingDeposit = ownerDepositsInContract.find(deposit2=>
//         deposit2.liquidateTo===deposit.liquidateTo &&
//         deposit2.token===deposit.pool
//       )
//       expect(matchingDeposit).not.to.be.undefined
//       expect(matchingDeposit?.amount).to.greaterThan(ethers.BigNumber.from(deposit.amount).mul("9").div("10"))
//       expect(matchingDeposit?.amount).to.lessThan(ethers.BigNumber.from(deposit.amount).mul("11").div("10"))
//       expect(deposit.liquidationPoints.length).to.equal(matchingDeposit?.liquidationPoints.length)
//       for (const point of deposit.liquidationPoints) {
//         const matchingPoint = matchingDeposit?.liquidationPoints.find(point2 =>
//           point2.token===point.token &&
//           point2.priceUSD.toNumber()===point.priceUSD
//         )
//         expect(matchingPoint).not.to.be.undefined
//       }
//     }
//   }
// }

// describe("Large scale test", function () {
//   let stoploss:any
//   let owners:any
//   before(async function () {
//     owners = await ethers.getSigners();
//     stoploss = await deployTokenStopLoss();
//   })
//   it("Successfully deposits, withdraws and liquidates multiple users across multiple protocols", async function () {
//     let deposits: Deposit[] = []
//     const actions = ['deposit existing', 'deposit new', 'withdraw_partial', 'withdraw_partial_liquidate', 'withdraw_all', 'withdraw_all_liquidate', 'liquidate']
//     let i = 0
//     while(i<100) {
//       i+=1
//       console.log(`Running test ${i}`)
//       // const action = actions[rand(actions.length)]
//       const action = 'withdraw_partial'
//       const user = owners[rand(owners.length)]
//       // @ts-ignore
//       if (deposits.length==0 || action=='deposit new') {
//         console.log("Creating new deposit")
//         const newDeposit:Deposit = await generateRandomDeposit(user)
//         await deposit(
//           stoploss,
//           newDeposit.pool,
//           newDeposit.amount.toString(),
//           newDeposit.liquidateTo,
//           newDeposit.protocol,
//           newDeposit.liquidationPoints,
//           user
//         )
//         const existingDeposit = deposits.findIndex(eachDeposit=>eachDeposit.user===newDeposit.user && eachDeposit.pool===newDeposit.pool && eachDeposit.liquidateTo===newDeposit.liquidateTo)
//         if (existingDeposit==-1) {
//           deposits.push(newDeposit)
//         }
//         else {
//           deposits[existingDeposit].amount+=newDeposit.amount
//           deposits[existingDeposit].timestamp = await getTimestamp()
//           deposits[existingDeposit].liquidationPoints = newDeposit.liquidationPoints
//         }
//         await matchModelToSmartContracts(deposits, stoploss, owners)
//       }
//       // @ts-ignore
//       else if (action==='deposit existing') {
//         console.log("Depositing into existing")
//         const depositIndex = rand(deposits.length)
//         const depositToChange = deposits[depositIndex]
//         const owner = owners.find((o:any)=>o.address===depositToChange.user)
//         // @ts-ignore
//         const underlying = await getUnderlyingTokens[depositToChange.protocol](depositToChange.pool)
//         const liquidationPoints: LiquidationPoint[] = []
//         const tokenBalances:any[] = []
//         for (let i = 0; i<underlying.length; i+=1) {
//           liquidationPoints.push({token: underlying[i], priceUSD: rand(1000)})
//           const ether = 1+rand(1)
//           const {tokenBalance} = await getToken(underlying[i], owner, ether.toString())
//           tokenBalances.push(tokenBalance)
//         }
//         // @ts-ignore
//         const lpTokenBalance = await getLPTokens[depositToChange.protocol](underlying, tokenBalances, owner)
//         console.log(lpTokenBalance)
//         deposits[depositIndex].amount = ethers.BigNumber.from(lpTokenBalance).add(ethers.BigNumber.from(deposits[depositIndex].amount)).toString()
//         deposits[depositIndex].timestamp = await getTimestamp()
//         deposits[depositIndex].liquidationPoints = liquidationPoints
//         await deposit(stoploss, depositToChange.pool, lpTokenBalance, depositToChange.liquidateTo, depositToChange.protocol, liquidationPoints, owner)
//         await matchModelToSmartContracts(deposits, stoploss, owners)
//       }
//       else if (action==='withdraw_partial') {
//         console.log("Withdrawing partially")
//         const depositIndex = rand(deposits.length)
//         const randomNumber = Math.floor(Math.random()*100)
//         const toWithdraw = ethers.BigNumber.from(deposits[depositIndex].amount).mul(ethers.BigNumber.from(randomNumber)).div("100")
//         deposits[depositIndex].amount=ethers.BigNumber.from(deposits[depositIndex].amount).sub(toWithdraw).toString()
//         deposits[depositIndex].timestamp = await getTimestamp()
//         const deposit = deposits[depositIndex]
//         const owner = owners.find((o:any)=>o.address===deposit.user)
//         await withdraw(stoploss, deposit.pool, toWithdraw.toString(), deposit.liquidateTo, false, false, owner)
//         await matchModelToSmartContracts(deposits, stoploss, owners)
//       }
//       else if (action==='withdraw_partial_liquidate') {
//         console.log("Withdrwaing partially and liquidating")
//         const depositIndex = rand(deposits.length)
//         const randomNumber = Math.floor(Math.random()*100)
//         const toWithdraw = ethers.BigNumber.from(deposits[depositIndex].amount).mul(ethers.BigNumber.from(randomNumber)).div("100")
//         deposits[depositIndex].amount=ethers.BigNumber.from(deposits[depositIndex].amount).sub(toWithdraw).toString()
//         deposits[depositIndex].timestamp = await getTimestamp()
//         const deposit = deposits[depositIndex]
//         const owner = owners.find((o:any)=>o.address===deposit.user)
//         await withdraw(stoploss, deposit.pool, toWithdraw.toString(), deposit.liquidateTo, false, true, owner)
//         await matchModelToSmartContracts(deposits, stoploss, owners)
//       }
//       else if (action==='withdraw_all') {
//         console.log("Withdrawing all")
//         const depositIndex = rand(deposits.length)
//         const deposit = deposits[depositIndex]
//         const owner = owners.find((o:any)=>o.address===deposit.user)
//         await withdraw(stoploss, deposit.pool, "0", deposit.liquidateTo, true, false, owner)
//         deposits.splice(depositIndex, 1)
//         await matchModelToSmartContracts(deposits, stoploss, owners)
//       }
//       else if (action==='withdraw_all_liquidate') {
//         console.log("Withdrawing all and liquidating")
//         const depositIndex = rand(deposits.length)
//         const deposit = deposits[depositIndex]
//         const owner = owners.find((o:any)=>o.address===deposit.user)
//         await withdraw(stoploss, deposit.pool, "0", deposit.liquidateTo, true, true, owner)
//         deposits.splice(depositIndex, 1)
//         await matchModelToSmartContracts(deposits, stoploss, owners)
//       }
//       else if (action==="liquidate") {
//         console.log("Simulating bot liquiation")
//         const depositIndex = rand(deposits.length)
//         const deposit = deposits[depositIndex]
//         const token = deposit.liquidationPoints[0].token
//         const price = deposit.liquidationPoints[0].priceUSD-1
//         await liquidate(stoploss, token, price)
//         await matchModelToSmartContracts(deposits, stoploss, owners)
//       }
//     }
//   })
// })