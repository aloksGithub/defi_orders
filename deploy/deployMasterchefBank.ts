import { ethers } from 'hardhat';
import {DeployFunction, DeployOptions, DeployResult} from 'hardhat-deploy/types';
import { addresses, MasterChef } from '../utils';

const deployWrappers = async function (
  deployer: string,
  deploy: (name: string, options: DeployOptions) => Promise<DeployResult>,
  masterChefs: MasterChef[],
  wrapperVersion: string
) {
  const wrappers: string[] = []
  for (const [index, masterChef] of masterChefs.entries()) {
    const wrapper = await deploy(`${wrapperVersion}_${index}`, {
      from: deployer,
      contract: wrapperVersion,
      args: [
        masterChef.address,
        masterChef.reward,
        masterChef.pendingRewardsGetter
      ]
    })
    wrappers.push(wrapper.address)
  }
  return wrappers
}

const deployBank: DeployFunction = async function ({getNamedAccounts, deployments, network}) {
  const {deploy} = deployments;
  const namedAccounts = await getNamedAccounts();
  const {deployer} = namedAccounts;
  const wrappersV1 = await deployWrappers(deployer, deploy, addresses[network.name].v1MasterChefs, 'MasterChefV1Wrapper')
  const wrappersV2 = await deployWrappers(deployer, deploy, addresses[network.name].v2MasterChefs, 'MasterChefV2Wrapper')
  const chefs = addresses[network.name].v1MasterChefs.concat(addresses[network.name].v2MasterChefs)
  const wrappers = wrappersV1.concat(wrappersV2)
  if (network.name==="bsc" || ((network.name==="localhost" || network.name==="hardhat") && process.env.CURRENTLY_FORKING==="bsc")) {
    const masterChef = addresses["bsc"].pancakeV2MasterChef;
    const wrapper = await deploy('PancakeSwapMasterChefV2Wrapper', {
      from: deployer,
      contract: 'PancakeSwapMasterChefV2Wrapper',
      args: [
        masterChef!.address,
        masterChef!.reward,
        masterChef!.pendingRewardsGetter
      ]
    })
    chefs.push(masterChef!)
    wrappers.push(wrapper.address)
  }
  const positionsManager = await deployments.get('PositionsManager')
  const bank = await deploy('MasterChefBank', {
    from: deployer,
    contract: 'MasterChefBank',
    args: [positionsManager.address],
    log: true
  });
  const bankContract = await ethers.getContractAt("MasterChefBank", bank.address)
  for (const [index, wrapper] of wrappers.entries()) {
    bankContract.setMasterChefWrapper(chefs[index].address, wrapper)
  }
  const positionsManagerContract = await ethers.getContractAt("PositionsManager", positionsManager.address)
  await positionsManagerContract.addBank(bank.address)
};

module.exports = deployBank
module.exports.tags = ['MasterChefBank'];
module.exports.dependencies = ["PositionsManager"];