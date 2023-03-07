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
  LockingMaxLimit,
  LockingMinLimit,
  DAY,
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

    it("Should fail to if Stable Apr is more than 100%", async function () {
      // 10001 = 100.01 %
      await expect(lenderContract.changeBaseApr(10001)).to.be.revertedWith(
        "Invalid Stable Apr"
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

    it("Should fail to set apr address without curve interface support", async function () {
      await expect(
        lenderContract.switchAprBondingCurve(stableToken.address)
      ).to.be.revertedWith("Does not support Curve interface");
    });

    it("Should fail to set rate address without curve interface support", async function () {
      await expect(
        lenderContract.switchRateBondingCurve(stableToken.address)
      ).to.be.revertedWith("Does not support Curve interface");
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

    it("Should fail to to change Duration limit without admin access", async function () {
      await expect(
        lenderContract
          .connect(accounts[1])
          .changeDurationLimit(LockingMinLimit, LockingMaxLimit)
      ).to.be.revertedWith(
        `AccessControl: account ${addresses[1].toLowerCase()} is missing role ${ethers.utils.hexZeroPad(
          ethers.utils.hexlify(0),
          32
        )}`
      );
    });

    it("Should fail to change Duration limit more than 1 year", async function () {
      await expect(
        lenderContract.changeDurationLimit(LockingMinLimit, LockingMaxLimit + 1)
      ).to.be.revertedWith("Max. Limit should be <= 365 days");
    });

    it("Should fail to change Duration limit less than 3 months", async function () {
      await expect(
        lenderContract.changeDurationLimit(LockingMinLimit - 1, LockingMaxLimit)
      ).to.be.revertedWith("Min. Limit should be >= 90 days");
    });

    it("Should fail to change Duration limit if Max is less than Min", async function () {
      await expect(
        lenderContract.changeDurationLimit(LockingMaxLimit, LockingMinLimit)
      ).to.be.revertedWith("Max. Limit is not > Min. Limit");
    });

    it("Should change Duration limit", async function () {
      await expect(
        lenderContract.changeDurationLimit(LockingMinLimit, LockingMaxLimit)
      )
        .to.emit(lenderContract, "DurationLimitChanged")
        .withArgs(LockingMinLimit, LockingMaxLimit);
    });
  });

  describe("Deposit Without Lokcing Period", function () {
    before(async function () {
      lenderContract = await LenderFactory.deploy(
        addresses[0],
        USDCAddress,
        bonusAddress,
        MinDeposit,
        PoolMaxLimit
      );
      await lenderContract.deployed();
    });

    it("Should fail if lender didn't approve the same or higher stable for lender contract before deposit", async function () {
      const amount = await toStable("1000");
      await stableToken.transfer(addresses[1], amount);
      await expect(
        lenderContract.connect(accounts[1])["deposit(uint256)"](amount)
      ).to.be.revertedWith("ERC20: transfer amount exceeds allowance");
    });

    it("Should deposit to base 1000 stable tokens before initialize", async function () {
      const amount = await toStable("1000");
      await stableToken
        .connect(accounts[1])
        .approve(lenderContract.address, amount);
      await expect(
        lenderContract.connect(accounts[1])["deposit(uint256)"](amount)
      )
        .to.emit(lenderContract, "Deposited")
        .withArgs(addresses[1], 0, amount, 0, 0, 0);
    });

    it("Should deposit 1000 stable tokens after setting base Apr and Rate", async function () {
      const amount = await toStable("1000");
      await stableToken.transfer(addresses[1], amount);
      await stableToken
        .connect(accounts[1])
        .approve(lenderContract.address, amount);
      await lenderContract.changeBaseApr(SampleAPR);
      await lenderContract.changeBaseRate(SampleRate);
      await expect(
        lenderContract.connect(accounts[1])["deposit(uint256)"](amount)
      )
        .to.emit(lenderContract, "Deposited")
        .withArgs(addresses[1], 0, amount, 0, 0, 0);
    });

    it("Should fail if deposit amount is less than Min. deposit", async function () {
      const deposit = (MinDeposit - 1).toString();
      await stableToken
        .connect(accounts[1])
        .approve(lenderContract.address, toStable(deposit));
      await expect(
        lenderContract
          .connect(accounts[1])
          ["deposit(uint256)"](toStable(deposit))
      ).to.be.revertedWith("Amount is less than Min. Deposit");
    });

    it("Should not increase pool Size if stable tokens transfer directly to contract", async function () {
      const poolSizeBeforeTransfer = await lenderContract.poolSize();
      await stableToken.transfer(
        lenderContract.address,
        toStable(`${PoolMaxLimit}`)
      );
      const poolSizeAfterTransfer = await lenderContract.poolSize();
      expect(poolSizeAfterTransfer).to.be.equal(poolSizeBeforeTransfer);
    });

    it("Should fail if deposit amount + pool size pass the Pool Max. Limit", async function () {
      await stableToken
        .connect(accounts[1])
        .approve(lenderContract.address, toStable(`${PoolMaxLimit}`));
      await expect(
        lenderContract
          .connect(accounts[1])
          ["deposit(uint256)"](toStable(`${PoolMaxLimit}`))
      ).to.be.revertedWith("Pool has reached its limit");
    });
  });

  describe("Deposit With Lokcing Period", function () {
    before(async function () {
      lenderContract = await LenderFactory.deploy(
        addresses[0],
        USDCAddress,
        bonusAddress,
        MinDeposit,
        PoolMaxLimit
      );
      await lenderContract.deployed();
    });

    it("Should fail if Duration Limit has not been set", async function () {
      const amount = await toStable("1000");
      await stableToken.transfer(addresses[1], amount);
      await expect(
        lenderContract
          .connect(accounts[1])
          ["deposit(uint256,uint256)"](amount, LockingMinLimit)
      ).to.be.reverted;
    });

    it("Should fail if Apr or Rate Bonding Curve has not been set", async function () {
      const amount = await toStable("1000");
      await stableToken.transfer(addresses[1], amount);
      await lenderContract.changeDurationLimit(
        LockingMinLimit,
        LockingMaxLimit
      );
      await expect(
        lenderContract
          .connect(accounts[1])
          ["deposit(uint256,uint256)"](amount, LockingMinLimit)
      ).to.be.reverted;
      await lenderContract.switchAprBondingCurve(aprCurve.address);
      await expect(
        lenderContract
          .connect(accounts[1])
          ["deposit(uint256,uint256)"](amount, LockingMinLimit)
      ).to.be.reverted;
    });

    it("Should fail if lender didn't approve the same or higher stable for lender contract before deposit", async function () {
      const amount = await toStable("1000");
      await stableToken.transfer(addresses[1], amount);
      await lenderContract.switchRateBondingCurve(rateCurve.address);
      await expect(
        lenderContract
          .connect(accounts[1])
          ["deposit(uint256,uint256)"](amount, LockingMinLimit)
      ).to.be.revertedWith("ERC20: transfer amount exceeds allowance");
    });

    it("Should deposit 1000 stable tokens after initializing Bonding Curve and Duration Limit", async function () {
      const amount = await toStable("1000");
      await stableToken.transfer(addresses[1], amount);
      await stableToken
        .connect(accounts[1])
        .approve(lenderContract.address, amount);
      await lenderContract.changeBaseApr(SampleAPR);
      await lenderContract.changeBaseRate(SampleRate);
      const apr = await aprCurve.getRate(LockingMinLimit);
      const rate = await rateCurve.getRate(LockingMinLimit);
      await expect(
        lenderContract
          .connect(accounts[1])
          ["deposit(uint256,uint256)"](amount, LockingMinLimit)
      )
        .to.emit(lenderContract, "Deposited")
        .withArgs(addresses[1], 1, amount, LockingMinLimit * DAY, apr, rate);
    });

    it("Should fail if deposit amount is less than Min. deposit", async function () {
      const deposit = (MinDeposit - 1).toString();
      await stableToken
        .connect(accounts[1])
        .approve(lenderContract.address, toStable(deposit));
      await expect(
        lenderContract
          .connect(accounts[1])
          ["deposit(uint256,uint256)"](toStable(deposit), LockingMinLimit)
      ).to.be.revertedWith("Amount is less than Min. Deposit");
    });

    it("Should fail to deposit if locking duration is less than Min Duration Limit", async function () {
      const amount = await toStable("1000");
      await stableToken.transfer(addresses[1], amount);
      await stableToken
        .connect(accounts[1])
        .approve(lenderContract.address, amount);
      await expect(
        lenderContract
          .connect(accounts[1])
          ["deposit(uint256,uint256)"](amount, LockingMinLimit - 1)
      ).to.be.revertedWith("Locking Duration is < Min. Limit");
    });

    it("Should fail to deposit if locking duration is more than Max Duration Limit", async function () {
      const amount = await toStable("1000");
      await stableToken.transfer(addresses[1], amount);
      await stableToken
        .connect(accounts[1])
        .approve(lenderContract.address, amount);
      await expect(
        lenderContract
          .connect(accounts[1])
          ["deposit(uint256,uint256)"](amount, LockingMaxLimit + 1)
      ).to.be.revertedWith("Locking Duration is > Max. Limit");
    });

    it("Should not increase pool Size if stable tokens transfer directly to contract", async function () {
      const poolSizeBeforeTransfer = await lenderContract.poolSize();
      await stableToken.transfer(
        lenderContract.address,
        toStable(`${PoolMaxLimit}`)
      );
      const poolSizeAfterTransfer = await lenderContract.poolSize();
      expect(poolSizeAfterTransfer).to.be.equal(poolSizeBeforeTransfer);
    });

    it("Should fail if deposit amount + pool size pass the Pool Max. Limit", async function () {
      await stableToken
        .connect(accounts[1])
        .approve(lenderContract.address, toStable(`${PoolMaxLimit}`));
      await expect(
        lenderContract
          .connect(accounts[1])
          ["deposit(uint256,uint256)"](
            toStable(`${PoolMaxLimit}`),
            LockingMaxLimit
          )
      ).to.be.revertedWith("Pool has reached its limit");
    });
  });
});
