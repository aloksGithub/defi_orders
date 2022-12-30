import { ethers } from "hardhat";
import deployments from "../constants/deployments.json";
import hre from "hardhat";
require("dotenv").config();

async function main() {
  const [owner] = await ethers.getSigners();
  // @ts-ignore
  const positionManager = await ethers.getContractAt(
    "PositionsManager",
    deployments[hre.network.name].positionsManager
  );
  const universalSwapAddress = await positionManager.universalSwap();
  const universalSwap = await ethers.getContractAt("UniversalSwap", universalSwapAddress);

  const numPositions = await positionManager.numPositions();
  const positions = Array.from(Array(numPositions.toNumber()).keys());
  const promises = positions.map(async (position) => {
    const { index, liquidate } = await positionManager.checkLiquidate(position);
    if (liquidate) {
      const {
        underlyingTokens,
        underlyingAmounts,
        rewardTokens,
        rewardAmounts,
        position: { liquidationPoints },
      } = await positionManager.getPosition(position);
      const liquidateTo = liquidationPoints[index.toNumber()].liquidateTo;
      const { swaps, conversions } = await universalSwap.preSwapCalculateSwaps(
        {
          tokens: underlyingTokens.concat(rewardTokens),
          amounts: underlyingAmounts.concat(rewardAmounts),
          nfts: [],
        },
        {
          outputERC20s: [liquidateTo],
          outputERC721s: [],
          minAmountsOut: [0],
          ratios: [1],
        }
      );
      await positionManager.botLiquidate(position, index, swaps, conversions, { from: owner.address });
    }
  });
  await Promise.all(promises);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
