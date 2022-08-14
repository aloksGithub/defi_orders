import { assert, expect } from "chai";
import { ethers, network } from "hardhat";
import { IWETH, PositionsManager, UniversalSwap } from "../typechain-types";
import { ERC20 } from "../typechain-types";
import {deployAndInitializeManager, addresses, getNetworkToken, getLPToken, depositNew, isRoughlyEqual} from "../utils"
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
require('dotenv').config();

const NETWORK = process.env.NETWORK!
// @ts-ignore
const networkAddresses = addresses[NETWORK]

describe ("Position opening", function () {
    let manager: PositionsManager
    let owners: SignerWithAddress[]
    let networkTokenContract: IWETH
    let universalSwap: UniversalSwap
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
    })
    it("Opens recompounds and closes position", async function () {
        const test = async (lpToken: string) => {
            const {lpBalance: lpBalance0, lpTokenContract} = await getLPToken(lpToken, NETWORK, universalSwap, "1", owners[0])
            expect(lpBalance0).to.greaterThan(0)
    
            await lpTokenContract.connect(owners[0]).approve(manager.address, lpBalance0)
            const {positionId, rewards, rewardContracts} = await depositNew(
                manager,
                lpToken,
                lpBalance0.toString(),
                networkAddresses.networkToken,
                [networkAddresses.networkToken],
                [false],
                [100],
                owners[0]
            )
            const positionInfo1 = await manager.getPosition(positionId)
            await ethers.provider.send("hardhat_mine", ["0x100"]);
            await manager.connect(owners[0]).harvestAndRecompound(positionId)
            const positionInfo2 = await manager.getPosition(positionId)
            expect(positionInfo2.amount).to.greaterThan(positionInfo1.amount)
            await manager.connect(owners[0]).close(positionId, true)
            const finalBalance = await networkTokenContract.balanceOf(owners[0].address)
            expect(finalBalance).to.greaterThan(ethers.utils.parseEther("1"))
        }
        const lpTokens = networkAddresses.masterChefLps
        for (const lpToken of lpTokens) {
            await test(lpToken)
        }
    })
    it("Handles multiple actions", async function () {
        const test = async (lpToken:string) => {
            const users = [owners[3], owners[4], owners[5], owners[6]]
            const {lpBalance: lpBalance0, lpTokenContract} = await getLPToken(lpToken, NETWORK, universalSwap, "1", owners[3])
            const {lpBalance: lpBalance1} = await getLPToken(lpToken, NETWORK, universalSwap, "1", owners[4])
            const {lpBalance: lpBalance2} = await getLPToken(lpToken, NETWORK, universalSwap, "1", owners[5])
            const {lpBalance: lpBalance3} = await getLPToken(lpToken, NETWORK, universalSwap, "1", owners[6])
            const lpBalances = [lpBalance0, lpBalance1, lpBalance2, lpBalance3]

            const {positionId: position0, rewards, rewardContracts} = await depositNew(
                manager,
                lpToken,
                lpBalance0.toString(),
                networkAddresses.networkToken,
                [networkAddresses.networkToken],
                [false],
                [100],
                users[0]
            )
            const clearRewards = async (usersToClear: SignerWithAddress[]) => {
                for (const user of usersToClear) {
                    for (const rewardContract of rewardContracts) {
                        const balance = await rewardContract.balanceOf(user.address)
                        await rewardContract.connect(user).transfer(owners[0].address, balance)
                    }
                }
            }
            await clearRewards(users)
            const {positionId: position1} = await depositNew(
                manager,
                lpToken,
                lpBalance1.div("3").toString(),
                networkAddresses.networkToken,
                [networkAddresses.networkToken],
                [false],
                [100],
                users[1]
            )
            await ethers.provider.send("hardhat_mine", ["0x100"]);
            await manager.harvestRewards(position0)
            await manager.harvestRewards(position1)

            for (const rewardContract of rewardContracts) {
                const user0Bal = await rewardContract.balanceOf(users[0].address)
                const user1Bal = await rewardContract.balanceOf(users[1].address)
                isRoughlyEqual(user0Bal.mul('1000').div(user1Bal), lpBalances[0].mul('1000').div(lpBalances[1].div('3')))
            }

            await clearRewards(users)

            const {positionId: position2} = await depositNew(manager, lpToken, lpBalance2.toString(), networkAddresses.networkToken, [networkAddresses.networkToken], [false], [100], users[2])
            const {positionId: position3} = await depositNew(manager, lpToken, lpBalance3.div("2").toString(), networkAddresses.networkToken, [networkAddresses.networkToken], [false], [100], users[3])
            await ethers.provider.send("hardhat_mine", ["0x100"]);
            await manager.connect(users[2]).harvestRewards(position2)
            await manager.connect(users[3]).harvestRewards(position3)
            
            for (const rewardContract of rewardContracts) {
                const user2Bal = await rewardContract.balanceOf(users[2].address)
                const user3Bal = await rewardContract.balanceOf(users[3].address)
                isRoughlyEqual(user2Bal.mul('1000').div(user3Bal), lpBalances[2].mul('1000').div(lpBalances[3].div('2')))
            }
            await clearRewards(users)

            await ethers.provider.send("hardhat_mine", ["0x100"]);
            await manager.connect(users[0]).harvestRewards(position0)
            await manager.connect(users[1]).harvestRewards(position1)
            await manager.connect(users[2]).harvestRewards(position2)
            await manager.connect(users[3]).harvestRewards(position3)
            
            for (const rewardContract of rewardContracts) {
                const user0Bal = await rewardContract.balanceOf(users[0].address)
                const user1Bal = await rewardContract.balanceOf(users[1].address)
                const user2Bal = await rewardContract.balanceOf(users[2].address)
                const user3Bal = await rewardContract.balanceOf(users[3].address)
                isRoughlyEqual(user0Bal.mul('1000').div(user1Bal), lpBalance0.mul('1000').div(lpBalance1.div('3')))
                isRoughlyEqual(user2Bal.mul('1000').div(user3Bal), lpBalance2.mul('1000').div(lpBalance3.div('2')))
                isRoughlyEqual(user0Bal.mul('1000').div(user2Bal), lpBalance0.mul('1000').div(lpBalance2.div('2')))
            }

            await manager.connect(users[0]).withdraw(position0, lpBalance0.mul("2").div("3"), false)
            expect(lpBalance0.mul("2").div("3")).to.equal(await lpTokenContract.balanceOf(users[0].address))
            await lpTokenContract.connect(users[3]).approve(manager.address, lpBalance3.div("2"))
            await manager.connect(users[3])["deposit(uint256,uint256)"](position3, lpBalance3.div("2"))
            await clearRewards(users)
            
            await ethers.provider.send("hardhat_mine", ["0x100"]);
            await manager.connect(users[0]).harvestRewards(position0)
            await manager.connect(users[1]).harvestRewards(position1)
            await manager.connect(users[2]).harvestRewards(position2)
            await manager.connect(users[3]).harvestRewards(position3)

            for (const rewardContract of rewardContracts) {
                const user0Bal = await rewardContract.balanceOf(users[0].address)
                const user1Bal = await rewardContract.balanceOf(users[1].address)
                const user2Bal = await rewardContract.balanceOf(users[2].address)
                const user3Bal = await rewardContract.balanceOf(users[3].address)
                isRoughlyEqual(user0Bal.mul('1000').div(user1Bal), lpBalance0.mul('1000').div(lpBalance1))
                isRoughlyEqual(user2Bal.mul('1000').div(user3Bal), lpBalance2.mul('1000').div(lpBalance3))
            }
        }
        const lpTokens = networkAddresses.masterChefLps
        for (const lpToken of lpTokens) {
            await test(lpToken)
        }
    })
    it("Handles bot liquidation", async function () {
        const test = async (lpToken: string) => {
            const owner = owners[7]
            const {lpBalance: lpBalance0, lpTokenContract} = await getLPToken(lpToken, NETWORK, universalSwap, "1", owner)
            expect(lpBalance0).to.greaterThan(0)
    
            await lpTokenContract.connect(owner).approve(manager.address, lpBalance0)
            const {positionId} = await depositNew(
                manager,
                lpToken,
                lpBalance0.toString(),
                networkAddresses.networkToken,
                [networkAddresses.networkToken],
                [false],
                [100],
                owner
            )
            const positionInfo1 = await manager.getPosition(positionId)
            await ethers.provider.send("hardhat_mine", ["0x100"]);
            await manager.connect(owner).harvestAndRecompound(positionId)
            const positionInfo2 = await manager.getPosition(positionId)
            expect(positionInfo2.amount).to.greaterThan(positionInfo1.amount)
            await manager.connect(owners[0]).botLiquidate(positionId)
            const finalBalance = await networkTokenContract.balanceOf(owner.address)
            expect(finalBalance).to.greaterThan(ethers.utils.parseEther("1"))
        }
        const lpTokens = networkAddresses.masterChefLps
        for (const lpToken of lpTokens) {
            await test(lpToken)
        }
    })
})