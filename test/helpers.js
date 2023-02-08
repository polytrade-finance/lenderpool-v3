const { ethers } = require("hardhat");

module.exports.now = async function now() {
  return (
    await ethers.provider.getBlock(await ethers.provider.getBlockNumber())
  ).timestamp;
};
