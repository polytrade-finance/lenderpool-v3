const { expect } = require("chai");
const { ethers } = require("hardhat");
const { time } = require("@nomicfoundation/hardhat-network-helpers");
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
  YEAR,
  SamplePeriod,
} = require("./constants/constants.helpers");
const { toStable, toRate, toApr, fromBonus, toBonus } = require("./helpers");

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
    it("Should fail to set base Apr and rate without admin access", async function () {
      await expect(
        lenderContract
          .connect(accounts[1])
          .changeBaseRates(SampleAPR, SampleRate)
      ).to.be.revertedWith(
        `AccessControl: account ${addresses[1].toLowerCase()} is missing role ${ethers.utils.hexZeroPad(
          ethers.utils.hexlify(0),
          32
        )}`
      );
    });

    it("Should fail to if Stable Apr is more than 100%", async function () {
      // 10001 = 100.01 %
      await expect(
        lenderContract.changeBaseRates(10001, SampleRate)
      ).to.be.revertedWith("Invalid Stable Apr");
    });

    it("Should fail to if Bonus Rate is more than 100 per stable token", async function () {
      // 10001 = 100.01 rate
      await expect(
        lenderContract.changeBaseRates(SampleAPR, 10001)
      ).to.be.revertedWith("Invalid Bonus Rate");
    });

    it("Should set base Apr and Rate", async function () {
      await expect(lenderContract.changeBaseRates(SampleAPR, SampleRate))
        .to.emit(lenderContract, "BaseRateChanged")
        .withArgs(
          0,
          await toApr(SampleAPR),
          0,
          await toRate(SampleRate, BonusDecimal, StableDecimal)
        );
    });

    it("Should change base Apr", async function () {
      await expect(lenderContract.changeBaseRates(SampleAPR2, SampleRate))
        .to.emit(lenderContract, "BaseRateChanged")
        .withArgs(
          await toApr(SampleAPR),
          await toApr(SampleAPR2),
          await toRate(SampleRate, BonusDecimal, StableDecimal),
          await toRate(SampleRate, BonusDecimal, StableDecimal)
        );
    });

    it("Should change base Rate", async function () {
      await expect(lenderContract.changeBaseRates(SampleAPR2, SampleRate2))
        .to.emit(lenderContract, "BaseRateChanged")
        .withArgs(
          await toApr(SampleAPR2),
          await toApr(SampleAPR2),
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
      await lenderContract.changeBaseRates(SampleAPR, SampleRate);
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
      await lenderContract.changeBaseRates(SampleAPR, SampleRate);
      const apr = await aprCurve.getRate(LockingMinLimit);
      const rate = await rateCurve.getRate(LockingMinLimit);
      await expect(
        lenderContract
          .connect(accounts[1])
          ["deposit(uint256,uint256)"](amount, LockingMinLimit)
      )
        .to.emit(lenderContract, "Deposited")
        .withArgs(addresses[1], 0, amount, LockingMinLimit * DAY, apr, rate);
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

  describe("Claim Deposit without locking period", function () {
    beforeEach(async function () {
      lenderContract = await LenderFactory.deploy(
        addresses[0],
        USDCAddress,
        bonusAddress,
        MinDeposit,
        PoolMaxLimit
      );
      await lenderContract.deployed();
    });

    it("Should fail if there is no deposit before initialization", async function () {
      await expect(
        lenderContract.connect(accounts[1])["claimBonus()"]()
      ).to.be.revertedWith("You have not deposited anything");
    });

    it("Should fail if there is no deposit after initialization", async function () {
      await lenderContract.changeBaseRates(SampleAPR, SampleRate);
      await expect(
        lenderContract.connect(accounts[1])["claimBonus()"]()
      ).to.be.revertedWith("You have not deposited anything");
    });

    it("Should deposit 1000 stable before initialization and claim a 500 bonus after half of the year passed", async function () {
      const bonusAmount = await toBonus("1000");
      const stableAmount = await toStable("1000");
      await stableToken
        .connect(accounts[1])
        .approve(lenderContract.address, stableAmount);
      await lenderContract
        .connect(accounts[1])
        ["deposit(uint256)"](stableAmount);
      await bonusToken.transfer(lenderContract.address, bonusAmount);
      // increase 10 days after deposit
      await time.increase(10 * DAY);
      // initializing
      await lenderContract.changeBaseRates(SampleAPR, SampleRate);
      // half of the year passed
      const passedPeriod = YEAR / 2;
      await time.increase(passedPeriod);
      // SampleRate is 100 which is 1.00
      const expectedBonus = (1000 * passedPeriod * (SampleRate / 100)) / YEAR;
      const beforeClaim = await bonusToken.balanceOf(addresses[1]);
      await lenderContract.connect(accounts[1])["claimBonus()"]();
      const afterClaim = await bonusToken.balanceOf(addresses[1]);
      const bonusBalance = afterClaim.sub(beforeClaim);
      const actualBonus = parseFloat(await fromBonus(bonusBalance));
      expect(actualBonus).to.be.within(expectedBonus, expectedBonus + 0.0001);
    });

    it("Should deposit 1000 stable after initialization and claim a 500 bonus after half of the year (Sample Apr 1) and 1000 bonus after another half of the year passed (Sample Apr 2)", async function () {
      // initializing
      await lenderContract.changeBaseRates(SampleAPR, SampleRate);
      // increase 10 days after initialization
      await time.increase(10 * DAY);
      const bonusAmount = await toBonus("2000");
      const stableAmount = await toStable("1000");
      await stableToken
        .connect(accounts[1])
        .approve(lenderContract.address, stableAmount);
      await lenderContract
        .connect(accounts[1])
        ["deposit(uint256)"](stableAmount);
      await bonusToken.transfer(lenderContract.address, bonusAmount);
      // half of the year passed
      const passedPeriod = YEAR / 2;
      await time.increase(passedPeriod);
      // SampleRate is 100 which is 1.00
      const expectedBonus = (1000 * passedPeriod * (SampleRate / 100)) / YEAR;
      const beforeClaim = await bonusToken.balanceOf(addresses[1]);
      await lenderContract.connect(accounts[1])["claimBonus()"]();
      const afterClaim = await bonusToken.balanceOf(addresses[1]);
      const bonusBalance = afterClaim.sub(beforeClaim);
      const actualBonus = parseFloat(await fromBonus(bonusBalance));
      expect(actualBonus).to.be.within(expectedBonus, expectedBonus + 0.0001);
      // Changing Apr and Rate
      await lenderContract.changeBaseRates(SampleAPR2, SampleRate2);
      // half of the year passed
      await time.increase(passedPeriod);
      // SampleRate is 200 which is 2.00
      const expectedBonus2 = (1000 * passedPeriod * (SampleRate2 / 100)) / YEAR;
      const beforeClaim2 = await bonusToken.balanceOf(addresses[1]);
      await lenderContract.connect(accounts[1])["claimBonus()"]();
      const afterClaim2 = await bonusToken.balanceOf(addresses[1]);
      const bonusBalance2 = afterClaim2.sub(beforeClaim2);
      const actualBonus2 = parseFloat(await fromBonus(bonusBalance2));
      expect(actualBonus2).to.be.within(expectedBonus2, expectedBonus2 + 0.001);
    });

    it("Should deposit 100 stable with 5 different accounts after initialization and claim a 50 bonus after half of the year (Sample Apr 1) and 100 bonus after another half of the year passed (Sample Apr 2)", async function () {
      // initializing
      await lenderContract.changeBaseRates(SampleAPR, SampleRate);
      // increase 10 days after initialization
      await time.increase(10 * DAY);
      const bonusAmount = await toBonus("1000");
      const stableAmount = await toStable("100");
      for (let i = 1; i < 6; i++) {
        await stableToken.transfer(addresses[i], stableAmount);
        await stableToken
          .connect(accounts[i])
          .approve(lenderContract.address, stableAmount);
        await lenderContract
          .connect(accounts[i])
          ["deposit(uint256)"](stableAmount);
      }
      await bonusToken.transfer(lenderContract.address, bonusAmount);
      // half of the year passed
      const passedPeriod = YEAR / 2;
      await time.increase(passedPeriod);
      // SampleRate is 100 which is 1.00
      const expectedBonus = (100 * passedPeriod * (SampleRate / 100)) / YEAR;
      for (let i = 1; i < 6; i++) {
        const beforeClaim = await bonusToken.balanceOf(addresses[i]);
        await lenderContract.connect(accounts[i])["claimBonus()"]();
        const afterClaim = await bonusToken.balanceOf(addresses[i]);
        const bonusBalance = afterClaim.sub(beforeClaim);
        const actualBonus = parseFloat(await fromBonus(bonusBalance));
        expect(actualBonus).to.be.within(expectedBonus, expectedBonus + 0.0001);
      }

      // Changing Apr and Rate
      await lenderContract.changeBaseRates(SampleAPR2, SampleRate2);
      // half of the year passed
      await time.increase(passedPeriod);
      // SampleRate is 200 which is 2.00
      const expectedBonus2 = (100 * passedPeriod * (SampleRate2 / 100)) / YEAR;
      for (let i = 1; i < 6; i++) {
        const beforeClaim2 = await bonusToken.balanceOf(addresses[i]);
        await lenderContract.connect(accounts[i])["claimBonus()"]();
        const afterClaim2 = await bonusToken.balanceOf(addresses[i]);
        const bonusBalance2 = afterClaim2.sub(beforeClaim2);
        const actualBonus2 = parseFloat(await fromBonus(bonusBalance2));
        expect(actualBonus2).to.be.within(
          expectedBonus2,
          expectedBonus2 + 0.0001
        );
      }
    });
  });

  describe("Claim Deposit with locking period", function () {
    beforeEach(async function () {
      lenderContract = await LenderFactory.deploy(
        addresses[0],
        USDCAddress,
        bonusAddress,
        MinDeposit,
        PoolMaxLimit
      );
      await lenderContract.deployed();
      await lenderContract.changeDurationLimit(
        LockingMinLimit,
        LockingMaxLimit
      );
      await lenderContract.switchAprBondingCurve(aprCurve.address);
      await lenderContract.switchRateBondingCurve(rateCurve.address);
    });

    it("Should fail if there is no deposit before initialization", async function () {
      lenderContract = await LenderFactory.deploy(
        addresses[0],
        USDCAddress,
        bonusAddress,
        MinDeposit,
        PoolMaxLimit
      );
      await expect(
        lenderContract.connect(accounts[1])["claimBonus(uint256)"](0)
      ).to.be.revertedWith("You have nothing with this ID");
    });

    it("Should fail if there is no deposit after initialization", async function () {
      await expect(
        lenderContract.connect(accounts[1])["claimBonus(uint256)"](0)
      ).to.be.revertedWith("You have nothing with this ID");
    });

    it("Should deposit 1000 stable for 90 days (0.25 rate) and claim a 125 bonus after 45 days passed", async function () {
      const bonusAmount = await toBonus("1000");
      const stableAmount = await toStable("1000");
      await stableToken.transfer(addresses[1], stableAmount);
      await stableToken
        .connect(accounts[1])
        .approve(lenderContract.address, stableAmount);
      await lenderContract
        .connect(accounts[1])
        ["deposit(uint256,uint256)"](stableAmount, SamplePeriod);
      await bonusToken.transfer(lenderContract.address, bonusAmount);
      // half of the period passed
      const passedPeriod = (SamplePeriod * DAY) / 2;
      await time.increase(passedPeriod);
      const rate = await rateCurve.getRate(SamplePeriod);
      const expectedBonus =
        (1000 * passedPeriod * (rate / 100)) / (SamplePeriod * DAY);
      const beforeClaim = await bonusToken.balanceOf(addresses[1]);
      await lenderContract.connect(accounts[1])["claimBonus(uint256)"](0);
      const afterClaim = await bonusToken.balanceOf(addresses[1]);
      const bonusBalance = afterClaim.sub(beforeClaim);
      const actualBonus = parseFloat(await fromBonus(bonusBalance));
      expect(actualBonus).to.be.within(expectedBonus, expectedBonus + 0.0001);
    });

    it("Should deposit 100 stable for 3 times with 90, 180, 365 locking days and claim a 111 bonus after 180 days and rest after 365 days", async function () {
      const bonusAmount = await toBonus("300");
      const totalStableAmount = await toStable("300");
      const stableAmount = await toStable("100");
      await stableToken.transfer(addresses[1], totalStableAmount);
      await stableToken
        .connect(accounts[1])
        .approve(lenderContract.address, totalStableAmount);
      await lenderContract
        .connect(accounts[1])
        ["deposit(uint256,uint256)"](stableAmount, SamplePeriod);
      await lenderContract
        .connect(accounts[1])
        ["deposit(uint256,uint256)"](stableAmount, 180);
      await lenderContract
        .connect(accounts[1])
        ["deposit(uint256,uint256)"](stableAmount, 365);
      await bonusToken.transfer(lenderContract.address, bonusAmount);
      // 180 days passed
      const passedPeriod = 180 * DAY;
      await time.increase(passedPeriod);
      const rate1 = await rateCurve.getRate(SamplePeriod);
      const rate2 = await rateCurve.getRate(180);
      const rate3 = await rateCurve.getRate(365);
      const expectedBonus1 =
        (100 * SamplePeriod * DAY * (rate1 / 100)) / (SamplePeriod * DAY);
      const expectedBonus2 =
        (100 * passedPeriod * (rate2 / 100)) / passedPeriod;
      const expectedBonus3 = (100 * passedPeriod * (rate3 / 100)) / (365 * DAY);
      const firstExpected = expectedBonus1 + expectedBonus2 + expectedBonus3;
      const beforeClaim = await bonusToken.balanceOf(addresses[1]);
      for (let i = 0; i < 3; i++) {
        await lenderContract.connect(accounts[1])["claimBonus(uint256)"](i);
      }
      const afterClaim = await bonusToken.balanceOf(addresses[1]);
      const bonusBalance = afterClaim.sub(beforeClaim);
      const actualBonus = parseFloat(await fromBonus(bonusBalance));
      expect(actualBonus).to.be.within(firstExpected, firstExpected + 0.0001);
      // rest 185 days passed (190 days to make sure it calculates till 185 days)
      const passedPeriod2 = 190 * DAY;
      await time.increase(passedPeriod2);
      const secondExpected = (100 * 185 * DAY * (rate3 / 100)) / (365 * DAY);
      const beforeClaim2 = await bonusToken.balanceOf(addresses[1]);
      for (let i = 0; i < 3; i++) {
        await lenderContract.connect(accounts[1])["claimBonus(uint256)"](i);
      }
      const afterClaim2 = await bonusToken.balanceOf(addresses[1]);
      const bonusBalance2 = afterClaim2.sub(beforeClaim2);
      const actualBonus2 = parseFloat(await fromBonus(bonusBalance2));
      expect(actualBonus2).to.be.within(
        secondExpected - 0.0001,
        secondExpected
      );
    });

    it("Should deposit 100 stable with 5 different accounts with 180 days locking days and claim 38 bonus after 180 days", async function () {
      const bonusAmount = await toBonus("200");
      const stableAmount = await toStable("100");
      for (let i = 1; i < 3; i++) {
        await stableToken.transfer(addresses[i], stableAmount);
        await stableToken
          .connect(accounts[i])
          .approve(lenderContract.address, stableAmount);
        await lenderContract
          .connect(accounts[i])
          ["deposit(uint256,uint256)"](stableAmount, 180);
      }
      await time.increase(90 * DAY);
      for (let i = 3; i < 6; i++) {
        await stableToken.transfer(addresses[i], stableAmount);
        await stableToken
          .connect(accounts[i])
          .approve(lenderContract.address, stableAmount);
        await lenderContract
          .connect(accounts[i])
          ["deposit(uint256,uint256)"](stableAmount, 180);
      }
      await bonusToken.transfer(lenderContract.address, bonusAmount);
      // 180 days passed
      const passedPeriod = 90 * DAY;
      await time.increase(passedPeriod);
      const rate = await rateCurve.getRate(180);
      const expectedBonus = (100 * passedPeriod * (rate / 100)) / passedPeriod;
      for (let i = 1; i < 3; i++) {
        const beforeClaim = await bonusToken.balanceOf(addresses[i]);
        await lenderContract.connect(accounts[i])["claimBonus(uint256)"](0);
        const afterClaim = await bonusToken.balanceOf(addresses[i]);
        const bonusBalance = afterClaim.sub(beforeClaim);
        const actualBonus = parseFloat(await fromBonus(bonusBalance));
        expect(actualBonus).to.be.equal(expectedBonus);
      }
      await time.increase(passedPeriod);
      for (let i = 3; i < 6; i++) {
        const beforeClaim = await bonusToken.balanceOf(addresses[i]);
        await lenderContract.connect(accounts[i])["claimBonus(uint256)"](0);
        const afterClaim = await bonusToken.balanceOf(addresses[i]);
        const bonusBalance = afterClaim.sub(beforeClaim);
        const actualBonus = parseFloat(await fromBonus(bonusBalance));
        expect(actualBonus).to.be.equal(expectedBonus);
      }
    });
  });
  describe("Claim All Deposits together", function () {
    beforeEach(async function () {
      lenderContract = await LenderFactory.deploy(
        addresses[0],
        USDCAddress,
        bonusAddress,
        MinDeposit,
        PoolMaxLimit
      );
      await lenderContract.deployed();
      await lenderContract.changeBaseRates(SampleAPR, SampleRate);
      await lenderContract.changeDurationLimit(
        LockingMinLimit,
        LockingMaxLimit
      );
      await lenderContract.switchAprBondingCurve(aprCurve.address);
      await lenderContract.switchRateBondingCurve(rateCurve.address);
    });

    it("Should fail if there is no deposit", async function () {
      await expect(
        lenderContract.connect(accounts[1]).claimAllBonuses()
      ).to.be.revertedWith("You have not deposited anything");
    });

    it("Should deposit 100 stable for 90 days (0.25 rate) and 100 stable without locking and claim all bonus after 45 days passed", async function () {
      const bonusAmount = await toBonus("200");
      const totalStableAmount = await toStable("200");
      const stableAmount = await toStable("100");
      await stableToken.transfer(addresses[1], totalStableAmount);
      await stableToken
        .connect(accounts[1])
        .approve(lenderContract.address, totalStableAmount);
      await lenderContract
        .connect(accounts[1])
        ["deposit(uint256,uint256)"](stableAmount, SamplePeriod);
      await lenderContract
        .connect(accounts[1])
        ["deposit(uint256)"](stableAmount);
      await bonusToken.transfer(lenderContract.address, bonusAmount);
      // half of the period passed
      const passedPeriod = (SamplePeriod * DAY) / 2;
      await time.increase(passedPeriod);
      const rate = await rateCurve.getRate(SamplePeriod);
      const expectedBonus1 =
        (100 * passedPeriod * (rate / 100)) / (SamplePeriod * DAY);
      const expectedBonus2 = (100 * passedPeriod * (SampleRate / 100)) / YEAR;
      const expectedBonus = expectedBonus1 + expectedBonus2;
      const beforeClaim = await bonusToken.balanceOf(addresses[1]);
      await lenderContract.connect(accounts[1]).claimAllBonuses();
      const afterClaim = await bonusToken.balanceOf(addresses[1]);
      const bonusBalance = afterClaim.sub(beforeClaim);
      const actualBonus = parseFloat(await fromBonus(bonusBalance));
      expect(actualBonus).to.be.within(expectedBonus, expectedBonus + 0.0001);
    });

    it("Should deposit 100 stable for 4 times with 0, 90, 180, 365 locking days and claim all bonus after 180 days and rest after 365 days", async function () {
      const bonusAmount = await toBonus("400");
      const totalStableAmount = await toStable("400");
      const stableAmount = await toStable("100");
      await stableToken.transfer(addresses[1], totalStableAmount);
      await stableToken
        .connect(accounts[1])
        .approve(lenderContract.address, totalStableAmount);
      await lenderContract
        .connect(accounts[1])
        ["deposit(uint256)"](stableAmount);
      await lenderContract
        .connect(accounts[1])
        ["deposit(uint256,uint256)"](stableAmount, SamplePeriod);
      await lenderContract
        .connect(accounts[1])
        ["deposit(uint256,uint256)"](stableAmount, 180);
      await lenderContract
        .connect(accounts[1])
        ["deposit(uint256,uint256)"](stableAmount, 365);
      await bonusToken.transfer(lenderContract.address, bonusAmount);
      // 180 days passed
      const passedPeriod = 180 * DAY;
      await time.increase(passedPeriod);
      const rate1 = await rateCurve.getRate(SamplePeriod);
      const rate2 = await rateCurve.getRate(180);
      const rate3 = await rateCurve.getRate(365);
      const expectedBonus0 = (100 * passedPeriod * (SampleRate / 100)) / YEAR;
      const expectedBonus1 =
        (100 * SamplePeriod * DAY * (rate1 / 100)) / (SamplePeriod * DAY);
      const expectedBonus2 =
        (100 * passedPeriod * (rate2 / 100)) / passedPeriod;
      const expectedBonus3 = (100 * passedPeriod * (rate3 / 100)) / (365 * DAY);
      const firstExpected =
        expectedBonus0 + expectedBonus1 + expectedBonus2 + expectedBonus3;
      const beforeClaim = await bonusToken.balanceOf(addresses[1]);
      await lenderContract.connect(accounts[1]).claimAllBonuses();
      const afterClaim = await bonusToken.balanceOf(addresses[1]);
      const bonusBalance = afterClaim.sub(beforeClaim);
      const actualBonus = parseFloat(await fromBonus(bonusBalance));
      expect(actualBonus).to.be.within(firstExpected, firstExpected + 0.001);
      const passedPeriod2 = 185 * DAY;
      await time.increase(passedPeriod2);
      const expectedBonus4 = (100 * passedPeriod2 * (SampleRate / 100)) / YEAR;
      const expectedBonus5 = (100 * 185 * DAY * (rate3 / 100)) / (365 * DAY);
      const secondExpected = expectedBonus4 + expectedBonus5;
      const beforeClaim2 = await bonusToken.balanceOf(addresses[1]);
      await lenderContract.connect(accounts[1]).claimAllBonuses();
      const afterClaim2 = await bonusToken.balanceOf(addresses[1]);
      const bonusBalance2 = afterClaim2.sub(beforeClaim2);
      const actualBonus2 = parseFloat(await fromBonus(bonusBalance2));
      expect(actualBonus2).to.be.within(
        secondExpected - 0.00001,
        secondExpected
      );
    });
  });
});
