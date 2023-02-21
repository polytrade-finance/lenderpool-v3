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
  TestAAVEPool,
  TestUSDCAddress,
  TestaUSDCAddress,
  AccountToImpersonateUSDC,
} = require("./constants/constants.helpers");
const { now, toStable } = require("./helpers");

describe("Verification", function () {
  let accounts;
  let addresses;
  let lenderContract;
  let verification;
  let strategy;
  let polytradeProxy;
  let LenderFactory;
  let stableToken;
  let bonusToken;
  let bonusAddress;
  let currentTime;
  let minter;

  before(async function () {
    const hre = require("hardhat");
    currentTime = await now();
    accounts = await ethers.getSigners();
    addresses = accounts.map((account) => account.address);
    LenderFactory = await ethers.getContractFactory("FixLender");
    await hre.network.provider.request({
      method: "hardhat_impersonateAccount",
      params: [AccountToImpersonateUSDC],
    });
    minter = await ethers.getSigner(AccountToImpersonateUSDC);
    await hre.network.provider.send("hardhat_setBalance", [
      minter.address,
      "0x100000000000000000",
    ]);
    stableToken = await ethers.getContractAt("IToken", TestUSDCAddress);
    const BonusToken = await ethers.getContractFactory("Token");
    bonusToken = await BonusToken.deploy("Bonus", "BNS", BonusDecimal);
    await bonusToken.deployed();
    bonusAddress = bonusToken.address;
    await stableToken
      .connect(minter)
      .mint(addresses[0], await toStable("1000000000"));
    const PolytradeProxy = await ethers.getContractFactory("PolytradeProxy");
    polytradeProxy = await PolytradeProxy.deploy();
    await polytradeProxy.deployed();
    const Verification = await ethers.getContractFactory("Verification");
    verification = await Verification.deploy(polytradeProxy.address);
    await verification.deployed();
    const Strategy = await ethers.getContractFactory("Strategy");
    strategy = await Strategy.deploy(
      TestAAVEPool,
      TestUSDCAddress,
      TestaUSDCAddress
    );
    lenderContract = await LenderFactory.deploy(
      addresses[0],
      TestUSDCAddress,
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
