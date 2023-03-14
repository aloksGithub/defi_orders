import { ethers } from "hardhat";
import { DeployFunction } from "hardhat-deploy/types";
import { PositionsManager } from "../typechain-types";
import { addresses } from "../utils";

const deployPositionsManager: DeployFunction = async function ({ getNamedAccounts, deployments, network }) {
  const { deploy } = deployments;
  const namedAccounts = await getNamedAccounts();
  const { deployer } = namedAccounts;
  const universalSwap = await deployments.get('UniversalSwap')
  const deployedManager = await deploy("PositionsManager", {
    from: deployer,
    contract: 'PositionsManager',
    proxy: {
      owner: deployer,
      proxyContract: 'OpenZeppelinTransparentProxy',
      execute: {
        init: {
          methodName: 'initialize',
          args: [universalSwap.address, addresses[network.name].preferredStable],
        }
      }
    },
    log: true
  })
  if (deployedManager.newlyDeployed) {
    const manager: PositionsManager = await ethers.getContractAt("PositionsManager", deployedManager.address)
    await manager.setKeeper(addresses[network.name].keeper, true)
  }
};

module.exports = deployPositionsManager;
module.exports.tags = ["PositionsManager"];
module.exports.dependencies = ["UniversapSwap"];
