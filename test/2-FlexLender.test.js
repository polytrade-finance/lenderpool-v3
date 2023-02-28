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
} = require("./constants/constants.helpers");
const { toStable, toRate, toApr } = require("./helpers");

describe("Flexible Lender Pool", function () {
  let accounts;
  let addresses;
  let lenderContract;
  let LenderFactory;
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

  describe("Deposit", function () {
    it("Should fail if lender didn't approve the same or higher stable for lender contract before deposit", async function () {
      const amount = await toStable("1000");
      await stableToken.transfer(addresses[1], amount);
      await expect(
        lenderContract.connect(accounts[1]).deposit(amount)
      ).to.be.revertedWith("ERC20: transfer amount exceeds allowance");
    });

    it("Should deposit 1000 stable tokens before setting rate and apr", async function () {
      const amount = await toStable("1000");
      await stableToken
        .connect(accounts[1])
        .approve(lenderContract.address, amount);
      await expect(lenderContract.connect(accounts[1]).deposit(amount))
        .to.emit(lenderContract, "Deposited")
        .withArgs(addresses[1], 0, amount, 0, 0, 0);
    });

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

    it("Should deposit 1000 stable tokens after setting apr and rate", async function () {
      const amount = await toStable("1000");
      await stableToken.transfer(addresses[1], amount);
      await stableToken
        .connect(accounts[1])
        .approve(lenderContract.address, amount);
      await expect(lenderContract.connect(accounts[1]).deposit(amount))
        .to.emit(lenderContract, "Deposited")
        .withArgs(
          addresses[1],
          0,
          amount,
          0,
          await toApr(SampleAPR),
          await toRate(SampleRate, BonusDecimal, StableDecimal)
        );
    });

    it("Should fail if deposit amount is less than Min. deposit", async function () {
      const deposit = (MinDeposit - 1).toString();
      await stableToken
        .connect(accounts[1])
        .approve(lenderContract.address, toStable(deposit));
      await expect(
        lenderContract.connect(accounts[1]).deposit(toStable(deposit))
      ).to.be.revertedWith("Amount is less than Min. Deposit");
    });

    it("Should not increase pool Size if stable tokens transfer directly to contract", async function () {
      const poolBeforeTransfer = await lenderContract.poolSize();
      await stableToken.transfer(
        lenderContract.address,
        toStable(`${PoolMaxLimit}`)
      );
      const poolAfterTransfer = await lenderContract.poolSize();
      expect(poolBeforeTransfer).to.be.equal(poolAfterTransfer);
    });

    it("Should fail if deposit amount + pool size pass the Pool Max. Limit", async function () {
      await stableToken
        .connect(accounts[1])
        .approve(lenderContract.address, toStable(`${PoolMaxLimit}`));
      await expect(
        lenderContract.connect(accounts[1]).deposit(toStable(`${PoolMaxLimit}`))
      ).to.be.revertedWith("Pool has reached its limit");
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
  });
});
