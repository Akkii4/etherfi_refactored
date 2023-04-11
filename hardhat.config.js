require("hardhat-gas-reporter");
require("dotenv").config();
require("@nomicfoundation/hardhat-toolbox");
require("@nomiclabs/hardhat-etherscan");

const PRIVATE = process.env.PRIVATE_KEY;
const RPC_URL = process.env.RPC;

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  networks: {
    test: {
      url: RPC_URL,
      accounts: [`0x${PRIVATE}`],
    },
  },
  etherscan: {
    // Your API key for Etherscan
    // Obtain one at https://etherscan.io/
    apiKey: process.env.ETHERSCAN_API_KEY,
  },
  solidity: {
    compilers: [
      {
        version: "0.8.13",
        settings: {
          optimizer: {
            enabled: true,
            runs: 200,
          },
        },
      },
    ],
  },
  gasReporter: {
    enabled: true,
    excludeContracts: ["CustomToken", "ERC20"],
    token: "ETH",
    showTimeSpent: true,
  },
};
