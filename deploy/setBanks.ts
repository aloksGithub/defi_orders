import { ethers } from 'hardhat';
import {DeployFunction} from 'hardhat-deploy/types';

const deployBank: DeployFunction = async function ({getNamedAccounts, deployments, network}) {
  const namedAccounts = await getNamedAccounts();
  const {deployer} = namedAccounts;
  const positionsManagerAddress = (await deployments.get('PositionsManager')).address
  const positionsManager = await ethers.getContractAt("PositionsManager", positionsManagerAddress)
  const erc20Bank = await deployments.get('ERC20Bank')
  const masterChefBank = await deployments.get('MasterChefBank')
  const erc721Bank = await deployments.get('ERC721Bank')
  await positionsManager.setBanks([erc20Bank.address, erc721Bank.address, masterChefBank.address], {from: deployer})
};

module.exports = deployBank
module.exports.tags = ['SetBanks'];
module.exports.dependencies = ["ERC20Bank, MasterChefBank", "ERC721Bank"];