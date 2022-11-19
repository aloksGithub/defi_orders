// import {expect} from "chai";
// import {ethers} from "hardhat";
// import hre from "hardhat";
// import {ERC20, IERC20, IUniswapV2Pair, IWETH, PositionsManager, UniversalSwap} from "../typechain-types";
// import {
//   deployAndInitializeManager,
//   addresses,
//   getNetworkToken,
//   getLPToken,
//   depositNew
// } from "../utils";
// import supportedProtocols from "../constants/supported_protocols.json";
// require("dotenv").config();
// import fetch from "node-fetch"

// const NETWORK = hre.network.name;
// // @ts-ignore
// const networkAddresses = addresses[NETWORK];
// // @ts-ignore
// const protocols = supportedProtocols[process.env.CURRENTLY_FORKING!];
// const liquidationPoints = [{liquidateTo: networkAddresses.networkToken, watchedToken: networkAddresses.networkToken, lessThan:true, liquidationPoint: 100}]

// const chainIds = {
//   bsc: 56,
//   mainnet: 1
// }

// const getPrice = async (chain:string, address:string) => {
//   for (let i = 0; i<5; i++) {
//     try {
//       // @ts-ignore
//       const baseUrl = `https://api.covalenthq.com/v1/pricing/historical_by_addresses_v2/${chainIds[chain]}/USD/${address}/?quote-currency=USD&format=JSON&key=${process.env.COVALENT_KEY}`;
//       const response:any = await (await fetch (baseUrl)).json();
//       return response.data[0].items[0].price
//     } catch (err) {
//       console.log(`Failed attempt ${i} to fetch token price. Error: ${err}`)
//       continue
//     }
//   }
// }

// const getAssets = async (
//   url: string,
//   query: string,
//   protocol: string,
//   manager: string
// ) => {
//   for (let i = 0; i < 5; i++) {
//     try {
//       const res:any = await (
//         await fetch(url, {
//           method: "POST",
//           headers: {"Content-Type": "application/json"},
//           body: JSON.stringify({query}),
//         })
//       ).json();
//       if ("tokens" in res.data) {
//         return res.data.tokens?.map((token: any) => {
//           return {
//             value: token.id,
//             label: token.symbol,
//             manager,
//           };
//         });
//       } else if ("pairs" in res.data) {
//         const formattedAssets = res.data.pairs?.map((asset: any) => {
//           if (protocol === "Uniswap V3") {
//             return {
//               value: asset.id,
//               label: `${protocol} ${asset.token0.symbol}-${
//                 asset.token1.symbol
//               } (${+asset.feeTier / 10000}%) LP`,
//               manager,
//             };
//           }
//           return {
//             value: asset.id,
//             label: `${protocol} ${asset.token0.symbol}-${asset.token1.symbol} LP`,
//             manager,
//           };
//         });
//         return formattedAssets;
//       } else if ("pools" in res.data) {
//         const formattedAssets = res.data.pools?.map((asset: any) => {
//           if (protocol === "Uniswap V3") {
//             return {
//               value: asset.id,
//               label: `${protocol} ${asset.token0.symbol}-${
//                 asset.token1.symbol
//               } (${+asset.feeTier / 10000}%) LP`,
//               manager,
//             };
//           }
//           return {
//             value: asset.id,
//             label: `${protocol} ${asset.token0.symbol}-${asset.token1.symbol} LP`,
//             manager,
//           };
//         });
//         return formattedAssets;
//       } else if ("markets" in res.data) {
//         const formattedAssets = res.data.markets?.map((asset: any) => {
//           return {
//             value: asset.id,
//             label: asset.name,
//             manager,
//           };
//         });
//         return formattedAssets;
//       }
//       return res.data;
//     } catch (err) {
//       console.log(err)
//       continue;
//     }
//   }
// };

// const fetchAssets = async () => {
//   let assets:any[] = [];
//   for (const protocol of protocols) {
//     const data = await getAssets(
//       protocol.url,
//       protocol.query,
//       protocol.name,
//       protocol.manager
//     );
//     assets = assets.concat(data);
//   }
//   return assets;
// };

// describe("Slippage tests", function () {
//   let manager: PositionsManager;
//   let owners: any[];
//   let networkTokenContract: IWETH;
//   let universalSwap: UniversalSwap;
//   let bnbBusd: IUniswapV2Pair
//   let depositedUsd: number
//   let stableContract: ERC20
//   let amountUsed="1"
//   before(async function () {
//     manager = await deployAndInitializeManager();
//     owners = await ethers.getSigners();
//     const universalSwapAddress = await manager.universalSwap();
//     for (const owner of owners) {
//       const {wethContract} = await getNetworkToken(owner, "9990.0");
//       await wethContract
//         .connect(owner)
//         .approve(universalSwapAddress, ethers.utils.parseEther("10000000"));
//     }
//     networkTokenContract = await ethers.getContractAt(
//       "IWETH",
//       networkAddresses.networkToken
//     );
//     universalSwap = await ethers.getContractAt(
//       "UniversalSwap",
//       universalSwapAddress
//     );
//     bnbBusd = await ethers.getContractAt("IUniswapV2Pair", "0x58F876857a02D6762E0101bb5C46A8c1ED44Dc16")
//     const {reserve0, reserve1} = await bnbBusd.getReserves()
//     const networkTokenPrice = reserve1.mul('1000').div(reserve0).toNumber()/1000
//     depositedUsd = +amountUsed*networkTokenPrice
//     stableContract = await ethers.getContractAt("ERC20", networkAddresses.preferredStable)
//   });
//   it("Doesn't have more than 2% slippage for any ERC20 swaps", async function () {
//     const assets = await fetchAssets();
//     let index = 0
//     for (const asset of assets) {
//       if (["0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c".toLowerCase(), "0x4269e4090ff9dfc99d8846eb0d42e67f01c3ac8b".toLowerCase()].includes(asset.value)) continue
//       try {
//         index+=1
//         const balanceBefore = await stableContract.balanceOf(owners[0].address)
//         const {lpBalance: lpBalance0, lpTokenContract} = await getLPToken(asset.value, universalSwap, amountUsed, owners[0])
//         await lpTokenContract.connect(owners[0]).approve(manager.address, lpBalance0)
//         const {positionId} = await depositNew(manager, lpTokenContract.address, lpBalance0.div(2).toString(), liquidationPoints, owners[0])
//         await lpTokenContract.connect(owners[0]).approve(manager.address, lpBalance0)
//         await manager.connect(owners[0])["deposit(uint256,address[],uint256[],uint256[])"](positionId, [lpTokenContract.address], [lpBalance0.div(2)], [0])
//         await manager.connect(owners[0]).withdraw(positionId, lpBalance0.div(2))
//         await manager.connect(owners[0]).close(positionId)
//         await lpTokenContract.approve(universalSwap.address, lpBalance0)
//         await universalSwap.connect(owners[0]).swapV2([asset.value], [lpBalance0], [], [networkAddresses.preferredStable], [], [1], [0])
//         const balance = await stableContract.balanceOf(owners[0].address)
//         const fundsLost = depositedUsd-+ethers.utils.formatUnits(balance.sub(balanceBefore), (await stableContract.decimals()))
//         const slippage = 100*fundsLost/depositedUsd
//         await stableContract.transfer(owners[1].address, balance)
//         console.log(slippage.toString(), asset.value)
//       } catch (error) {
//         console.log(`Failed conversion ${index} for token ${asset.value}, Error: ${error}`)
//       }
//     }
//   });
//   // it.only("Check slippage for few ERC20 tokens", async function () {
//   //   const assets = ["0x78650b139471520656b9e7aa7a5e9276814a38e9", "0x1633b7157e7638c4d6593436111bf125ee74703f", "0x68e374f856bf25468d365e539b700b648bf94b67", "0x04c747b40be4d535fc83d09939fb0f626f32800b"]
//   //   for (const wanted of assets) {
//   //       const balanceBefore = await stableContract.balanceOf(owners[0].address)
//   //       const {lpBalance: lpBalance0, lpTokenContract} = await getLPToken(wanted, universalSwap, amountUsed, owners[0])
//   //       await lpTokenContract.connect(owners[0]).approve(manager.address, lpBalance0)
//   //       const {positionId} = await depositNew(manager, lpTokenContract.address, lpBalance0.div(2).toString(), liquidationPoints, owners[0])
//   //       await lpTokenContract.connect(owners[0]).approve(manager.address, lpBalance0)
//   //       await manager.connect(owners[0])["deposit(uint256,address[],uint256[],uint256[])"](positionId, [lpTokenContract.address], [lpBalance0.div(2)], [0])
//   //       await manager.connect(owners[0]).withdraw(positionId, lpBalance0.div(2))
//   //       await manager.connect(owners[0]).close(positionId)
//   //       await lpTokenContract.approve(universalSwap.address, lpBalance0)
//   //       await universalSwap.connect(owners[0]).swapERC20([wanted], [lpBalance0], [], networkAddresses.preferredStable, 0)
//   //       const balance = await stableContract.balanceOf(owners[0].address)
//   //       const fundsLost = depositedUsd-+ethers.utils.formatUnits(balance.sub(balanceBefore), (await stableContract.decimals()))
//   //       const slippage = 100*fundsLost/depositedUsd
//   //       await stableContract.transfer(owners[1].address, balance)
//   //       console.log(slippage.toString())
//   //   }
//   // })
// });
