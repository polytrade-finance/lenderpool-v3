const { expect } = require("chai");
const { ethers } = require("hardhat");
const { time } = require("@nomicfoundation/hardhat-network-helpers");
const {
  BonusDecimal,
  MinDeposit,
  USDCAddress,
  AccountToImpersonateUSDC,
  SampleAPR,
  SampleRate,
  StableDecimal,
  p1Apr,
  p2Apr,
  p3Apr,
  p1Rate,
  p2Rate,
  p3Rate,
  LockingMaxLimit,
  LockingMinLimit,
  DAY,
  YEAR,
  SamplePeriod,
  aUSDCAddress,
  AAVEPool,
  LenderPoolAccess,
  PoolMaxLimit2,
  oUSDCAddress,
  AccountToImpersonateAdmin,
  UnitrollerAddress,
} = require("./constants/constants.helpers");
const { toStable, fromBonus, toBonus, fromStable } = require("./helpers");

describe("Flexible Lender Pool 2nd test", function () {
  let accounts;
  let addresses;
  let lenderContract;
  let LenderFactory;
  let aprCurve;
  let rateCurve;
  let stableToken;
  let bonusToken;
  let bonusAddress;
  let impersonated;
  let strategy;
  let admin;
  let strategy2;
  let unitroller;

  before(async function () {
    const hre = require("hardhat");
    accounts = await ethers.getSigners();
    addresses = accounts.map((account) => account.address);
    LenderFactory = await ethers.getContractFactory("FlexLender");
    await hre.network.provider.request({
      method: "hardhat_impersonateAccount",
      params: [AccountToImpersonateUSDC],
    });
    const OracleFactory = await ethers.getContractFactory("OracleMock");
    const oracle = await OracleFactory.deploy();
    await oracle.deployed();
    const FORK_UNI_ABI = [
      "function _setPriceOracle(address newOracle) public returns (uint256)",
    ];
    await hre.network.provider.request({
      method: "hardhat_impersonateAccount",
      params: [AccountToImpersonateAdmin],
    });
    admin = await ethers.getSigner(AccountToImpersonateAdmin);
    await accounts[0].sendTransaction({
      to: admin.address,
      value: ethers.utils.parseEther("100.0"), // Sends exactly 100.0 ether
    });
    unitroller = new ethers.Contract(UnitrollerAddress, FORK_UNI_ABI, admin);
    await unitroller._setPriceOracle(oracle.address);
    impersonated = await ethers.getSigner(AccountToImpersonateUSDC);
    stableToken = await ethers.getContractAt("IToken", USDCAddress);
    const BonusToken = await ethers.getContractFactory("Token");
    bonusToken = await BonusToken.deploy("Bonus", "BNS", BonusDecimal);
    await bonusToken.deployed();
    bonusAddress = bonusToken.address;
    await stableToken
      .connect(impersonated)
      .transfer(addresses[0], await toStable("200000"));
    const CurveFactory = await ethers.getContractFactory("BondingCurve");
    aprCurve = await CurveFactory.deploy(p1Apr, p2Apr, p3Apr, 6);
    rateCurve = await CurveFactory.deploy(p1Rate, p2Rate, p3Rate, 6);
    const Strategy = await ethers.getContractFactory("Strategy");
    strategy = await Strategy.deploy(AAVEPool, USDCAddress, aUSDCAddress);
    const Strategy2 = await ethers.getContractFactory("OvixStrategy");
    strategy2 = await Strategy2.deploy(USDCAddress, oUSDCAddress);
  });

  describe("Withdraw", function () {
    beforeEach(async function () {
      lenderContract = await LenderFactory.deploy(
        addresses[0],
        USDCAddress,
        bonusAddress,
        MinDeposit,
        PoolMaxLimit2
      );
      await lenderContract.deployed();
      await lenderContract.switchStrategy(strategy.address);
      await strategy.grantRole(LenderPoolAccess, lenderContract.address);
      await lenderContract.changeBaseRates(SampleAPR, SampleRate);
      await lenderContract.changeDurationLimit(
        LockingMinLimit,
        LockingMaxLimit
      );
      await lenderContract.switchAprBondingCurve(aprCurve.address);
      await lenderContract.switchRateBondingCurve(rateCurve.address);
      const initialDeposit = await toStable("10000");
      await stableToken.approve(lenderContract.address, initialDeposit);
      await lenderContract["deposit(uint256)"](initialDeposit);
    });

    it("Should withdraw all rewards + principal after depositing 3 times with locking period", async function () {
      const amount = await toStable("100");
      const totalAmount = await toStable("300");
      const bonusAmount = await toBonus("100");
      await stableToken.transfer(addresses[1], totalAmount);
      await bonusToken.transfer(lenderContract.address, bonusAmount);
      await stableToken
        .connect(accounts[1])
        .approve(lenderContract.address, totalAmount);
      for (let i = 0; i < 3; i++) {
        await lenderContract
          .connect(accounts[1])
          ["deposit(uint256,uint256)"](amount, SamplePeriod);
      }
      const Period = SamplePeriod * DAY;
      const apr = await aprCurve.getRate(SamplePeriod);
      const rate = await rateCurve.getRate(SamplePeriod);
      await time.increase(Period);
      const expectedBonus = (300 * Period * (rate / 100)) / YEAR;
      const unroundExpectedStable = (300 * Period * (apr / 10000)) / YEAR + 300;
      // need to round expected stable with 6 decimal since stable has 6 decimal
      const expectedStable =
        Math.round(unroundExpectedStable * 10 ** 5) / 10 ** 5;
      const bonusBeforeWith = await bonusToken.balanceOf(addresses[1]);
      const stableBeforeWith = await stableToken.balanceOf(addresses[1]);
      for (let i = 0; i < 3; i++) {
        await lenderContract.connect(accounts[1])["withdraw(uint256)"](i);
      }
      const bonusAfterWith = await bonusToken.balanceOf(addresses[1]);
      const stableAfterWith = await stableToken.balanceOf(addresses[1]);
      const bonusBalance = bonusAfterWith.sub(bonusBeforeWith);
      const stableBalance = stableAfterWith.sub(stableBeforeWith);
      const actualBonus = parseFloat(await fromBonus(bonusBalance));
      const actualStable = parseFloat(await fromStable(stableBalance));
      expect(actualBonus).to.be.equal(expectedBonus);
      expect(actualStable).to.be.equal(expectedStable);
    });

    it("Should deposit 100 stable with 2 different accounts and withdraw after locking period and decrease pool size", async function () {
      const amount = await toStable("100");
      const bonusAmount = await toBonus("1000");
      const apr = await aprCurve.getRate(180);
      const rate = await rateCurve.getRate(180);
      for (let i = 1; i < 4; i++) {
        await stableToken.transfer(addresses[i], 3 * amount);
        await bonusToken.transfer(lenderContract.address, bonusAmount);
        await stableToken
          .connect(accounts[i])
          .approve(lenderContract.address, 3 * amount);
      }
      // deposit with account 1 and 2
      for (let i = 0; i < 2; i++) {
        for (let i = 1; i < 3; i++) {
          await lenderContract
            .connect(accounts[i])
            ["deposit(uint256,uint256)"](amount, 2 * SamplePeriod);
        }
      }
      await time.increase(YEAR);
      for (let i = 1; i < 3; i++) {
        await lenderContract.connect(accounts[i])["deposit(uint256)"](amount);
      }
      await time.increase(YEAR);
      const Period = 2 * SamplePeriod * DAY;
      const Expected1 = (200 * Period * (apr / 10000)) / YEAR;
      const Expected2 = (100 * YEAR * (SampleAPR / 10000)) / YEAR;
      const StableExpect = Expected1 + Expected2 + 300;
      const BonusExpect1 = (200 * Period * (rate / 100)) / YEAR;
      const BonusExpect2 = (100 * YEAR * (SampleRate / 100)) / YEAR;
      // need to round expected stable with 6 decimal since stable has 6 decimal
      const ExpectedStable =
        Math.round(StableExpect * 10 ** StableDecimal) / 10 ** StableDecimal;
      const ExpectedBonus = BonusExpect1 + BonusExpect2;
      for (let i = 1; i < 3; i++) {
        const bonusBeforeWith = await bonusToken.balanceOf(addresses[i]);
        const stableBeforeWith = await stableToken.balanceOf(addresses[i]);
        const beforePoolSize = await lenderContract.getPoolSize();
        await lenderContract.connect(accounts[i])["withdraw()"]();
        await lenderContract.connect(accounts[i])["withdraw(uint256)"](1);
        await lenderContract.connect(accounts[i])["withdraw(uint256)"](0);
        const afterPoolSize = await lenderContract.getPoolSize();
        const bonusAfterWith = await bonusToken.balanceOf(addresses[i]);
        const stableAfterWith = await stableToken.balanceOf(addresses[i]);
        const bonusBalance = bonusAfterWith.sub(bonusBeforeWith);
        const stableBalance = stableAfterWith.sub(stableBeforeWith);
        const actualBonus = parseFloat(await fromBonus(bonusBalance));
        const actualStable = parseFloat(await fromStable(stableBalance));
        const poolSize = beforePoolSize.sub(afterPoolSize);
        expect(actualStable).to.be.within(
          ExpectedStable - 0.00001,
          ExpectedStable
        );
        expect(actualBonus).to.be.within(ExpectedBonus, ExpectedBonus + 0.0001);
        expect(poolSize).to.be.equal(3 * amount);
      }
    });
  });
  describe("Emergency Withdraw and Switch Strategy", function () {
    beforeEach(async function () {
      lenderContract = await LenderFactory.deploy(
        addresses[0],
        USDCAddress,
        bonusAddress,
        MinDeposit,
        PoolMaxLimit2
      );
      await lenderContract.deployed();
      await lenderContract.switchStrategy(strategy.address);
      await strategy.grantRole(LenderPoolAccess, lenderContract.address);
      await lenderContract.changeBaseRates(SampleAPR, SampleRate);
      await lenderContract.changeDurationLimit(
        LockingMinLimit,
        LockingMaxLimit
      );
      await lenderContract.switchAprBondingCurve(aprCurve.address);
      await lenderContract.switchRateBondingCurve(rateCurve.address);
      const initialDeposit = await toStable("10000");
      await stableToken.approve(lenderContract.address, initialDeposit);
      await lenderContract["deposit(uint256)"](initialDeposit);
    });

    it("Should emergency withdraw all deposits before pool end date (Rate: 0%)", async function () {
      const amount = await toStable("100");
      const rate = 0;
      await stableToken.transfer(addresses[1], 2 * amount);
      await bonusToken.transfer(lenderContract.address, await toBonus("100"));
      await stableToken
        .connect(accounts[1])
        .approve(lenderContract.address, 2 * amount);
      await lenderContract
        .connect(accounts[1])
        ["deposit(uint256,uint256)"](amount, SamplePeriod);
      await time.increase(DAY);
      await lenderContract
        .connect(accounts[1])
        ["deposit(uint256,uint256)"](amount, SamplePeriod);
      await time.increase(80 * DAY);
      const expectedStable = 200 - 200 * rate;
      const expectedBonus1 = await lenderContract[
        "getBonusRewards(address,uint256)"
      ](addresses[1], 0);
      const expectedBonus2 = await lenderContract[
        "getBonusRewards(address,uint256)"
      ](addresses[1], 1);
      const bonusBeforeWith = await bonusToken.balanceOf(addresses[1]);
      const stableBeforeWith = await stableToken.balanceOf(addresses[1]);
      const expectedBonus = expectedBonus1.add(expectedBonus2);
      for (let i = 0; i < 2; i++) {
        await lenderContract.connect(accounts[1]).emergencyWithdraw(i);
      }
      const bonusAfterWith = await bonusToken.balanceOf(addresses[1]);
      const stableAfterWith = await stableToken.balanceOf(addresses[1]);
      const bonusBalance = bonusAfterWith.sub(bonusBeforeWith);
      const stableBalance = stableAfterWith.sub(stableBeforeWith);
      const actualBonus = Math.round(parseFloat(await fromBonus(bonusBalance)));
      const actualStable = parseFloat(await fromStable(stableBalance));
      expect(actualBonus).to.be.equal(
        Math.round(parseFloat(await fromBonus(expectedBonus)))
      );
      expect(actualStable).to.be.equal(expectedStable);
    });

    it("Should switch to ovix strategy and deposit lender balance to new strategy and revoke approval", async function () {
      const amount = await toStable("1000");
      await stableToken.transfer(lenderContract.address, amount);
      await strategy2.grantRole(LenderPoolAccess, lenderContract.address);
      const strategyBalance = await strategy.getBalance();
      const lenderBalance = await stableToken.balanceOf(lenderContract.address);
      const expectedBalance = strategyBalance.add(lenderBalance);
      const expected = parseFloat(await fromStable(expectedBalance));
      await lenderContract.switchStrategy(strategy2.address);
      const actualBalance = await strategy2.callStatic.getBalance();
      const actual = parseFloat(await fromStable(actualBalance));
      const allowance = await stableToken.allowance(
        lenderContract.address,
        strategy.address
      );
      expect(actual).to.be.within(expected, expected + 0.0001);
      expect(allowance).to.be.equal(0);
    });

    it("Should emergencyWithdraw and withdraw from 0vix strategy", async function () {
      const bonusAmount = await toBonus("10000");
      await bonusToken.transfer(lenderContract.address, bonusAmount);
      await strategy2.grantRole(LenderPoolAccess, lenderContract.address);
      await lenderContract.switchStrategy(strategy2.address);
      const amount = await toStable("1000");
      for (let i = 1; i < 3; i++) {
        await stableToken.transfer(addresses[i], amount);
        await stableToken
          .connect(accounts[i])
          .approve(lenderContract.address, amount);
        await lenderContract
          .connect(accounts[i])
          ["deposit(uint256,uint256)"](amount, SamplePeriod);
      }
      const apr = await aprCurve.getRate(SamplePeriod);
      const unroundExpectedStable =
        (1000 * SamplePeriod * DAY * (apr / 10000)) / YEAR + 1000;
      // need to round expected stable with 6 decimal since stable has 6 decimal
      const expectedStable =
        Math.round(unroundExpectedStable * 10 ** StableDecimal) /
        10 ** StableDecimal;
      const Period = (SamplePeriod - 10) * DAY;
      // increase to 10 days before pool end date
      await time.increase(Period - 10);
      const acc1Before = await stableToken.balanceOf(addresses[1]);
      await lenderContract.connect(accounts[1]).emergencyWithdraw(0);
      const acc1After = await stableToken.balanceOf(addresses[1]);
      expect(acc1After.sub(acc1Before)).to.be.equal(amount);
      await time.increase(12 * DAY);
      const acc2Before = await stableToken.balanceOf(addresses[2]);
      await lenderContract.connect(accounts[2])["withdraw(uint256)"](0);
      const acc2After = await stableToken.balanceOf(addresses[2]);
      const actualAcc2 = parseFloat(
        await fromStable(acc2After.sub(acc2Before))
      );
      expect(actualAcc2).to.be.within(expectedStable - 0.0001, expectedStable);
    });
  });
});
