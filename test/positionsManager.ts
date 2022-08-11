import { assert, expect } from "chai";
import { ethers, network } from "hardhat";
import { IWETH, PositionsManager, UniversalSwap } from "../typechain-types";
import { ERC20 } from "../typechain-types";
import {deployAndInitializeManager, addresses, getNetworkToken, getLPToken, depositNew, isRoughlyEqual} from "../utils"
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { BigNumber } from "ethers";

const NETWORK = 'ethereum'
const networkAddresses = addresses[NETWORK]
let owners: SignerWithAddress[]
let networkTokenContract: IWETH
let universalSwap: UniversalSwap
let sushiContract: ERC20
let positionsCreated = 0

// describe ("Deployment", function () {
//     it("Deploys successfully", async function () {
//         await deployAndInitializeManager()
//     })
// })

describe ("Position opening", function () {
    let manager: PositionsManager
    before(async function () {
        manager = await deployAndInitializeManager(NETWORK)
        owners = await ethers.getSigners()
        const universalSwapAddress = await manager.universalSwap()
        for (const owner of owners) {
            const {wethContract} = await getNetworkToken(NETWORK, owner, '1000.0')
            await wethContract.connect(owner).approve(universalSwapAddress, ethers.utils.parseEther("1000"))
        }
        networkTokenContract = await ethers.getContractAt("IWETH", networkAddresses.networkToken)
        universalSwap = await ethers.getContractAt("UniversalSwap", universalSwapAddress)
        sushiContract = await ethers.getContractAt("ERC20", networkAddresses.sushi)
    })
    // it("Deposits and withdraws simple USDC position", async function () {
    //     const [owners[0]] = await ethers.getSigners()
    //     const {tokenBalance, tokenContract} = await getToken(networkAddresses.usdc, owners[0], "1.0")
    //     await tokenContract.approve(manager.address, tokenBalance.toString())
    //     const bankAddress = await manager.banks(0)
    //     const erc20Bank = await ethers.getContractAt("ERC20Bank", bankAddress)
    //     const tokenId = await erc20Bank.encodeId(tokenContract.address)
    //     const position = {
    //         user: owners[0].address,
    //         bankId: 0,
    //         bankToken: tokenId,
    //         amount: tokenBalance.toString(),
    //         liquidateTo: networkAddresses.networkToken,
    //         watchedTokens: [networkAddresses.usdc],
    //         liquidationPoints: ["1"]
    //     }
    //     const positionId = await manager["deposit((address,uint256,uint256,uint256,address,address[],uint256[]))"](position)
    //     // console.log(positionId)
    //     const networkTokenContract = await ethers.getContractAt("ERC20", networkAddresses.networkToken)
    //     const b1 = await networkTokenContract.balanceOf(owners[0].address)
    //     await manager.withdraw(0, tokenBalance.toString(), true);
    //     const b2 = await networkTokenContract.balanceOf(owners[0].address)
    //     expect(b2.sub(b1)).to.greaterThan(0)
    //     const positionData = await manager.getPosition(0)
    //     expect(positionData.amount).to.equal(0)
    //     expect(manager.withdraw(0, "1", false)).to.be.revertedWith("Withdrawing more funds than available")
    // })
    // it("Opens simle BALANCER position", async function () {
    //     const [owners[0]] = await ethers.getSigners()
    //     // await getToken("0x2260fac5e5542a773aa44fbcfedf7c193bc2c599", owners[0], "1.0")
    //     const {balance, wethContract} = await getNetworkToken(NETWORK, owners[0], '100.0')
    //     const universalSwapAddress = await manager.universalSwap()
    //     const universalSwap = await ethers.getContractAt("UniversalSwap", universalSwapAddress)
    //     await wethContract.approve(universalSwapAddress, balance)
    //     await universalSwap.swap([wethContract.address], [balance], "0xa6f548df93de924d73be7d25dc02554c6bd66db5")
    //     const lpTokenContract = await ethers.getContractAt("ERC20", "0xa6f548df93de924d73be7d25dc02554c6bd66db5")
    //     const lpBalance1 = await lpTokenContract.balanceOf(owners[0].address)
    //     expect(lpBalance1).to.greaterThan(0)

    //     await lpTokenContract.approve(manager.address, lpBalance1)
    //     const bankAddress = await manager.banks(2)
    //     const erc20Bank = await ethers.getContractAt("BalancerLiquidityGaugeBank", bankAddress)
    //     const tokenId = await erc20Bank.encodeId(lpTokenContract.address)
    //     const position = {
    //         user: owners[0].address,
    //         bankId: 2,
    //         bankToken: tokenId,
    //         amount: lpBalance1.toString(),
    //         liquidateTo: networkAddresses.networkToken,
    //         watchedTokens: [networkAddresses.usdc],
    //         liquidationPoints: ["1"]
    //     }
    //     await manager["deposit((address,uint256,uint256,uint256,address,address[],uint256[]))"](position)
    //     await ethers.provider.send("hardhat_mine", ["0x10000"]);
    //     await manager.harvestRewards(0)
    //     const balancerContract = await ethers.getContractAt("ERC20", addresses[NETWORK].bal)
    //     const balBalance = await balancerContract.balanceOf(owners[0].address)
    //     console.log(balBalance)
    // })
    it("Opens and closes Sushiswap V1 position", async function () {
        const lpToken = "0x31503dcb60119A812feE820bb7042752019F2355"
        const {lpBalance: lpBalance1, lpTokenContract} = await getLPToken(lpToken, NETWORK, universalSwap, "1", owners[0])
        const {lpBalance: lpBalance2} = await getLPToken(lpToken, NETWORK, universalSwap, "1", owners[1])
        expect(lpBalance1).to.greaterThan(0)
        expect(lpBalance2).to.greaterThan(0)

        await lpTokenContract.connect(owners[0]).approve(manager.address, lpBalance1)
        await lpTokenContract.connect(owners[1]).approve(manager.address, lpBalance2)
        const [bankId, tokenId] = await manager.recommendBank(lpToken)
        const position1 = {
            user: owners[0].address,
            bankId,
            bankToken: tokenId,
            amount: lpBalance1.toString(),
            liquidateTo: networkAddresses.networkToken,
            watchedTokens: [networkAddresses.usdc],
            liquidationPoints: ["1"]
        }
        const position2 = {
            user: owners[1].address,
            bankId,
            bankToken: tokenId,
            amount: lpBalance2.toString(),
            liquidateTo: networkAddresses.networkToken,
            watchedTokens: [networkAddresses.usdc],
            liquidationPoints: ["1"]
        }
        await manager.connect(owners[0])["deposit((address,uint256,uint256,uint256,address,address[],uint256[]))"](position1)
        await ethers.provider.send("hardhat_mine", ["0x100"]);
        await manager.connect(owners[1])["deposit((address,uint256,uint256,uint256,address,address[],uint256[]))"](position2)
        await ethers.provider.send("hardhat_mine", ["0x100"]);
        await manager.harvestRewards(0)
        await manager.harvestRewards(1)
        // await manager.close(positionId1, false)
        const sushiContract = await ethers.getContractAt("ERC20", networkAddresses.sushi)
        const sushiBalance1 = await sushiContract.balanceOf(owners[0].address)
        const sushiBalance2 = await sushiContract.balanceOf(owners[1].address)
        isRoughlyEqual(sushiBalance1.div("2").mul("1000").div(sushiBalance2), lpBalance1.mul("1000").div(lpBalance2))
        const b1 = await networkTokenContract.balanceOf(owners[0].address)
        const b2 = await networkTokenContract.balanceOf(owners[1].address)
        await manager.connect(owners[0]).close(0, true)
        await manager.connect(owners[1]).close(1, true)
        const b3 = await networkTokenContract.balanceOf(owners[0].address)
        const b4 = await networkTokenContract.balanceOf(owners[1].address)
        // console.log(b3.sub(b1), b4.sub(b2))
    })
    it("Opens and recompounds position rewards", async function () {
        const lpToken = "0x31503dcb60119A812feE820bb7042752019F2355"
        const {lpBalance: lpBalance1, lpTokenContract} = await getLPToken(lpToken, NETWORK, universalSwap, "1", owners[0])
        const {lpBalance: lpBalance2} = await getLPToken(lpToken, NETWORK, universalSwap, "1", owners[1])
        expect(lpBalance1).to.greaterThan(0)
        expect(lpBalance2).to.greaterThan(0)

        await lpTokenContract.connect(owners[0]).approve(manager.address, lpBalance1)
        await lpTokenContract.connect(owners[1]).approve(manager.address, lpBalance2)
        const [bankId, tokenId] = await manager.recommendBank(lpToken)
        const position = {
            user: owners[0].address,
            bankId,
            bankToken: tokenId,
            amount: lpBalance1.toString(),
            liquidateTo: networkAddresses.networkToken,
            watchedTokens: [networkAddresses.usdc],
            liquidationPoints: ["1"]
        }
        const positionId = 2;
        await manager.connect(owners[0])["deposit((address,uint256,uint256,uint256,address,address[],uint256[]))"](position)
        const positionInfo1 = await manager.getPosition(positionId)
        await ethers.provider.send("hardhat_mine", ["0x100"]);
        await manager.connect(owners[0]).harvestAndRecompound(positionId)
        const positionInfo2 = await manager.getPosition(positionId)
        expect(positionInfo2.amount).to.greaterThan(positionInfo1.amount)
    })
    it("Handles Masterchef v2 positions", async function () {
        const lpToken = "0x05767d9EF41dC40689678fFca0608878fb3dE906"
        const {lpBalance: lpBalance1, lpTokenContract} = await getLPToken(lpToken, NETWORK, universalSwap, "1", owners[0])
        expect(lpBalance1).to.greaterThan(0)

        await lpTokenContract.connect(owners[0]).approve(manager.address, lpBalance1)
        const [bankId, tokenId] = await manager.recommendBank(lpToken)
        const position1 = {
            user: owners[0].address,
            bankId,
            bankToken: tokenId,
            amount: lpBalance1.toString(),
            liquidateTo: networkAddresses.networkToken,
            watchedTokens: [networkAddresses.usdc],
            liquidationPoints: ["1"]
        }
        await manager.connect(owners[0])["deposit((address,uint256,uint256,uint256,address,address[],uint256[]))"](position1)
        await ethers.provider.send("hardhat_mine", ["0x100"]);
        const sushiContract = await ethers.getContractAt("ERC20", networkAddresses.sushi)
        const sushiBalance1 = await sushiContract.balanceOf(owners[0].address)
        await manager.harvestRewards(3)
        const sushiBalance2 = await sushiContract.balanceOf(owners[0].address)
        expect(sushiBalance2.sub(sushiBalance1)).to.greaterThan(0)
        const b1 = await networkTokenContract.balanceOf(owners[0].address)
        await manager.connect(owners[0]).close(3, true)
        const b3 = await networkTokenContract.balanceOf(owners[0].address)
        expect(b3.sub(b1)).to.greaterThan(0)
    })
    it("Handles multiple positions", async function () {
        const lpToken = "0x99B42F2B49C395D2a77D973f6009aBb5d67dA343"
        const extraRewardContract = await ethers.getContractAt("ERC20", "0x25f8087ead173b73d6e8b84329989a8eea16cf73")

        const {lpBalance: lpBalance1, lpTokenContract} = await getLPToken(lpToken, NETWORK, universalSwap, "1", owners[3])
        const {lpBalance: lpBalance2} = await getLPToken(lpToken, NETWORK, universalSwap, "1", owners[4])
        const {lpBalance: lpBalance3} = await getLPToken(lpToken, NETWORK, universalSwap, "1", owners[5])
        const {lpBalance: lpBalance4} = await getLPToken(lpToken, NETWORK, universalSwap, "1", owners[6])
        console.log(lpBalance1, lpBalance2, lpBalance3, lpBalance4)
        await depositNew(manager, lpToken, lpBalance1.toString(), networkAddresses.networkToken, [networkAddresses.networkToken], [100], owners[3])
        await depositNew(manager, lpToken, lpBalance2.div("3").toString(), networkAddresses.networkToken, [networkAddresses.networkToken], [100], owners[4])
        await ethers.provider.send("hardhat_mine", ["0x100"]);
        await manager.harvestRewards(4)
        await manager.harvestRewards(5)

        let owner1Sushi = ethers.BigNumber.from("0")
        let owner2Sushi = ethers.BigNumber.from("0")
        let owner3Sushi = ethers.BigNumber.from("0")
        let owner4Sushi = ethers.BigNumber.from("0")
        let owner1Convex = ethers.BigNumber.from("0")
        let owner2Convex = ethers.BigNumber.from("0")
        let owner3Convex = ethers.BigNumber.from("0")
        let owner4Convex = ethers.BigNumber.from("0")

        
        const getBalances = async () => {
            owner1Sushi = await sushiContract.balanceOf(owners[3].address)
            owner2Sushi = await sushiContract.balanceOf(owners[4].address)
            owner1Convex = await extraRewardContract.balanceOf(owners[3].address)
            owner2Convex = await extraRewardContract.balanceOf(owners[4].address)
            owner3Sushi = await sushiContract.balanceOf(owners[5].address)
            owner4Sushi = await sushiContract.balanceOf(owners[6].address)
            owner3Convex = await extraRewardContract.balanceOf(owners[5].address)
            owner4Convex = await extraRewardContract.balanceOf(owners[6].address)
        }

        const clearRewards = async () => {
            await getBalances()
            await sushiContract.connect(owners[3]).transfer(owners[0].address, owner1Sushi)
            await sushiContract.connect(owners[4]).transfer(owners[0].address, owner2Sushi)
            await extraRewardContract.connect(owners[3]).transfer(owners[0].address, owner1Convex)
            await extraRewardContract.connect(owners[4]).transfer(owners[0].address, owner2Convex)
            await sushiContract.connect(owners[5]).transfer(owners[0].address, owner3Sushi)
            await sushiContract.connect(owners[6]).transfer(owners[0].address, owner4Sushi)
            await extraRewardContract.connect(owners[5]).transfer(owners[0].address, owner3Convex)
            await extraRewardContract.connect(owners[6]).transfer(owners[0].address, owner4Convex)
            await getBalances()
        }

        await getBalances()
        isRoughlyEqual(owner1Sushi.mul('1000').div(owner2Sushi), lpBalance1.mul('1000').div(lpBalance2.div("3")))
        isRoughlyEqual(owner1Convex.mul('1000').div(owner2Convex), lpBalance1.mul('1000').div(lpBalance2.div("3")))

        await clearRewards()

        await depositNew(manager, lpToken, lpBalance3.toString(), networkAddresses.networkToken, [networkAddresses.networkToken], [100], owners[5])
        await depositNew(manager, lpToken, lpBalance4.div("2").toString(), networkAddresses.networkToken, [networkAddresses.networkToken], [100], owners[6])
        await ethers.provider.send("hardhat_mine", ["0x100"]);
        await manager.connect(owners[5]).harvestRewards(6)
        await manager.connect(owners[6]).harvestRewards(7)
        
        await getBalances()
        isRoughlyEqual(owner3Sushi.mul("1000").div(owner4Sushi), lpBalance3.mul("1000").div(lpBalance4.div("2")))
        isRoughlyEqual(owner3Convex.mul("1000").div(owner4Convex), lpBalance3.mul("1000").div(lpBalance4.div("2")))
        await clearRewards()
        await sushiContract.connect(owners[5]).transfer(owners[0].address, owner3Sushi)
        await sushiContract.connect(owners[6]).transfer(owners[0].address, owner4Sushi)
        await extraRewardContract.connect(owners[5]).transfer(owners[0].address, owner3Convex)
        await extraRewardContract.connect(owners[6]).transfer(owners[0].address, owner4Convex)
        await getBalances()

        await ethers.provider.send("hardhat_mine", ["0x100"]);
        await manager.connect(owners[3]).harvestRewards(4)
        await manager.connect(owners[4]).harvestRewards(5)
        await manager.connect(owners[5]).harvestRewards(6)
        await manager.connect(owners[6]).harvestRewards(7)
        
        await getBalances()

        isRoughlyEqual(owner1Sushi.mul("1000").div(owner2Sushi), lpBalance1.mul("1000").div(lpBalance2.div("3")))
        isRoughlyEqual(owner1Convex.mul("1000").div(owner2Convex), lpBalance1.mul("1000").div(lpBalance2.div("3")))
        isRoughlyEqual(owner3Sushi.mul("1000").div(owner4Sushi), lpBalance3.mul("1000").div(lpBalance4.div("2")))
        isRoughlyEqual(owner3Convex.mul("1000").div(owner4Convex), lpBalance3.mul("1000").div(lpBalance4.div("2")))
        isRoughlyEqual(owner1Sushi.mul("1000").div(owner3Sushi.mul("2")), lpBalance1.mul("1000").div(lpBalance3))
        isRoughlyEqual(owner1Convex.mul("1000").div(owner3Convex.mul("2")), lpBalance1.mul("1000").div(lpBalance3))

        await manager.connect(owners[3]).withdraw(4, lpBalance1.mul("2").div("3"), true)
        await lpTokenContract.connect(owners[6]).approve(manager.address, lpBalance4.div("2"))
        await manager.connect(owners[6])["deposit(uint256,uint256)"](7, lpBalance4.div("2"))
        await clearRewards()
        
        await ethers.provider.send("hardhat_mine", ["0x100"]);
        await manager.connect(owners[3]).harvestRewards(4)
        await manager.connect(owners[4]).harvestRewards(5)
        await manager.connect(owners[5]).harvestRewards(6)
        await manager.connect(owners[6]).harvestRewards(7)

        await getBalances()
        isRoughlyEqual(owner1Sushi.mul("1000").div(owner2Sushi), lpBalance1.mul("1000").div(lpBalance2))
        isRoughlyEqual(owner1Convex.mul("1000").div(owner2Convex), lpBalance1.mul("1000").div(lpBalance2))
        isRoughlyEqual(owner3Sushi.mul("1000").div(owner4Sushi), lpBalance3.mul("1000").div(lpBalance4))
        isRoughlyEqual(owner3Convex.mul("1000").div(owner4Convex), lpBalance3.mul("1000").div(lpBalance4))
    })
})