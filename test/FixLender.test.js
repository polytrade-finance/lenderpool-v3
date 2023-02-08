// const { expect } = require("chai");
// const { ethers } = require("hardhat");
// const {
//   StableDecimal,
//   BonusDecimal,
//   ZeroAddress,
//   SampleAPR,
//   SampleRate,
//   DAY,
//   SamplePeriod,
//   MinDeposit,
//   MaxPoolSize,
// } = require("./constants/constants.helpers");
// const { now } = require("./helpers");

// describe("Fixed Lender Pool", function () {
//   let admin;
//   let lenderContract;
//   let stableToken;
//   let bonusToken;
//   let stableAddress;
//   let bonusAddress;
//   before(async function () {
//     const [_admin] = await ethers.getSigners();
//     admin = _admin;
//     const StableToken = await ethers.getContractFactory("Token");
//     stableToken = await StableToken.deploy("Stable", "STB", StableDecimal);
//     await stableToken.deployed();
//     stableAddress = stableToken.address;

//     const BonusToken = await ethers.getContractFactory("Token");
//     bonusToken = await BonusToken.deploy("Bonus", "BNS", BonusDecimal);
//     await bonusToken.deployed();
//     bonusAddress = bonusToken.address;
//   });

//   describe("Constructor", function () {
//     it("Should deploy lender successfully", async function () {
//       const currentTime = await now();
//       const LenderContract = await ethers.getContractFactory("FixLender");
//       lenderContract = await LenderContract.deploy(
//         admin.address,
//         stableAddress,
//         bonusAddress,
//         SampleAPR,
//         SampleRate,
//         currentTime + DAY,
//         currentTime + 3 * DAY,
//         SamplePeriod,
//         MinDeposit,
//         MaxPoolSize,
//         true
//       );
//       await lenderContract.deployed();
//     });
//     it("Should fail if any address is zero", async function () {
//       const currentTime = await now();
//       const LenderContract = await ethers.getContractFactory("FixLender");
//       await expect(
//         LenderContract.deploy(
//           ZeroAddress,
//           stableAddress,
//           bonusAddress,
//           SampleAPR,
//           SampleRate,
//           currentTime + DAY,
//           currentTime + 3 * DAY,
//           SamplePeriod,
//           MinDeposit,
//           MaxPoolSize,
//           true
//         )
//       ).to.be.revertedWith("Invalid Admin address");
//       await expect(
//         LenderContract.deploy(
//           admin.address,
//           ZeroAddress,
//           bonusAddress,
//           SampleAPR,
//           SampleRate,
//           currentTime + DAY,
//           currentTime + 3 * DAY,
//           SamplePeriod,
//           MinDeposit,
//           MaxPoolSize,
//           true
//         )
//       ).to.be.revertedWith("Invalid Stable Token address");
//       await expect(
//         LenderContract.deploy(
//           admin.address,
//           stableAddress,
//           ZeroAddress,
//           SampleAPR,
//           SampleRate,
//           currentTime + DAY,
//           currentTime + 3 * DAY,
//           SamplePeriod,
//           MinDeposit,
//           MaxPoolSize,
//           true
//         )
//       ).to.be.revertedWith("Invalid Bonus Token address");
//     });
//     it("Should fail if Dates are invalid", async function () {
//       const currentTime = await now();
//       const LenderContract = await ethers.getContractFactory("FixLender");
//       await expect(
//         LenderContract.deploy(
//           admin.address,
//           stableAddress,
//           bonusAddress,
//           SampleAPR,
//           SampleRate,
//           currentTime - DAY,
//           currentTime + 3 * DAY,
//           SamplePeriod,
//           MinDeposit,
//           MaxPoolSize,
//           true
//         )
//       ).to.be.revertedWith("Invalid Pool Start Date");
//       await expect(
//         LenderContract.deploy(
//           admin.address,
//           stableAddress,
//           bonusAddress,
//           SampleAPR,
//           SampleRate,
//           currentTime + DAY,
//           currentTime - 3 * DAY,
//           SamplePeriod,
//           MinDeposit,
//           MaxPoolSize,
//           true
//         )
//       ).to.be.revertedWith("Invalid Deposit End Date");
//     });
//     it("Should fail if pool period duration is invalid", async function () {
//       const currentTime = await now();
//       const LenderContract = await ethers.getContractFactory("FixLender");
//       await expect(
//         LenderContract.deploy(
//           admin.address,
//           stableAddress,
//           bonusAddress,
//           SampleAPR,
//           SampleRate,
//           currentTime + DAY,
//           currentTime + 3 * DAY,
//           0,
//           MinDeposit,
//           MaxPoolSize,
//           true
//         )
//       ).to.be.revertedWith("Invalid Pool Duration");
//     });
//     it("Should fail if Max. Pool size is less than or equal to Min. Deposit", async function () {
//       const currentTime = await now();
//       const LenderContract = await ethers.getContractFactory("FixLender");
//       await expect(
//         LenderContract.deploy(
//           admin.address,
//           stableAddress,
//           bonusAddress,
//           SampleAPR,
//           SampleRate,
//           currentTime + DAY,
//           currentTime + 3 * DAY,
//           SamplePeriod,
//           MinDeposit,
//           MinDeposit,
//           true
//         )
//       ).to.be.revertedWith("Invalid Max. Pool Size");
//     });
//   });
// });
