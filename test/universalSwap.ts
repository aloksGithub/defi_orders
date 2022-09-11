import { expect } from "chai";
import { ethers } from "hardhat";
import { IWETH, UniversalSwap } from "../typechain-types";
import { getUniversalSwap, addresses, getNetworkToken, getNFT, isRoughlyEqual } from "../utils"

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
            const {wethContract} = await getNetworkToken(owner, '1000.0')
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
            universalSwap["swap(address[],uint256[],address,uint256)"]([currentToken], [balance], token, 0)
            currentToken = token
        }
        const endingbalance = await networkTokenContract.balanceOf(owners[0].address)
        isRoughlyEqual(startingBalance, endingbalance)
    })
    it("Swaps for uniswap nft", async function () {
        const getNFTForPool = async (pool:string) => {
            const managerAddress = networkAddresses.NFTManagers[0]
            const startingBalance = await networkTokenContract.balanceOf(owners[0].address)
            const id = await getNFT(universalSwap, "10", managerAddress, pool, owners[0])
            const manager = await ethers.getContractAt("INonfungiblePositionManager", managerAddress)
            const result = await manager.positions(id)
            const liquidity = result[7]
            expect(liquidity).to.greaterThan(0)
            expect(id).to.greaterThan(0)
            await manager.approve(universalSwap.address, id)
            await universalSwap.swapNFT({pool, manager:managerAddress, tokenId: id, data:[]}, networkAddresses.networkToken)
            const endingbalance = await networkTokenContract.balanceOf(owners[0].address)
            isRoughlyEqual(startingBalance, endingbalance)
        }
        for (const pool of networkAddresses.nftBasaedPairs) {
            await getNFTForPool(pool)
        }
    })
})