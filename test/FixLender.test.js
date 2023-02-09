const { expect } = require("chai");
const { ethers } = require("hardhat");
const { time } = require("@nomicfoundation/hardhat-network-helpers");
const {
  StableDecimal,
  BonusDecimal,
  ZeroAddress,
  SampleAPR,
  SampleRate,
  DAY,
  SamplePeriod,
  MinDeposit,
  PoolMaxLimit,
} = require("./constants/constants.helpers");
const { now, toStable } = require("./helpers");

describe("Fixed Lender Pool", function () {
  let admin;
  let lender;
  let lenderContract;
  let LenderFactory;
  let stableToken;
  let bonusToken;
  let stableAddress;
  let bonusAddress;
  let currentTime;

  beforeEach(async function () {
    currentTime = await now();
  });

  before(async function () {
    [admin, lender] = await ethers.getSigners();
    LenderFactory = await ethers.getContractFactory("FixLender");
    const StableToken = await ethers.getContractFactory("Token");
    stableToken = await StableToken.connect(lender).deploy(
      "Stable",
      "STB",
      StableDecimal
    );
    await stableToken.deployed();
    stableAddress = stableToken.address;

    const BonusToken = await ethers.getContractFactory("Token");
    bonusToken = await BonusToken.connect(lender).deploy(
      "Bonus",
      "BNS",
      BonusDecimal
    );
    await bonusToken.deployed();
    bonusAddress = bonusToken.address;
  });

  describe("Constructor", function () {
    it("Should deploy lender successfully", async function () {
      lenderContract = await LenderFactory.deploy(
        admin.address,
        stableAddress,
        bonusAddress,
        SampleAPR,
        SampleRate,
        currentTime + DAY,
        currentTime + 3 * DAY,
        SamplePeriod,
        MinDeposit,
        PoolMaxLimit,
        true
      );
      await lenderContract.deployed();
    });

    it("Should fail if admin address is zero", async function () {
      await expect(
        LenderFactory.deploy(
          ZeroAddress,
          stableAddress,
          bonusAddress,
          SampleAPR,
          SampleRate,
          currentTime + DAY,
          currentTime + 3 * DAY,
          SamplePeriod,
          MinDeposit,
          PoolMaxLimit,
          true
        )
      ).to.be.revertedWith("Invalid Admin address");
    });

    it("Should fail if stable address is zero", async function () {
      await expect(
        LenderFactory.deploy(
          admin.address,
          ZeroAddress,
          bonusAddress,
          SampleAPR,
          SampleRate,
          currentTime + DAY,
          currentTime + 3 * DAY,
          SamplePeriod,
          MinDeposit,
          PoolMaxLimit,
          true
        )
      ).to.be.revertedWith("Invalid Stable Token address");
    });

    it("Should fail if bonus address is zero", async function () {
      await expect(
        LenderFactory.deploy(
          admin.address,
          stableAddress,
          ZeroAddress,
          SampleAPR,
          SampleRate,
          currentTime + DAY,
          currentTime + 3 * DAY,
          SamplePeriod,
          MinDeposit,
          PoolMaxLimit,
          true
        )
      ).to.be.revertedWith("Invalid Bonus Token address");
    });

    it("Should fail if Pool Start Date is invalid", async function () {
      await expect(
        LenderFactory.deploy(
          admin.address,
          stableAddress,
          bonusAddress,
          SampleAPR,
          SampleRate,
          currentTime - DAY,
          currentTime + 3 * DAY,
          SamplePeriod,
          MinDeposit,
          PoolMaxLimit,
          true
        )
      ).to.be.revertedWith("Invalid Pool Start Date");
    });

    it("Should fail if Deposit End Date is invalid", async function () {
      await expect(
        LenderFactory.deploy(
          admin.address,
          stableAddress,
          bonusAddress,
          SampleAPR,
          SampleRate,
          currentTime + DAY,
          currentTime - 3 * DAY,
          SamplePeriod,
          MinDeposit,
          PoolMaxLimit,
          true
        )
      ).to.be.revertedWith("Invalid Deposit End Date");
    });

    it("Should fail if pool period duration is invalid", async function () {
      await expect(
        LenderFactory.deploy(
          admin.address,
          stableAddress,
          bonusAddress,
          SampleAPR,
          SampleRate,
          currentTime + DAY,
          currentTime + 3 * DAY,
          0,
          MinDeposit,
          PoolMaxLimit,
          true
        )
      ).to.be.revertedWith("Invalid Pool Duration");
    });

    it("Should fail if Max. Pool size is less than or equal to Min. Deposit", async function () {
      await expect(
        LenderFactory.deploy(
          admin.address,
          stableAddress,
          bonusAddress,
          SampleAPR,
          SampleRate,
          currentTime + DAY,
          currentTime + 3 * DAY,
          SamplePeriod,
          MinDeposit,
          MinDeposit,
          true
        )
      ).to.be.revertedWith("Invalid Pool Max. Limit");
    });
  });

  describe("Deposit", function () {
    it("Should fail if lender didn't approve the same or higher stable for lender contract before deposit", async function () {
      await expect(
        lenderContract.connect(lender).deposit(toStable("1000"))
      ).to.be.revertedWith("ERC20: insufficient allowance");
    });

    it("Should deposit 1000 stable tokens", async function () {
      const amount = await toStable("1000");
      await stableToken.connect(lender).approve(lenderContract.address, amount);
      await expect(lenderContract.connect(lender).deposit(amount))
        .to.emit(lenderContract, "Deposited")
        .withArgs(lender.address, amount);
    });

    it("Should fail if deposit amount is less than Min. deposit", async function () {
      const deposit = (MinDeposit - 1).toString();
      await stableToken
        .connect(lender)
        .approve(lenderContract.address, toStable(deposit));
      await expect(
        lenderContract.connect(lender).deposit(toStable(deposit))
      ).to.be.revertedWith("Amount is less than Min. Deposit");
    });

    it("Should fail if has passed deposit end date", async function () {
      time.increase(5 * DAY);
      await expect(
        lenderContract.connect(lender).deposit(toStable("100"))
      ).to.be.revertedWith("Deposit End Date has passed");
    });

    it("Should fail if deposit amount + pool size pass the Pool Max. Limit", async function () {
      await stableToken
        .connect(lender)
        .approve(lenderContract.address, toStable(`${PoolMaxLimit}`));
      await expect(
        lenderContract.connect(lender).deposit(toStable(`${PoolMaxLimit}`))
      ).to.be.revertedWith("Pool has reached its limit");
    });
  });
});
