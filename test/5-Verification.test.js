const { expect } = require("chai");
const { ethers } = require("hardhat");
const {
  BonusDecimal,
  ZeroAddress,
  LenderPoolAccess,
  SampleAPR,
  SampleRate,
  DAY,
  SamplePeriod,
  MinDeposit,
  PoolMaxLimit,
  AAVEPool,
  USDCAddress,
  aUSDCAddress,
  AccountToImpersonateUSDC,
} = require("./constants/constants.helpers");
const { now, toStable } = require("./helpers");

describe("Verification", function () {
  let accounts;
  let addresses;
  let lenderContract;
  let verification;
  let strategy;
  let flexLenderContract;
  let FlexLenderFactory;
  let polytradeProxy;
  let LenderFactory;
  let stableToken;
  let bonusToken;
  let bonusAddress;
  let currentTime;
  let impersonated;

  before(async function () {
    const hre = require("hardhat");
    currentTime = await now();
    accounts = await ethers.getSigners();
    addresses = accounts.map((account) => account.address);
    LenderFactory = await ethers.getContractFactory("FixLender");
    FlexLenderFactory = await ethers.getContractFactory("FlexLender");
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
    const PolytradeProxy = await ethers.getContractFactory("PolytradeProxy");
    polytradeProxy = await PolytradeProxy.deploy();
    await polytradeProxy.deployed();
    const Verification = await ethers.getContractFactory("Verification");
    verification = await Verification.deploy(polytradeProxy.address);
    await verification.deployed();
    const Strategy = await ethers.getContractFactory("Strategy");
    strategy = await Strategy.deploy(AAVEPool, USDCAddress, aUSDCAddress);
    flexLenderContract = await FlexLenderFactory.deploy(
      addresses[0],
      USDCAddress,
      bonusAddress,
      MinDeposit,
      PoolMaxLimit
    );
    await flexLenderContract.deployed();
    lenderContract = await LenderFactory.deploy(
      addresses[0],
      USDCAddress,
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
    await lenderContract.switchStrategy(strategy.address);
    await strategy.grantRole(LenderPoolAccess, lenderContract.address);
    await flexLenderContract.switchStrategy(strategy.address);
    await strategy.grantRole(LenderPoolAccess, flexLenderContract.address);
  });

  it("Should fail if verification address is zero", async () => {
    await expect(
      lenderContract.switchVerification(ZeroAddress)
    ).to.be.reverted;
    await expect(
      flexLenderContract.switchVerification(ZeroAddress)
    ).to.be.reverted;
  });

  it("Should fail to change verification without admin access", async function () {
    await expect(
      lenderContract
        .connect(accounts[1])
        .switchVerification(verification.address)
    ).to.be.revertedWith(
      `AccessControl: account ${addresses[1].toLowerCase()} is missing role ${ethers.utils.hexZeroPad(
        ethers.utils.hexlify(0),
        32
      )}`
    );
    await expect(
      flexLenderContract
        .connect(accounts[1])
        .switchVerification(verification.address)
    ).to.be.revertedWith(
      `AccessControl: account ${addresses[1].toLowerCase()} is missing role ${ethers.utils.hexZeroPad(
        ethers.utils.hexlify(0),
        32
      )}`
    );
  });

  it("Should fail to set apr address without interface support", async function () {
    await expect(lenderContract.switchVerification(stableToken.address)).to.be
      .reverted;
    await expect(flexLenderContract.switchVerification(stableToken.address)).to
      .be.reverted;
  });

  it("Should change verification contract for Fix and Flex lender", async () => {
    await flexLenderContract.switchVerification(verification.address);
    await lenderContract.switchVerification(verification.address);
    expect(await lenderContract.verification()).to.be.equal(
      verification.address
    );
  });

  it("Should fail to change verification status without admin access for Flex lender", async () => {
    await expect(
      flexLenderContract.connect(accounts[1]).changeVerificationStatus()
    ).to.be.revertedWith(
      `AccessControl: account ${addresses[1].toLowerCase()} is missing role ${ethers.utils.hexZeroPad(
        ethers.utils.hexlify(0),
        32
      )}`
    );
  });

  it("Should change verification status for flex lender to true", async () => {
    await flexLenderContract.changeVerificationStatus();
  });

  it("should fail to deposit stable token without KYC", async function () {
    const amount = await toStable("100");
    await stableToken.transfer(addresses[1], 3 * amount);
    await stableToken
      .connect(accounts[1])
      .approve(lenderContract.address, 2 * amount);
    await stableToken
      .connect(accounts[1])
      .approve(flexLenderContract.address, amount);
    await expect(
      lenderContract.connect(accounts[1]).deposit(amount)
    ).to.be.revertedWith("You are not verified");
    await expect(
      flexLenderContract.connect(accounts[1])["deposit(uint256)"](amount)
    ).to.be.revertedWith("You are not verified");
    await expect(
      flexLenderContract
        .connect(accounts[1])
        ["deposit(uint256,uint256)"](amount, 180)
    ).to.be.revertedWith("You are not verified");
  });

  it("Should set acc1 KYC valid and deposit", async function () {
    const amount = await toStable("100");
    await polytradeProxy.addKYC(addresses[1]);
    expect(await verification.isValid(addresses[1])).to.equal(true);
    await expect(lenderContract.connect(accounts[1]).deposit(amount))
      .to.emit(lenderContract, "Deposited")
      .withArgs(addresses[1], amount);
    await expect(
      flexLenderContract.connect(accounts[1])["deposit(uint256)"](amount)
    )
      .to.emit(flexLenderContract, "BaseDeposited")
      .withArgs(addresses[1], amount);
  });

  it("Should revoke acc1 KYC and acc1 should not able to deposit", async function () {
    const amount = await toStable("100");
    await polytradeProxy.revokeKYC(addresses[1]);
    expect(await verification.isValid(addresses[1])).to.equal(false);
    await expect(
      lenderContract.connect(accounts[1]).deposit(amount)
    ).to.be.revertedWith("You are not verified");
    await expect(
      flexLenderContract.connect(accounts[1])["deposit(uint256)"](amount)
    ).to.be.revertedWith("You are not verified");
  });

  it("Should change verification status for flex lender to false", async () => {
    await flexLenderContract.changeVerificationStatus();
  });
});
