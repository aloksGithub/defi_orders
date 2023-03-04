import { HardhatRuntimeEnvironment, Network } from "hardhat/types";
import { DeployFunction, DeployOptions, DeployResult } from "hardhat-deploy/types";
import { SupportedNetworks } from "../utils/protocolDataGetter";
import { addresses } from "../utils";
import { ethers } from "hardhat";
import { UniversalSwap } from "../typechain-types";

const getSwappers = async (
  network: string,
  deploy: (name: string, options: DeployOptions) => Promise<DeployResult>,
  deployer: string
) => {
  const swappers: string[] = [];
  for (const [index, router] of addresses[network].uniswapV2Routers.entries()) {
    const deployed = await deploy(`UniswapV2Swapper_${index}`, {
      from: deployer,
      contract: "UniswapV2Swapper",
      args: [router, addresses[network].commonPoolTokens],
    });
    swappers.push(deployed.address);
  }
  return swappers;
};

const deployUniswapV2PoolInteractor = async function (
  deployer: string,
  deploy: (name: string, options: DeployOptions) => Promise<DeployResult>,
  network: Network
) {
  const uniswapV2PoolInteractor = await deploy(`UniswapV2PoolInteractor`, {
    from: deployer,
    contract: "UniswapV2PoolInteractor",
    args: [],
  });
  return uniswapV2PoolInteractor.address;
};

const deployVenusInteractor = async function (
  deployer: string,
  deploy: (name: string, options: DeployOptions) => Promise<DeployResult>,
  network: Network
) {
  if (network.name==="bsc" || ((network.name==="localhost" || network.name==="hardhat") && process.env.CURRENTLY_FORKING==="bsc")) {
    const deployed = await deploy(`VenusPoolInteractor`, {
      from: deployer,
      contract: "VenusPoolInteractor",
      args: [],
      log: true,
    });
    return deployed.address;
  }
  return "";
};

const deployAAVEInteractor = async function (
  deployer: string,
  deploy: (name: string, options: DeployOptions) => Promise<DeployResult>,
  network: Network
) {
  if (network.name==="mainnet" || ((network.name==="localhost" || network.name==="hardhat") && process.env.CURRENTLY_FORKING==="mainnet")) {
    const deployed = await deploy(`AaveV2PoolInteractor`, {
      from: deployer,
      contract: "AaveV2PoolInteractor",
      args: [
        addresses["mainnet"].aaveV1LendingPool!,
        addresses["mainnet"].aaveV2LendingPool!,
        addresses["mainnet"].aaveV3LendingPool!,
      ],
      log: true,
    });
    return deployed.address;
  }
  return "";
};

const deployNFTInteractors = async function (
  deployer: string,
  deploy: (name: string, options: DeployOptions) => Promise<DeployResult>,
  network: Network
) {
  const interactors = [];
  for (const [index, manager] of addresses[network.name].NFTManagers.entries()) {
    const deployed = await deploy(`UniswapV3PoolInteractor_${index}`, {
      from: deployer,
      contract: "UniswapV3PoolInteractor",
      args: [manager],
    });
    interactors.push(deployed.address);
  }
  return interactors;
};

const deployHelpers = async function (
  universalSwap: string,
  deployer: string,
  deploy: (name: string, options: DeployOptions) => Promise<DeployResult>,
  network: Network
) {
  const providedHelper = await deploy("ProvidedHelper", {
    from: deployer,
    contract: "ProvidedHelper",
    args: [universalSwap],
    log: true,
  });
  const conversionHelper = await deploy("ConversionHelper", {
    from: deployer,
    contract: "ConversionHelper",
    args: [universalSwap],
    log: true,
  });
  const swapHelper = await deploy("SwapHelper", {
    from: deployer,
    contract: "SwapHelper",
    args: [universalSwap, conversionHelper.address],
    log: true,
  });
  const coreLogic = await deploy("CoreLogic", {
    from: deployer,
    contract: "CoreLogic",
    args: [],
    log: true,
  });
  return {coreLogic, providedHelper, conversionHelper, swapHelper}
}

const deployUniversalSwap: DeployFunction = async function ({ getNamedAccounts, deployments, network }) {
  const { deploy } = deployments;
  const namedAccounts = await getNamedAccounts();
  const { deployer } = namedAccounts;
  const oracle = await deployments.get("BasicOracle");
  const swappers = await getSwappers(network.name, deploy, deployer);
  const uniswapPoolInteractor = await deployUniswapV2PoolInteractor(deployer, deploy, network);
  const venusInteractor = await deployVenusInteractor(deployer, deploy, network);
  const aaveInteractor = await deployAAVEInteractor(deployer, deploy, network);
  const interactors = [uniswapPoolInteractor, venusInteractor, aaveInteractor].filter((address) => address != "");
  const nftInteractors = await deployNFTInteractors(deployer, deploy, network);
  const universalSwap = await deploy("UniversalSwap", {
    from: deployer,
    contract: "UniversalSwap",
    proxy: {
      owner: deployer,
      proxyContract: 'OpenZeppelinTransparentProxy',
      execute: {
        init: {
          methodName: 'initialize',
          args: [
            interactors,
            nftInteractors,
            addresses[network.name].networkToken,
            addresses[network.name].preferredStable,
            swappers,
            oracle.address
          ],
        }
      }
    },
    log: true,
  });
  const universalSwapContract: UniversalSwap = await ethers.getContractAt("UniversalSwap", universalSwap.address, deployer)
  const {coreLogic, providedHelper, conversionHelper, swapHelper} = await deployHelpers(universalSwap.address, deployer, deploy, network);
  if (universalSwap.newlyDeployed) {
    const tx = await universalSwapContract.setHelpers(coreLogic.address, providedHelper.address, conversionHelper.address, swapHelper.address)
    await tx.wait()
  }
};

module.exports = deployUniversalSwap;
module.exports.tags = ["UniversapSwap"];
module.exports.dependencies = ["Oracle"];
