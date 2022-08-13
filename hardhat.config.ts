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
        url: process.env.QUICKNODE_BSC!,
      }
    },
    bsc: {
      url: 'http://127.0.0.1:8545',
      forking: {
        url: process.env.QUICKNODE_BSC!,
      }
    }
  },
  mocha: {
    timeout: 100000000
  },
};

export default config;
