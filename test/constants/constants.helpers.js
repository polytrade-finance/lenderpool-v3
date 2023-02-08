const { ethers } = require("hardhat");

const ZeroAddress = ethers.constants.AddressZero;
const SampleAPR = 1000; // 10.00%
const SampleRate = 100; // 1.00
const StableDecimal = 6;
const BonusDecimal = 18;
const SamplePeriod = 90; // 90 days
const MinDeposit = 100;
const MaxPoolSize = 1000;
const DAY = 1 * 60 * 60 * 24;
const YEAR = 365 * 60 * 60 * 24;
module.exports = {
  StableDecimal,
  BonusDecimal,
  ZeroAddress,
  SampleAPR,
  SampleRate,
  SamplePeriod,
  MinDeposit,
  MaxPoolSize,
  DAY,
  YEAR,
};
