require("@nomicfoundation/hardhat-toolbox");
require("dotenv").config();

const { PRIVATE_KEY, CHAINSTACK_URL } = process.env;

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  solidity: "0.8.17",
  settings: { optimizer: { enabled: true, runs: 200 } },
  networks: {
    mumbai: {
      url: `${CHAINSTACK_URL}`,
      accounts: [`${PRIVATE_KEY}`],
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
