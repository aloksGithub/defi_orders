require("dotenv").config();

const currentlyForking = process.env.CURRENTLY_FORKING;

let skipFiles;

if (currentlyForking === "bsc") {
  skipFiles = [
    "interfaces",
    "PoolInteractors/UniswapV3PoolInteractor.sol",
    "PoolInteractors/AaveV2PoolInteractor.sol",
  ];
} else if (currentlyForking === "mainnet") {
  skipFiles = ["interfaces", "PoolInteractors/VenusPoolInteractor.sol"];
}

module.exports = {
  skipFiles,
  configureYulOptimizer: true,
};
