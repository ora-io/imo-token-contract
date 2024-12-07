const { expect } = require("chai");
const { ethers, network } = require("hardhat");

describe("ERC7641", function () {
  let erc7641;
  let addr0;
  let addr1;
  let addr2;
  let addrs;
  let erc7641Address;

  const percentClaimable = 80;
  const supply = 1000000000;
  const gas = ethers.parseEther("0.001");
  const snapshotInterval = "0x76a700";
  const snapshotIntervalTimestamp = 7776000;

  beforeEach(async function () {
    [addr0, addr1, addr2, ...addrs] = await ethers.getSigners();
    const ERC7641 = await ethers.getContractFactory("ERC7641");
    erc7641 = await ERC7641.deploy("ERC7641", "ERCX", supply, percentClaimable, snapshotIntervalTimestamp);
    await erc7641.waitForDeployment();
    erc7641Address = await erc7641.getAddress();
  });

  describe("Deployment", function () {
    it("Should set the right name", async function () {
      expect(await erc7641.name()).to.equal("ERC7641");
    });

    it("Should set the right symbol", async function () {
      expect(await erc7641.symbol()).to.equal("ERCX");
    });

    it("Should set the right total supply", async function () {
      expect(await erc7641.totalSupply()).to.equal(supply);
    });

    it("Should set the right last snapshot timestamp", async function () {
      const timestamp = await ethers.provider.getBlockTimestamp();
      expect(await erc7641.lastSnapshotTimestamp()).to.equal(timestamp);
    });

    it("Should set the right percent claimable", async function () {
      expect(await erc7641.percentClaimable()).to.equal(percentClaimable);
    });

    it("Should set the right snapshot interval", async function () {
      expect(await erc7641.snapshotInterval()).to.equal(snapshotIntervalTimestamp);
    });

    it("Should assign the total supply to the owner", async function () {
      expect(await erc7641.balanceOf(await ethers.provider.getSigner(0))).to.equal(supply);
    });
  });

  describe("Deposit", function () {
    it("Should deposit ETH to the contract", async function () {
      await addr0.sendTransaction({ to: erc7641Address, value: 1000 });
      expect(await ethers.provider.getBalance(erc7641Address)).to.equal(1000);
    });
  });

  describe("Snapshot", function () {
    it("Should not snapshot if 648,000 blocks have not passed", async function () {
      await expect(erc7641.snapshot()).to.be.revertedWith("snapshot interval is too short");
    });

    it("Should snapshot if > 648,000 blocks have passed", async function () {
      await network.provider.send("hardhat_mine", [snapshotInterval]);
      expect(await erc7641.snapshot()).to.emit(erc7641, "Snapshot");
    });
  });

  describe("Burn", function () {
    it("Should burn tokens", async function () {
      expect(await erc7641.redeemableOnBurn(10000)).to.equal(0);
      await erc7641.burn(10000);
      expect(await erc7641.balanceOf(await ethers.provider.getSigner(0))).to.equal(supply - 10000);
    });

    it("Should burn tokens and receive ETH", async function () {
      await addr0.sendTransaction({ to: erc7641Address, value: ethers.parseEther("1000") });
      expect(await ethers.provider.getBalance(erc7641Address)).to.equal(ethers.parseEther("1000"));
      expect(await erc7641.redeemableOnBurn(10000)).to.equal(ethers.parseEther("1000") * BigInt(10000) * BigInt(100 - percentClaimable) / BigInt(supply) / BigInt(100));
      const balanceBefore = await ethers.provider.getBalance(await ethers.provider.getSigner(0));
      await erc7641.burn(10000);
      const balanceAfter = await ethers.provider.getBalance(await ethers.provider.getSigner(0));
      expect(balanceAfter - balanceBefore).to.greaterThan(ethers.parseEther("1000") * BigInt(10000) * BigInt(100 - percentClaimable) / BigInt(supply) / BigInt(100) - gas);
    });

    it("Should snapshot and burn tokens", async function () {
      await addr0.sendTransaction({ to: erc7641Address, value: ethers.parseEther("1000") });
      await network.provider.send("hardhat_mine", [snapshotInterval]);
      await erc7641.snapshot();
      expect(await erc7641.redeemableOnBurn(10000)).to.equal(ethers.parseEther("1000") * BigInt(10000) * BigInt(100 - percentClaimable) / BigInt(supply) / BigInt(100));
      const balanceBefore = await ethers.provider.getBalance(await ethers.provider.getSigner(0));
      await erc7641.burn(10000);
      const balanceAfter = await ethers.provider.getBalance(await ethers.provider.getSigner(0));
      expect(balanceAfter - balanceBefore).to.greaterThan(ethers.parseEther("1000") * BigInt(10000) * BigInt(100 - percentClaimable) / BigInt(supply) / BigInt(100) - gas);
    });

    it("Should snapshot, deposit, and burn", async function () {
      await addr0.sendTransaction({ to: erc7641Address, value: ethers.parseEther("1000") });
      await network.provider.send("hardhat_mine", [snapshotInterval]);
      await erc7641.snapshot();
      await addr0.sendTransaction({ to: erc7641Address, value: ethers.parseEther("1000") });
      expect(await erc7641.redeemableOnBurn(10000)).to.equal(ethers.parseEther("2000") * BigInt(10000) * BigInt(100 - percentClaimable) / BigInt(supply) / BigInt(100));
      const balanceBefore = await ethers.provider.getBalance(await ethers.provider.getSigner(0));
      await erc7641.burn(10000);
      const balanceAfter = await ethers.provider.getBalance(await ethers.provider.getSigner(0));
      expect(balanceAfter - balanceBefore).to.greaterThan(ethers.parseEther("2000") * BigInt(10000) * BigInt(100 - percentClaimable) / BigInt(supply) / BigInt(100) - gas);
    });
  });

  describe("Claim", function () {
    it("Should not claim if no snapshot has been taken", async function () {
      await expect(erc7641.claim(1)).to.be.revertedWithPanic(0x11);
    });

    it("Should claim after snapshot", async function () {
      await addr0.sendTransaction({ to: erc7641Address, value: ethers.parseEther("1000") });
      await network.provider.send("hardhat_mine", [snapshotInterval]);
      await erc7641.snapshot();
      expect(await erc7641.claimableRevenue(addr0, 1)).to.equal(ethers.parseEther("1000") * BigInt(percentClaimable) / BigInt(100));
      const balanceBefore = await ethers.provider.getBalance(await ethers.provider.getSigner(0));
      await erc7641.claim(1);
      const balanceAfter = await ethers.provider.getBalance(await ethers.provider.getSigner(0));
      expect(balanceAfter - balanceBefore).to.greaterThan(ethers.parseEther("1000") * BigInt(percentClaimable) / BigInt(100) - gas);
    });

    it("Should not re-claim on the same snapshot", async function () {
      await addr0.sendTransaction({ to: erc7641Address, value: ethers.parseEther("1000") });
      await network.provider.send("hardhat_mine", [snapshotInterval]);
      await erc7641.snapshot();
      expect(await erc7641.claimableRevenue(addr0, 1)).to.equal(ethers.parseEther("1000") * BigInt(percentClaimable) / BigInt(100));
      await erc7641.claim(1);
      await expect(erc7641.claim(1)).to.be.revertedWith("already claimed");
    });

    it("Should claim after snapshot and deposit", async function () {
      await addr0.sendTransaction({ to: erc7641Address, value: ethers.parseEther("1000") });
      await network.provider.send("hardhat_mine", [snapshotInterval]);
      await erc7641.snapshot();
      await addr0.sendTransaction({ to: erc7641Address, value: ethers.parseEther("1000") });
      expect(await erc7641.claimableRevenue(addr0, 1)).to.equal(ethers.parseEther("1000") * BigInt(percentClaimable) / BigInt(100));
      const balanceBefore = await ethers.provider.getBalance(await ethers.provider.getSigner(0));
      await erc7641.claim(1);
      const balanceAfter = await ethers.provider.getBalance(await ethers.provider.getSigner(0));
      expect(balanceAfter - balanceBefore).to.greaterThan(ethers.parseEther("1000") * BigInt(percentClaimable) / BigInt(100) - gas);
    });

    it("Should claim correctly after snapshot with two holders", async function () {
      await erc7641.transfer(addr1.address, 100000);
      await addr0.sendTransaction({ to: erc7641Address, value: ethers.parseEther("1000") });
      await network.provider.send("hardhat_mine", [snapshotInterval]);
      await erc7641.snapshot();
      expect(await erc7641.claimableRevenue(addr0, 1)).to.equal(ethers.parseEther("1000") * BigInt(supply - 100000) * BigInt(percentClaimable) / BigInt(100) / BigInt(supply));
      expect(await erc7641.claimableRevenue(addr1, 1)).to.equal(ethers.parseEther("1000") * BigInt(100000) * BigInt(percentClaimable) / BigInt(100) / BigInt(supply));
      const balanceBefore0 = await ethers.provider.getBalance(addr0.address);
      const balanceBefore1 = await ethers.provider.getBalance(addr1.address);
      await erc7641.claim(1);
      await erc7641.connect(addr1).claim(1);
      const balanceAfter0 = await ethers.provider.getBalance(addr0.address);
      const balanceAfter1 = await ethers.provider.getBalance(addr1.address);
      expect(balanceAfter0 - balanceBefore0).to.greaterThan(ethers.parseEther("1000") * BigInt(supply - 100000) * BigInt(percentClaimable) / BigInt(100) / BigInt(supply) - gas);
      expect(balanceAfter1 - balanceBefore1).to.greaterThan(ethers.parseEther("1000") * BigInt(100000) * BigInt(percentClaimable) / BigInt(100) / BigInt(supply) - gas);
    });

    it("Should claim multiple snapshots correctly", async function () {
      await addr0.sendTransaction({ to: erc7641Address, value: ethers.parseEther("1000") });
      await network.provider.send("hardhat_mine", [snapshotInterval]);
      await erc7641.snapshot();
      await addr0.sendTransaction({ to: erc7641Address, value: ethers.parseEther("2000") });
      await network.provider.send("hardhat_mine", [snapshotInterval]);
      await erc7641.snapshot();
      expect(await erc7641.claimableRevenue(addr0, 1)).to.equal(ethers.parseEther("1000") * BigInt(percentClaimable) / BigInt(100));
      expect(await erc7641.claimableRevenue(addr0, 2)).to.equal(ethers.parseEther("2000") * BigInt(percentClaimable) / BigInt(100));
      const balanceBefore = await ethers.provider.getBalance(await ethers.provider.getSigner(0));
      await erc7641.claimBatch([1, 2]);
      const balanceAfter = await ethers.provider.getBalance(await ethers.provider.getSigner(0));
      expect(balanceAfter - balanceBefore).to.greaterThan(ethers.parseEther("3000") * BigInt(percentClaimable) / BigInt(100) - gas);
    });

    it("Should not claim if not most recent two snapshots", async function () {
      await addr0.sendTransaction({ to: erc7641Address, value: ethers.parseEther("100") });
      await network.provider.send("hardhat_mine", [snapshotInterval]);
      await erc7641.snapshot();
      await addr0.sendTransaction({ to: erc7641Address, value: ethers.parseEther("200") });
      await network.provider.send("hardhat_mine", [snapshotInterval]);
      await erc7641.snapshot();
      await addr0.sendTransaction({ to: erc7641Address, value: ethers.parseEther("300") });
      await network.provider.send("hardhat_mine", [snapshotInterval]);
      await erc7641.snapshot();
      await addr0.sendTransaction({ to: erc7641Address, value: ethers.parseEther("400") });
      await network.provider.send("hardhat_mine", [snapshotInterval]);
      await erc7641.snapshot();
      await expect(erc7641.claimableRevenue(addr0, 1)).to.be.revertedWith("snapshot unclaimable");
      await expect(erc7641.claimableRevenue(addr0, 2)).to.be.revertedWith("snapshot unclaimable");
      // should add 100 from snapshot 1
      expect(await erc7641.claimableRevenue(addr0, 3)).to.equal(ethers.parseEther("400") * BigInt(percentClaimable) / BigInt(100));
      // should add 200 from snapshot 2
      expect(await erc7641.claimableRevenue(addr0, 4)).to.equal(ethers.parseEther("600") * BigInt(percentClaimable) / BigInt(100));
    });
  });

  describe("Mixed operations", function () {
    it("deposit -> snapshot -> deposit -> burn -> deposit -> burn -> snapshot -> claim -> burn", async function () {
      await addr0.sendTransaction({ to: erc7641Address, value: ethers.parseEther("100") });
      await network.provider.send("hardhat_mine", [snapshotInterval]);
      await erc7641.snapshot();
      await addr0.sendTransaction({ to: erc7641Address, value: ethers.parseEther("100") });
      let redeemed = ethers.parseEther("200") * BigInt(10000) * BigInt(100 - percentClaimable) / BigInt(supply) / BigInt(100);
      expect(await erc7641.redeemableOnBurn(10000)).to.equal(redeemed);
      await erc7641.burn(10000);
      await addr0.sendTransaction({ to: erc7641Address, value: ethers.parseEther("100") });
      redeemed += ethers.parseEther("100") * BigInt(10000) * BigInt(100 - percentClaimable) / BigInt(supply - 10000) / BigInt(100);
      expect(await erc7641.redeemableOnBurn(10000)).to.equal(redeemed);
      await erc7641.burn(10000);
      await network.provider.send("hardhat_mine", [snapshotInterval]);
      await erc7641.snapshot();
      expect(await erc7641.claimableRevenue(addr0, 2)).to.equal(ethers.parseEther("200") * BigInt(percentClaimable) / BigInt(100));
      const balanceBefore = await ethers.provider.getBalance(await ethers.provider.getSigner(0));
      await erc7641.claim(2);
      const balanceAfter = await ethers.provider.getBalance(await ethers.provider.getSigner(0));
      expect(balanceAfter - balanceBefore).to.greaterThan(ethers.parseEther("200") * BigInt(percentClaimable) / BigInt(100) - gas);
      expect(await erc7641.redeemableOnBurn(10000)).to.equal(redeemed);
    });
  });
});
