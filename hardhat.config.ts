import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
require('dotenv').config();

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
        url: process.env.BSC_RPC!,
      }
    },
    bsc: {
      url: process.env.BSC_RPC!,
      // accounts: [process.env.BSC_ACCOUNT!]
    },
    bsc_testnet: {
      url: process.env.BSC_TESTNET_RPC,
      // accounts: [process.env.BSC_TESTNET_ACCOUNT!]
    },
    ethereum: {
      url: process.env.ETHEREUM_RPC,
      // accounts: [process.env.ETHEREUM_ACCOUNT!]
    },
    ethereum_testnet: {
      url: process.env.ETHEREUM_TESTNET_RPC,
      // accounts: [process.env.ETHEREUM_TESTNET_ACCOUNT!]
    }
  },
  mocha: {
    timeout: 100000000
  },
};

export default config;
