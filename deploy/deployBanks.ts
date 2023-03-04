import { ethers } from 'hardhat';
import {DeployFunction, DeployOptions, DeployResult} from 'hardhat-deploy/types';
import { PositionsManager } from '../typechain-types';
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
  const positionsManagerAddress = (await deployments.get('PositionsManager')).address
  const positionsManager: PositionsManager = await ethers.getContractAt("PositionsManager", positionsManagerAddress)
  const erc20Bank = await deploy('ERC20Bank', {
    from: deployer,
    contract: 'ERC20Bank',
    proxy: {
      owner: deployer,
      proxyContract: 'OpenZeppelinTransparentProxy',
      execute: {
        init: {
          methodName: 'initialize',
          args: [positionsManager.address],
        },
      }
    },
    log: true
  });
  
  const erc721Bank = await deploy('ERC721Bank', {
    from: deployer,
    contract: 'ERC721Bank',
    proxy: {
      owner: deployer,
      proxyContract: 'OpenZeppelinTransparentProxy',
      execute: {
        init: {
          methodName: 'initialize',
          args: [positionsManager.address],
        }
      }
    },
    log: true
  });
  const wrapper = await deploy('UniswapV3Wrapper', {
    from: deployer,
    contract: 'UniswapV3Wrapper',
    args: [],
    log: true
  });
  if (erc721Bank.newlyDeployed) {
    const bankContract = await ethers.getContractAt("ERC721Bank", erc721Bank.address)
    for (const manager of addresses[network.name].NFTManagers) {
      await bankContract.addManager(manager);
      await bankContract.setWrapper(manager, wrapper.address);
    }
  }
  
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
  const masterChefBank = await deploy('MasterChefBank', {
    from: deployer,
    contract: 'MasterChefBank',
    proxy: {
      owner: deployer,
      proxyContract: 'OpenZeppelinTransparentProxy',
      execute: {
        init: {
          methodName: 'initialize',
          args: [positionsManager.address],
        }
      }
    },
    log: true
  });
  if (masterChefBank.newlyDeployed) {
    const bankContract = await ethers.getContractAt("MasterChefBank", masterChefBank.address)
    for (const [index, wrapper] of wrappers.entries()) {
      await bankContract.setMasterChefWrapper(chefs[index].address, wrapper)
    }
  }

  if (masterChefBank.newlyDeployed || erc721Bank.newlyDeployed || erc20Bank.newlyDeployed) {
    await positionsManager.setBanks([erc20Bank.address, erc721Bank.address, masterChefBank.address], {from: deployer})
  }
};

module.exports = deployBank
module.exports.tags = ['Banks'];
module.exports.dependencies = ["PositionsManager"];