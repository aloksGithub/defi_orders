import { BigNumber, constants } from "ethers";
import { ethers } from "hardhat";
import { ISwapper, ERC20__factory, ISwapper__factory } from "../typechain-types";
import { ProvidedStruct, SwapPointStruct } from "../typechain-types/contracts/PositionsManager";
import { DesiredStruct } from "../typechain-types/contracts/UniversalSwap";
import { parseUnits } from "ethers/lib/utils";
import { SwapContracts } from "../Types";

const eighteen = ethers.BigNumber.from("1000000000000000000");

const logSwap = (swap: SwapPointStruct) => {
  console.log("Swapping ", swap.tokenIn, " for ", swap.tokenOut);
  console.log("Amount in: ", swap.amountIn.toString(), " Value in: ", swap.valueIn.toString());
  console.log("Amount out: ", swap.amountOut.toString(), " Value out: ", swap.valueOut.toString());
  console.log("Swappers used:");
  for (let i = 0; i < swap.swappers.length; i++) {
    console.log(swap.swappers[i]);
    console.log("Path used:");
    for (let j = 0; j < swap.paths[i].length; j++) {
      console.log(swap.paths[i][j]);
    }
    console.log("___________________");
  }
};

export const findMultipleSwaps = async (
  contracts: SwapContracts,
  inputTokens: string[],
  inputAmounts: BigNumber[],
  inputValues: BigNumber[],
  outputTokens: string[],
  outputValues: BigNumber[]
) => {
  const routes: SwapPointStruct[] = [];
  const prices = outputTokens.map(
    async (token) => await contracts.oracle.getPrice(token, contracts.networkToken.address)
  );
  const decimals = outputTokens.map(async (token) => await (ERC20__factory.connect(token, contracts.universalSwap.provider)).decimals());
  const tokenData = await Promise.all([...prices, ...decimals]);
  const tokenPrices: { [token: string]: BigNumber } = tokenData.slice(0, prices.length).reduce((acc, curr, index) => {
    return { ...acc, [outputTokens[index]]: curr };
  }, {});
  const tokenDecimals: { [token: string]: number } = tokenData.slice(prices.length).reduce((acc, curr, index) => {
    return { ...acc, [outputTokens[index]]: curr };
  }, {});
  for (const [i, inToken] of inputTokens.entries()) {
    for (const [j, outToken] of outputTokens.entries()) {
      const route = await findBestRoute(
        contracts,
        tokenPrices[outToken],
        tokenDecimals[outToken],
        inToken,
        outToken,
        outputValues[j],
        inputAmounts[i],
        inputValues[i]
      )
      routes.push(
        route
      );
    }
  }
  const sortedSwaps = routes.sort((a, b) => (BigNumber.from(a.slippage).gt(BigNumber.from(b.slippage)) ? 1 : -1));
  let bestSwaps: SwapPointStruct[] = [];
  const valuesUsed: BigNumber[] = Array(inputTokens.length).fill(BigNumber.from(0));
  const valuesProvided: BigNumber[] = Array(outputTokens.length).fill(BigNumber.from(0));
  for (const swap of sortedSwaps) {
    const valueIn: BigNumber = BigNumber.from(swap.valueIn);
    const tokenInIndex = inputTokens.findIndex((token) => token === swap.tokenIn);
    const tokenOutIndex = outputTokens.findIndex((token) => token === swap.tokenOut);
    if (swap.tokenIn === constants.AddressZero || swap.tokenOut === constants.AddressZero) continue;
    if (
      valuesUsed[tokenInIndex].lt(inputValues[tokenInIndex]) &&
      valuesProvided[tokenOutIndex].lt(outputValues[tokenOutIndex])
    ) {
      const moreValueInAvailable = inputValues[tokenInIndex].sub(valuesUsed[tokenInIndex]);
      const moreValueOutNeeded = outputValues[tokenOutIndex].sub(valuesProvided[tokenOutIndex]);
      let valueInAdjusted = moreValueInAvailable.gte(valueIn) ? valueIn : moreValueInAvailable;
      valueInAdjusted = valueInAdjusted.gt(moreValueOutNeeded) ? moreValueOutNeeded : valueInAdjusted;
      bestSwaps.push({
        ...swap,
        amountIn: valueInAdjusted.mul(inputAmounts[tokenInIndex]).div(inputValues[tokenInIndex]),
        valueIn: valueInAdjusted,
        amountOut: valueInAdjusted.mul(BigNumber.from(swap.amountOut)).div(BigNumber.from(swap.valueIn)),
      });
      valuesUsed[tokenInIndex] = valuesUsed[tokenInIndex].add(valueInAdjusted);
      valuesProvided[tokenOutIndex] = valuesProvided[tokenOutIndex].add(valueInAdjusted);
      continue;
    }
  }
  bestSwaps = bestSwaps.filter((swap) => swap.tokenIn != constants.AddressZero && swap.amountIn > 0);
  for (const swap of bestSwaps) {
    swap.amountIn = eighteen
      .mul(BigNumber.from(swap.amountIn))
      .div(inputAmounts[inputTokens.findIndex((token) => token === swap.tokenIn)]);
  }
  return bestSwaps;
};

const recommendConnectors = async (
  swappers: ISwapper[],
  tokenIn: string,
  tokenOut: string,
  amount: BigNumber,
  connectorTokens: string[] | undefined = undefined
) => {
  let commonPoolTokens: string[];
  if (!connectorTokens) {
    commonPoolTokens = await swappers[0].getCommonPoolTokens();
  } else {
    commonPoolTokens = connectorTokens;
  }
  let scoresIn: Promise<{ swapper: string; amount: BigNumber; token: string }>[] = [];
  let scoresOut: Promise<{
    swapper: string;
    amount: BigNumber;
    token: string;
  }>[] = [];
  for (const swapper of swappers) {
    scoresIn = [
      ...scoresIn,
      ...commonPoolTokens.map(async (token) => {
        return {
          swapper: swapper.address,
          amount: await swapper.getAmountOut(amount, [tokenIn, token, tokenIn]),
          token,
        };
      }),
    ];
  }
  for (const swapper of swappers) {
    scoresOut = [
      ...scoresOut,
      ...commonPoolTokens.map(async (token) => {
        return {
          swapper: swapper.address,
          amount: await swapper.getAmountOut(amount, [tokenOut, token, tokenOut]),
          token,
        };
      }),
    ];
  }
  const allScores = await Promise.all([...scoresIn, ...scoresOut]);
  let bestScoreIn = BigNumber.from(0);
  let bestInToken = { swapper: "", amount: BigNumber.from(0), token: "" };
  for (const score of allScores.slice(0, swappers.length * commonPoolTokens.length)) {
    if (score.amount.gt(bestScoreIn)) {
      bestScoreIn = score.amount;
      bestInToken = score;
    }
  }
  let bestScoreOut = BigNumber.from(0);
  let bestOutToken = { swapper: "", amount: BigNumber.from(0), token: "" };
  for (const score of allScores.slice(swappers.length * commonPoolTokens.length)) {
    if (score.amount.gt(bestScoreOut)) {
      bestScoreOut = score.amount;
      bestOutToken = score;
    }
  }
  return { bestInToken, bestOutToken };
};

const evaluateRoute = async (contracts: SwapContracts, swappers: string[], paths: string[][], amount: BigNumber) => {
  let currentAmount = amount;
  for (const [index, swapper] of swappers.entries()) {
    const path = paths[index];
    const swapperContract = ISwapper__factory.connect(swapper, contracts.universalSwap.provider)
    currentAmount = await swapperContract.getAmountOut(currentAmount, path);
  }
  return currentAmount;
};

const findBestRoute = async (
  contracts: SwapContracts,
  tokenPrice: BigNumber,
  decimals: number,
  tokenIn: string,
  tokenOut: string,
  valueNeeded: BigNumber,
  amountInAvailable: BigNumber,
  valueInAvailable: BigNumber
) => {
  const amountIn = valueNeeded.gt(valueInAvailable)
    ? amountInAvailable
    : valueNeeded.mul(amountInAvailable).div(valueInAvailable);
  const valueIn = amountIn.mul(valueInAvailable).div(amountInAvailable);
  const swapperAddresses = await contracts.universalSwap.getSwappers();
  const swappers = await Promise.all(
    swapperAddresses.map(async (address) => ISwapper__factory.connect(address, contracts.universalSwap.provider))
  );
  const connectors = await recommendConnectors(swappers, tokenIn, tokenOut, amountIn);
  const allRoutes = swappers.map((swapper) => {
    return { paths: [[tokenIn, tokenOut]], swappers: [swapper.address] };
  });
  allRoutes.push({
    paths: [[tokenIn, connectors.bestInToken.token, tokenOut]],
    swappers: [connectors.bestInToken.swapper],
  });
  allRoutes.push({
    paths: [[tokenIn, connectors.bestOutToken.token, tokenOut]],
    swappers: [connectors.bestOutToken.swapper],
  });
  if (connectors.bestInToken.swapper === connectors.bestOutToken.swapper) {
    allRoutes.push({
      paths: [[tokenIn, connectors.bestInToken.token, connectors.bestOutToken.token, tokenOut]],
      swappers: [connectors.bestOutToken.swapper],
    });
  } else {
    allRoutes.push({
      paths: [
        [tokenIn, connectors.bestInToken.token],
        [connectors.bestInToken.token, connectors.bestOutToken.token, tokenOut],
      ],
      swappers: [connectors.bestInToken.swapper, connectors.bestOutToken.swapper],
    });
  }
  let maxOut = BigNumber.from(0);
  let bestRoute = allRoutes[0];
  const allScores = await Promise.all(
    allRoutes.map(async (route) => evaluateRoute(contracts, route.swappers, route.paths, amountIn))
  );
  for (const [index, score] of allScores.entries()) {
    if (score.gt(maxOut)) {
      maxOut = score;
      bestRoute = allRoutes[index];
    }
  }
  const valueOut = tokenPrice.mul(maxOut).div(parseUnits("1", decimals));
  const slippage = parseUnits("1", 12).mul(valueIn.sub(valueOut)).div(valueIn);
  const swapPoint: SwapPointStruct = {
    amountIn,
    valueIn,
    amountOut: maxOut,
    valueOut,
    slippage,
    tokenIn,
    swappers: bestRoute.swappers,
    tokenOut,
    paths: bestRoute.paths,
  };
  return swapPoint;
};

export const getSwapsAndConversionsFromProvidedAndDesired = async (contracts: SwapContracts, provided: ProvidedStruct, desired: DesiredStruct) => {
  const [tokens, amounts, inputTokenValues, conversions, conversionUnderlying, conversionUnderlyingValues] =
    await contracts.universalSwap.preSwapCalculateUnderlying(provided, desired);
  const swaps = await findMultipleSwaps(
    contracts,
    tokens,
    amounts,
    inputTokenValues,
    conversionUnderlying,
    conversionUnderlyingValues
  );
  return { swaps, conversions };
};
