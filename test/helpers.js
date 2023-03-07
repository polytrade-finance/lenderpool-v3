const { ethers } = require("hardhat");

module.exports.now = async function now() {
  return (
    await ethers.provider.getBlock(await ethers.provider.getBlockNumber())
  ).timestamp;
};

module.exports.fromStable = async function fromStable(amount) {
  return ethers.utils.formatUnits(amount, "6");
};

module.exports.toStable = async function toStable(amount) {
  return ethers.utils.parseUnits(amount, "6");
};

module.exports.fromBonus = async function toBonus(amount) {
  return ethers.utils.formatUnits(amount, "18");
};

module.exports.toBonus = async function toBonus(amount) {
  return ethers.utils.parseUnits(amount, "18");
};

module.exports.toRate = async function toRate(amount, bDecimal, sDecimal) {
  return amount * 10 ** (bDecimal - sDecimal);
};

module.exports.toApr = async function toApr(amount) {
  return amount / 100;
};
