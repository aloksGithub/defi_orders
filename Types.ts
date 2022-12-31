import { UniversalSwap, IOracle, ISwapper, IERC20 } from "./typechain-types";

export interface SwapContracts {
  universalSwap: UniversalSwap;
  oracle: IOracle;
  swappers: ISwapper[];
  networkToken: IERC20;
}