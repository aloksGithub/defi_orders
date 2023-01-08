import { ethers } from 'hardhat';
import {DeployFunction} from 'hardhat-deploy/types';

const deployBank: DeployFunction = async function ({getNamedAccounts, deployments, network}) {
  const {deploy} = deployments;
  const namedAccounts = await getNamedAccounts();
  const {deployer} = namedAccounts;
  const positionsManager = await deployments.get('PositionsManager')
  const bank = await deploy('ERC20Bank', {
    from: deployer,
    contract: 'ERC20Bank',
    args: [positionsManager.address],
    log: true
  });
  const positionsManagerContract = await ethers.getContractAt("PositionsManager", positionsManager.address)
  await positionsManagerContract.addBank(bank.address)
};

module.exports = deployBank
module.exports.tags = ['ECR20Bank'];
module.exports.dependencies = ["PositionsManager"];