const { ethers } = require("hardhat");

const ZeroAddress = ethers.constants.AddressZero;
const LenderPoolAccess = ethers.utils.keccak256(
  ethers.utils.toUtf8Bytes("LENDER_POOL")
);
const SampleAPR = 1000; // 10.00%
const SampleRate = 100; // 1.00
const StableDecimal = 6;
const BonusDecimal = 18;
const SamplePeriod = 90; // 90 days
const MinDeposit = 100;
const PoolMaxLimit = 10000;
const DAY = 1 * 60 * 60 * 24;
const YEAR = 365 * 60 * 60 * 24;
const TestaUSDCAddress = "0x9daBC9860F8792AeE427808BDeF1f77eFeF0f24E";
const TestUSDCAddress = "0xe9DcE89B076BA6107Bb64EF30678efec11939234";
const TestAAVEPool = "0x0b913A76beFF3887d35073b8e5530755D60F78C7";
const AccountToImpersonateUSDC = "0xb00b414f9e45ba73b44ffc3e3ce64a806552cd02";
module.exports = {
  StableDecimal,
  BonusDecimal,
  ZeroAddress,
  LenderPoolAccess,
  SampleAPR,
  SampleRate,
  SamplePeriod,
  MinDeposit,
  PoolMaxLimit,
  DAY,
  YEAR,
  TestaUSDCAddress,
  TestUSDCAddress,
  TestAAVEPool,
  AccountToImpersonateUSDC,
};
