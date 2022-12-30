require("dotenv").config();

const currentlyForking = process.env.CURRENTLY_FORKING;

let skipFiles;

if (currentlyForking === "bsc") {
  skipFiles = [
    "libraries/TickMath.sol",
    "libraries/LiquidityAmounts.sol",
    "libraries/FullMath.sol",
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
