import { DeployFunction } from "hardhat-deploy/types";
import { addresses } from "../utils";

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
