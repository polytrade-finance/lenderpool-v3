const { expect } = require("chai");
const { ethers } = require("hardhat");
const { time } = require("@nomicfoundation/hardhat-network-helpers");
const {
  StableDecimal,
  BonusDecimal,
  LenderPoolAccess,
  SampleAPR,
  SampleRate,
  DAY,
  YEAR,
  SamplePeriod,
  MinDeposit,
  PoolMaxLimit2,
  AAVEPool,
  USDCAddress,
  aUSDCAddress,
  oUSDCAddress,
  AccountToImpersonateUSDC,
  AccountToImpersonateAdmin,
  UnitrollerAddress,
} = require("./constants/constants.helpers");
const { now, toStable, toBonus, fromBonus, fromStable } = require("./helpers");

describe("Fixed Lender Pool 2nd Test", function () {
  let accounts;
  let addresses;
  let admin;
  let lenderContract;
  let LenderFactory;
  let strategy;
  let strategy2;
  let stableToken;
  let bonusToken;
  let bonusAddress;
  let currentTime;
  let impersonated;
  let unitroller;

  beforeEach(async function () {
    currentTime = await now();
  });

  before(async function () {
    const hre = require("hardhat");
    accounts = await ethers.getSigners();
    addresses = accounts.map((account) => account.address);
    LenderFactory = await ethers.getContractFactory("FixLender");
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
    const Strategy = await ethers.getContractFactory("Strategy");
    const Strategy2 = await ethers.getContractFactory("OvixStrategy");
    strategy = await Strategy.deploy(AAVEPool, USDCAddress, aUSDCAddress);
    strategy2 = await Strategy2.deploy(USDCAddress, oUSDCAddress);
  });

  describe("Withdraw", function () {
    beforeEach(async function () {
      currentTime = await now();
      lenderContract = await LenderFactory.deploy(
        addresses[0],
        USDCAddress,
        bonusAddress,
        SampleAPR,
        SampleRate,
        currentTime + DAY,
        currentTime + 10 * DAY,
        SamplePeriod,
        MinDeposit,
        PoolMaxLimit2,
        false
      );
      await lenderContract.deployed();
      await lenderContract.switchStrategy(strategy.address);
      await strategy.grantRole(LenderPoolAccess, lenderContract.address);
      const initialDeposit = await toStable("10000");
      await stableToken.approve(lenderContract.address, initialDeposit);
      await lenderContract.deposit(initialDeposit);
      console.log("account 0 deposited 10k");
    });

    it("Should withdraw all rewards + principal after pool end date", async function () {
      const amount = await toStable("100");
      const bonusAmount = await toBonus("100");
      await stableToken.transfer(addresses[1], amount);
      await bonusToken.transfer(lenderContract.address, bonusAmount);
      await stableToken
        .connect(accounts[1])
        .approve(lenderContract.address, amount);
      await lenderContract.connect(accounts[1]).deposit(amount);
      console.log("account 1 deposited 100");
      // Increase to pool start date
      await time.increase(DAY);
      const Period = SamplePeriod * DAY;
      await time.increase(Period);
      console.log("90 days passed from start date");
      const expectedBonus = (100 * Period * (SampleRate / 100)) / YEAR;
      const unroundExpectedStable =
        (100 * Period * (SampleAPR / 10000)) / YEAR + 100;
      // need to round expected stable with 6 decimal since stable has 6 decimal
      const expectedStable =
        Math.round(unroundExpectedStable * 10 ** StableDecimal) /
        10 ** StableDecimal;
      const bonusBeforeWith = await bonusToken.balanceOf(addresses[1]);
      const stableBeforeWith = await stableToken.balanceOf(addresses[1]);
      await lenderContract.connect(accounts[1]).withdraw();
      const bonusAfterWith = await bonusToken.balanceOf(addresses[1]);
      const stableAfterWith = await stableToken.balanceOf(addresses[1]);
      const bonusBalance = bonusAfterWith.sub(bonusBeforeWith);
      const stableBalance = stableAfterWith.sub(stableBeforeWith);
      const actualBonus = parseFloat(await fromBonus(bonusBalance));
      const actualStable = parseFloat(await fromStable(stableBalance));
      expect(actualBonus).to.be.equal(expectedBonus);
      expect(actualStable).to.be.equal(expectedStable);
      console.log(`withdrawn ${expectedStable} stable for account 1`);
    });

    it("Should deposit 100 stable with 3 different accounts before and after pool start date and withdraw after pool end date and decrease pool size", async function () {
      const amount = await toStable("100");
      const bonusAmount = await toBonus("1000");
      for (let i = 1; i < 4; i++) {
        await stableToken.transfer(addresses[i], 2 * amount);
        await bonusToken.transfer(lenderContract.address, bonusAmount);
        await stableToken
          .connect(accounts[i])
          .approve(lenderContract.address, 2 * amount);
      }
      for (let i = 1; i < 4; i++) {
        await expect(lenderContract.connect(accounts[i]).deposit(amount))
          .to.emit(lenderContract, "Deposited")
          .withArgs(addresses[i], amount);
        console.log(`account ${i} deposited 100 stable`);
      }
      // Increase to one day after pool start date
      await time.increase(2 * DAY);
      console.log(`1 day passed from start date`);
      for (let i = 1; i < 4; i++) {
        await expect(lenderContract.connect(accounts[i]).deposit(amount))
          .to.emit(lenderContract, "Deposited")
          .withArgs(addresses[i], amount);
        console.log(`account ${i} deposited 100 stable`);
      }
      const Period = SamplePeriod * DAY;
      const secondPeriod = (SamplePeriod - 1) * DAY;
      await time.increase(secondPeriod);
      console.log("90 days passed from start date");
      const expectedBonus1st = (100 * Period * (SampleRate / 100)) / YEAR;
      const expectedBonus2nd = (100 * secondPeriod * (SampleRate / 100)) / YEAR;
      const unroundExpectedStable1st =
        (100 * Period * (SampleAPR / 10000)) / YEAR;
      const unroundExpectedStable2nd =
        (100 * secondPeriod * (SampleAPR / 10000)) / YEAR;
      // need to round expected stable with 6 decimal since stable has 6 decimal
      const expectedStable1st =
        Math.round(unroundExpectedStable1st * 10 ** StableDecimal) /
        10 ** StableDecimal;
      const expectedStable2nd =
        Math.round(unroundExpectedStable2nd * 10 ** StableDecimal) /
        10 ** StableDecimal;
      for (let i = 1; i < 4; i++) {
        const bonusBeforeWith = await bonusToken.balanceOf(addresses[i]);
        const stableBeforeWith = await stableToken.balanceOf(addresses[i]);
        const beforePoolSize = await lenderContract.getPoolSize();
        await lenderContract.connect(accounts[i]).withdraw();
        const afterPoolSize = await lenderContract.getPoolSize();
        const bonusAfterWith = await bonusToken.balanceOf(addresses[i]);
        const stableAfterWith = await stableToken.balanceOf(addresses[i]);
        const bonusBalance = bonusAfterWith.sub(bonusBeforeWith);
        const stableBalance = stableAfterWith.sub(stableBeforeWith);
        const actualBonus = parseFloat(await fromBonus(bonusBalance));
        const actualStable = parseFloat(await fromStable(stableBalance));
        const expectedStable = expectedStable1st + expectedStable2nd + 200;
        const expectedBonus = expectedBonus1st + expectedBonus2nd;
        const poolSize = beforePoolSize.sub(afterPoolSize);
        expect(actualStable).to.be.within(
          expectedStable - 0.00001,
          expectedStable
        );
        console.log(`withdrawn ${expectedStable} stable for account ${i}`);
        expect(actualBonus).to.be.within(expectedBonus - 0.0003, expectedBonus);
        expect(poolSize).to.be.equal(2 * amount);
      }
    });
  });
  describe("Emergency Withdraw and Switch Strategy", function () {
    beforeEach(async function () {
      currentTime = await now();
      lenderContract = await LenderFactory.deploy(
        addresses[0],
        USDCAddress,
        bonusAddress,
        SampleAPR,
        SampleRate,
        currentTime + DAY,
        currentTime + 10 * DAY,
        SamplePeriod,
        MinDeposit,
        PoolMaxLimit2,
        false
      );
      await lenderContract.deployed();
      await strategy.grantRole(LenderPoolAccess, lenderContract.address);
      await lenderContract.switchStrategy(strategy.address);
    });

    it("Should emergency withdraw all deposits before pool end date (Rate: 0%)", async function () {
      const amount = await toStable("100");
      const rate = 0;
      await stableToken.transfer(addresses[1], 2 * amount);
      await stableToken
        .connect(accounts[1])
        .approve(lenderContract.address, 2 * amount);
      await lenderContract.connect(accounts[1]).deposit(amount);
      console.log(`account 1 deposited 100 stable`);

      // Increase to pool start date
      await time.increase(DAY);

      await lenderContract.connect(accounts[1]).deposit(amount);

      const Period = (SamplePeriod - 10) * DAY;
      // increase to 10 days before pool end date
      await time.increase(Period - 10);
      console.log(`80 days passed from 90 days period`);
      const expectedStable = 200 - 200 * rate;
      const expectedBonus = 0;
      const bonusBeforeWith = await bonusToken.balanceOf(addresses[1]);
      const stableBeforeWith = await stableToken.balanceOf(addresses[1]);
      await expect(lenderContract.connect(accounts[1]).emergencyWithdraw())
        .to.emit(lenderContract, "WithdrawnEmergency")
        .withArgs(addresses[1], 2 * amount);
      const bonusAfterWith = await bonusToken.balanceOf(addresses[1]);
      const stableAfterWith = await stableToken.balanceOf(addresses[1]);
      const bonusBalance = bonusAfterWith.sub(bonusBeforeWith);
      const stableBalance = stableAfterWith.sub(stableBeforeWith);
      const actualBonus = parseFloat(await fromBonus(bonusBalance));
      const actualStable = parseFloat(await fromStable(stableBalance));
      expect(actualBonus).to.be.equal(expectedBonus);
      expect(actualStable).to.be.equal(expectedStable);
      console.log(`withdrawn ${actualStable} stable for account 1`);
      expect(await lenderContract.getPoolSize());
    });

    it("Should switch to ovix strategy and deposit lender balance to new strategy and revoke approval", async function () {
      const initialDeposit = await toStable("10000");
      await stableToken.approve(lenderContract.address, initialDeposit);
      await lenderContract.deposit(initialDeposit);
      console.log("account 0 deposited 10k");
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
      const initialDeposit = await toStable("10000");
      const bonusAmount = await toBonus("10000");
      await stableToken.approve(lenderContract.address, initialDeposit);
      await lenderContract.deposit(initialDeposit);
      await bonusToken.transfer(lenderContract.address, bonusAmount);
      console.log("account 0 deposited 10k");
      await strategy2.grantRole(LenderPoolAccess, lenderContract.address);
      await lenderContract.switchStrategy(strategy2.address);
      const amount = await toStable("1000");
      for (let i = 1; i < 3; i++) {
        await stableToken.transfer(addresses[i], amount);
        await stableToken
          .connect(accounts[i])
          .approve(lenderContract.address, amount);
        await lenderContract.connect(accounts[i]).deposit(amount);
        console.log(`account ${i} deposited 1000 stable`);
      }
      const unroundExpectedStable =
        (1000 * SamplePeriod * DAY * (SampleAPR / 10000)) / YEAR + 1000;
      // need to round expected stable with 6 decimal since stable has 6 decimal
      const expectedStable =
        Math.round(unroundExpectedStable * 10 ** StableDecimal) /
        10 ** StableDecimal;
      const Period = (SamplePeriod - 10) * DAY;
      // increase to 10 days before pool end date
      await time.increase(Period - 10);
      const acc1Before = await stableToken.balanceOf(addresses[1]);
      await lenderContract.connect(accounts[1]).emergencyWithdraw();
      console.log(`account 1 emergency withdrew 1000 stable`);
      const acc1After = await stableToken.balanceOf(addresses[1]);
      expect(acc1After.sub(acc1Before)).to.be.equal(amount);
      await time.increase(12 * DAY);
      const acc2Before = await stableToken.balanceOf(addresses[2]);
      await lenderContract.connect(accounts[2]).withdraw();
      const acc2After = await stableToken.balanceOf(addresses[2]);
      const actualAcc2 = parseFloat(
        await fromStable(acc2After.sub(acc2Before))
      );
      console.log(
        `account 2 emergency withdrew ${actualAcc2} stable + rewards`
      );
      expect(actualAcc2).to.be.equal(expectedStable);
    });
  });
});
