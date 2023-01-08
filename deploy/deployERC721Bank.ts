import { ethers } from 'hardhat';
import {DeployFunction} from 'hardhat-deploy/types';
import { addresses } from '../utils';

const deployBank: DeployFunction = async function ({getNamedAccounts, deployments, network}) {
  const {deploy} = deployments;
  const namedAccounts = await getNamedAccounts();
  const {deployer} = namedAccounts;
  const positionsManager = await deployments.get('PositionsManager')
  const bank = await deploy('ERC721Bank', {
    from: deployer,
    contract: 'ERC721Bank',
    args: [positionsManager.address],
    log: true
  });
  const wrapper = await deploy('UniswapV3Wrapper', {
    from: deployer,
    contract: 'UniswapV3Wrapper',
    args: [],
    log: true
  });
  const bankContract = await ethers.getContractAt("ERC721Bank", bank.address)
  for (const manager of addresses[network.name].NFTManagers) {
    await bankContract.addManager(manager);
    await bankContract.setWrapper(manager, wrapper.address);
  }
  const positionsManagerContract = await ethers.getContractAt("PositionsManager", positionsManager.address)
  await positionsManagerContract.addBank(bank.address)
};

module.exports = deployBank
module.exports.tags = ['ERC721Bank'];
module.exports.dependencies = ["PositionsManager"];