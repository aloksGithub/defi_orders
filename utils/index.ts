import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { ethers, upgrades } from "hardhat";
import hre from "hardhat";
import { PositionsManager, UniversalSwap } from "../typechain-types";
import { BigNumber, constants, Contract } from "ethers";
import { expect } from "chai";
import { addresses as ethereumAddresses } from "../constants/ethereum_addresses.json";
import { addresses as bscAddresses } from "../constants/bsc_addresses.json";
import { addresses as bscTestnetAddresses } from "../constants/bsc_testnet_addresses.json";
import { getAssets, SupportedNetworks } from "./protocolDataGetter";
import { getSwapsAndConversionsFromProvidedAndDesired } from "./routeCalculator";

// @ts-ignore
const CURRENTLY_FORKING: SupportedNetworks = process.env.CURRENTLY_FORKING!;

const delay = (ms: number) => new Promise((res) => setTimeout(res, ms));

export interface MasterChef {
  address: string
  rewardGetter: string
  reward: string
  pendingRewardsGetter: string
  hasExtraRewards: boolean
}

interface Addresses {
  preferredStable: string
  networkToken: string
  commonPoolTokens: string[]
  uniswapV2Routers: string[]
  uniswapV2RouterFees: number[]
  uniswapV2Factories: string[]
  uniswapV3Factories: string[]
  uniswapV3Routers: string[]
  NFTManagers: string[]
  v1MasterChefs: MasterChef[]
  v2MasterChefs: MasterChef[]
  masterChefLps: string[]
  erc20BankLps: string[]
  universwalSwapTestingTokens: string[]
  nftBasaedPairs: string[]
  pancakeV2MasterChef?: MasterChef
  aaveV1LendingPool?: string
  aaveV2LendingPool?: string
  aaveV3LendingPool?: string
}

export const addresses: {[network: string]:Addresses} = {
  mainnet: ethereumAddresses,
  bsc: bscAddresses,
  bscTestnet: bscTestnetAddresses
};
addresses.localhost = addresses[CURRENTLY_FORKING];
addresses.hardhat = addresses[CURRENTLY_FORKING];

export async function getNetworkToken(signer: any, ether: string) {
  const network = hre.network.name;
  // @ts-ignore
  const wethContract = await ethers.getContractAt("IWETH", addresses[network].networkToken);
  await wethContract.connect(signer).deposit({ value: ethers.utils.parseEther(ether) });
  const balance = await wethContract.balanceOf(signer.address);
  return { balance, wethContract };
}

export const getLPToken = async (
  lpToken: string,
  universalSwap: UniversalSwap,
  etherAmount: string,
  owner: SignerWithAddress
) => {
  const network = hre.network.name;
  // @ts-ignore
  const wethContract = await ethers.getContractAt("IWETH", addresses[network].networkToken);
  await wethContract.connect(owner).approve(universalSwap.address, ethers.utils.parseEther(etherAmount));
  const lpTokenContract = lpToken != constants.AddressZero ? await ethers.getContractAt("ERC20", lpToken) : undefined;
  const balanceBefore =
    lpToken != constants.AddressZero ? await lpTokenContract!.balanceOf(owner.address) : await owner.getBalance();
  // @ts-ignore
  await universalSwap
    .connect(owner)
    .swap(
      // @ts-ignore
      { tokens: [addresses[network].networkToken], amounts: [ethers.utils.parseEther(etherAmount)], nfts: [] },
      [],
      [],
      { outputERC20s: [lpToken], outputERC721s: [], ratios: [1], minAmountsOut: [0] },
      owner.address
    );
  const balanceAfter =
    lpToken != constants.AddressZero ? await lpTokenContract!.balanceOf(owner.address) : await owner.getBalance();
  return { lpBalance: balanceAfter.sub(balanceBefore), lpTokenContract };
};

export const depositNew = async (
  manager: PositionsManager,
  lpToken: string,
  amount: string,
  liquidationPoints: any[],
  owner: any
) => {
  const lpTokenContract = lpToken != constants.AddressZero ? await ethers.getContractAt("ERC20", lpToken) : undefined;
  const [banks, tokenIds] = await manager.recommendBank(lpToken);
  const bankAddress = banks.slice(-1)[0];
  const tokenId = tokenIds.slice(-1)[0];
  await lpTokenContract?.connect(owner).approve(manager.address, amount);
  const numPositions = await manager.numPositions();
  const bank = await ethers.getContractAt("BankBase", bankAddress);
  const rewards = await bank.getRewards(tokenId);
  const rewardContracts = await Promise.all(rewards.map(async (r: any) => await ethers.getContractAt("ERC20", r)));
  const position = {
    user: owner.address,
    bank: bankAddress,
    bankToken: tokenId,
    amount,
    liquidationPoints,
  };
  const tokens = lpToken != constants.AddressZero ? [lpToken] : [];
  const amounts = lpToken != constants.AddressZero ? [amount] : [];
  await manager
    .connect(owner)
    .deposit(position, tokens, amounts, { value: lpToken === constants.AddressZero ? amount : "0" });
  return { positionId: numPositions, rewards, rewardContracts };
};

export const getNearestUsableTick = (currentTick: number, space: number) => {
  // 0 is always a valid tick
  if (currentTick == 0) {
    return 0;
  }
  // Determines direction
  const direction = currentTick >= 0 ? 1 : -1;
  // Changes direction
  currentTick *= direction;
  // Calculates nearest tick based on how close the current tick remainder is to space / 2
  let nearestTick =
    currentTick % space <= space / 2
      ? currentTick - (currentTick % space)
      : currentTick + (space - (currentTick % space));
  // Changes direction back
  nearestTick *= direction;

  return nearestTick;
};

export const getNFT = async (
  universalSwap: UniversalSwap,
  etherAmount: string,
  manager: string,
  pool: string,
  owner: any
) => {
  const network = hre.network.name;
  // @ts-ignore
  const networkToken = addresses[network].networkToken;
  const networkTokenContract = await ethers.getContractAt("IERC20", networkToken);
  await networkTokenContract.connect(owner).approve(universalSwap.address, ethers.utils.parseEther(etherAmount));
  const abi = ethers.utils.defaultAbiCoder;
  const poolContract = await ethers.getContractAt("IUniswapV3Pool", pool);
  const { tick } = await poolContract.slot0();
  const tickSpacing = await poolContract.tickSpacing();
  const nearestTick = getNearestUsableTick(tick, tickSpacing);
  const data = abi.encode(
    ["int24", "int24", "uint256", "uint256"],
    [nearestTick - 2500 * tickSpacing, nearestTick + 20 * tickSpacing, 0, 0]
  );
  const tx = await universalSwap.connect(owner).swap(
    { tokens: [networkToken], amounts: [ethers.utils.parseEther((+etherAmount).toString())], nfts: [] },
    [],
    [],
    {
      outputERC20s: [],
      outputERC721s: [{ pool, manager, tokenId: 0, liquidity: 0, data }],
      ratios: [1],
      minAmountsOut: [],
    },
    owner.address
  );
  const rc = await tx.wait();
  const event = rc.events?.find((event: any) => event.event === "NFTMinted");
  // @ts-ignore
  const [managerAddress, id] = event?.args;
  return id;
};

export const depositNewNFT = async (
  manager: PositionsManager,
  nftManager: string,
  id: string,
  liquidationPoints: any[],
  owner: any
) => {
  const [banks] = await manager.recommendBank(nftManager);
  const bankAddress = banks.slice(-1)[0];
  const managerContract = await ethers.getContractAt("IERC721", nftManager);
  await managerContract.connect(owner).approve(manager.address, id);
  const numPositions = await manager.numPositions();
  const bank = await ethers.getContractAt("ERC721Bank", bankAddress);
  const bankToken = await bank.encodeId(id, nftManager);
  const rewards = await bank.getRewards(bankToken);
  const rewardContracts = await Promise.all(rewards.map(async (r: any) => await ethers.getContractAt("ERC20", r)));
  const position = {
    user: owner.address,
    bank: bankAddress,
    bankToken,
    amount: 0,
    liquidationPoints,
  };
  await manager.connect(owner).deposit(position, [nftManager], [id]);
  return { positionId: numPositions, rewards, rewardContracts };
};

export const checkNFTLiquidity = async (manager: string, id: string) => {
  const nftManager = await ethers.getContractAt("INonfungiblePositionManager", manager);
  const data = await nftManager.positions(id);
  return data.liquidity;
};

export const isRoughlyEqual = (a: BigNumber, b: BigNumber, percentage: number = 100) => {
  expect(a).to.lessThanOrEqual(b.mul(10000 + percentage).div("10000"));
  expect(a).to.greaterThanOrEqual(b.mul(10000 - percentage).div("10000"));
};

export { getAssets };
export { getSwapsAndConversionsFromProvidedAndDesired as calculateRoute };
