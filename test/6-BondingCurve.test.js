const { expect } = require("chai");
const { ethers } = require("hardhat");
const {
  p1Apr,
  p2Apr,
  p3Apr,
  p1Rate,
  p2Rate,
  p3Rate,
} = require("./constants/constants.helpers");

describe("Bonding Curve", function () {
  let aprCurve;
  let rateCurve;

  before(async function () {
    const CurveFactory = await ethers.getContractFactory("BondingCurve");
    aprCurve = await CurveFactory.deploy(p1Apr, p2Apr, p3Apr, 6);
    rateCurve = await CurveFactory.deploy(p1Rate, p2Rate, p3Rate, 6);
  });

  it("Should return 5% (with 2 decimals) as APR for 3 months locking period", async function () {
    expect(await aprCurve.getRate(90)).to.be.within(500 - 1, 500);
  });

  it("Should return 5.5% (with 2 decimals) as APR for 6 months locking period", async function () {
    expect(await aprCurve.getRate(180)).to.be.within(550, 550 + 1);
  });

  it("Should return 6.5% (with 2 decimals) as APR for 9 months locking period", async function () {
    expect(await aprCurve.getRate(270)).to.be.within(650 - 2, 650);
  });

  it("Should return 8% (with 2 decimals) as APR for 12 months locking period", async function () {
    expect(await aprCurve.getRate(365)).to.be.equal(800);
  });

  it("Should return 0.25 (with 2 decimals) as Bonus Rate for 3 months locking period", async function () {
    expect(await rateCurve.getRate(90)).to.be.equal(25);
  });

  it("Should return 0.4 (with 2 decimals) as Bonus Rate for 6 months locking period", async function () {
    expect(await rateCurve.getRate(180)).to.be.within(40 - 2, 40);
  });

  it("Should return 0.6 (with 2 decimals) as Bonus Rate for 9 months locking period", async function () {
    expect(await rateCurve.getRate(270)).to.be.within(60, 60 + 1);
  });

  it("Should return 1 (with 2 decimals) as Bonus Rate for 12 months locking period", async function () {
    expect(await rateCurve.getRate(365)).to.be.within(100 - 1, 100);
  });
});
