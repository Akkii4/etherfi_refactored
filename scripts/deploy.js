// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// When running the script with `hardhat run <script>` you'll find the Hardhat
// Runtime Environment's members available in the global scope.
const hre = require("hardhat");
const ConstructorParams = require("./constructorParams.json");

async function main() {
  const RefactoredEarlyAdopterPool = await hre.ethers.getContractFactory(
    "RefactoredEarlyAdopterPool"
  );
  const RefactoredEarlyAdopterPoolInstance =
    await RefactoredEarlyAdopterPool.deploy(
      ConstructorParams.rETH,
      ConstructorParams.wstETH,
      ConstructorParams.sfrxETH,
      ConstructorParams.cbETH
    );
  await RefactoredEarlyAdopterPoolInstance.deployed();
  console.log(
    "RefactoredEarlyAdopterPool deployed at " +
      RefactoredEarlyAdopterPoolInstance.address
  );
  await RefactoredEarlyAdopterPoolInstance.deployTransaction.wait([
    (confirms = 6),
  ]);

  await hre.run("verify:verify", {
    address: RefactoredEarlyAdopterPoolInstance.address,
    constructorArguments: [
      ConstructorParams.rETH,
      ConstructorParams.wstETH,
      ConstructorParams.sfrxETH,
      ConstructorParams.cbETH,
    ],
  });
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
