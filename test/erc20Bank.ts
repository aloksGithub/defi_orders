import { expect } from "chai";
import { ethers } from "hardhat";
import hre from 'hardhat'
import { IWETH, IPositionsManager, PositionsManager, UniversalSwap } from "../typechain-types";
import {deployAndInitializeManager, addresses, getNetworkToken, getLPToken, depositNew, isRoughlyEqual} from "../utils"
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
require('dotenv').config();

const NETWORK = hre.network.name
// @ts-ignore
const networkAddresses = addresses[NETWORK]
const liquidationPoints = [{liquidateTo: networkAddresses.networkToken, watchedToken: networkAddresses.networkToken, lessThan:true, liquidationPoint: 100}]

describe("ERC20Bank tests", function () {
    let manager: PositionsManager
    let owners: any[]
    let networkTokenContract: IWETH
    let universalSwap: UniversalSwap
    before(async function () {
        manager = await deployAndInitializeManager()
        owners = await ethers.getSigners()
        const universalSwapAddress = await manager.universalSwap()
        for (const owner of owners) {
            const {wethContract} = await getNetworkToken(owner, '1000.0')
            await wethContract.connect(owner).approve(universalSwapAddress, ethers.utils.parseEther("1000"))
        }
        networkTokenContract = await ethers.getContractAt("IWETH", networkAddresses.networkToken)
        universalSwap = await ethers.getContractAt("UniversalSwap", universalSwapAddress)
    })
    it.only("Opens, deposits, withdraws and closes position", async function () {
        const test = async (lpToken: string) => {
            const {lpBalance: lpBalance0, lpTokenContract} = await getLPToken(lpToken, universalSwap, "1", owners[0])
            const amountsOut = await universalSwap.getAmountsOut(
                {tokens: [networkTokenContract.address], amounts: [ethers.utils.parseEther('1')], nfts: []},
                {outputERC20s: [lpToken], outputERC721s: [], ratios: [1], minAmountsOut: [0]}
            )
            console.log(lpToken, lpBalance0, amountsOut)
            const {lpBalance: lpBalance1} = await getLPToken(lpToken, universalSwap, "1", owners[1])
            expect(lpBalance0).to.greaterThan(0)
            expect(lpBalance1).to.greaterThan(0)

    
            await lpTokenContract.connect(owners[0]).approve(manager.address, lpBalance0)
            await lpTokenContract.connect(owners[1]).approve(manager.address, lpBalance1)
            const {positionId: positionId1} = await depositNew(
                manager,
                lpToken,
                lpBalance0.div("2").toString(),
                liquidationPoints,
                owners[0]
            )
            const {positionId: positionId2} = await depositNew(
                manager,
                lpToken,
                lpBalance1.toString(),
                liquidationPoints,
                owners[1]
            )
            let user0PositionBalance = (await manager.getPosition(positionId1)).position.amount
            let user0lpBalance = await lpTokenContract.balanceOf(owners[0].address)
            expect(user0PositionBalance).to.equal(lpBalance0.div("2"))
            isRoughlyEqual(user0lpBalance, lpBalance0.div("2"))
            // expect(user0lpBalance).to.equal(lpBalance0.div("2"))
            let user1PositionBalance = (await manager.getPosition(positionId2)).position.amount
            let user1lpBalance = await lpTokenContract.balanceOf(owners[1].address)
            expect(user1PositionBalance).to.equal(lpBalance1)
            expect(user1lpBalance).to.lessThanOrEqual(100)
            await lpTokenContract.connect(owners[0]).approve(manager.address, lpBalance0.div("2"))
            await manager.connect(owners[0]).depositInExisting(positionId1, {tokens: [lpToken], amounts: [lpBalance0.div("2").toString()], nfts: []}, [], [], [])
            user0PositionBalance = (await manager.getPosition(positionId1)).position.amount
            user0lpBalance = await lpTokenContract.balanceOf(owners[0].address)
            expect(user0lpBalance).to.lessThanOrEqual(100)
            isRoughlyEqual(user0PositionBalance, lpBalance0)
            // expect(user0PositionBalance).to.equal(lpBalance0)
            await manager.connect(owners[0]).withdraw(positionId1, lpBalance0.div("2"))
            await manager.connect(owners[1]).withdraw(positionId2, lpBalance1.div("2"))
            user0PositionBalance = (await manager.getPosition(positionId1)).position.amount
            user0lpBalance = await lpTokenContract.balanceOf(owners[0].address)
            isRoughlyEqual(user0PositionBalance, lpBalance0.div("2"))
            isRoughlyEqual(user0lpBalance, lpBalance0.div("2"))
            user1PositionBalance = (await manager.getPosition(positionId2)).position.amount
            user1lpBalance = await lpTokenContract.balanceOf(owners[1].address)
            isRoughlyEqual(user1PositionBalance, lpBalance1.div("2"))
            isRoughlyEqual(user1lpBalance, lpBalance1.div("2"))
            await manager.connect(owners[1]).close(positionId2)
            await manager.connect(owners[0]).botLiquidate(positionId1, 0, [], [], 0)
            user0PositionBalance = (await manager.getPosition(positionId1)).position.amount
            user0lpBalance = await lpTokenContract.balanceOf(owners[0].address)
            expect(user0PositionBalance).to.equal(0)
            isRoughlyEqual(user0lpBalance, lpBalance0.div("2"))
            user1PositionBalance = (await manager.getPosition(positionId2)).position.amount
            user1lpBalance = await lpTokenContract.balanceOf(owners[1].address)
            expect(user1PositionBalance).to.equal(0)
            isRoughlyEqual(user1lpBalance, lpBalance1)
        }
        const lpTokens = networkAddresses.erc20BankLps
        for (const lpToken of lpTokens) {
            await test(lpToken)
        }
    })
})