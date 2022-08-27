import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import "@nomiclabs/hardhat-ethers";
require('dotenv').config();
require("@nomiclabs/hardhat-etherscan");

const rpcs = {
  bsc: process.env.BSC_RPC!,
  mainnet: process.env.ETHEREUM_RPC!
}

const config: HardhatUserConfig = {
  solidity: {
    version: "0.8.9",
    settings: {
      optimizer: {
        enabled: true,
        runs: 1000,
      },
    },
  },
  networks: {
    hardhat: {
      forking: {
        // @ts-ignore
        url: rpcs[process.env.CURRENTLY_FORKING!],
      }
    },
    localhost: {
      url: "http://127.0.0.1:8545/",
      accounts: ["0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"]
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

export default config;
