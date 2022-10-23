// import {expect} from "chai";
// import {ethers} from "hardhat";
// import hre from "hardhat";
// import {IWETH, PositionsManager, UniversalSwap} from "../typechain-types";
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

// describe.only("Slippage tests", function () {
//   let manager: PositionsManager;
//   let owners: any[];
//   let networkTokenContract: IWETH;
//   let universalSwap: UniversalSwap;
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
//   });
//   it("Doesn't have more than 2% slippage for any ERC20 swaps", async function () {
//     const assets = await fetchAssets();
//     let index = 0
//     const usdcContract = await ethers.getContractAt("ERC20", networkAddresses.usdc)
//     const networkTokenPrice = await getPrice(process.env.CURRENTLY_FORKING!, networkTokenContract.address)
//     const amountUsed = "10"
//     const depositedUsd = +amountUsed*networkTokenPrice
//     for (const asset of assets) {
//       // if (asset.value==="0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c".toLowerCase()) continue
//       // try {
//         index+=1
//         const {lpBalance: lpBalance0, lpTokenContract} = await getLPToken(asset.value, universalSwap, "10", owners[0])
//         await lpTokenContract.connect(owners[0]).approve(manager.address, lpBalance0)
//         const {positionId} = await depositNew(manager, lpTokenContract.address, lpBalance0.div(2).toString(), liquidationPoints, owners[0])
//         await lpTokenContract.connect(owners[0]).approve(manager.address, lpBalance0)
//         await manager.connect(owners[0])["deposit(uint256,address[],uint256[],uint256[])"](positionId, [lpTokenContract.address], [lpBalance0.div(2)], [0])
//         await manager.connect(owners[0]).withdraw(positionId, lpBalance0.div(2))
//         await manager.connect(owners[0]).close(positionId)
//         await lpTokenContract.approve(universalSwap.address, lpBalance0)
//         const balanceBefore = await usdcContract.balanceOf(owners[0].address)
//         await universalSwap.connect(owners[0]).swapERC20([asset.value], [lpBalance0], [], networkAddresses.usdc, 0)
//         const balance = await usdcContract.balanceOf(owners[0].address)
//         const fundsLost = depositedUsd-+ethers.utils.formatUnits(balance.sub(balanceBefore), (await usdcContract.decimals()))
//         const slippage = 100*fundsLost/depositedUsd
//         await usdcContract.transfer(owners[1].address, balance)
//         if (slippage>5) {
//             console.log(`Too much slippage for ${asset.value} (${slippage.toString()})`)
//         }
//         console.log(slippage.toString(), fundsLost, balance, depositedUsd, balanceBefore)
//       // } catch (error) {
//       //   console.log(`Failed conversion ${index} for token ${asset.value}, Error: ${error}`)
//       // }
//     }
//   });
//   // it.only("Check slippage for few ERC20 tokens", async function () {
//   //   const assets = ["0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c", "0x31ec8f77a11aa0277948ed5f9b7b1daf23de3fda", "0x845d301c864d48027db73ec4394e6ddbe52cbc39", "0xACF47CBEaab5c8A6Ee99263cfE43995f89fB3206", "0x426c72701833fddbdfc06c944737c6031645c708", "0x284F871d6F2D4fE070F1E18c355eF2825e676AA2"]
//   //   for (const wanted of assets) {
//   //       const balanceBefore = await networkTokenContract.balanceOf(owners[0].address)
//   //       const {lpBalance: lpBalance0, lpTokenContract} = await getLPToken(wanted, universalSwap, "10", owners[0])
//   //       await lpTokenContract.approve(universalSwap.address, lpBalance0)
//   //       await universalSwap.connect(owners[0]).swapERC20([wanted], [lpBalance0], [], networkTokenContract.address, 0)
//   //       const balanceAfter = await networkTokenContract.balanceOf(owners[0].address)
//   //       const fundsLost = balanceBefore.sub(balanceAfter)
//   //       const slippage = ethers.BigNumber.from("1000000").div(ethers.utils.parseEther("10").div(fundsLost.add("1"))).toNumber()/10000
//   //       console.log(slippage.toString(), fundsLost, balanceBefore, balanceAfter)
//   //   }
//   // })
// });
