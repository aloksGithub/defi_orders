import { expect } from "chai";
import { ethers } from "hardhat";
import { IWETH, UniversalSwap } from "../typechain-types";
import { getUniversalSwap, addresses, getNetworkToken, getNFT, isRoughlyEqual, getNearestUsableTick } from "../utils"

// @ts-ignore
const networkAddresses = addresses[hre.network.name]


describe.only("UniversalSwap tests", function () {
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
            await universalSwap.connect(owners[0]).swapV2([currentToken], [balance], [], [token], [], [1], [0])
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
            await universalSwap.connect(owners[0]).swapV2([], [], [{pool, manager:managerAddress, liquidity, tokenId: id, data:[]}], [networkAddresses.networkToken], [], [1], [0])
            const endingbalance = await networkTokenContract.balanceOf(owners[0].address)
            isRoughlyEqual(startingBalance, endingbalance)
        }
        for (const pool of networkAddresses.nftBasaedPairs) {
            await getNFTForPool(pool)
        }
    })
    it.only("Performs multi-swap", async function () {
        // const startingBalance = await networkTokenContract.balanceOf(owners[0].address)
        // const adminBalanceBegin = await owners[0].getBalance()
        // const erc20s: string[] = networkAddresses.universwalSwapTestingTokens
        // let erc721s:any = networkAddresses.nftBasaedPairs
        // const erc20sStep1 = erc20s.slice(0, Math.floor(erc20s.length/2))
        // const erc20sStep2 = erc20s.slice(Math.floor(erc20s.length/2), erc20s.length)
        // erc721s = erc721s.map(async (pool:string)=> {
        //     const abi = ethers.utils.defaultAbiCoder;
        //     const poolContract = await ethers.getContractAt("IUniswapV3Pool", pool)
        //     const {tick} = await poolContract.slot0()
        //     const tickSpacing = await poolContract.tickSpacing()
        //     const nearestTick = getNearestUsableTick(tick, tickSpacing)
        //     const data = abi.encode(
        //         ["int24","int24","uint256","uint256"],
        //         [nearestTick-2500*tickSpacing, nearestTick+20*tickSpacing, 0, 0]);
        //     return {pool, manager: networkAddresses.NFTManagers[0], tokenId: 0, liquidity: 0, data}
        // })
        // erc721s = await Promise.all(erc721s)
        // const erc721sStep1 = erc721s.slice(0, Math.floor(erc721s.length/2))
        // const erc721sStep2 = erc721s.slice(Math.floor(erc721s.length/2), erc721s.length)
        // const ratiosStep1 = []
        // for (let i = 0; i<erc20sStep1.length+erc721sStep1.length; i++) {
        //     ratiosStep1.push(100)
        // }
        // const ratiosStep2 = []
        // for (let i = 0; i<erc20sStep2.length+erc721sStep2.length; i++) {
        //     ratiosStep2.push(100)
        // }
        // const minAmountsStep1 = Array(erc20sStep1.length).fill(0)
        // const minAmountsStep2 = Array(erc20sStep2.length).fill(0)
        // await networkTokenContract.approve(universalSwap.address, (await networkTokenContract.balanceOf(owners[0].address)))
        // const tx1Gas = await universalSwap.estimateGas.swapV2([networkAddresses.networkToken], [(await networkTokenContract.balanceOf(owners[0].address))], [], erc20sStep1, erc721sStep1, ratiosStep1, minAmountsStep1, {gasLimit:30000000})
        // console.log(tx1Gas)
        // const tx = await universalSwap.swapV2([networkAddresses.networkToken], [(await networkTokenContract.balanceOf(owners[0].address))], [], erc20sStep1, erc721sStep1, ratiosStep1, minAmountsStep1)
        // const rc = await tx.wait()
        // const events = rc.events?.filter(event => event.event === 'NFTMinted')
        // // @ts-ignore
        // const ids = events.map(event=>event.args?.tokenId.toNumber())
        // const erc20sBalance = []
        // for (const erc20 of erc20sStep1) {
        //     const contract = await ethers.getContractAt("ERC20", erc20)
        //     const balance = await contract.balanceOf(owners[0].address)
        //     await contract.approve(universalSwap.address, balance)
        //     erc20sBalance.push(balance)
        // }
        // let inputERC721s = erc721sStep1.map(async (nft:any, index:number)=> {
        //     const managerContract = await ethers.getContractAt("INonfungiblePositionManager", nft.manager)
        //     await managerContract.approve(universalSwap.address, ids[index])
        //     const position = await managerContract.positions(ids[index])
        //     return {...nft, tokenId: ids[index], liquidity: position.liquidity}
        // })
        // inputERC721s = await Promise.all(inputERC721s)
        // const tx2Gas = await universalSwap.estimateGas.swapV2(erc20sStep1, erc20sBalance, inputERC721s, erc20sStep2, erc721sStep2, ratiosStep2, minAmountsStep2)
        // console.log(tx2Gas)
        // const tx2 = await universalSwap.swapV2(erc20sStep1, erc20sBalance, inputERC721s, erc20sStep2, erc721sStep2, ratiosStep2, minAmountsStep2)
        // const rc2 = await tx2.wait()
        // const events2 = rc2.events?.filter(event => event.event === 'NFTMinted')
        // // @ts-ignore
        // const ids2 = events2.map(event=>event.args?.tokenId.toNumber())
        // inputERC721s = erc721sStep2.map(async (nft:any, index:number)=> {
        //     const managerContract = await ethers.getContractAt("INonfungiblePositionManager", nft.manager)
        //     await managerContract.approve(universalSwap.address, ids2[index])
        //     const position = await managerContract.positions(ids2[index])
        //     return {...nft, tokenId: ids2[index], liquidity: position.liquidity}
        // })
        // inputERC721s = await Promise.all(inputERC721s)
        // const erc20sBalanceFinal = []
        // for (const erc20 of erc20sStep2) {
        //     const contract = await ethers.getContractAt("ERC20", erc20)
        //     const balance = await contract.balanceOf(owners[0].address)
        //     await contract.approve(universalSwap.address, balance)
        //     erc20sBalanceFinal.push(balance)
        // }
        const gas = await universalSwap.estimateGas.swapV3([], [], [], [networkAddresses.networkToken], [], [1], [0])
        console.log(gas)
        // const usdcContract = await ethers.getContractAt("ERC20", networkAddresses.usdc)
        // const balanceFinal = await networkTokenContract.balanceOf(owners[0].address)
        // console.log(startingBalance, balanceFinal)
        // console.log(startingBalance.sub(balanceFinal))
        // const adminBalanceEnd = await owners[0].getBalance()
        // console.log(adminBalanceBegin.sub(adminBalanceEnd))
    })
})