const { expect } = require("chai");
const { ethers } = require("hardhat");
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
const { now } = require("./helpers");

describe("Fixed Lender Pool", function () {
  let admin;
  let lender;
  let lenderContract;
  let stableToken;
  let bonusToken;
  let stableAddress;
  let bonusAddress;
  before(async function () {
    const [_admin, _lender] = await ethers.getSigners();
    admin = _admin;
    lender = _lender;
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
      const currentTime = await now();
      const LenderContract = await ethers.getContractFactory("FixLender");
      lenderContract = await LenderContract.deploy(
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
    it("Should fail if any address is zero", async function () {
      const currentTime = await now();
      const LenderContract = await ethers.getContractFactory("FixLender");
      await expect(
        LenderContract.deploy(
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
      await expect(
        LenderContract.deploy(
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
      await expect(
        LenderContract.deploy(
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
    it("Should fail if Dates are invalid", async function () {
      const currentTime = await now();
      const LenderContract = await ethers.getContractFactory("FixLender");
      await expect(
        LenderContract.deploy(
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
      await expect(
        LenderContract.deploy(
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
      const currentTime = await now();
      const LenderContract = await ethers.getContractFactory("FixLender");
      await expect(
        LenderContract.deploy(
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
      const currentTime = await now();
      const LenderContract = await ethers.getContractFactory("FixLender");
      await expect(
        LenderContract.deploy(
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
        lenderContract
          .connect(lender)
          .deposit(ethers.utils.parseUnits("1000", StableDecimal))
      ).to.be.revertedWith("ERC20: insufficient allowance");
    });
    it("Should deposit 1000 stable tokens", async function () {
      await stableToken
        .connect(lender)
        .approve(
          lenderContract.address,
          ethers.utils.parseUnits("1000", StableDecimal)
        );
      await expect(
        lenderContract
          .connect(lender)
          .deposit(ethers.utils.parseUnits("1000", StableDecimal))
      )
        .to.emit(lenderContract, "Deposited")
        .withArgs(
          lender.address,
          ethers.utils.parseUnits("1000", StableDecimal)
        );
    });
    it("Should fail if deposit amount is less than Min. deposit", async function () {
      const deposit = (MinDeposit - 1).toString();
      await stableToken
        .connect(lender)
        .approve(
          lenderContract.address,
          ethers.utils.parseUnits(deposit, StableDecimal)
        );
      await expect(
        lenderContract
          .connect(lender)
          .deposit(ethers.utils.parseUnits(deposit, StableDecimal))
      ).to.be.revertedWith("Amount is less than Min. Deposit");
    });
    it("Should fail if deposit amount is Invalid", async function () {
      await expect(
        lenderContract
          .connect(lender)
          .deposit(ethers.utils.parseUnits("0", StableDecimal))
      ).to.be.revertedWith("Invalid Amount");
    });
    it("Should fail if deposit amount pass Pool Max. Limit", async function () {
      await stableToken
        .connect(lender)
        .approve(
          lenderContract.address,
          ethers.utils.parseUnits(PoolMaxLimit.toString(), StableDecimal)
        );
      await expect(
        lenderContract
          .connect(lender)
          .deposit(
            ethers.utils.parseUnits(PoolMaxLimit.toString(), StableDecimal)
          )
      ).to.be.revertedWith("Pool has reached its limit");
    });
  });
});
