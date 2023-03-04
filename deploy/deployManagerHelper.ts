import { ethers } from "hardhat";
import { DeployFunction } from "hardhat-deploy/types";
import { ManagerHelper } from "../typechain-types";

const deployManagerHelper: DeployFunction = async function ({ getNamedAccounts, deployments, network }) {
  const { deploy } = deployments;
  const namedAccounts = await getNamedAccounts();
  const { deployer } = namedAccounts;
  const manager = await deployments.get('PositionsManager')
  await deploy("ManagerHelper", {
    from: deployer,
    contract: 'ManagerHelper',
    proxy: {
      owner: deployer,
      proxyContract: 'OpenZeppelinTransparentProxy',
      execute: {
        init: {
          methodName: 'initialize',
          args: [manager.address],
        }
      }
    },
    log: true
  })
};

module.exports = deployManagerHelper;
module.exports.tags = ["ManagerHelper"];
module.exports.dependencies = ["PositionsManager"];
