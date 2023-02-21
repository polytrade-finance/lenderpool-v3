require("@nomicfoundation/hardhat-toolbox");
require("dotenv").config();

const { PRIVATE_KEY, MUMBAI_ARCHIVAL_RPC } = process.env;

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  solidity: "0.8.17",
  settings: { optimizer: { enabled: true, runs: 200 } },
  networks: {
    hardhat: {
      forking: {
        url: `${MUMBAI_ARCHIVAL_RPC}`,
        blockNumber: 32228672,
      },
    },
    mumbai: {
      url: `${MUMBAI_ARCHIVAL_RPC}`,
      accounts: [
        `${
          PRIVATE_KEY ||
          "0x0000000000000000000000000000000000000000000000000000000000000000"
        }`,
      ],
    },
  },
  gasReporter: {
    enabled: process.env.REPORT_GAS !== undefined,
    currency: "USD",
  },
  etherscan: {
    apiKey: process.env.POLYGONSCAN_API_KEY,
  },
};
