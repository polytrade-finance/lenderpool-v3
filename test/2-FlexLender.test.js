const { expect } = require("chai");
const { ethers } = require("hardhat");
const {
  BonusDecimal,
  ZeroAddress,
  MinDeposit,
  PoolMaxLimit,
  USDCAddress,
  AccountToImpersonateUSDC,
  SampleAPR,
  SampleAPR2,
  SampleRate,
  SampleRate2,
  StableDecimal,
  p1Apr,
  p2Apr,
  p3Apr,
  p1Rate,
  p2Rate,
  p3Rate,
} = require("./constants/constants.helpers");
const { toStable, toRate, toApr } = require("./helpers");

describe("Flexible Lender Pool", function () {
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

  before(async function () {
    const hre = require("hardhat");
    accounts = await ethers.getSigners();
    addresses = accounts.map((account) => account.address);
    LenderFactory = await ethers.getContractFactory("FlexLender");
    await hre.network.provider.request({
      method: "hardhat_impersonateAccount",
      params: [AccountToImpersonateUSDC],
    });
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
  });

  describe("Constructor", function () {
    it("Should deploy lender successfully", async function () {
      lenderContract = await LenderFactory.deploy(
        addresses[0],
        USDCAddress,
        bonusAddress,
        MinDeposit,
        PoolMaxLimit
      );
      await lenderContract.deployed();
    });

    it("Should fail if admin address is zero", async function () {
      await expect(
        LenderFactory.deploy(
          ZeroAddress,
          USDCAddress,
          bonusAddress,
          MinDeposit,
          PoolMaxLimit
        )
      ).to.be.revertedWith("Invalid Admin address");
    });

    it("Should fail if stable address is zero", async function () {
      await expect(
        LenderFactory.deploy(
          addresses[0],
          ZeroAddress,
          bonusAddress,
          MinDeposit,
          PoolMaxLimit
        )
      ).to.be.revertedWith("Invalid Stable Token address");
    });

    it("Should fail if bonus address is zero", async function () {
      await expect(
        LenderFactory.deploy(
          addresses[0],
          USDCAddress,
          ZeroAddress,
          MinDeposit,
          PoolMaxLimit
        )
      ).to.be.revertedWith("Invalid Bonus Token address");
    });

    it("Should fail if Max. Pool size is less than Min. Deposit", async function () {
      await expect(
        LenderFactory.deploy(
          addresses[0],
          USDCAddress,
          bonusAddress,
          MinDeposit,
          MinDeposit - 1
        )
      ).to.be.revertedWith("Invalid Pool Max. Limit");
    });

    it("Should fail if Max. Pool size is equal to Min. Deposit", async function () {
      await expect(
        LenderFactory.deploy(
          addresses[0],
          USDCAddress,
          bonusAddress,
          MinDeposit,
          MinDeposit
        )
      ).to.be.revertedWith("Invalid Pool Max. Limit");
    });
  });

  describe("Initialize", function () {
    it("Should fail to set base Apr without admin access", async function () {
      await expect(
        lenderContract.connect(accounts[1]).changeBaseApr(SampleAPR)
      ).to.be.revertedWith(
        `AccessControl: account ${addresses[1].toLowerCase()} is missing role ${ethers.utils.hexZeroPad(
          ethers.utils.hexlify(0),
          32
        )}`
      );
    });

    it("Should fail to set base Rate without admin access", async function () {
      await expect(
        lenderContract.connect(accounts[1]).changeBaseRate(SampleRate)
      ).to.be.revertedWith(
        `AccessControl: account ${addresses[1].toLowerCase()} is missing role ${ethers.utils.hexZeroPad(
          ethers.utils.hexlify(0),
          32
        )}`
      );
    });

    it("Should fail to if Bonus Rate is more than 100 per stable token", async function () {
      // 10001 = 100.01 rate
      await expect(lenderContract.changeBaseRate(10001)).to.be.revertedWith(
        "Invalid Bonus Rate"
      );
    });

    it("Should set base Apr", async function () {
      await expect(lenderContract.changeBaseApr(SampleAPR))
        .to.emit(lenderContract, "BaseAprChanged")
        .withArgs(0, await toApr(SampleAPR));
    });

    it("Should set base Rate", async function () {
      await expect(lenderContract.changeBaseRate(SampleRate))
        .to.emit(lenderContract, "BaseRateChanged")
        .withArgs(0, await toRate(SampleRate, BonusDecimal, StableDecimal));
    });

    it("Should change base Apr", async function () {
      await expect(lenderContract.changeBaseApr(SampleAPR2))
        .to.emit(lenderContract, "BaseAprChanged")
        .withArgs(await toApr(SampleAPR), await toApr(SampleAPR2));
    });

    it("Should change base Rate", async function () {
      await expect(lenderContract.changeBaseRate(SampleRate2))
        .to.emit(lenderContract, "BaseRateChanged")
        .withArgs(
          await toRate(SampleRate, BonusDecimal, StableDecimal),
          await toRate(SampleRate2, BonusDecimal, StableDecimal)
        );
    });

    it("Should fail to set Apr Bonding Curve without admin access", async function () {
      await expect(
        lenderContract
          .connect(accounts[1])
          .switchAprBondingCurve(aprCurve.address)
      ).to.be.revertedWith(
        `AccessControl: account ${addresses[1].toLowerCase()} is missing role ${ethers.utils.hexZeroPad(
          ethers.utils.hexlify(0),
          32
        )}`
      );
    });

    it("Should fail to set Rate Bonding Curve without admin access", async function () {
      await expect(
        lenderContract
          .connect(accounts[1])
          .switchRateBondingCurve(rateCurve.address)
      ).to.be.revertedWith(
        `AccessControl: account ${addresses[1].toLowerCase()} is missing role ${ethers.utils.hexZeroPad(
          ethers.utils.hexlify(0),
          32
        )}`
      );
    });

    it("Should fail to set zero address for apr bonding curve", async function () {
      await expect(
        lenderContract.switchAprBondingCurve(ZeroAddress)
      ).to.be.revertedWith("Invalid Curve Address");
    });

    it("Should fail to set zero address for rate bonding curve", async function () {
      await expect(
        lenderContract.switchRateBondingCurve(ZeroAddress)
      ).to.be.revertedWith("Invalid Curve Address");
    });

    it("Should set Apr bonding Curve", async function () {
      await expect(lenderContract.switchAprBondingCurve(aprCurve.address))
        .to.emit(lenderContract, "AprBondingCurveSwitched")
        .withArgs(ZeroAddress, aprCurve.address);
    });

    it("Should set Rate bonding Curve", async function () {
      await expect(lenderContract.switchRateBondingCurve(rateCurve.address))
        .to.emit(lenderContract, "RateBondingCurveSwitched")
        .withArgs(ZeroAddress, rateCurve.address);
    });
  });
});
