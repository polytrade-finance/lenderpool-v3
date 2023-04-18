const { ethers } = require("hardhat");
const DAY = 24 * 60 * 60;

const LenderPoolAccess = ethers.utils.keccak256(
  ethers.utils.toUtf8Bytes("LENDER_POOL")
);
const Admin = "0x17b7c1765611E0ce15b20aF68ECFdF86Eac636B3";
const StableApr = 100000; // 1000.00%
const BonusRate = 109500; // 1095.00
const BaseApr = 100000; // 1000.00%
const BaseRate = 109500; // 1095.00
const MinDeposit = 1 * 10 ** 6;
const p1Apr1 = 5821;
const p2Apr1 = 341100;
const p3Apr1 = 100000000;
const p1Rate1 = 3754;
const p2Rate1 = 629900;
const p3Rate1 = 365000000;
const p1Apr2 = 5678;
const p2Apr2 = 689100;
const p3Apr2 = 8010000;
const p1Rate2 = 6241;
const p2Rate2 = 185000;
const p3Rate2 = 331100000;
const PoolPeriod = 2;
const PoolMaxLimit = 1000000 * 10 ** 6;
const aUSDCAddress = "0x9daBC9860F8792AeE427808BDeF1f77eFeF0f24E";
const oUSDCAddress = "0x4413dbCf851D73bEc0BBF50b474EA89bded11153";
const USDCAddress = "0xe9DcE89B076BA6107Bb64EF30678efec11939234";
const ovixUSDCAddress = "0xe6b8a5CF854791412c1f6EFC7CAf629f5Df1c747";
const AAVEPool = "0x0b913A76beFF3887d35073b8e5530755D60F78C7";
const TRADEAddress = "0x8d2e5dc3D8215d3033bd547938Fb6CE6C16992D6";
module.exports = {
  Admin,
  BaseApr,
  BaseRate,
  LenderPoolAccess,
  MinDeposit,
  PoolMaxLimit,
  aUSDCAddress,
  oUSDCAddress,
  ovixUSDCAddress,
  USDCAddress,
  AAVEPool,
  TRADEAddress,
  p1Apr1,
  p2Apr1,
  p3Apr1,
  p1Rate1,
  p2Rate1,
  p3Rate1,
  p1Apr2,
  p2Apr2,
  p3Apr2,
  p1Rate2,
  p2Rate2,
  p3Rate2,
  DAY,
  StableApr,
  BonusRate,
  PoolPeriod,
};
