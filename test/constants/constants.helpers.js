const { ethers } = require("hardhat");

const ZeroAddress = ethers.constants.AddressZero;
const LenderPoolAccess = ethers.utils.keccak256(
  ethers.utils.toUtf8Bytes("LENDER_POOL")
);
const ClientPortalAccess = ethers.utils.keccak256(
  ethers.utils.toUtf8Bytes("CLIENT_PORTAL")
);
const SampleAPR = 1000; // 10.00%
const SampleAPR2 = 2000; // 10.00%
const SampleRate = 100; // 1.00
const SampleRate2 = 200; // 1.00
const StableDecimal = 6;
const BonusDecimal = 18;
const SamplePeriod = 90; // 90 days
const MinDeposit = 100 * 10 ** StableDecimal;
const p1Apr = 2799;
const p2Apr = 179200;
const p3Apr = 493000000;
const p1Rate = 704;
const p2Rate = 52150;
const p3Rate = 24640000;
const LockingMaxLimit = 365;
const LockingMinLimit = 90;
const PoolMaxLimit = 10000 * 10 ** StableDecimal;
const PoolMaxLimit2 = 100000000 * 10 ** StableDecimal;
const DAY = 1 * 60 * 60 * 24;
const YEAR = 365 * 60 * 60 * 24;
const oUSDCAddress = "0xEBb865Bf286e6eA8aBf5ac97e1b56A76530F3fBe";
const aUSDCAddress = "0x625E7708f30cA75bfd92586e17077590C60eb4cD";
const USDCAddress = "0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174";
const AAVEPool = "0x794a61358D6845594F94dc1DB02A252b5b4814aD";
const AccountToImpersonateUSDC = "0x0D0707963952f2fBA59dD06f2b425ace40b492Fe";
const AccountToImpersonateAdmin = "0x7b2b0cBaDC25953A64D77B4785848b48B45E1017";
const UnitrollerAddress = "0x8849f1a0cB6b5D6076aB150546EddEe193754F1C";
module.exports = {
  StableDecimal,
  BonusDecimal,
  ZeroAddress,
  LenderPoolAccess,
  ClientPortalAccess,
  SampleAPR,
  SampleAPR2,
  SampleRate,
  SampleRate2,
  SamplePeriod,
  MinDeposit,
  PoolMaxLimit,
  PoolMaxLimit2,
  DAY,
  YEAR,
  oUSDCAddress,
  aUSDCAddress,
  USDCAddress,
  AAVEPool,
  AccountToImpersonateUSDC,
  AccountToImpersonateAdmin,
  UnitrollerAddress,
  p1Apr,
  p2Apr,
  p3Apr,
  p1Rate,
  p2Rate,
  p3Rate,
  LockingMaxLimit,
  LockingMinLimit,
};
