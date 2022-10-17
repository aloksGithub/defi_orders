// import {expect} from "chai";
// import {ethers} from "hardhat";
// import hre from "hardhat";
// import {IWETH, PositionsManager, UniversalSwap} from "../typechain-types";
// import {
//   deployAndInitializeManager,
//   addresses,
//   getNetworkToken,
//   getLPToken
// } from "../utils";
// import supportedProtocols from "../constants/supported_protocols.json";
// require("dotenv").config();
// import fetch from "node-fetch"

// const NETWORK = hre.network.name;
// // @ts-ignore
// const networkAddresses = addresses[NETWORK];
// // @ts-ignore
// const protocols = supportedProtocols[process.env.CURRENTLY_FORKING!];

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
//       const {wethContract} = await getNetworkToken(owner, "1000.0");
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
//     for (const asset of assets) {
//       try {
//         index+=1
//         const balanceBefore = await networkTokenContract.balanceOf(owners[0].address)
//         const {lpBalance: lpBalance0, lpTokenContract} = await getLPToken(asset.value, universalSwap, "10", owners[0])
//         await lpTokenContract.approve(universalSwap.address, lpBalance0)
//         await universalSwap.connect(owners[0]).swapERC20([asset.value], [lpBalance0], [], networkTokenContract.address, 0)
//         const balanceAfter = await networkTokenContract.balanceOf(owners[0].address)
//         const fundsLost = balanceBefore.sub(balanceAfter)
//         const slippage = ethers.BigNumber.from("1000000").div(ethers.utils.parseEther("10").div(fundsLost.add("1"))).toNumber()/10000
//         console.log(slippage.toString())
//       } catch (error) {
//         console.log(`Failed conversion ${index} for token ${asset.value}, Error: ${error}`)
//       }
//     }
//   });
//   // it.only("Check slippage for few ERC20 tokens", async function () {
//   //   const assets = ["0xc748673057861a797275cd8a068abb95a902e8de"]
//   //   for (const wanted of assets) {
//   //       const balanceBefore = await networkTokenContract.balanceOf(owners[0].address)
//   //       const {lpBalance: lpBalance0, lpTokenContract} = await getLPToken(wanted, universalSwap, "10", owners[0])
//   //       await lpTokenContract.approve(universalSwap.address, lpBalance0)
//   //       await universalSwap.connect(owners[0]).swapERC20([wanted], [lpBalance0], [], networkTokenContract.address, 0)
//   //       const balanceAfter = await networkTokenContract.balanceOf(owners[0].address)
//   //       const fundsLost = balanceBefore.sub(balanceAfter)
//   //       const slippage = ethers.BigNumber.from("1000000").div(ethers.utils.parseEther("10").div(fundsLost.add("1"))).toNumber()/10000
//   //       console.log(slippage.toString())
//   //   }
//   // })
// });
