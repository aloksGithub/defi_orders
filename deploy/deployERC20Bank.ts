import { ethers } from 'hardhat';
import {DeployFunction} from 'hardhat-deploy/types';

const deployBank: DeployFunction = async function ({getNamedAccounts, deployments, network}) {
  const {deploy} = deployments;
  const namedAccounts = await getNamedAccounts();
  const {deployer} = namedAccounts;
  const positionsManager = await deployments.get('PositionsManager')
  await deploy('ERC20Bank', {
    from: deployer,
    contract: 'ERC20Bank',
    args: [positionsManager.address],
    log: true
  });
};

module.exports = deployBank
module.exports.tags = ['ECR20Bank'];
module.exports.dependencies = ["PositionsManager"];