import { HardhatRuntimeEnvironment, Network } from "hardhat/types";
import { DeployFunction, DeployOptions, DeployResult } from "hardhat-deploy/types";
import { SupportedNetworks } from "../utils/protocolDataGetter";
import { addresses } from "../utils";

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

const deployUniswapV2PoolInteractor = async function (deployer: string, deploy: (name: string, options: DeployOptions) => Promise<DeployResult>, network: Network) {
  const uniswapV2PoolInteractor = await deploy(`UniswapV2PoolInteractor`, {
    from: deployer,
    contract: "UniswapV2PoolInteractor",
    args: [],
  })
  return uniswapV2PoolInteractor.address
}

const deployVenusInteractor = async function (deployer: string, deploy: (name: string, options: DeployOptions) => Promise<DeployResult>, network: Network) {
  if (network.name==='mainnet') {
    const deployed = await deploy(`VenusPoolInteractor`, {
      from: deployer,
      contract: "VenusPoolInteractor",
      args: [],
      log: true
    })
    return deployed.address
  }
  return ''
};

const deployAAVEInteractor = async function (deployer: string, deploy: (name: string, options: DeployOptions) => Promise<DeployResult>, network: Network) {
  if (network.name==='mainnet') {
    const deployed = await deploy(`AaveV2PoolInteractor`, {
      from: deployer,
      contract: "AaveV2PoolInteractor",
      args: [
        addresses["mainnet"].aaveV1LendingPool!,
        addresses["mainnet"].aaveV2LendingPool!,
        addresses["mainnet"].aaveV3LendingPool!
      ],
      log: true
    })
    return deployed.address
  }
  return ''
}

const deployNFTInteractors = async function (deployer: string, deploy: (name: string, options: DeployOptions) => Promise<DeployResult>, network: Network) {
  const interactors = []
  for (const [index, manager] of addresses[network.name].NFTManagers.entries()) {
    const deployed = await deploy(`UniswapV3PoolInteractor_${index}`, {
      from: deployer,
      contract: 'UniswapV3PoolInteractor',
      args: [manager]
    })
    interactors.push(deployed.address)
  }
  return interactors
}

const deployPositionsManager: DeployFunction = async function ({ getNamedAccounts, deployments, network }) {
  const { deploy } = deployments;
  const namedAccounts = await getNamedAccounts();
  const { deployer } = namedAccounts;
  const universapSwap = await deployments.get('UniversalSwap')
  await deploy("PositionsManager", {
    from: deployer,
    contract: "PositionsManager",
    args: [universapSwap.address, addresses[network.name].preferredStable],
    log: true
  });
};

module.exports = deployPositionsManager;
module.exports.tags = ["PositionsManager"];
module.exports.dependencies = ["UniversapSwap"];
