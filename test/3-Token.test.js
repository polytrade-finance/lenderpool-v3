const { expect } = require("chai");
const { ethers } = require("hardhat");
const { StableDecimal } = require("./constants/constants.helpers");

describe("Token", function () {
  let deployer;
  let customToken;

  before(async function () {
    const [, _deployer] = await ethers.getSigners();
    deployer = _deployer;
  });

  it("Should deploy token successfully", async function () {
    const CustomToken = await ethers.getContractFactory("Token");
    customToken = await CustomToken.deploy("PolyTrade", "TRADE", StableDecimal);
    await customToken.deployed();
    expect(await customToken.decimals()).to.be.equal(StableDecimal);
    expect(
      ethers.utils
        .parseUnits("1000000000", "6")
        .eq(await customToken.balanceOf(deployer.address))
    );
  });
});
