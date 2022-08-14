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
    it("Opens, deposits, withdraws and closes position", async function () {
        const test = async (lpToken: string) => {
            const {lpBalance: lpBalance0, lpTokenContract} = await getLPToken(lpToken, NETWORK, universalSwap, "1", owners[0])
            const {lpBalance: lpBalance1} = await getLPToken(lpToken, NETWORK, universalSwap, "1", owners[1])
            expect(lpBalance0).to.greaterThan(0)
            expect(lpBalance1).to.greaterThan(0)
    
            await lpTokenContract.connect(owners[0]).approve(manager.address, lpBalance0)
            await lpTokenContract.connect(owners[1]).approve(manager.address, lpBalance1)
            const {positionId: positionId1} = await depositNew(
                manager,
                lpToken,
                lpBalance0.div("2").toString(),
                networkAddresses.networkToken,
                [networkAddresses.networkToken],
                [false],
                [100],
                owners[0]
            )
            const {positionId: positionId2} = await depositNew(
                manager,
                lpToken,
                lpBalance1.toString(),
                networkAddresses.networkToken,
                [networkAddresses.networkToken],
                [false],
                [100],
                owners[1]
            )
            let user0PositionBalance = (await manager.getPosition(positionId1)).amount
            let user0lpBalance = await lpTokenContract.balanceOf(owners[0].address)
            expect(user0PositionBalance).to.equal(lpBalance0.div("2"))
            isRoughlyEqual(user0lpBalance, lpBalance0.div("2"))
            // expect(user0lpBalance).to.equal(lpBalance0.div("2"))
            let user1PositionBalance = (await manager.getPosition(positionId2)).amount
            let user1lpBalance = await lpTokenContract.balanceOf(owners[1].address)
            expect(user1PositionBalance).to.equal(lpBalance1)
            expect(user1lpBalance).to.equal(0)
            await lpTokenContract.connect(owners[0]).approve(manager.address, lpBalance0.div("2"))
            await manager.connect(owners[0])["deposit(uint256,uint256)"](positionId1, lpBalance0.div("2").toString())
            user0PositionBalance = (await manager.getPosition(positionId1)).amount
            user0lpBalance = await lpTokenContract.balanceOf(owners[0].address)
            expect(user0lpBalance).to.lessThanOrEqual(1)
            isRoughlyEqual(user0PositionBalance, lpBalance0)
            // expect(user0PositionBalance).to.equal(lpBalance0)
            await manager.connect(owners[0]).withdraw(positionId1, lpBalance0.div("2"), false)
            await manager.connect(owners[1]).withdraw(positionId2, lpBalance1.div("2"), true)
            user0PositionBalance = (await manager.getPosition(positionId1)).amount
            user0lpBalance = await lpTokenContract.balanceOf(owners[0].address)
            // expect(user0PositionBalance).to.equal(lpBalance0.div("2"))
            isRoughlyEqual(user0lpBalance, lpBalance0.div("2"))
            // expect(user0lpBalance).to.equal()
            user1PositionBalance = (await manager.getPosition(positionId2)).amount
            isRoughlyEqual(user1PositionBalance, lpBalance1.div("2"))
            // expect(user1PositionBalance).to.equal(lpBalance1.div("2"))
            await manager.connect(owners[0]).close(positionId1, false)
            await manager.connect(owners[0]).botLiquidate(positionId2)
            user0PositionBalance = (await manager.getPosition(positionId1)).amount
            user0lpBalance = await lpTokenContract.balanceOf(owners[0].address)
            expect(user0PositionBalance).to.equal(0)
            expect(user0lpBalance).to.equal(lpBalance0)
            user1PositionBalance = (await manager.getPosition(positionId2)).amount
            const user1LiquidatedBalance = await networkTokenContract.balanceOf(owners[1].address)
            expect(user1PositionBalance).to.equal(0)
            expect(user1LiquidatedBalance).to.greaterThan(ethers.utils.parseEther("1"))
        }
        const lpTokens = networkAddresses.masterChefLps
        for (const lpToken of lpTokens) {
            await test(lpToken)
        }
    })
})