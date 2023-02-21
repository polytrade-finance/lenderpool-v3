const { expect } = require("chai");
const { ethers } = require("hardhat");
const { time } = require("@nomicfoundation/hardhat-network-helpers");
const {
  StableDecimal,
  BonusDecimal,
  ZeroAddress,
  LenderPoolAccess,
  SampleAPR,
  SampleRate,
  DAY,
  YEAR,
  SamplePeriod,
  MinDeposit,
  PoolMaxLimit,
  TestAAVEPool,
  TestUSDCAddress,
  TestaUSDCAddress,
  AccountToImpersonateUSDC,
} = require("./constants/constants.helpers");
const { now, toStable, toBonus, fromBonus, fromStable } = require("./helpers");

describe("Fixed Lender Pool", function () {
  let accounts;
  let addresses;
  let lenderContract;
  let LenderFactory;
  let strategy;
  let stableToken;
  let bonusToken;
  let bonusAddress;
  let currentTime;
  let minter;

  beforeEach(async function () {
    currentTime = await now();
  });

  before(async function () {
    const hre = require("hardhat");
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
    const Strategy = await ethers.getContractFactory("Strategy");
    strategy = await Strategy.deploy(
      TestAAVEPool,
      TestUSDCAddress,
      TestaUSDCAddress
    );
  });

  describe("Constructor", function () {
    it("Should deploy lender successfully", async function () {
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
        false
      );
      await lenderContract.deployed();
      await lenderContract.switchStrategy(strategy.address);
      await strategy.grantRole(LenderPoolAccess, lenderContract.address);
    });

    it("Should fail if admin address is zero", async function () {
      await expect(
        LenderFactory.deploy(
          ZeroAddress,
          TestUSDCAddress,
          bonusAddress,
          SampleAPR,
          SampleRate,
          currentTime + DAY,
          currentTime + 3 * DAY,
          SamplePeriod,
          MinDeposit,
          PoolMaxLimit,
          false
        )
      ).to.be.revertedWith("Invalid Admin address");
    });

    it("Should fail if stable address is zero", async function () {
      await expect(
        LenderFactory.deploy(
          addresses[0],
          ZeroAddress,
          bonusAddress,
          SampleAPR,
          SampleRate,
          currentTime + DAY,
          currentTime + 3 * DAY,
          SamplePeriod,
          MinDeposit,
          PoolMaxLimit,
          false
        )
      ).to.be.revertedWith("Invalid Stable Token address");
    });

    it("Should fail if bonus address is zero", async function () {
      await expect(
        LenderFactory.deploy(
          addresses[0],
          TestUSDCAddress,
          ZeroAddress,
          SampleAPR,
          SampleRate,
          currentTime + DAY,
          currentTime + 3 * DAY,
          SamplePeriod,
          MinDeposit,
          PoolMaxLimit,
          false
        )
      ).to.be.revertedWith("Invalid Bonus Token address");
    });

    it("Should fail if Pool Start Date is less than currentTime", async function () {
      await expect(
        LenderFactory.deploy(
          addresses[0],
          TestUSDCAddress,
          bonusAddress,
          SampleAPR,
          SampleRate,
          currentTime - DAY,
          currentTime + 3 * DAY,
          SamplePeriod,
          MinDeposit,
          PoolMaxLimit,
          false
        )
      ).to.be.revertedWith("Invalid Pool Start Date");
    });

    it("Should fail if Pool Start Date is equal to currentTime", async function () {
      await expect(
        LenderFactory.deploy(
          addresses[0],
          TestUSDCAddress,
          bonusAddress,
          SampleAPR,
          SampleRate,
          currentTime,
          currentTime + 3 * DAY,
          SamplePeriod,
          MinDeposit,
          PoolMaxLimit,
          false
        )
      ).to.be.revertedWith("Invalid Pool Start Date");
    });

    it("Should fail if Deposit End Date is less than currentTime", async function () {
      await expect(
        LenderFactory.deploy(
          addresses[0],
          TestUSDCAddress,
          bonusAddress,
          SampleAPR,
          SampleRate,
          currentTime + DAY,
          currentTime - 3 * DAY,
          SamplePeriod,
          MinDeposit,
          PoolMaxLimit,
          false
        )
      ).to.be.revertedWith("Invalid Deposit End Date");
    });

    it("Should fail if Deposit End Date is equal to currentTime", async function () {
      await expect(
        LenderFactory.deploy(
          addresses[0],
          TestUSDCAddress,
          bonusAddress,
          SampleAPR,
          SampleRate,
          currentTime + DAY,
          currentTime,
          SamplePeriod,
          MinDeposit,
          PoolMaxLimit,
          false
        )
      ).to.be.revertedWith("Invalid Deposit End Date");
    });

    it("Should fail if pool period duration is invalid", async function () {
      await expect(
        LenderFactory.deploy(
          addresses[0],
          TestUSDCAddress,
          bonusAddress,
          SampleAPR,
          SampleRate,
          currentTime + DAY,
          currentTime + 3 * DAY,
          0,
          MinDeposit,
          PoolMaxLimit,
          false
        )
      ).to.be.revertedWith("Invalid Pool Duration");
    });

    it("Should fail if Max. Pool size is less than Min. Deposit", async function () {
      await expect(
        LenderFactory.deploy(
          addresses[0],
          TestUSDCAddress,
          bonusAddress,
          SampleAPR,
          SampleRate,
          currentTime + DAY,
          currentTime + 3 * DAY,
          SamplePeriod,
          MinDeposit,
          MinDeposit - 1,
          false
        )
      ).to.be.revertedWith("Invalid Pool Max. Limit");
    });

    it("Should fail if Max. Pool size is equal to Min. Deposit", async function () {
      await expect(
        LenderFactory.deploy(
          addresses[0],
          TestUSDCAddress,
          bonusAddress,
          SampleAPR,
          SampleRate,
          currentTime + DAY,
          currentTime + 3 * DAY,
          SamplePeriod,
          MinDeposit,
          MinDeposit,
          false
        )
      ).to.be.revertedWith("Invalid Pool Max. Limit");
    });

    it("Should fail if Bonus Rate is more than 100 per stable token", async function () {
      // 10001 = 100.01 rate
      await expect(
        LenderFactory.deploy(
          addresses[0],
          TestUSDCAddress,
          bonusAddress,
          SampleAPR,
          10001,
          currentTime + DAY,
          currentTime + 3 * DAY,
          SamplePeriod,
          MinDeposit,
          PoolMaxLimit,
          false
        )
      ).to.be.revertedWith("Invalid Bonus Rate");
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

    it("Should deposit 1000 stable tokens before starting", async function () {
      const amount = await toStable("1000");
      await stableToken
        .connect(accounts[1])
        .approve(lenderContract.address, amount);
      await expect(lenderContract.connect(accounts[1]).deposit(amount))
        .to.emit(lenderContract, "Deposited")
        .withArgs(addresses[1], amount);
    });

    it("Should deposit 1000 stable tokens after starting before deposit end date", async function () {
      await time.increase(2 * DAY);
      const amount = await toStable("1000");
      await stableToken.transfer(addresses[1], amount);
      await stableToken
        .connect(accounts[1])
        .approve(lenderContract.address, amount);
      await expect(lenderContract.connect(accounts[1]).deposit(amount))
        .to.emit(lenderContract, "Deposited")
        .withArgs(addresses[1], amount);
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
      const amount = await toStable("100");
      await stableToken.transfer(
        lenderContract.address,
        toStable(`${PoolMaxLimit}`)
      );
      await stableToken
        .connect(accounts[1])
        .approve(lenderContract.address, amount);
      await stableToken.transfer(addresses[1], amount);
      await lenderContract.connect(accounts[1]).deposit(amount);
    });

    it("Should fail if has passed deposit end date", async function () {
      await time.increase(DAY);
      await expect(
        lenderContract.connect(accounts[1]).deposit(toStable("100"))
      ).to.be.revertedWith("Deposit End Date has passed");
    });

    it("Should fail if deposit amount + pool size pass the Pool Max. Limit", async function () {
      await stableToken
        .connect(accounts[1])
        .approve(lenderContract.address, toStable(`${PoolMaxLimit}`));
      await expect(
        lenderContract.connect(accounts[1]).deposit(toStable(`${PoolMaxLimit}`))
      ).to.be.revertedWith("Pool has reached its limit");
    });

    it("Should deposit 1 (Min. possible amount) stable for 10 times and claim each 10 days till end of pool period", async function () {
      lenderContract = await LenderFactory.deploy(
        addresses[0],
        TestUSDCAddress,
        bonusAddress,
        SampleAPR,
        SampleRate,
        currentTime + DAY,
        currentTime + 10 * DAY,
        SamplePeriod,
        1,
        PoolMaxLimit,
        false
      );
      await lenderContract.deployed();
      await lenderContract.switchStrategy(strategy.address);
      await strategy.grantRole(LenderPoolAccess, lenderContract.address);
      const amount = await toStable("1");
      const bonusAmount = await toBonus("10");
      await stableToken.transfer(addresses[1], 10 * amount);
      await bonusToken.transfer(lenderContract.address, bonusAmount);
      await stableToken
        .connect(accounts[1])
        .approve(lenderContract.address, 10 * amount);
      for (let i = 0; i < 10; i++) {
        await expect(lenderContract.connect(accounts[1]).deposit(amount))
          .to.emit(lenderContract, "Deposited")
          .withArgs(addresses[1], amount);
      }
      // Increase to pool start date
      await time.increase(DAY);
      const Period = SamplePeriod * DAY;
      const passedPeriod = 10 * DAY;
      const expectedBonus = (10 * passedPeriod * (SampleRate / 100)) / Period;
      for (let i = 0; i < 9; i++) {
        await time.increase(passedPeriod);
        const beforeClaim = await bonusToken.balanceOf(addresses[1]);
        await lenderContract.connect(accounts[1]).claimBonus();
        const afterClaim = await bonusToken.balanceOf(addresses[1]);
        const bonusBalance = afterClaim.sub(beforeClaim);
        const actualBonus = parseFloat(await fromBonus(bonusBalance));
        expect(actualBonus).to.be.within(
          expectedBonus - 0.0001,
          expectedBonus + 0.0001
        );
      }
    });
  });

  describe("Claim Single Deposit", function () {
    before(async function () {
      currentTime = await now();
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
        false
      );
      await lenderContract.deployed();
      await lenderContract.switchStrategy(strategy.address);
      await strategy.grantRole(LenderPoolAccess, lenderContract.address);
    });

    it("Should fail if there is no deposit", async function () {
      await expect(
        lenderContract.connect(accounts[1]).claimBonus()
      ).to.be.revertedWith("You have not deposited anything");
    });

    it("Should fail if claim before starting pool", async function () {
      const amount = await toStable("1000");
      await stableToken.transfer(addresses[1], amount);
      await stableToken
        .connect(accounts[1])
        .approve(lenderContract.address, amount);
      await expect(lenderContract.connect(accounts[1]).deposit(amount))
        .to.emit(lenderContract, "Deposited")
        .withArgs(addresses[1], amount);

      await expect(
        lenderContract.connect(accounts[1]).claimBonus()
      ).to.be.revertedWith("Pool has not started yet");
    });

    it("Should deposit 1000 stable before pool start date and claim a 500 bonus after half of the period passed from starting pool", async function () {
      const amount = await toBonus("1000");
      await bonusToken.transfer(lenderContract.address, amount);
      // increase to Pool Start Date
      await time.increase(DAY);
      const Period = SamplePeriod * DAY;
      // half of period passed
      const passedPeriod = Period / 2;
      await time.increase(passedPeriod);
      // SampleRate is 100 which is 1.00
      const expectedBonus = (1000 * passedPeriod * (SampleRate / 100)) / Period;
      const beforeClaim = await bonusToken.balanceOf(addresses[1]);
      await lenderContract.connect(accounts[1]).claimBonus();
      const afterClaim = await bonusToken.balanceOf(addresses[1]);
      const bonusBalance = afterClaim.sub(beforeClaim);
      const actualBonus = parseFloat(await fromBonus(bonusBalance));
      expect(actualBonus).to.be.within(expectedBonus, expectedBonus + 0.01);
    });

    it("Should claim rest of 500 bonus after pool end date", async function () {
      // increase to after Pool end Date
      await time.increase(46 * DAY);
      const Period = SamplePeriod * DAY;
      // half of period passed
      const passedPeriod = Period / 2;
      // SampleRate is 100 which is 1.00
      const expectedBonus = (1000 * passedPeriod * (SampleRate / 100)) / Period;
      const beforeClaim = await bonusToken.balanceOf(addresses[1]);
      await lenderContract.connect(accounts[1]).claimBonus();
      const afterClaim = await bonusToken.balanceOf(addresses[1]);
      const bonusBalance = afterClaim.sub(beforeClaim);
      const actualBonus = parseFloat(await fromBonus(bonusBalance));
      expect(actualBonus).to.be.within(expectedBonus - 0.01, expectedBonus);
    });
  });

  describe("Claim Multiple Deposit", function () {
    before(async function () {
      currentTime = await now();
      lenderContract = await LenderFactory.deploy(
        addresses[0],
        TestUSDCAddress,
        bonusAddress,
        SampleAPR,
        SampleRate,
        currentTime + DAY,
        currentTime + 10 * DAY,
        SamplePeriod,
        MinDeposit,
        PoolMaxLimit,
        false
      );
      await lenderContract.deployed();
      await lenderContract.switchStrategy(strategy.address);
      await strategy.grantRole(LenderPoolAccess, lenderContract.address);
    });

    it("Should deposit 100 stable with 5 different accounts for 10 times and claim each 10 days till end of pool period", async function () {
      const amount = await toStable("100");
      const bonusAmount = await toBonus("1000");
      for (let i = 1; i < 6; i++) {
        await stableToken.transfer(addresses[i], 10 * amount);
        await bonusToken.transfer(lenderContract.address, bonusAmount);
        await stableToken
          .connect(accounts[i])
          .approve(lenderContract.address, 10 * amount);
      }
      for (let i = 1; i < 6; i++) {
        for (let j = 0; j < 10; j++) {
          await expect(lenderContract.connect(accounts[i]).deposit(amount))
            .to.emit(lenderContract, "Deposited")
            .withArgs(addresses[i], amount);
        }
      }
      // Increase to pool start date
      await time.increase(DAY);
      const Period = SamplePeriod * DAY;
      const passedPeriod = 10 * DAY;
      const expectedBonus = (1000 * passedPeriod * (SampleRate / 100)) / Period;
      for (let i = 0; i < 9; i++) {
        await time.increase(passedPeriod);
        for (let j = 1; j < 6; j++) {
          const beforeClaim = await bonusToken.balanceOf(addresses[j]);
          await lenderContract.connect(accounts[j]).claimBonus();
          const afterClaim = await bonusToken.balanceOf(addresses[j]);
          const bonusBalance = afterClaim.sub(beforeClaim);
          const actualBonus = parseFloat(await fromBonus(bonusBalance));
          expect(actualBonus).to.be.within(
            expectedBonus - 0.02,
            expectedBonus + 0.01
          );
        }
      }
    });

    it("Should claim nothing after claiming all bonuses till pool end date", async function () {
      const expectedBonus = 0;
      const beforeClaim = await bonusToken.balanceOf(addresses[1]);
      await lenderContract.connect(accounts[1]).claimBonus();
      const afterClaim = await bonusToken.balanceOf(addresses[1]);
      const bonusBalance = afterClaim.sub(beforeClaim);
      const actualBonus = parseFloat(await fromBonus(bonusBalance));
      expect(actualBonus).to.be.equal(expectedBonus);
    });
  });

  describe("Withdraw", function () {
    beforeEach(async function () {
      currentTime = await now();
      lenderContract = await LenderFactory.deploy(
        addresses[0],
        TestUSDCAddress,
        bonusAddress,
        SampleAPR,
        SampleRate,
        currentTime + DAY,
        currentTime + 10 * DAY,
        SamplePeriod,
        MinDeposit,
        PoolMaxLimit,
        false
      );
      await lenderContract.deployed();
      await lenderContract.switchStrategy(strategy.address);
      await strategy.grantRole(LenderPoolAccess, lenderContract.address);
    });

    it("Should fail if caller has no deposit", async function () {
      // Increase to pool start date
      await time.increase(DAY);
      const Period = SamplePeriod * DAY;
      await time.increase(Period);
      await expect(
        lenderContract.connect(accounts[1]).withdraw()
      ).to.be.revertedWith("You have nothing to withdraw");
    });

    it("Should fail if withdraw before pool end date", async function () {
      const amount = await toStable("100");
      const bonusAmount = await toBonus("100");
      await stableToken.transfer(addresses[1], amount);
      await bonusToken.transfer(lenderContract.address, bonusAmount);
      await stableToken
        .connect(accounts[1])
        .approve(lenderContract.address, amount);
      await expect(lenderContract.connect(accounts[1]).deposit(amount))
        .to.emit(lenderContract, "Deposited")
        .withArgs(addresses[1], amount);
      const Period = SamplePeriod * DAY;
      const passedPeriod = Period / 2;
      await time.increase(passedPeriod);
      await expect(
        lenderContract.connect(accounts[1]).withdraw()
      ).to.be.revertedWith("Pool has not ended yet");
    });

    it("Should withdraw all rewards + principal after pool end date", async function () {
      const amount = await toStable("100");
      const bonusAmount = await toBonus("100");
      await stableToken.transfer(addresses[1], amount);
      await stableToken.transfer(lenderContract.address, amount * 0.1);
      await bonusToken.transfer(lenderContract.address, bonusAmount);
      await stableToken
        .connect(accounts[1])
        .approve(lenderContract.address, amount);
      await lenderContract.connect(accounts[1]).deposit(amount);
      // Increase to pool start date
      await time.increase(DAY);
      const Period = SamplePeriod * DAY;
      await time.increase(Period);
      const expectedBonus = (100 * Period * (SampleRate / 100)) / Period;
      const unroundExpectedStable =
        (100 * Period * (SampleAPR / 10000)) / YEAR + 100;
      // need to round expected stable with 6 decimal since stable has 6 decimal
      const expectedStable =
        Math.round(unroundExpectedStable * 10 ** StableDecimal) /
        10 ** StableDecimal;
      const bonusBeforeWith = await bonusToken.balanceOf(addresses[1]);
      const stableBeforeWith = await stableToken.balanceOf(addresses[1]);
      await lenderContract.connect(accounts[1]).withdraw();
      const bonusAfterWith = await bonusToken.balanceOf(addresses[1]);
      const stableAfterWith = await stableToken.balanceOf(addresses[1]);
      const bonusBalance = bonusAfterWith.sub(bonusBeforeWith);
      const stableBalance = stableAfterWith.sub(stableBeforeWith);
      const actualBonus = parseFloat(await fromBonus(bonusBalance));
      const actualStable = parseFloat(await fromStable(stableBalance));
      expect(actualBonus).to.be.equal(expectedBonus);
      expect(actualStable).to.be.equal(expectedStable);
    });

    it("Should deposit 100 stable with 3 different accounts before and after pool start date and withdraw after pool end date and decrease pool size", async function () {
      const amount = await toStable("100");
      const bonusAmount = await toBonus("1000");
      for (let i = 1; i < 4; i++) {
        await stableToken.transfer(addresses[i], 2 * amount);
        await stableToken.transfer(lenderContract.address, 0.1 * 2 * amount);
        await bonusToken.transfer(lenderContract.address, bonusAmount);
        await stableToken
          .connect(accounts[i])
          .approve(lenderContract.address, 2 * amount);
      }
      for (let i = 1; i < 4; i++) {
        await expect(lenderContract.connect(accounts[i]).deposit(amount))
          .to.emit(lenderContract, "Deposited")
          .withArgs(addresses[i], amount);
      }
      // Increase to one day after pool start date
      await time.increase(2 * DAY);
      for (let i = 1; i < 4; i++) {
        await expect(lenderContract.connect(accounts[i]).deposit(amount))
          .to.emit(lenderContract, "Deposited")
          .withArgs(addresses[i], amount);
      }
      const Period = SamplePeriod * DAY;
      const secondPeriod = (SamplePeriod - 1) * DAY;
      await time.increase(secondPeriod);
      const expectedBonus1st = (100 * Period * (SampleRate / 100)) / Period;
      const expectedBonus2nd =
        (100 * secondPeriod * (SampleRate / 100)) / Period;
      const unroundExpectedStable1st =
        (100 * Period * (SampleAPR / 10000)) / YEAR;
      const unroundExpectedStable2nd =
        (100 * secondPeriod * (SampleAPR / 10000)) / YEAR;
      // need to round expected stable with 6 decimal since stable has 6 decimal
      const expectedStable1st =
        Math.round(unroundExpectedStable1st * 10 ** StableDecimal) /
        10 ** StableDecimal;
      const expectedStable2nd =
        Math.round(unroundExpectedStable2nd * 10 ** StableDecimal) /
        10 ** StableDecimal;
      for (let i = 1; i < 4; i++) {
        const bonusBeforeWith = await bonusToken.balanceOf(addresses[i]);
        const stableBeforeWith = await stableToken.balanceOf(addresses[i]);
        const beforePoolSize = await lenderContract.poolSize();
        await lenderContract.connect(accounts[i]).withdraw();
        const afterPoolSize = await lenderContract.poolSize();
        const bonusAfterWith = await bonusToken.balanceOf(addresses[i]);
        const stableAfterWith = await stableToken.balanceOf(addresses[i]);
        const bonusBalance = bonusAfterWith.sub(bonusBeforeWith);
        const stableBalance = stableAfterWith.sub(stableBeforeWith);
        const actualBonus = parseFloat(await fromBonus(bonusBalance));
        const actualStable = parseFloat(await fromStable(stableBalance));
        const expectedStable = expectedStable1st + expectedStable2nd + 200;
        const expectedBonus = expectedBonus1st + expectedBonus2nd;
        const poolSize = beforePoolSize.sub(afterPoolSize);
        expect(actualStable).to.be.within(
          expectedStable - 0.00001,
          expectedStable
        );
        expect(actualBonus).to.be.within(expectedBonus - 0.0003, expectedBonus);
        expect(poolSize).to.be.equal(2 * amount);
      }
    });
  });
  describe("Emergency Withdraw", function () {
    beforeEach(async function () {
      currentTime = await now();
      lenderContract = await LenderFactory.deploy(
        addresses[0],
        TestUSDCAddress,
        bonusAddress,
        SampleAPR,
        SampleRate,
        currentTime + DAY,
        currentTime + 10 * DAY,
        SamplePeriod,
        MinDeposit,
        PoolMaxLimit,
        false
      );
      await lenderContract.deployed();
      await strategy.grantRole(LenderPoolAccess, lenderContract.address);
      await lenderContract.switchStrategy(strategy.address);
    });

    it("Should fail if caller has no deposit", async function () {
      // Increase to pool start date
      await time.increase(DAY);
      await expect(
        lenderContract.connect(accounts[1]).emergencyWithdraw()
      ).to.be.revertedWith("You have nothing to withdraw");
    });

    it("Should fail to change withdraw rate to more than or equal to 100%", async function () {
      await expect(lenderContract.setWithdrawRate(10000)).to.be.revertedWith(
        "Rate can not be more than 100%"
      );
    });

    it("Should fail to change withdraw rate without admin access", async function () {
      await expect(
        lenderContract.connect(accounts[1]).setWithdrawRate(500)
      ).to.be.revertedWith(
        `AccessControl: account ${addresses[1].toLowerCase()} is missing role ${ethers.utils.hexZeroPad(
          ethers.utils.hexlify(0),
          32
        )}`
      );
    });

    it("Should fail if emergency withdraw after pool end date", async function () {
      const amount = await toStable("100");
      // increase to pool start date
      await time.increase(DAY);
      await stableToken.transfer(addresses[1], amount);
      await stableToken
        .connect(accounts[1])
        .approve(lenderContract.address, amount);
      await lenderContract.connect(accounts[1]).deposit(amount);
      const Period = SamplePeriod * DAY;
      const passedPeriod = Period;
      await time.increase(passedPeriod);
      await expect(
        lenderContract.connect(accounts[1]).emergencyWithdraw()
      ).to.be.revertedWith("You can not emergency withdraw");
    });

    it("Should emergency withdraw all deposits before pool end date (Rate: 0%)", async function () {
      const amount = await toStable("100");
      const rate = 0;
      await stableToken.transfer(addresses[1], 2 * amount);
      await stableToken
        .connect(accounts[1])
        .approve(lenderContract.address, 2 * amount);
      await lenderContract.connect(accounts[1]).deposit(amount);

      // Increase to pool start date
      await time.increase(DAY);

      await lenderContract.connect(accounts[1]).deposit(amount);

      const Period = SamplePeriod * DAY;
      // increase to 10 seconds before pool end date
      await time.increase(Period - 10);
      const expectedStable = 200 - 200 * rate;
      const expectedBonus = 0;
      const bonusBeforeWith = await bonusToken.balanceOf(addresses[1]);
      const stableBeforeWith = await stableToken.balanceOf(addresses[1]);
      await expect(lenderContract.connect(accounts[1]).emergencyWithdraw())
        .to.emit(lenderContract, "WithdrawnEmergency")
        .withArgs(addresses[1], 2 * amount);
      const bonusAfterWith = await bonusToken.balanceOf(addresses[1]);
      const stableAfterWith = await stableToken.balanceOf(addresses[1]);
      const bonusBalance = bonusAfterWith.sub(bonusBeforeWith);
      const stableBalance = stableAfterWith.sub(stableBeforeWith);
      const actualBonus = parseFloat(await fromBonus(bonusBalance));
      const actualStable = parseFloat(await fromStable(stableBalance));
      expect(actualBonus).to.be.equal(expectedBonus);
      expect(actualStable).to.be.equal(expectedStable);
      expect(await lenderContract.poolSize());
    });

    it("Should deposit 100 stable with 3 different accounts before and after pool start date and emergency withdraw before pool end date (Rate: 0.52%) and decrease pool size", async function () {
      const rate = 0.0052;
      await expect(lenderContract.setWithdrawRate(52))
        .to.emit(lenderContract, "WithdrawRateChanged")
        .withArgs(0, 52);
      const amount = await toStable("100");
      for (let i = 1; i < 4; i++) {
        await stableToken.transfer(addresses[i], 2 * amount);
        await stableToken
          .connect(accounts[i])
          .approve(lenderContract.address, 2 * amount);
      }
      for (let i = 1; i < 4; i++) {
        await lenderContract.connect(accounts[i]).deposit(amount);
      }
      // Increase to one day after pool start date
      await time.increase(2 * DAY);
      for (let i = 1; i < 4; i++) {
        await lenderContract.connect(accounts[i]).deposit(amount);
      }
      const Period = SamplePeriod * DAY;
      const passedPeriod = Period / 2;
      await time.increase(passedPeriod);
      const expectedBonus = 0;
      const unroundExpectedStable = 200 - 200 * rate;
      // need to round expected stable with 6 decimal since stable has 6 decimal
      const expectedStable =
        Math.round(unroundExpectedStable * 10 ** StableDecimal) /
        10 ** StableDecimal;
      for (let i = 1; i < 4; i++) {
        const bonusBeforeWith = await bonusToken.balanceOf(addresses[i]);
        const stableBeforeWith = await stableToken.balanceOf(addresses[i]);
        const beforePoolSize = await lenderContract.poolSize();
        await lenderContract.connect(accounts[i]).emergencyWithdraw();
        const afterPoolSize = await lenderContract.poolSize();
        const bonusAfterWith = await bonusToken.balanceOf(addresses[i]);
        const stableAfterWith = await stableToken.balanceOf(addresses[i]);
        const bonusBalance = bonusAfterWith.sub(bonusBeforeWith);
        const stableBalance = stableAfterWith.sub(stableBeforeWith);
        const poolSize = beforePoolSize.sub(afterPoolSize);
        const actualBonus = parseFloat(await fromBonus(bonusBalance));
        const actualStable = parseFloat(await fromStable(stableBalance));
        expect(actualBonus).to.be.equal(expectedBonus);
        expect(actualStable).to.be.equal(expectedStable);
        expect(poolSize).to.be.equal(2 * amount);
      }
    });
  });
});