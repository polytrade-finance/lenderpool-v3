const { expect } = require("chai");
const { ethers } = require("hardhat");
const { time } = require("@nomicfoundation/hardhat-network-helpers");
const {
  BonusDecimal,
  LenderPoolAccess,
  ZeroAddress,
  SampleAPR,
  SampleRate,
  DAY,
  SamplePeriod,
  MinDeposit,
  PoolMaxLimit,
  AAVEPool,
  USDCAddress,
  aUSDCAddress,
  oUSDCAddress,
  AccountToImpersonateUSDC,
  AccountToImpersonateAdmin,
  UnitrollerAddress,
} = require("./constants/constants.helpers");
const { now, toStable, toBonus, fromStable } = require("./helpers");

describe("Strategy", function () {
  let accounts;
  let addresses;
  let lenderContract;
  let flexLenderContract;
  let LenderFactory;
  let FlexLenderFactory;
  let StrategyFactory;
  let StrategyFactory2;
  let strategy;
  let strategy2;
  let stableToken;
  let bonusToken;
  let bonusAddress;
  let currentTime;
  let impersonated;
  let admin;
  let unitroller;

  before(async function () {
    const hre = require("hardhat");
    currentTime = await now();
    accounts = await ethers.getSigners();
    addresses = accounts.map((account) => account.address);
    LenderFactory = await ethers.getContractFactory("FixLender");
    FlexLenderFactory = await ethers.getContractFactory("FlexLender");
    const OracleFactory = await ethers.getContractFactory("OracleMock");
    const oracle = await OracleFactory.deploy();
    await oracle.deployed();
    const FORK_UNI_ABI = [
      "function _setPriceOracle(address newOracle) public returns (uint256)",
      "function _setMintPaused(address oToken, bool state) public returns (bool)",
    ];
    await hre.network.provider.request({
      method: "hardhat_impersonateAccount",
      params: [AccountToImpersonateUSDC],
    });
    await hre.network.provider.request({
      method: "hardhat_impersonateAccount",
      params: [AccountToImpersonateAdmin],
    });
    impersonated = await ethers.getSigner(AccountToImpersonateUSDC);
    admin = await ethers.getSigner(AccountToImpersonateAdmin);
    await accounts[0].sendTransaction({
      to: admin.address,
      value: ethers.utils.parseEther("100.0"), // Sends exactly 1.0 ether
    });
    unitroller = new ethers.Contract(UnitrollerAddress, FORK_UNI_ABI, admin);
    await unitroller._setPriceOracle(oracle.address);
    stableToken = await ethers.getContractAt("IToken", USDCAddress);
    const BonusToken = await ethers.getContractFactory("Token");
    bonusToken = await BonusToken.deploy("Bonus", "BNS", BonusDecimal);
    await bonusToken.deployed();
    bonusAddress = bonusToken.address;
    StrategyFactory = await ethers.getContractFactory("Strategy");
    StrategyFactory2 = await ethers.getContractFactory("OvixStrategy");
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
      false
    );
    await lenderContract.deployed();
    await stableToken
      .connect(impersonated)
      .transfer(addresses[0], await toStable("200000"));
  });

  it("Should fail to deposit without strategy", async function () {
    const amount = await toStable("100");
    await expect(lenderContract.deposit(amount)).to.be.revertedWith(
      "There is no Strategy"
    );
    await expect(
      flexLenderContract["deposit(uint256)"](amount)
    ).to.be.revertedWith("There is no Strategy");
    await expect(
      flexLenderContract["deposit(uint256,uint256)"](amount, 180)
    ).to.be.revertedWith("There is no Strategy");
  });

  it("Should set first Strategy contract", async function () {
    strategy = await StrategyFactory.deploy(
      AAVEPool,
      USDCAddress,
      aUSDCAddress
    );
    await strategy.deployed();
    strategy2 = await StrategyFactory2.deploy(USDCAddress, oUSDCAddress);
    await lenderContract.switchStrategy(strategy.address);
    await expect(flexLenderContract.switchStrategy(strategy2.address))
      .to.emit(flexLenderContract, "StrategySwitched")
      .withArgs(ZeroAddress, strategy2.address);
  });

  it("Should fail to deposit without LENDER_POOL access", async function () {
    const amount = await toStable("100");
    await stableToken.transfer(addresses[1], amount);
    await stableToken
      .connect(accounts[1])
      .approve(lenderContract.address, amount);
    await expect(
      lenderContract.connect(accounts[1]).deposit(amount)
    ).to.be.revertedWith(
      `AccessControl: account ${lenderContract.address.toLowerCase()} is missing role ${LenderPoolAccess}`
    );
    await strategy.grantRole(LenderPoolAccess, lenderContract.address);
    await strategy2.grantRole(LenderPoolAccess, flexLenderContract.address);
  });

  it("Should deposit 100 stable tokens with 5 accounts to strategy", async function () {
    const amount = await toStable("100");
    const bonusAmount = await toBonus("500");
    await stableToken.transfer(lenderContract.address, 6 * amount);
    await bonusToken.transfer(lenderContract.address, bonusAmount);
    for (let i = 1; i < 6; i++) {
      await stableToken.transfer(addresses[i], amount);
      await stableToken
        .connect(accounts[i])
        .approve(lenderContract.address, amount);
      await expect(lenderContract.connect(accounts[i]).deposit(amount))
        .to.emit(strategy, "Deposited")
        .withArgs(amount);
    }
  });

  it("Should increase aStable balance of strategy contract to 500 aUSDC", async function () {
    const actual = await strategy.getBalance();
    expect(parseFloat(await fromStable(actual))).to.be.within(
      500 - 0.00001,
      500 + 0.00001
    );
  });

  it("Should fail to withdraw without LENDER_POOL access", async function () {
    await strategy.revokeRole(LenderPoolAccess, lenderContract.address);
    await expect(
      lenderContract.connect(accounts[1]).emergencyWithdraw()
    ).to.be.revertedWith(
      `AccessControl: account ${lenderContract.address.toLowerCase()} is missing role ${LenderPoolAccess}`
    );
    await strategy.grantRole(LenderPoolAccess, lenderContract.address);
  });

  it("Should fail to switch Strategy contract without admin access", async function () {
    await expect(
      lenderContract.connect(accounts[1]).switchStrategy(strategy.address)
    ).to.be.revertedWith(
      `AccessControl: account ${addresses[1].toLowerCase()} is missing role ${ethers.utils.hexZeroPad(
        ethers.utils.hexlify(0),
        32
      )}`
    );
    await expect(
      flexLenderContract.connect(accounts[1]).switchStrategy(strategy.address)
    ).to.be.revertedWith(
      `AccessControl: account ${addresses[1].toLowerCase()} is missing role ${ethers.utils.hexZeroPad(
        ethers.utils.hexlify(0),
        32
      )}`
    );
  });

  it("Should fail to set strategy without interface support", async function () {
    await expect(lenderContract.switchStrategy(stableToken.address)).to.be
      .reverted;
    await expect(flexLenderContract.switchStrategy(stableToken.address)).to.be
      .reverted;
  });

  it("Should fail to switch Strategy contract to invalid address", async function () {
    await expect(lenderContract.switchStrategy(ZeroAddress)).to.be.reverted;
    await expect(flexLenderContract.switchStrategy(ZeroAddress)).to.be.reverted;
  });

  it("Should switch Strategy Contract and transfer funds from old strategy to new one for fix lender", async function () {
    const oldStrategyBalance = await strategy.getBalance();
    const oldBalance = parseFloat(await fromStable(oldStrategyBalance));
    strategy = await StrategyFactory2.deploy(USDCAddress, oUSDCAddress);
    await strategy.deployed();
    await strategy.grantRole(LenderPoolAccess, lenderContract.address);
    await lenderContract.switchStrategy(strategy.address);
    const newStrategyBalance = await strategy.callStatic.getBalance();
    const newBalance = parseFloat(await fromStable(newStrategyBalance));
    expect(oldBalance).to.be.within(newBalance - 0.00001, newBalance + 0.00001);
  });

  it("Should fail to withdraw without LENDER_POOL access", async function () {
    await strategy.revokeRole(LenderPoolAccess, lenderContract.address);
    await expect(
      lenderContract.connect(accounts[1]).emergencyWithdraw()
    ).to.be.revertedWith(
      `AccessControl: account ${lenderContract.address.toLowerCase()} is missing role ${LenderPoolAccess}`
    );
    await strategy.grantRole(LenderPoolAccess, lenderContract.address);
  });

  it("Should emergency withdraw from strategy for first 2 accounts", async function () {
    for (let i = 1; i < 3; i++) {
      const oldStrategyBalance = await strategy.callStatic.getBalance();
      const oldSBalance = parseFloat(await fromStable(oldStrategyBalance));
      const oldLenderBalance = await stableToken.balanceOf(addresses[i]);
      const oldLBalance = parseFloat(await fromStable(oldLenderBalance));
      await expect(lenderContract.connect(accounts[i]).emergencyWithdraw())
        .to.emit(strategy, "Withdrawn")
        .withArgs(await toStable("100"));
      const newStrategyBalance = await strategy.callStatic.getBalance();
      const newSBalance = parseFloat(await fromStable(newStrategyBalance));
      const newLenderBalance = await stableToken.balanceOf(addresses[i]);
      const newLBalance = parseFloat(await fromStable(newLenderBalance));
      expect(oldSBalance - newSBalance).to.be.within(
        100 - 0.000001,
        100 + 0.000001
      );
      expect(newLBalance - oldLBalance).to.be.equal(100);
    }
  });

  it("Should withdraw from strategy after pool end date for last 3 accounts", async function () {
    await time.increase(SamplePeriod * DAY + DAY);
    for (let i = 3; i < 6; i++) {
      const oldStrategyBalance = await strategy.callStatic.getBalance();
      const oldSBalance = parseFloat(await fromStable(oldStrategyBalance));
      await lenderContract.connect(accounts[i]).withdraw();
      const newStrategyBalance = await strategy.callStatic.getBalance();
      const newSBalance = parseFloat(await fromStable(newStrategyBalance));
      expect(oldSBalance - newSBalance).to.be.within(
        100 - 0.00001,
        100 + 0.00001
      );
    }
  });

  it("Should fail to deposit without LENDER_POOL access", async function () {
    const amount = await toStable("100");
    await strategy2.revokeRole(LenderPoolAccess, flexLenderContract.address);
    await stableToken.transfer(addresses[1], amount);
    await stableToken
      .connect(accounts[1])
      .approve(flexLenderContract.address, amount);
    await expect(
      flexLenderContract.connect(accounts[1])["deposit(uint256)"](amount)
    ).to.be.revertedWith(
      `AccessControl: account ${flexLenderContract.address.toLowerCase()} is missing role ${LenderPoolAccess}`
    );
    await strategy2.grantRole(LenderPoolAccess, flexLenderContract.address);
  });

  it("Should deposit 100 stable tokens with 5 accounts to strategy for flex lender", async function () {
    const amount = await toStable("100");
    const bonusAmount = await toBonus("500");
    await stableToken.transfer(flexLenderContract.address, 5 * amount);
    await bonusToken.transfer(flexLenderContract.address, bonusAmount);
    for (let i = 1; i < 6; i++) {
      const oldStrategyBalance = await strategy2.callStatic.getBalance();
      const oldSBalance = parseFloat(await fromStable(oldStrategyBalance));
      await stableToken.transfer(addresses[i], amount);
      await stableToken
        .connect(accounts[i])
        .approve(flexLenderContract.address, amount);
      await flexLenderContract.connect(accounts[i])["deposit(uint256)"](amount);
      const newStrategyBalance = await strategy2.callStatic.getBalance();
      const newSBalance = parseFloat(await fromStable(newStrategyBalance));
      expect(newSBalance - oldSBalance).to.be.within(
        100 - 0.00001,
        100 + 0.00001
      );
    }
  });

  it("Should switch Strategy Contract and transfer funds from old strategy to new one for flex lender", async function () {
    const oldStrategyBalance = await strategy2.callStatic.getBalance();
    const oldBalance = parseFloat(await fromStable(oldStrategyBalance));
    strategy = await StrategyFactory.deploy(
      AAVEPool,
      USDCAddress,
      aUSDCAddress
    );
    await strategy.deployed();
    await strategy.grantRole(LenderPoolAccess, flexLenderContract.address);
    await flexLenderContract.switchStrategy(strategy.address);
    const newStrategyBalance = await strategy.callStatic.getBalance();
    const newBalance = parseFloat(await fromStable(newStrategyBalance));
    expect(oldBalance).to.be.within(newBalance - 0.00001, newBalance + 0.00001);
  });

  it("Should fail to deposit to strategy with Error", async function () {
    const amount = await toStable("100");
    await unitroller._setMintPaused(oUSDCAddress, true);
    await strategy2.grantRole(LenderPoolAccess, addresses[0]);
    await stableToken.approve(strategy2.address, amount);
    await expect(strategy2.deposit(amount)).to.be.reverted;
  });

  it("Should fail to withdraw from strategy with Error", async function () {
    const amount = await toStable("100");
    await expect(strategy2.withdraw(amount)).to.be.revertedWith(
      "Failed to withdraw from strategy"
    );
  });
});
