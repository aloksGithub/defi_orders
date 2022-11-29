import { expect } from "chai";
import { ethers } from "hardhat";
import { IWETH, UniversalSwap, INonfungiblePositionManager } from "../typechain-types";
import { ProvidedStruct } from "../typechain-types/contracts/PositionsManager";
import { DesiredStruct } from "../typechain-types/contracts/UniversalSwap";
import { getUniversalSwap, addresses, getNetworkToken, getNFT, isRoughlyEqual, getNearestUsableTick } from "../utils"

// @ts-ignore
const networkAddresses = addresses[hre.network.name]

const compareComputedWithActual = async (computed: any[], actual: any[], manager: string, numERC20s: number) => {
    for (let i = 0; i<numERC20s; i++) {
        isRoughlyEqual(computed[i], actual[i])
    }
    if (!manager) return
    const managerContract = await ethers.getContractAt("INonfungiblePositionManager", manager)
    for (let i = numERC20s; i<computed.length; i++) {
        const tokenId = actual[i]
        const {liquidity} = await managerContract.positions(tokenId)
        expect(liquidity).to.equal(computed[i])
    }
}

describe("UniversalSwap tests", function () {
    let universalSwap: UniversalSwap
    let owners: any[]
    let networkTokenContract: IWETH
    before(async function () {
        universalSwap = await getUniversalSwap()
        owners = await ethers.getSigners()
        for (const owner of owners) {
            const {wethContract} = await getNetworkToken(owner, '100.0')
            await wethContract.connect(owner).approve(universalSwap.address, ethers.utils.parseEther("1000"))
        }
        networkTokenContract = await ethers.getContractAt("IWETH", networkAddresses.networkToken)
    })
    it("Swaps tokens correctly without losing too much equity", async function () {
        let currentToken = networkAddresses.networkToken
        const startingBalance = await networkTokenContract.balanceOf(owners[0].address)
        const tokensToSwapThrough: string[] = networkAddresses.universwalSwapTestingTokens
        tokensToSwapThrough.push(networkAddresses.networkToken)
        for (const token of tokensToSwapThrough) {
            const contract = await ethers.getContractAt("IERC20", currentToken)
            const balance = await contract.balanceOf(owners[0].address)
            expect(balance).to.greaterThan(0)
            await contract.approve(universalSwap.address, balance)
            await universalSwap.connect(owners[0]).swap({tokens: [currentToken], amounts: [balance], nfts: []}, [], [],
                {outputERC20s: [token], outputERC721s: [], ratios: [1], minAmountsOut: [0]}, owners[0].address)
            currentToken = token
        }
        const endingbalance = await networkTokenContract.balanceOf(owners[0].address)
        isRoughlyEqual(startingBalance, endingbalance)
    })
    it("Swaps for uniswap nft", async function () {
        const getNFTForPool = async (pool:string) => {
            const managerAddress = networkAddresses.NFTManagers[0]
            const startingBalance = await networkTokenContract.balanceOf(owners[0].address)
            const id = await getNFT(universalSwap, "1", managerAddress, pool, owners[0])
            const manager = await ethers.getContractAt("INonfungiblePositionManager", managerAddress)
            const result = await manager.positions(id)
            const liquidity = result[7]
            expect(liquidity).to.greaterThan(0)
            expect(id).to.greaterThan(0)
            await manager.approve(universalSwap.address, id)
            await universalSwap.connect(owners[0]).swap({tokens: [], amounts: [], nfts: [{pool, manager:managerAddress, liquidity, tokenId: id, data:[]}]}, [], [],
                {outputERC20s: [networkAddresses.networkToken], outputERC721s: [], ratios: [1], minAmountsOut: [0]}, owners[0].address)
            const endingbalance = await networkTokenContract.balanceOf(owners[0].address)
            isRoughlyEqual(startingBalance, endingbalance)
        }
        for (const pool of networkAddresses.nftBasaedPairs) {
            await getNFTForPool(pool)
        }
    })
    it.only("Performs multi-swap", async function () {
        const startingBalance = await networkTokenContract.balanceOf(owners[0].address)
        const adminBalanceBegin = await owners[0].getBalance()
        const erc20s: string[] = networkAddresses.universwalSwapTestingTokens
        let erc721s:any = networkAddresses.nftBasaedPairs
        const erc20sStep1 = erc20s.slice(0, Math.floor(erc20s.length/2))
        const erc20sStep2 = erc20s.slice(Math.floor(erc20s.length/2), erc20s.length)
        erc721s = erc721s.map(async (pool:string)=> {
            const abi = ethers.utils.defaultAbiCoder;
            const poolContract = await ethers.getContractAt("IUniswapV3Pool", pool)
            const {tick} = await poolContract.slot0()
            const tickSpacing = await poolContract.tickSpacing()
            const nearestTick = getNearestUsableTick(tick, tickSpacing)
            const data = abi.encode(
                ["int24","int24","uint256","uint256"],
                [nearestTick-2500*tickSpacing, nearestTick+20*tickSpacing, 0, 0]);
            return {pool, manager: networkAddresses.NFTManagers[0], tokenId: 0, liquidity: 0, data}
        })
        erc721s = await Promise.all(erc721s)
        const erc721sStep1 = erc721s.slice(0, Math.floor(erc721s.length/2))
        const erc721sStep2 = erc721s.slice(Math.floor(erc721s.length/2), erc721s.length)
        const ratiosStep1 = []
        for (let i = 0; i<erc20sStep1.length+erc721sStep1.length; i++) {
            ratiosStep1.push(100)
        }
        const ratiosStep2 = []
        for (let i = 0; i<erc20sStep2.length+erc721sStep2.length; i++) {
            ratiosStep2.push(100)
        }
        const minAmountsStep1 = Array(erc20sStep1.length).fill(0)
        const minAmountsStep2 = Array(erc20sStep2.length).fill(0)
        await networkTokenContract.approve(universalSwap.address, (await networkTokenContract.balanceOf(owners[0].address)))


        const performMultiSwap = async (provided:ProvidedStruct, desired:DesiredStruct) => {
            const {amounts, swaps, conversions} = await universalSwap.getAmountsOut(provided, desired)
            const tx = await universalSwap.swap(provided, swaps, conversions, desired, owners[0].address)
            const rc = await tx.wait()
            const events = rc.events?.filter((event:any) => event.event === 'NFTMinted')
            // @ts-ignore
            const ids = events.map(event=>event.args?.tokenId.toNumber())
            let nextInputERC721sPromises = await desired.outputERC721s.map(async (nft:any, index:number)=> {
                const managerContract = await ethers.getContractAt("INonfungiblePositionManager", nft.manager)
                await managerContract.approve(universalSwap.address, ids[index])
                const position = await managerContract.positions(ids[index])
                return {...nft, tokenId: ids[index], liquidity: position.liquidity}
            })
            const nextInputERC721s = await Promise.all(nextInputERC721sPromises)
            const erc20sBalance = []
            for (const erc20 of desired.outputERC20s) {
                // @ts-ignore
                const contract = await ethers.getContractAt("ERC20", erc20)
                const balance = await contract.balanceOf(owners[0].address)
                await contract.approve(universalSwap.address, balance)
                erc20sBalance.push(balance)
            }
            await compareComputedWithActual(amounts, erc20sBalance.concat(ids), networkAddresses.NFTManagers[0], erc20sBalance.length)
            return {tokens: desired.outputERC20s, amounts: erc20sBalance, nfts: nextInputERC721s}
        }

        let nextProvided = await performMultiSwap(
            {tokens: [networkAddresses.networkToken], amounts: [(await networkTokenContract.balanceOf(owners[0].address))], nfts: []},
            {outputERC20s: erc20sStep1, outputERC721s: erc721sStep1, ratios: ratiosStep1, minAmountsOut: minAmountsStep1}
        )

        nextProvided = await performMultiSwap(
            nextProvided, {outputERC20s: erc20sStep2, outputERC721s: erc721sStep2, ratios: ratiosStep2, minAmountsOut: minAmountsStep2}
        )
        
        nextProvided = await performMultiSwap(
            nextProvided, {outputERC20s: [networkAddresses.networkToken], outputERC721s: [], ratios: [1], minAmountsOut: [0]}
        )

        const balanceFinal = await networkTokenContract.balanceOf(owners[0].address)
        isRoughlyEqual(startingBalance, balanceFinal)
        console.log(`Slippage: ${startingBalance.sub(balanceFinal).mul('10000').div(startingBalance).toNumber()/100}%`)
        const adminBalanceEnd = await owners[0].getBalance()
        const gasCost = adminBalanceBegin.sub(adminBalanceEnd)
        console.log(`Gas cost: ${ethers.utils.formatEther(gasCost)}`)
    })
})