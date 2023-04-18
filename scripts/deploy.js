const { ethers } = require("hardhat");
const {
  Admin,
  BaseApr,
  BaseRate,
  LenderPoolAccess,
  MinDeposit,
  PoolMaxLimit,
  aUSDCAddress,
  oUSDCAddress,
  USDCAddress,
  ovixUSDCAddress,
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
  BonusRate,
  StableApr,
} = require("./constants");

async function main() {
  const startDate = Math.round(Date.now() / 1000 + 100);
  const depositEndDate = Math.round(Date.now() / 1000 + 1 * DAY - 100);
  const FlexLender = await ethers.getContractFactory("FlexLender");
  const flex = await FlexLender.deploy(
    Admin,
    USDCAddress,
    TRADEAddress,
    MinDeposit,
    PoolMaxLimit
  );
  await flex.deployed();
  const flex2 = await FlexLender.deploy(
    Admin,
    USDCAddress,
    TRADEAddress,
    MinDeposit,
    PoolMaxLimit
  );
  await flex2.deployed();

  const FixLender = await ethers.getContractFactory("FixLender");
  const fix = await FixLender.deploy(
    Admin,
    ovixUSDCAddress,
    TRADEAddress,
    StableApr,
    BonusRate,
    startDate,
    depositEndDate,
    1,
    MinDeposit,
    PoolMaxLimit,
    false
  );
  await fix.deployed();

  const Strategy = await ethers.getContractFactory("Strategy");
  const strategy = await Strategy.deploy(AAVEPool, USDCAddress, aUSDCAddress);
  await strategy.deployed();

  const Strategy2 = await ethers.getContractFactory("OvixStrategy");
  const strategy2 = await Strategy2.deploy(ovixUSDCAddress, oUSDCAddress);
  await strategy2.deployed();

  const UsdContract = await ethers.getContractFactory("Token");
  const usdc = UsdContract.attach(ovixUSDCAddress);

  await usdc.approve(fix.address, ethers.constants.MaxUint256);

  const CurveFactory1 = await ethers.getContractFactory("BondingCurve");
  const aprCurve1 = await CurveFactory1.deploy(p1Apr1, p2Apr1, p3Apr1, 4);
  await aprCurve1.deployed();
  const rateCurve1 = await CurveFactory1.deploy(p1Rate1, p2Rate1, p3Rate1, 4);
  await rateCurve1.deployed();

  const CurveFactory2 = await ethers.getContractFactory("BondingCurve");
  const aprCurve2 = await CurveFactory2.deploy(p1Apr2, p2Apr2, p3Apr2, 4);
  await aprCurve2.deployed();
  const rateCurve2 = await CurveFactory2.deploy(p1Rate2, p2Rate2, p3Rate2, 4);
  await rateCurve2.deployed();

  await strategy.grantRole(LenderPoolAccess, flex.address);
  await strategy.grantRole(LenderPoolAccess, flex2.address);
  await strategy.grantRole(LenderPoolAccess, fix.address);
  await strategy2.grantRole(LenderPoolAccess, fix.address);
  await flex.switchStrategy(strategy.address);
  await flex2.switchStrategy(strategy.address);
  await fix.switchStrategy(strategy.address);
  await fix.switchStrategy(strategy2.address);
  await flex.changeBaseRates(BaseApr, BaseRate);
  await flex2.changeBaseRates(BaseApr, BaseRate);
  await flex.changeDurationLimit(0, 365);
  await flex2.changeDurationLimit(90, 365);
  await flex.switchAprBondingCurve(aprCurve1.address);
  await flex.switchRateBondingCurve(rateCurve1.address);
  await flex2.switchAprBondingCurve(aprCurve2.address);
  await flex2.switchRateBondingCurve(rateCurve2.address);

  console.log(startDate, depositEndDate);
  console.log("FlexLender deployed to:", flex.address);
  console.log("FlexLender deployed to:", flex2.address);
  console.log("FixLender deployed to:", fix.address);
  console.log("Strategy deployed to:", strategy.address);
  console.log("Strategy2 deployed to:", strategy2.address);
  console.log("aprCurve1 deployed to:", aprCurve1.address);
  console.log("rateCurve1 deployed to:", rateCurve1.address);
  console.log("aprCurve2 deployed to:", aprCurve2.address);
  console.log("rateCurve2 deployed to:", rateCurve2.address);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  throw new Error(error);
});
