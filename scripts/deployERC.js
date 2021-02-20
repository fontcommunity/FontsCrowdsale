// scripts/deploy.js
async function main() {
  // We get the contract to deploy
  const TestERC20 = await ethers.getContractFactory("TestERC20");
  console.log("Deploying TestERC20...");
  const _testERC20 = await TestERC20.deploy();
  await _testERC20.deployed();
  console.log("TestERC20 deployed to:", _testERC20.address);
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });