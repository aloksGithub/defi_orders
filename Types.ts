import { UniversalSwap, IOracle, ISwapper, IERC20 } from "./typechain-types";
import { ProvidedHelper } from "./typechain-types/contracts/SwapHelper.sol";

export interface SwapContracts {
  universalSwap: UniversalSwap;
  oracle: IOracle;
  swappers: ISwapper[];
  networkToken: IERC20;
  providedHelper: ProvidedHelper
}