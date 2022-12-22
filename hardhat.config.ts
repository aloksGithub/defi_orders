import { HardhatUserConfig, task } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import "@nomiclabs/hardhat-ethers";
require('dotenv').config();
require("@nomiclabs/hardhat-etherscan");
import deployments from "./constants/deployments.json"
import '@openzeppelin/hardhat-upgrades';
require('hardhat-contract-sizer');
require('solidity-coverage')
require('@typechain/hardhat')
require('@nomiclabs/hardhat-ethers')
import "solidity-coverage"
import { ethers } from "ethers";

const rpcs = {
  bsc: process.env.BSC_RPC!,
  bscTestnet: process.env.BSC_TESTNET_RPC!,
  mainnet: process.env.ETHEREUM_RPC!
}

const approximateGasPrices = {
  bsc: 7*10**9,
  mainnet: 35*10**9
}

const config: HardhatUserConfig = {
  solidity: {
    compilers: [
      {
        version: "0.8.9",
        settings: {
          optimizer: {
            enabled: true,
            runs: 500,
          },
        },
      },
      {
        version: "0.6.7",
        settings: {},
      },
    ],
  },
  networks: {
    hardhat: {
      allowUnlimitedContractSize: true,
      forking: {
        // @ts-ignore
        url: rpcs[process.env.CURRENTLY_FORKING!],
      },
      chainId: 1337,
        // @ts-ignore
      gasPrice: approximateGasPrices[process.env.CURRENTLY_FORKING!]
    },
    localhost: {
      url: "http://127.0.0.1:8545/",
      timeout: 100000000,
      // @ts-ignore
      gasPrice: approximateGasPrices[process.env.CURRENTLY_FORKING!]
    },
    bsc: {
      url: process.env.BSC_RPC!,
      accounts: [process.env.BSC_ACCOUNT!]
    },
    bscTestnet: {
      url: process.env.BSC_TESTNET_RPC,
      accounts: [process.env.BSC_TESTNET_ACCOUNT!]
    },
    mainnet: {
      url: process.env.ETHEREUM_RPC,
      // accounts: [process.env.ETHEREUM_ACCOUNT!]
    },
    goerli: {
      url: process.env.ETHEREUM_TESTNET_RPC,
      // accounts: [process.env.ETHEREUM_TESTNET_ACCOUNT!]
    }
  },
  etherscan: {
    apiKey: {
        mainnet: process.env.ETHERSCAN_API_KEY!,
        goerli: process.env.ETHERSCAN_API_KEY!,
        bsc: process.env.BSCSCAN_API_KEY!,
        bscTestnet: process.env.BSCSCAN_API_KEY!,
    },
  },
  mocha: {
    timeout: 100000000
  },
};

// task("estimate_value_ERC20", "Estimates the value of an ERC20 asset")
// .addParam("account", "Owner of asset")
// .addParam("asset", "address of asset")
// .addParam("amount", "amount of asset")
// .addParam("currency", "Value in terms of")
// .setAction(async ({account, asset, amount, currency}) => {
//   // @ts-ignore
//   const [gasAccount] = await ethers.getSigners()
//   await gasAccount.sendTransaction({to: account, value: (await gasAccount.getBalance()).div(2)})
//   // @ts-ignore
//   await network.provider.request({method: "hardhat_impersonateAccount", params: [account]})
//   // @ts-ignore
//   const signer = await ethers.getSigner(account)
//   // @ts-ignore
//   const addresses = deployments.localhost
//   // @ts-ignore
//   const universalSwap = await ethers.getContractAt("UniversalSwap", addresses.universalSwap)
//   // @ts-ignore
//   const assetContract = await ethers.getContractAt("IERC20", asset)
//   // @ts-ignore
//   const currencyContract = await ethers.getContractAt("IERC20", currency)
//   await assetContract.connect(signer).approve(universalSwap.address, amount)
//   const valueBefore = await currencyContract.balanceOf(account)
//   await universalSwap.connect(signer)["swap(address[],uint256[],address,uint256)"]([asset], [amount], currency, 0)
//   const valueAfter = await currencyContract.balanceOf(account)
//   console.log(valueAfter.sub(valueBefore).toString())
//   return valueAfter.sub(valueBefore)
// })

// task("estimate_value_UniswapV3", "Estimates the value of an ERC721 asset")
// .addParam("account", "Owner of asset")
// .addParam("asset", "address of asset")
// .addParam("id", "token ID of asset")
// .addParam("currency", "Value in terms of")
// .setAction(async ({account, asset, id, currency}) => {
//   // @ts-ignore
//   const [gasAccount] = await ethers.getSigners()
//   await gasAccount.sendTransaction({to: account, value: (await gasAccount.getBalance()).div(2)})
//   // @ts-ignore
//   await network.provider.request({method: "hardhat_impersonateAccount", params: [account]})
//   // @ts-ignore
//   const signer = await ethers.getSigner(account)
//   // @ts-ignore
//   const addresses = deployments.localhost
//   // @ts-ignore
//   const universalSwap = await ethers.getContractAt("UniversalSwap", addresses.universalSwap)
//   // @ts-ignore
//   const assetContract = await ethers.getContractAt("INonfungiblePositionManager", asset)
//   // @ts-ignore
//   const currencyContract = await ethers.getContractAt("IERC20", currency)
//   const position = await assetContract.positions(id)
//   const factory = await assetContract.factory()
//   // @ts-ignore
//   const factoryContract = await ethers.getContractAt("IUniswapV3Factory", factory)
//   const pool = factoryContract.getPool(position.token0, position.token1, position.fee)
//   await assetContract.connect(signer).approve(universalSwap.address, id)
//   const valueBefore = await currencyContract.balanceOf(account)
//   await universalSwap.connect(signer).swapNFT({pool, manager:asset, tokenId: id, data:[]}, currency)
//   const valueAfter = await currencyContract.balanceOf(account)
//   console.log(valueAfter.sub(valueBefore).toString())
//   return valueAfter.sub(valueBefore)
// })

export default config;
