require("@nomicfoundation/hardhat-toolbox");
require("dotenv").config();
const path = require("path");



module.exports = {
  solidity:  {
    compilers: [
      { version: "0.8.19", settings: {
        optimizer: {
          enabled: true,
          runs: 200
        },
        viaIR: true // 👈 Enable this
      }}, // 👈 Add this if it's missing
      { version: "0.8.18" }  // 👈 You can support multiple versions
    ],
    
  },
  paths: {
    sources: path.join(__dirname, "contracts"),
    cache: "./cache",
    artifacts: "./artifacts",
    tests: "./test",
    cache: "./cache",
  },
  allowPaths: [path.resolve(__dirname, "./node_modules")],
  networks: {
    hardhat: {
      hardfork: "merge",
      
      chainId: 31337,
  },
},
  defaultNetwork: "hardhat",

 
};

