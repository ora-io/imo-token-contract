require("@nomicfoundation/hardhat-toolbox");
require('dotenv').config();
require("hardhat-gas-reporter");

const { API_URL, PRIVATE_KEY } = process.env;

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  solidity: {
    version: "0.8.24",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
      },
    },
  },
  networks: {
    hardhat: {},
    mainnet: {
      url: API_URL,
      accounts: [PRIVATE_KEY],
    },
    base: {
      url: API_URL,
      accounts: [PRIVATE_KEY]
    },
    sepolia: {
      url: API_URL,
      accounts: [PRIVATE_KEY],
    },
    local: {
      url: "http://127.0.0.1:8545",
      accounts: [PRIVATE_KEY],
    },
  },
  etherscan: {
    apiKey: {
        base: "JS31YSNXIGA33YKDC45Z6TKU6JSVXSXDQD",
    }
  },
  gasReporter: {
    enabled: (process.env.REPORT_GAS) ? true : false,
    L1: "ethereum",
  }
};
