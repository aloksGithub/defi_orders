import { expect } from "chai";
import { ethers } from "hardhat";
import { IWETH, UniversalSwap } from "../typechain-types";
import { getUniversalSwap, addresses, getNetworkToken, getNFT, isRoughlyEqual, getNearestUsableTick } from "../utils"

// @ts-ignore
const networkAddresses = addresses[hre.network.name]


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
    it("Performs multi-swap", async function () {
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
        const [bestSwaps1, conversions1] = await universalSwap.preSwapComputation(
            {tokens: [networkAddresses.networkToken], amounts: [(await networkTokenContract.balanceOf(owners[0].address))], nfts: []},
            {outputERC20s: erc20sStep1, outputERC721s: erc721sStep1, ratios: ratiosStep1, minAmountsOut: minAmountsStep1}
        )
        // const tx1Gas = await universalSwap.estimateGas.swap(
        //     {tokens: [networkAddresses.networkToken], amounts: [(await networkTokenContract.balanceOf(owners[0].address))], nfts: []}, bestSwaps1, conversions1, 
        //     {outputERC20s: erc20sStep1, outputERC721s: erc721sStep1, ratios: ratiosStep1, minAmountsOut: minAmountsStep1}, owners[0].address)
        // console.log(tx1Gas)
        const tx = await universalSwap.swap(
            {tokens: [networkAddresses.networkToken], amounts: [(await networkTokenContract.balanceOf(owners[0].address))], nfts: []}, bestSwaps1, conversions1, 
            {outputERC20s: erc20sStep1, outputERC721s: erc721sStep1, ratios: ratiosStep1, minAmountsOut: minAmountsStep1}, owners[0].address)
        const rc = await tx.wait()
        const events = rc.events?.filter((event:any) => event.event === 'NFTMinted')
        // @ts-ignore
        const ids = events.map(event=>event.args?.tokenId.toNumber())
        const erc20sBalance = []
        for (const erc20 of erc20sStep1) {
            const contract = await ethers.getContractAt("ERC20", erc20)
            const balance = await contract.balanceOf(owners[0].address)
            await contract.approve(universalSwap.address, balance)
            erc20sBalance.push(balance)
        }
        let inputERC721s = erc721sStep1.map(async (nft:any, index:number)=> {
            const managerContract = await ethers.getContractAt("INonfungiblePositionManager", nft.manager)
            await managerContract.approve(universalSwap.address, ids[index])
            const position = await managerContract.positions(ids[index])
            return {...nft, tokenId: ids[index], liquidity: position.liquidity}
        })
        inputERC721s = await Promise.all(inputERC721s)

        const [bestSwaps2, conversions2] = await universalSwap.preSwapComputation(
            {tokens: erc20sStep1, amounts: erc20sBalance, nfts: inputERC721s},
            {outputERC20s: erc20sStep2, outputERC721s: erc721sStep2, ratios: ratiosStep2, minAmountsOut: minAmountsStep2}
        )
        // const tx2Gas = await universalSwap.estimateGas.swap(
        //     {tokens: erc20sStep1, amounts: erc20sBalance, nfts: inputERC721s}, bestSwaps2, conversions2,
        //     {outputERC20s: erc20sStep2, outputERC721s: erc721sStep2, ratios: ratiosStep2, minAmountsOut: minAmountsStep2}, owners[0].address
        // )
        // console.log(tx2Gas)
        const tx2 = await universalSwap.swap(
            {tokens: erc20sStep1, amounts: erc20sBalance, nfts: inputERC721s}, bestSwaps2, conversions2,
            {outputERC20s: erc20sStep2, outputERC721s: erc721sStep2, ratios: ratiosStep2, minAmountsOut: minAmountsStep2}, owners[0].address
        )
        const rc2 = await tx2.wait()
        const events2 = rc2.events?.filter((event:any) => event.event === 'NFTMinted')
        // @ts-ignore
        const ids2 = events2.map(event=>event.args?.tokenId.toNumber())
        inputERC721s = erc721sStep2.map(async (nft:any, index:number)=> {
            const managerContract = await ethers.getContractAt("INonfungiblePositionManager", nft.manager)
            await managerContract.approve(universalSwap.address, ids2[index])
            const position = await managerContract.positions(ids2[index])
            return {...nft, tokenId: ids2[index], liquidity: position.liquidity}
        })
        inputERC721s = await Promise.all(inputERC721s)
        const erc20sBalanceFinal = []
        for (const erc20 of erc20sStep2) {
            const contract = await ethers.getContractAt("ERC20", erc20)
            const balance = await contract.balanceOf(owners[0].address)
            await contract.approve(universalSwap.address, balance)
            erc20sBalanceFinal.push(balance)
        }
        const [bestSwaps3, conversions3] = await universalSwap.preSwapComputation(
            {tokens: erc20sStep2, amounts: erc20sBalanceFinal, nfts: inputERC721s},
            {outputERC20s: [networkAddresses.networkToken], outputERC721s: [], ratios: [1], minAmountsOut: [0]}
        )
        // const tx3Gas = await universalSwap.estimateGas.swap(
        //     {tokens: erc20sStep2, amounts: erc20sBalanceFinal, nfts: inputERC721s}, bestSwaps3, conversions3,
        //     {outputERC20s: [networkAddresses.networkToken], outputERC721s: [], ratios: [1], minAmountsOut: [0]}, owners[0].address
        // )
        // console.log(tx3Gas)
        await universalSwap.swap(
            {tokens: erc20sStep2, amounts: erc20sBalanceFinal, nfts: inputERC721s}, bestSwaps3, conversions3,
            {outputERC20s: [networkAddresses.networkToken], outputERC721s: [], ratios: [1], minAmountsOut: [0]}, owners[0].address
        )
        const balanceFinal = await networkTokenContract.balanceOf(owners[0].address)
        isRoughlyEqual(startingBalance, balanceFinal)
        console.log(`Slippage: ${startingBalance.sub(balanceFinal).mul('10000').div(startingBalance).toNumber()/100}%`)
        const adminBalanceEnd = await owners[0].getBalance()
        const gasCost = adminBalanceBegin.sub(adminBalanceEnd)
        console.log(`Gas cost: ${ethers.utils.formatEther(gasCost)}`)
    })
})