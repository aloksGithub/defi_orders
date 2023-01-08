import {DeployFunction} from 'hardhat-deploy/types';
import { addresses } from '../utils';
import { SupportedNetworks } from '../utils/protocolDataGetter';

const deployOracle: DeployFunction = async function ({getNamedAccounts, deployments, network}) {
  // @ts-ignore
  const networkName: SupportedNetworks = network.name
  const {log, deploy} = deployments;
  const namedAccounts = await getNamedAccounts();
  const {deployer} = namedAccounts;
  const sources: string[] = []
  for (const [index, factory] of addresses[networkName].uniswapV2Factories.entries()) {
    const deployed = await deploy(`UniswapV2Source_${index}`, {
      from: deployer,
      contract: 'UniswapV2Source',
      args: [factory, addresses[networkName].commonPoolTokens]
    })
    sources.push(deployed.address)
  }
  for (const [index, factory] of addresses[networkName].uniswapV3Factories.entries()) {
    const deployed = await deploy(`UniswapV3Source_${index}`, {
      from: deployer,
      contract: 'UniswapV3Source',
      args: [factory, addresses[networkName].commonPoolTokens]
    })
    sources.push(deployed.address)
  }
  const deployed = await deploy('BasicOracle', {
    from: deployer,
    contract: 'BasicOracle',
    args: [sources],
    log: true
  });
};

module.exports = deployOracle
module.exports.tags = ['Oracle'];