import { ethers } from "hardhat";
import { BasicOracle } from "../typechain-types";
import { addresses, deployOracle, isRoughlyEqual } from "../utils"

// @ts-ignore
const networkAddresses = addresses[hre.network.name]

describe("UniversalSwap tests", function () {
    let oracle: BasicOracle
    before(async function () {
        oracle = await deployOracle(false, false)
    })
    it("Oracle works correctly", async function () {
        const price = await oracle.getPrice(networkAddresses.usdc, networkAddresses.networkToken)
        const price2 = await oracle.getPrice(networkAddresses.networkToken, networkAddresses.usdc)
        const usdc = await ethers.getContractAt("ERC20", networkAddresses.usdc)
        const usdcDecimals = await usdc.decimals()
        const networkToken = await ethers.getContractAt("ERC20", networkAddresses.networkToken)
        const networkTokenDecimals = await networkToken.decimals()
        isRoughlyEqual(price.mul(price2), ethers.utils.parseUnits('1', usdcDecimals+networkTokenDecimals))
    })
})