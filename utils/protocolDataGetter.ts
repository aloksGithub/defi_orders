import {ethers} from "hardhat";
import fetch from "node-fetch"

type SupportedChains = 56|1
type AllChains = 1|137|8001|56|97|250|4002|1337
type SupportedProcols = 'Pancakeswap' | 'Biswap' | 'Uniswap V2' | 'Sushiswap' | 'ERC20' | 'Uniswap V3' | 'Venus' | 'AAVE'

interface AssetUnderlying {
  contract_name: string;
  contract_ticker_symbol: string;
  contract_address: string;
  contract_decimals: number;
  logo_url: string;
}

interface ProtocolQuery {
  name: SupportedProcols
  url?: string
  query?: string
  manager?: string
  defaultTokens?: string[]
}

export interface Asset {
  contract_name: string;
  contract_ticker_symbol: string;
  contract_address: string;
  contract_decimals: number;
  underlying: AssetUnderlying[]
  logo_url: string;
  protocol_name: string;
  chain_id: number;
  manager?: string;
}

const chainLogos = {
  1: "https://cryptologos.cc/logos/ethereum-eth-logo.svg?v=023",
  137: "https://cryptologos.cc/logos/polygon-matic-logo.svg?v=023",
  8001: "https://cryptologos.cc/logos/polygon-matic-logo.svg?v=023",
  56: "https://seeklogo.com/images/B/binance-coin-bnb-logo-CD94CC6D31-seeklogo.com.png?v=637697418070000000",
  97: "https://seeklogo.com/images/B/binance-coin-bnb-logo-CD94CC6D31-seeklogo.com.png?v=637697418070000000",
  250: "https://cryptologos.cc/logos/fantom-ftm-logo.svg?v=023",
  4002: "https://cryptologos.cc/logos/fantom-ftm-logo.svg?v=023",
  1337: "https://cryptologos.cc/logos/ethereum-eth-logo.svg?v=023",
};

const nativeTokens = {
  56: {
    contract_name: 'BNB',
    contract_ticker_symbol: 'BNB',
    contract_address: ethers.constants.AddressZero,
    contract_decimals: 18,
    underlying: [],
    protocol_name: 'ERC20',
    chain_id: 56,
    logo_url: chainLogos[56]
  },
  1: {
    contract_name: 'Ether',
    contract_ticker_symbol: 'ETH',
    contract_address: ethers.constants.AddressZero,
    contract_decimals: 18,
    underlying: [],
    protocol_name: 'ERC20',
    chain_id: 1,
    logo_url: chainLogos[1]
  },
  137: {
    contract_name: 'Matic',
    contract_ticker_symbol: 'MATIC',
    contract_address: ethers.constants.AddressZero,
    contract_decimals: 18,
    underlying: [],
    protocol_name: 'ERC20',
    chain_id: 137,
    logo_url: chainLogos[137]
  },
  250: {
    contract_name: 'Fantom',
    contract_ticker_symbol: 'FTM',
    contract_address: ethers.constants.AddressZero,
    contract_decimals: 18,
    underlying: [],
    protocol_name: 'ERC20',
    chain_id: 250,
    logo_url: chainLogos[250]
  },
}

const protocolSymbols = {
  ERC20: 'ERC20',
  Pancakeswap: 'Pancake LP',
  Biswap: 'Biswap LP',
  'Uniswap V2': 'Uniswap LP',
  'Uniswap V3': 'Uniswap V3',
  Sushiswap: 'Sushi LP',
  Venus: 'Venus',
  AAVE: 'AAVE'
}

const logos = {
  ERC20: '',
  Pancakeswap: 'https://cryptologos.cc/logos/pancakeswap-cake-logo.svg?v=023',
  Biswap: 'https://cryptologos.cc/logos/biswap-bsw-logo.svg?v=023',
  'Uniswap V2': 'https://cryptologos.cc/logos/uniswap-uni-logo.svg?v=023',
  'Uniswap V3': 'https://cryptologos.cc/logos/uniswap-uni-logo.svg?v=023',
  Sushiswap: 'https://cryptologos.cc/logos/sushiswap-sushi-logo.svg?v=023',
  AAVE: 'https://cryptologos.cc/logos/aave-aave-logo.svg?v=023',
  Venus: ''
}

const getLogoUrl = (name: string, address: string, chainId: number) => {
  if (name === "Biswap LPs") {
    return logos.Biswap;
  } else if (name === "Pancake LPs") {
    return logos.Pancakeswap;
  } else if (name.includes("Venus")) {
    return "https://logos.covalenthq.com/tokens/56/0xcf6bb5389c92bdda8a3747ddb454cb7a64626c63.png";
  } else if (name.includes("AAVE")) {
    return logos.AAVE;
  } else if (name.includes("Uniswap")) {
    return logos["Uniswap V2"];
  }
  return `https://logos.covalenthq.com/tokens/${chainId}/${address.toLowerCase()}.png`;
};

const dataExtractorERC20 = (data:any, chainId: SupportedChains, protocol: SupportedProcols, manager: string | undefined) => {
  const assets: Asset[] = data.tokens.map((token:any)=> {
    return {
      contract_name: token.name,
      contract_address: token.id,
      contract_ticker_symbol: token.symbol,
      contract_decimals: token.decimals,
      underlying: [],
      logo_url: `https://logos.covalenthq.com/tokens/${chainId}/${token.id}.png`,
      protocol_name: protocol,
      chain_id: chainId,
      manager
    }
  })
  assets.unshift({...nativeTokens[chainId]})
  return assets
}

const dataExtractorUniV2 = (data:any, chainId: SupportedChains, protocol: SupportedProcols, manager: string | undefined) => {
  const assets: Asset[] = data.pairs.map((asset:any)=> {
    return {
      contract_name: `${protocol} ${asset.token0.symbol}-${asset.token1.symbol} LP`,
      contract_address: asset.id,
      contract_ticker_symbol: protocolSymbols[protocol],
      contract_decimals: 18,
      underlying: [
        {
          contract_name: asset.token0.name,
          contract_address: asset.token0.id,
          contract_ticker_symbol: asset.token0.symbol,
          contract_decimals: asset.token0.decimals,
          logo_url: `https://logos.covalenthq.com/tokens/${chainId}/${asset.token0.id}.png`
        },
        {
          contract_name: asset.token1.name,
          contract_address: asset.token1.id,
          contract_ticker_symbol: asset.token1.symbol,
          contract_decimals: asset.token1.decimals,
          logo_url: `https://logos.covalenthq.com/tokens/${chainId}/${asset.token1.id}.png`
        }
      ],
      logo_url: logos[protocol],
      protocol_name: protocol,
      chain_id: chainId,
      manager
    }
  })
  return assets
}

const dataExtractorPancakeSwap = async (data: string[], chainId: SupportedChains, protocol: SupportedProcols, manager: string | undefined) => {
  const assets: Asset[] = []
  for (const pool of data) {
    const contract = await ethers.getContractAt("IUniswapV2Pair", pool)
    const token0 = await contract.token0()
    const token1 = await contract.token1()
    const token0Contract = await ethers.getContractAt("ERC20", token0)
    const token1Contract = await ethers.getContractAt("ERC20", token1)
    const token0Symbol = await token0Contract.symbol()
    const token1Symbol = await token1Contract.symbol()
    const token0Name = await token0Contract.name()
    const token1Name = await token1Contract.name()
    const token0Decimals = await token0Contract.decimals()
    const token1Decimals = await token1Contract.decimals()
    const contract_name = `${protocol} ${token0Symbol}-${token1Symbol} LP`
    const contract_address = pool
    const contract_ticker_symbol = protocolSymbols[protocol]
    const contract_decimals = 18
    const underlying = [
      {
        contract_name: token0Name,
        contract_address: token0,
        contract_ticker_symbol: token0Symbol,
        contract_decimals: token0Decimals,
        logo_url: `https://logos.covalenthq.com/tokens/${chainId}/${token0}.png`
      },
      {
        contract_name: token1Name,
        contract_address: token1,
        contract_ticker_symbol: token1Symbol,
        contract_decimals: token1Decimals,
        logo_url: `https://logos.covalenthq.com/tokens/${chainId}/${token1}.png`
      }
    ]
    const logo_url = logos[protocol]
    const protocol_name = protocol
    assets.push({
      contract_name, contract_address, contract_ticker_symbol, contract_decimals, underlying, logo_url, protocol_name, chain_id: chainId, manager
    })
  }
  return assets
}

const dataExtractorUniV3 = (data:any, chainId: SupportedChains, protocol: SupportedProcols, manager: string | undefined) => {
  const assets: Asset[] = data.pools.map((asset:any)=> {
    return {
      contract_name: `${protocol} ${asset.token0.symbol}-${asset.token1.symbol} (${+asset.feeTier/10000}%) LP`,
      contract_address: asset.id,
      contract_ticker_symbol: `UNI-V3`,
      contract_decimals: 18,
      underlying: [
        {
          contract_name: asset.token0.name,
          contract_address: asset.token0.id,
          contract_ticker_symbol: asset.token0.symbol,
          contract_decimals: asset.token0.decimals,
          logo_url: `https://logos.covalenthq.com/tokens/${chainId}/${asset.token0.id}.png`},
        {
          contract_name: asset.token1.name,
          contract_address: asset.token1.id,
          contract_ticker_symbol: asset.token1.symbol,
          contract_decimals: asset.token1.decimals,
          logo_url: `https://logos.covalenthq.com/tokens/${chainId}/${asset.token1.id}.png`}
      ],
      logo_url: logos[protocol],
      protocol_name: protocol,
      chain_id: chainId,
      manager
    }
  })
  return assets
}

const dataExtractorVenus = (data:any, chainId: SupportedChains, protocol: SupportedProcols, manager: string | undefined) => {
  const assets: Asset[] = data.markets.map((asset:any)=> {
    return {
      contract_name: asset.name,
      contract_address: asset.id,
      contract_ticker_symbol: asset.symbol,
      contract_decimals: 18,
      underlying: [{
        contract_name: asset.underlyingName,
        contract_address: asset.underlyingAddress,
        contract_ticker_symbol: asset.underlyingSymbol,
        contract_decimals: asset.underlyingDecimals,
        logo_url: `https://logos.covalenthq.com/tokens/${chainId}/${asset.underlyingAddress}.png`
      }],
      logo_url: getLogoUrl(asset.name, asset.id, chainId),
      protocol_name: protocol,
      chain_id: chainId,
      manager
    }
  })
  return assets
}

const dataExtractorAAVE = (data:any, chainId: SupportedChains, protocol: SupportedProcols, manager: string | undefined) => {
  const assets: Asset[] = data.markets.map((asset:any)=> {
    return {
      contract_name: asset.outputToken.name,
      contract_address: asset.outputToken.id,
      contract_ticker_symbol: `a${asset.inputToken.symbol}`,
      contract_decimals: asset.inputToken.decimals,
      unedrlying: [{
        contract_name: asset.inputToken.name,
        contract_address: asset.inputToken.id,
        contract_ticker_symbol: asset.inputToken.symbol,
        contract_decimals: asset.inputToken.decimals,
        logo_url: `https://logos.covalenthq.com/tokens/${chainId}/${asset.inputToken.id}.png`
      }],
      logo_url: logos[protocol],
      protocol_name: protocol,
      chain_id: chainId,
      manager
    }
  })
  return assets
}

const dataExtractors = {
  'ERC20': dataExtractorERC20,
  'Uniswap V2': dataExtractorUniV2,
  'Sushiswap': dataExtractorUniV2,
  'Pancakeswap': dataExtractorPancakeSwap,
  'Biswap': dataExtractorUniV2,
  'Uniswap V3': dataExtractorUniV3,
  'Venus': dataExtractorVenus,
  'AAVE': dataExtractorAAVE
}

export const getAssets = async (protocol: ProtocolQuery, chainId:SupportedChains) => {
  for (let i =0; i<5; i++) {
    try {
      let data: any
      if (protocol.url) {
        const res: any = await (await fetch(protocol.url, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ query: protocol.query }),
        })).json()
        data = res.data
      } else {
        data = protocol.defaultTokens
      }
      const dataExtractor = dataExtractors[protocol.name]
      const assets = dataExtractor(data, chainId, protocol.name, protocol.manager)
      return assets
    } catch (error) {
      console.error(error)
      continue
    }
  }
}