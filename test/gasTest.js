// Import necessary modules
const { expect } = require("chai");
const { ethers } = require("hardhat");
describe("GasCompare", function () {
  let owner;
  let user1;
  let receiver;
  const depositAmount = ethers.utils.parseEther("1");
  let Token;
  let rETH;
  let wstETH;
  let sfrxETH;
  let cbETH;

  beforeEach(async () => {
    // Deploy the four dummy tokens
    Token = await ethers.getContractFactory("CustomToken");
    [owner, user1, receiver] = await ethers.getSigners();
    rETH = await Token.deploy("rETH", "rETH");
    wstETH = await Token.deploy("wstETH", "wstETH");
    sfrxETH = await Token.deploy("sfrxETH", "sfrxETH");
    cbETH = await Token.deploy("cbETH", "cbETH");
  });

  // Define test suite for EarlyAdopterPool contract
  describe("EarlyAdopterPool", () => {
    // Define variables for contract instance and test accounts
    let earlyAdopterPool;

    // Define function to deploy contract and get test accounts
    beforeEach(async () => {
      // Deploy the EarlyAdopterPool contract and pass the tokens as constructor arguments
      const EarlyAdopterPool = await ethers.getContractFactory(
        "EarlyAdopterPool"
      );
      earlyAdopterPool = await EarlyAdopterPool.deploy(
        rETH.address,
        wstETH.address,
        sfrxETH.address,
        cbETH.address
      );

      await earlyAdopterPool.deployed();
    });

    describe("Handling Ether Deposits", function () {
      beforeEach(async () => {
        // Deposit ETH into pool
        await earlyAdopterPool
          .connect(user1)
          .depositEther({ value: depositAmount });
      });

      // Test deposit Ether function
      it("should allow a user to deposit ETH twice into the pool", async () => {
        // Deposit ETH into pool
        await earlyAdopterPool
          .connect(user1)
          .depositEther({ value: depositAmount });
      });

      describe("Handling Token Deposits", function () {
        beforeEach(async () => {
          // Mint 1 cbETH tokens
          await cbETH.connect(user1).mint(user1.address, depositAmount);

          // Approve the EarlyAdopterPool contract to spend 1 cbETH tokens
          await cbETH
            .connect(user1)
            .approve(earlyAdopterPool.address, depositAmount);

          // Deposit 1 cbETH tokens into the EarlyAdopterPool contract
          await earlyAdopterPool
            .connect(user1)
            .deposit(cbETH.address, depositAmount);
        });

        it("should allow deposit of multiple tokens by same user", async function () {
          await sfrxETH.connect(user1).mint(user1.address, depositAmount);

          // Approve the EarlyAdopterPool contract to spend 1 sfrxETH tokens
          await sfrxETH
            .connect(user1)
            .approve(earlyAdopterPool.address, depositAmount);

          // Deposit 1 sfrxETH tokens into the EarlyAdopterPool contract
          await earlyAdopterPool
            .connect(user1)
            .deposit(sfrxETH.address, depositAmount);

          expect(await earlyAdopterPool.getContractTVL()).to.equal(
            ethers.utils.parseEther("3")
          );
        });

        // Test withdraw function
        it("should allow a user to withdraw all their balance from the pool", async () => {
          // Withdraw all previous deposited tokens & ether from pool
          await earlyAdopterPool.connect(user1).withdraw();
          const res = await earlyAdopterPool.getUserTVL(user1.address);
          // Access the totalBal value from the returned tuple
          const totalBal = res[5];
          expect(totalBal).to.equal("0");
        });

        // Test claim function
        it("should allow a user to claim their share of the reward pool", async () => {
          // Open claiming called by owner
          await earlyAdopterPool.connect(owner).setClaimingOpen(1);

          // Set reciever contract address - by owner
          await earlyAdopterPool.setClaimReceiverContract(receiver.address);

          // user1 can claim once reciever contract & claiming is opened
          await earlyAdopterPool.connect(user1).claim();
        });
      });
    });
  });

  // Define test suite for RefactoredEarlyAdopterPool contract
  describe("RefactoredEarlyAdopterPool", () => {
    // Define variables for contract instance and test accounts
    let refactoredPool;

    // Define function to deploy contract and get test accounts
    beforeEach(async () => {
      // Deploy the RefactoredEarlyAdopterPool contract and pass the tokens as constructor arguments
      const RefactoredEarlyAdopterPool = await ethers.getContractFactory(
        "RefactoredEarlyAdopterPool"
      );
      refactoredPool = await RefactoredEarlyAdopterPool.deploy(
        rETH.address,
        wstETH.address,
        sfrxETH.address,
        cbETH.address
      );

      await refactoredPool.deployed();
    });

    describe("Handling Ether Deposits", function () {
      beforeEach(async () => {
        // Deposit ETH into pool
        await refactoredPool
          .connect(user1)
          .depositEther({ value: depositAmount });
      });

      // Test deposit Ether function
      it("should allow a user to deposit ETH twice into the pool", async () => {
        // Deposit ETH into pool
        await refactoredPool
          .connect(user1)
          .depositEther({ value: depositAmount });
      });

      describe("Handling Token Deposits", function () {
        beforeEach(async () => {
          // Mint 1 rETH tokens
          await rETH.connect(user1).mint(user1.address, depositAmount);

          // Approve the RefactoredEarlyAdopterPool contract to spend 1 rETH tokens
          await rETH
            .connect(user1)
            .approve(refactoredPool.address, depositAmount);

          // Deposit 1 rETH tokens into the RefactoredEarlyAdopterPool contract
          await refactoredPool
            .connect(user1)
            .deposit(rETH.address, depositAmount);
        });

        it("should allow deposit of multiple tokens by same user", async function () {
          await wstETH.connect(user1).mint(user1.address, depositAmount);

          // Approve the RefactoredEarlyAdopterPool contract to spend 1 wstETH tokens
          await wstETH
            .connect(user1)
            .approve(refactoredPool.address, depositAmount);

          // Deposit 1 wstETH tokens into the RefactoredEarlyAdopterPool contract
          await refactoredPool
            .connect(user1)
            .deposit(wstETH.address, depositAmount);
          const res = await refactoredPool.getContractTVL();
          // Access the tvl value from the returned tuple
          const tvl = res[5];
          expect(tvl).to.equal(ethers.utils.parseEther("3"));
        });

        // Test withdraw function
        it("should allow a user to withdraw all their balance from the pool", async () => {
          // Withdraw all previous deposited tokens & ether from pool
          await refactoredPool.connect(user1).withdraw();
          const res = await refactoredPool.getUserTVL(user1.address);
          // Access the totalBal value from the returned tuple
          const totalBal = res[5];
          expect(totalBal).to.equal("0");
        });

        // Test claim function
        it("should allow a user to claim their share of the reward pool", async () => {
          // Open claiming called by owner
          await refactoredPool.connect(owner).setClaimingOpen(1);

          // Set reciever contract address - by owner
          await refactoredPool.setClaimReceiverContract(receiver.address);

          // user1 can claim once reciever contract & claiming is opened
          await refactoredPool.connect(user1).claim();
        });
      });
    });
  });
});
