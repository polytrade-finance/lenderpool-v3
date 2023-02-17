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
const { now, toStable } = require("./helpers");

describe("Verification", function () {
  let accounts;
  let addresses;
  let lenderContract;
  let verification;
  let polytradeProxy;
  let LenderFactory;
  let stableToken;
  let bonusToken;
  let stableAddress;
  let bonusAddress;
  let currentTime;

  before(async function () {
    currentTime = await now();
    accounts = await ethers.getSigners();
    addresses = accounts.map((account) => account.address);
    LenderFactory = await ethers.getContractFactory("FixLender");
    const StableToken = await ethers.getContractFactory("Token");
    stableToken = await StableToken.deploy("Stable", "STB", StableDecimal);
    await stableToken.deployed();
    stableAddress = stableToken.address;
    const BonusToken = await ethers.getContractFactory("Token");
    bonusToken = await BonusToken.deploy("Bonus", "BNS", BonusDecimal);
    await bonusToken.deployed();
    bonusAddress = bonusToken.address;
    const PolytradeProxy = await ethers.getContractFactory("PolytradeProxy");
    polytradeProxy = await PolytradeProxy.deploy();
    await polytradeProxy.deployed();
    const Verification = await ethers.getContractFactory("Verification");
    verification = await Verification.deploy(polytradeProxy.address);
    await verification.deployed();
    lenderContract = await LenderFactory.deploy(
      addresses[0],
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

  it("Should fail if verification address is zero", async () => {
    await expect(
      lenderContract.switchVerification(ZeroAddress)
    ).to.be.revertedWith("Invalid Verification Address");
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
  });

  it("Should change verification contract for Fix lender", async () => {
    await lenderContract.switchVerification(verification.address);
    expect(await lenderContract.verification()).to.be.equal(
      verification.address
    );
  });

  it("should fail to deposit stable token without KYC", async function () {
    const amount = await toStable("100");
    await stableToken.transfer(addresses[1], amount);
    await stableToken
      .connect(accounts[1])
      .approve(lenderContract.address, amount);
    await expect(
      lenderContract.connect(accounts[1]).deposit(amount)
    ).to.be.revertedWith("You are not verified");
  });

  it("Should set acc1 KYC valid and deposit", async function () {
    const amount = await toStable("100");
    await polytradeProxy.addKYC(addresses[1]);
    expect(await verification.isValid(addresses[1])).to.equal(true);
    await expect(lenderContract.connect(accounts[1]).deposit(amount))
      .to.emit(lenderContract, "Deposited")
      .withArgs(addresses[1], amount);
  });

  it("Should revoke acc1 KYC and acc1 should not able to deposit", async function () {
    const amount = await toStable("100");
    await polytradeProxy.revokeKYC(addresses[1]);
    expect(await verification.isValid(addresses[1])).to.equal(false);
    await expect(
      lenderContract.connect(accounts[1]).deposit(amount)
    ).to.be.revertedWith("You are not verified");
  });
});
