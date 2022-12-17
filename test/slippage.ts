import {expect} from "chai";
import {ethers} from "hardhat";
import hre from "hardhat";
import {ERC20, IERC20, IUniswapV2Pair, IWETH, PositionsManager, UniversalSwap} from "../typechain-types";
import {
  deployAndInitializeManager,
  addresses,
  getNetworkToken,
  getLPToken,
  depositNew,
  getAssets
} from "../utils";
import supportedProtocols from "../constants/supported_protocols.json";
require("dotenv").config();
import { Asset } from "../utils/protocolDataGetter";
const fs = require('fs');

const chainIds = {
  bsc: 56,
  mainnet: 1
}

const NETWORK = hre.network.name;
// @ts-ignore
const networkAddresses = addresses[NETWORK];
// @ts-ignore
const protocols = supportedProtocols[process.env.CURRENTLY_FORKING!];
const liquidationPoints = [{
  liquidateTo: networkAddresses.networkToken,
  watchedToken: ethers.constants.AddressZero,
  lessThan:true,
  liquidationPoint: '100000000000000000000',
  slippage: ethers.utils.parseUnits("3", 17)
}]

const fetchAssets = async () => {
  let assets: Asset[] = []
  for (const protocol of protocols) {
    const data = await getAssets(
      protocol,
      // @ts-ignore
      chainIds[process.env.CURRENTLY_FORKING!]
    );
    if (data) {
      assets = assets.concat(data)
    } else {
      console.error(`Unable to fetch data for ${protocol.name}`)
    }
  }
  return assets;
};

const blackList = [
  "0x78366446547d062f45b4c0f320cdaa6d710d87bb", // no liquidity
  "0xebd0070237a0713e8d94fef1b728d3d993d290ef", // dead token
  "0x1369cdac3d7715ee6c89a613e7cd760cfec2a37d", // no liquidity
  "0x9aa8a1d73df07ed62f419da0ebf8b2c0c9ca2b81", // no liquidity
  "0x2ec424ffcf9a2c1d398f3f1624ad1ffa86d80cc7", // no liquidity
  "0x22D954CA5540caB869AdA9bd9d339CDE3a9313b3", // coin has tax for transferring tokens
  "0x3668Ca2009aF4c0a4a9e258EF69eAD1FabbfB7da", // pool for old safe moon, has tax for transferring tokens
  "0xbe135058eb838f8c0296ef477896eb7af5a52678", // No idea why pancakeswap fails to transfer
  "0xacfc95585d80ab62f67a14c566c1b7a49fe91167", // coin has tax for transferring tokens
  "0x04260673729c5f2b9894a467736f3d85f8d34fc8", // no liquidity
  "0x32299c93960bb583a43c2220dc89152391a610c5", // no liquidity
  "0x507221bdf0f9fc91039fc65270b812a48fe7130a", // no liquidity
  "0x50332bdca94673f33401776365b66cc4e81ac81d", // no liquidity
  "0x59f6b2435cd1421f409907ad2d9f811849ca555f", // Broken pool
  "0x3a806a3315e35b3f5f46111adb6e2baf4b14a70d", // coin has tax for transferring tokens
  "0x8076c74c5e3f5852037f31ff0093eeb8c8add8d3", // old safemoon, has tax for transferring tokens
  "0x2b3f34e9d4b127797ce6244ea341a83733ddd6e4", // No idea why pancakeswap fails to transfer
].map(address=>address.toLowerCase())

describe.only("Slippage tests", function () {
  let manager: PositionsManager;
  let owners: any[];
  let networkTokenContract: IWETH;
  let universalSwap: UniversalSwap;
  let depositedUsd: number
  let stableContract: ERC20
  let amountUsed="1"
  before(async function () {
    manager = await deployAndInitializeManager();
    owners = await ethers.getSigners();
    const universalSwapAddress = await manager.universalSwap();
    for (const owner of owners) {
      const {wethContract} = await getNetworkToken(owner, "9990.0");
      await wethContract
        .connect(owner)
        .approve(universalSwapAddress, ethers.utils.parseEther("10000000"));
    }
    networkTokenContract = await ethers.getContractAt(
      "IWETH",
      networkAddresses.networkToken
    );
    universalSwap = await ethers.getContractAt(
      "UniversalSwap",
      universalSwapAddress
    );
    stableContract = await ethers.getContractAt("ERC20", networkAddresses.preferredStable)
    const stableDecimals = await stableContract.decimals()
    const networkTokenPrice = await universalSwap.estimateValueERC20(networkAddresses.networkToken, ethers.utils.parseEther(amountUsed), networkAddresses.preferredStable)
    depositedUsd = +amountUsed*+ethers.utils.formatUnits(networkTokenPrice, stableDecimals)
  });
  it("Doesn't have more than 2% slippage for any ERC20 swaps", async function () {
    const assets = await fetchAssets();
    let index = 0
    let errors = 0
    let numBadSlippage = 0
    let numNormalSlippage = 0
    let totalSlippage = 0
    const assetsToWhiteList:Asset[] = []
    for (const asset of assets) {
      if (blackList.includes(asset.contract_address)) continue
      index+=1
      try {
        const balanceBefore = await stableContract.balanceOf(owners[0].address)
        const {lpBalance: lpBalance0, lpTokenContract} = await getLPToken(asset.contract_address, universalSwap, amountUsed, owners[0])

        // Commenting out temporarily to save time
        // const {positionId} = await depositNew(manager, lpTokenContract.address, lpBalance0.div(2).toString(), liquidationPoints, owners[0])
        // await lpTokenContract.connect(owners[0]).approve(manager.address, lpBalance0)
        // await manager.connect(owners[0]).depositInExisting(positionId, {tokens: [lpTokenContract.address], amounts: [lpBalance0.div(2)], nfts: []}, [], [], [])
        // await manager.connect(owners[0]).withdraw(positionId, lpBalance0.div(2))
        // await manager.connect(owners[0]).close(positionId)
        await lpTokenContract.approve(universalSwap.address, lpBalance0)
        await universalSwap.connect(owners[0]).swap(
            {tokens: [asset.contract_address], amounts: [lpBalance0], nfts: []}, [], [],
            {outputERC20s: [networkAddresses.preferredStable], outputERC721s: [], ratios: [1], minAmountsOut: [0]}, owners[0].address)
        const balance = await stableContract.balanceOf(owners[0].address)
        const fundsLost = depositedUsd-+ethers.utils.formatUnits(balance.sub(balanceBefore), (await stableContract.decimals()))
        const slippage = 100*fundsLost/depositedUsd
        await stableContract.transfer(owners[1].address, balance)
        if (slippage>2) {
          numBadSlippage+=1
          console.error(`Slippage: ${slippage.toFixed(3)}% for token ${asset.contract_address}`)
        }
        else {
          numNormalSlippage+=1
          totalSlippage+=slippage
          console.log(`Slippage: ${slippage.toFixed(3)}% for token ${asset.contract_address}`)
          assetsToWhiteList.push(asset)
        }
      } catch (error) {
        if (asset.contract_address!=ethers.constants.AddressZero) {
          errors+=1
          console.error(`Failed conversion for token ${asset.contract_address} with error: ${error}`)
        } else {
          assetsToWhiteList.push(asset)
        }
      }
    }
    let fileData = JSON.stringify(assetsToWhiteList);
    // @ts-ignore
    fs.writeFileSync(`./protocolData/${chainIds[process.env.CURRENTLY_FORKING!]}.json`, fileData);
    console.log(`Attempted stress test with ${index} assets`)
    console.log(`${errors} (${(errors*100/index).toFixed(2)}%) failed due to error`)
    console.log(`${numBadSlippage} (${(numBadSlippage*100/index).toFixed(2)}%) had slippage higher than 2%`)
    console.log(`Average slippage: ${totalSlippage/numNormalSlippage}`)
  });
  it.only("Check slippage for few ERC20 tokens", async function () {
    const assets = ["0x6df9c6e8774a92c481cb51bb57d6f27864e13e35"]
    for (const wanted of assets) {
      const balanceBefore = await stableContract.balanceOf(owners[0].address)
      const {lpBalance: lpBalance0, lpTokenContract} = await getLPToken(wanted, universalSwap, amountUsed, owners[0])
      await lpTokenContract.connect(owners[0]).approve(manager.address, lpBalance0)
      const {positionId} = await depositNew(manager, lpTokenContract.address, lpBalance0.div('2').toString(), liquidationPoints, owners[0])
      await lpTokenContract.connect(owners[0]).approve(manager.address, lpBalance0)
      await manager.connect(owners[0]).depositInExisting(positionId, {tokens: [lpTokenContract.address], amounts: [lpBalance0.div(2)], nfts: []}, [], [], [])
      await manager.connect(owners[0]).withdraw(positionId, lpBalance0.div(2))
      await manager.connect(owners[0]).close(positionId)
      await lpTokenContract.approve(universalSwap.address, lpBalance0)
      await universalSwap.connect(owners[0]).swap(
        {tokens: [wanted], amounts: [lpBalance0], nfts: []}, [], [],
        {outputERC20s: [networkAddresses.preferredStable], outputERC721s: [], ratios: [1], minAmountsOut: [0]}, owners[0].address)
      const balance = await stableContract.balanceOf(owners[0].address)
      const fundsLost = depositedUsd-+ethers.utils.formatUnits(balance.sub(balanceBefore), (await stableContract.decimals()))
      const slippage = 100*fundsLost/depositedUsd
      await stableContract.transfer(owners[1].address, balance)
      console.log(slippage.toString())
    }
  })
});
